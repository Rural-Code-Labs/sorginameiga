import Fluent
import Vapor

/// Builds the `LayoutContext` shared by every page: the localized menu, the
/// language-switcher targets and the footer visit counter.
enum PageLayout {
    /// Assembles the layout for a request. `spanishURL` / `englishURL` are the
    /// current page's URLs in each language so the header flags keep the user
    /// on the same page when switching language.
    static func build(
        for language: Language,
        spanishURL: String,
        englishURL: String,
        on req: Request
    ) async -> LayoutContext {
        let translation = req.localization.translation(for: language)
        return LayoutContext(
            lang: language.htmlLang,
            spanishURL: spanishURL,
            englishURL: englishURL,
            menu: menu(for: language, translation: translation),
            visitCount: await registerVisit(on: req),
            social: SocialLinks.fromEnvironment(),
            t: translation
        )
    }

    /// Builds the localized navigation menu.
    ///
    /// Note: contact (`/contacto`) is implemented in a later phase and 404s for now.
    static func menu(for language: Language, translation t: Translation) -> [MenuItem] {
        switch language {
        case .esp:
            return [
                MenuItem(label: t.aboutUs, url: "/"),
                MenuItem(label: t.males, url: "/machos"),
                MenuItem(label: t.females, url: "/hembras"),
                MenuItem(label: t.puppies, url: "/cachorros"),
                MenuItem(label: t.gallery, url: "/galeria"),
                MenuItem(label: t.contact, url: "/contacto"),
            ]
        case .ing:
            return [
                MenuItem(label: t.aboutUs, url: "/en"),
                MenuItem(label: t.males, url: "/en/males"),
                MenuItem(label: t.females, url: "/en/females"),
                MenuItem(label: t.puppies, url: "/en/puppies"),
                MenuItem(label: t.gallery, url: "/en/gallery"),
                MenuItem(label: t.contact, url: "/en/contact"),
            ]
        }
    }

    /// Increments and returns the site-wide visit counter, mirroring the legacy
    /// footer (which counted every page view). Best-effort: returns `nil` if the
    /// database is unavailable so the page still renders.
    private static func registerVisit(on req: Request) async -> Int? {
        do {
            guard let counter = try await VisitCounter.find(VisitCounter.singletonID, on: req.db) else {
                return nil
            }
            counter.count += 1
            try await counter.save(on: req.db)
            return counter.count
        } catch {
            req.logger.warning("Visit counter unavailable: \(error)")
            return nil
        }
    }
}
