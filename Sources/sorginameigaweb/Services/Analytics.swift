import Vapor

/// Google Analytics 4 configuration (phase 12 / v2.2).
///
/// Analytics is **disabled** unless the `GA_MEASUREMENT_ID` environment variable
/// holds a GA4 Measurement ID (e.g. `G-XXXXXXXXXX`). When disabled, no Google
/// tag or cookie banner is rendered at all — so local development and the test
/// suite never load GA or send hits.
///
/// When enabled, the public site loads gtag.js behind **Google Consent Mode v2**
/// (all storage denied by default) and shows a cookie-consent banner; analytics
/// storage is only granted after the visitor accepts. The admin area does not
/// extend the public layout, so it is never tracked.
struct Analytics: Encodable {
    /// The GA4 Measurement ID, or an empty string when analytics is disabled.
    let measurementId: String
    /// Whether a Measurement ID is configured (drives rendering in the template).
    let enabled: Bool

    static func fromEnvironment() -> Analytics {
        let id = (Environment.get("GA_MEASUREMENT_ID") ?? "").trimmingCharacters(in: .whitespaces)
        return Analytics(measurementId: id, enabled: !id.isEmpty)
    }
}
