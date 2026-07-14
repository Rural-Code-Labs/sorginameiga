import Foundation

/// Supported embedded-video providers.
enum VideoProvider: String, Sendable {
    case youtube
    case vimeo
}

/// A parsed video reference: a provider plus the provider's own video id.
struct VideoEmbed: Equatable, Sendable {
    let provider: VideoProvider
    let ref: String

    /// Parses a pasted YouTube/Vimeo URL into a provider + id, or returns `nil`
    /// if the URL is not a recognised video link. Accepts the common shapes:
    /// `youtube.com/watch?v=ID`, `youtu.be/ID`, `youtube.com/embed/ID`,
    /// `youtube.com/shorts/ID`, `vimeo.com/ID`, `player.vimeo.com/video/ID`
    /// (with or without scheme, `www.`, or trailing query/params).
    static func parse(_ raw: String) -> VideoEmbed? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Normalise to a URLComponents by prepending a scheme when missing.
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme),
              let host = components.host?.lowercased() else { return nil }

        let path = components.path
        let segments = path.split(separator: "/").map(String.init)

        if host == "youtu.be" {
            return segments.first.flatMap { youtube($0) }
        }
        if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return youtube(v)
            }
            // /embed/ID, /shorts/ID, /v/ID
            if let marker = segments.firstIndex(where: { ["embed", "shorts", "v"].contains($0) }),
               segments.indices.contains(marker + 1) {
                return youtube(segments[marker + 1])
            }
            return nil
        }
        if host.hasSuffix("vimeo.com") {
            // player.vimeo.com/video/ID  or  vimeo.com/ID
            if let marker = segments.firstIndex(of: "video"), segments.indices.contains(marker + 1) {
                return vimeo(segments[marker + 1])
            }
            if let first = segments.first(where: { $0.allSatisfy(\.isNumber) }) {
                return vimeo(first)
            }
            return nil
        }
        return nil
    }

    private static func youtube(_ id: String) -> VideoEmbed? {
        let ref = sanitize(id)
        // YouTube ids are 11 URL-safe base64 chars.
        guard ref.count == 11, ref.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return nil
        }
        return VideoEmbed(provider: .youtube, ref: ref)
    }

    private static func vimeo(_ id: String) -> VideoEmbed? {
        let ref = sanitize(id)
        guard !ref.isEmpty, ref.allSatisfy(\.isNumber) else { return nil }
        return VideoEmbed(provider: .vimeo, ref: ref)
    }

    /// Drops any leftover query/fragment stuck to a path segment (e.g. an id
    /// captured as `ID?t=30`).
    private static func sanitize(_ id: String) -> String {
        String(id.prefix { $0 != "?" && $0 != "&" && $0 != "#" })
    }
}
