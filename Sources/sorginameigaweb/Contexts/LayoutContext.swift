/// A navigation menu entry (label + destination URL).
struct MenuItem: Encodable {
    let label: String
    let url: String
}

/// Context shared by every page through the Leaf layout (`base` + partials).
///
/// Carries the current language, the language-switcher targets (which preserve
/// the current page), the localized menu, the footer visit count and the
/// translated strings. Each page context embeds one of these as `layout`.
struct LayoutContext: Encodable {
    /// Value for the HTML `lang` attribute ("es" / "en").
    let lang: String
    /// URL of the current page in Spanish (target of the "esp" flag).
    let spanishURL: String
    /// URL of the current page in English (target of the "ing" flag).
    let englishURL: String
    /// Localized navigation menu.
    let menu: [MenuItem]
    /// Total visit count for the footer, or `nil` if the counter is unavailable.
    let visitCount: Int?
    /// Social media profile links shown in the header.
    let social: SocialLinks
    /// Translated strings for the current language.
    let t: Translation
}
