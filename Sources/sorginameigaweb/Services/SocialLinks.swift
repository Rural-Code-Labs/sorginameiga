import Vapor

/// The kennel's social media profiles, shown as icons in the header (phase 9c).
///
/// The URLs default to the real Sorgiña-Meiga profiles but can be overridden
/// with the `INSTAGRAM_URL` / `FACEBOOK_URL` environment variables, so they are
/// easy to change without a code edit.
struct SocialLinks: Encodable {
    let instagram: String
    let facebook: String

    static func fromEnvironment() -> SocialLinks {
        SocialLinks(
            instagram: Environment.get("INSTAGRAM_URL") ?? "https://www.instagram.com/sorginameiga/",
            facebook: Environment.get("FACEBOOK_URL") ?? "https://www.facebook.com/sorginameiga.lhasas"
        )
    }
}
