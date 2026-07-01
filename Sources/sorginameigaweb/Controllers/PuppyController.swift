import Fluent
import Vapor

/// Serves the puppies page (`/cachorros`, `/en/puppies`) in both languages.
/// Each puppy is shown as a titled block (with an availability badge) and its
/// photo grid. Replaces the legacy `cachorros.php`.
final class PuppyController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("cachorros", use: spanish)
        routes.get("en", "puppies", use: english)
    }

    @Sendable func spanish(req: Request) async throws -> View { try await render(.esp, on: req) }
    @Sendable func english(req: Request) async throws -> View { try await render(.ing, on: req) }

    private func render(_ language: Language, on req: Request) async throws -> View {
        let puppies = try await Puppy.query(on: req.db).sort(\.$id).all()
        let translation = req.localization.translation(for: language)
        let blocks = puppies.map { puppy in
            MediaBlock(
                title: puppy.name,
                badge: puppy.available ? translation.available : translation.unavailable,
                photos: PhotoDirectory.photos(in: "images/cachorros/\(puppy.id ?? 0)", on: req)
            )
        }

        let layout = await PageLayout.build(
            for: language,
            spanishURL: "/cachorros",
            englishURL: "/en/puppies",
            on: req
        )
        return try await req.view.render(
            "media",
            MediaPageContext(
                layout: layout,
                title: translation.puppies,
                blocks: blocks,
                emptyMessage: translation.noPuppies
            )
        )
    }
}
