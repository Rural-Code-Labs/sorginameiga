import Vapor

/// Serves the public home page ("¿Quiénes Somos?") in both languages.
///
/// Clean URLs: `/` and `/es` render Spanish, `/en` renders English.
/// Replaces the legacy `old_web/index.php`.
final class HomeController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        routes.get(use: spanishHome)       // /
        routes.get("es", use: spanishHome) // /es
        routes.get("en", use: englishHome) // /en
    }

    @Sendable
    func spanishHome(req: Request) async throws -> View {
        try await render(.esp, on: req)
    }

    @Sendable
    func englishHome(req: Request) async throws -> View {
        try await render(.ing, on: req)
    }

    private func render(_ language: Language, on req: Request) async throws -> View {
        let layout = await PageLayout.build(
            for: language,
            spanishURL: "/",
            englishURL: "/en",
            on: req
        )
        return try await req.view.render("home", HomeContext(layout: layout))
    }
}
