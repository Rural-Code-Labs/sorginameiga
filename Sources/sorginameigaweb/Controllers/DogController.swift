import Fluent
import Vapor

/// Serves the dog listings (`/machos`, `/hembras`) and the dog detail page
/// (`/perro/:id`) with its four-generation pedigree, in both languages.
/// Replaces the legacy `perros.php`, `includes/tablaperros.php` and `verperro.php`.
final class DogController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        // Listings
        routes.get("machos", use: spanishMales)
        routes.get("hembras", use: spanishFemales)
        routes.get("en", "males", use: englishMales)
        routes.get("en", "females", use: englishFemales)
        // Detail
        routes.get("perro", ":dogID", use: spanishDetail)
        routes.get("en", "dog", ":dogID", use: englishDetail)
    }

    // MARK: - Listings

    @Sendable func spanishMales(req: Request) async throws -> View {
        try await listing(.esp, sex: .male, on: req)
    }
    @Sendable func spanishFemales(req: Request) async throws -> View {
        try await listing(.esp, sex: .female, on: req)
    }
    @Sendable func englishMales(req: Request) async throws -> View {
        try await listing(.ing, sex: .male, on: req)
    }
    @Sendable func englishFemales(req: Request) async throws -> View {
        try await listing(.ing, sex: .female, on: req)
    }

    private func listing(_ language: Language, sex: Sex, on req: Request) async throws -> View {
        let dogs = try await Dog.query(on: req.db)
            .filter(\.$sex == sex.rawValue)
            .sort(\.$position)
            .all()

        let translation = req.localization.translation(for: language)
        let title = sex == .male ? translation.males : translation.females
        let cards = dogs.map { dog in
            DogCard(
                id: dog.id ?? 0,
                name: dog.name,
                photo: PhotoDirectory.url(in: "images/\(dog.id ?? 0)", index: 0, on: req),
                url: detailURL(language: language, id: dog.id ?? 0)
            )
        }

        let (spanishURL, englishURL) = listingURLs(sex: sex)
        let layout = await PageLayout.build(
            for: language,
            spanishURL: spanishURL,
            englishURL: englishURL,
            on: req
        )
        return try await req.view.render(
            "dogs",
            DogsPageContext(layout: layout, title: title, dogs: cards)
        )
    }

    // MARK: - Detail

    @Sendable func spanishDetail(req: Request) async throws -> View {
        try await detail(.esp, on: req)
    }
    @Sendable func englishDetail(req: Request) async throws -> View {
        try await detail(.ing, on: req)
    }

    private func detail(_ language: Language, on req: Request) async throws -> View {
        guard let id = req.parameters.get("dogID", as: Int.self),
              let dog = try await Dog.find(id, on: req.db) else {
            throw Abort(.notFound)
        }

        let layout = await PageLayout.build(
            for: language,
            spanishURL: detailURL(language: .esp, id: id),
            englishURL: detailURL(language: .ing, id: id),
            on: req
        )
        let listing = listingURLs(sex: dog.sexValue ?? .female)
        let backURL = language == .esp ? listing.0 : listing.1

        return try await req.view.render(
            "dog",
            DogDetailContext(
                layout: layout,
                name: dog.name,
                photos: PhotoDirectory.photos(in: "images/\(id)", on: req),
                pedigree: dog.pedigree,
                backURL: backURL
            )
        )
    }

    // MARK: - Helpers

    private func detailURL(language: Language, id: Int) -> String {
        language == .esp ? "/perro/\(id)" : "/en/dog/\(id)"
    }

    /// Returns (spanishURL, englishURL) for a sex listing.
    private func listingURLs(sex: Sex) -> (String, String) {
        switch sex {
        case .male: return ("/machos", "/en/males")
        case .female: return ("/hembras", "/en/females")
        }
    }
}
