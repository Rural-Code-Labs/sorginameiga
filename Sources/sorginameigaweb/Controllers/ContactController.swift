import Vapor

/// Serves the contact page (`/contacto`, `/en/contact`) in both languages.
///
/// Mirrors the current production `contactos.php`, which shows contact details
/// only — the legacy contact form (`contactos_old.php` + `enviaremail.php`) was
/// removed by the owners in favour of direct email / phone / WhatsApp.
final class ContactController: RouteCollection, Sendable {
    /// Kennel contact details (language-independent).
    private static let email = "sorginameiga@hotmail.com"
    private static let phones = ["696 214 610", "629 088 980"]

    func boot(routes: any RoutesBuilder) throws {
        routes.get("contacto", use: spanish)
        routes.get("en", "contact", use: english)
    }

    @Sendable func spanish(req: Request) async throws -> View { try await render(.esp, on: req) }
    @Sendable func english(req: Request) async throws -> View { try await render(.ing, on: req) }

    private func render(_ language: Language, on req: Request) async throws -> View {
        let translation = req.localization.translation(for: language)
        let layout = await PageLayout.build(
            for: language,
            spanishURL: "/contacto",
            englishURL: "/en/contact",
            on: req
        )
        return try await req.view.render(
            "contact",
            ContactContext(
                layout: layout,
                title: translation.contact,
                text: translation.formText,
                email: Self.email,
                phones: Self.phones
            )
        )
    }
}
