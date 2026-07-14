import Fluent

/// An embedded video (YouTube / Vimeo) belonging to a dog, puppy or gallery.
/// Videos are not files: they are references to an external provider, so they
/// live in the database rather than on the image volume (phase 2.3).
///
/// A video is attached to its owner by (`kind`, `entityID`) — the same pair the
/// file-based photos use via `PhotoKind.subpath(id:)` — so the same model serves
/// all three owners. Its position within the owner's media is encoded by:
/// - `photosBefore`: how many of the owner's photos are shown before this video
///   (0 = before all photos, `photoCount` = after all of them).
/// - `sortOrder`: tiebreaker ordering videos that share the same `photosBefore`.
final class MediaVideo: Model, @unchecked Sendable {
    static let schema = "media_videos"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    /// Owner kind: `perros` / `cachorros` / `galerias` (see `PhotoKind`).
    @Field(key: "kind")
    var kind: String

    /// Owner id (dog / puppy / gallery id).
    @Field(key: "entity_id")
    var entityID: Int

    /// Video provider: `youtube` or `vimeo` (see `VideoProvider`).
    @Field(key: "provider")
    var provider: String

    /// The provider's video id (already extracted from the pasted URL).
    @Field(key: "video_ref")
    var videoRef: String

    /// Number of the owner's photos shown before this video.
    @Field(key: "photos_before")
    var photosBefore: Int

    /// Orders videos that share the same `photosBefore`.
    @Field(key: "sort_order")
    var sortOrder: Int

    init() {}

    init(id: Int? = nil, kind: String, entityID: Int, provider: String, videoRef: String, photosBefore: Int, sortOrder: Int) {
        self.id = id
        self.kind = kind
        self.entityID = entityID
        self.provider = provider
        self.videoRef = videoRef
        self.photosBefore = photosBefore
        self.sortOrder = sortOrder
    }

    /// Public URL of the embeddable player, for the lightbox `<iframe>`.
    var embedURL: String {
        switch VideoProvider(rawValue: provider) {
        case .youtube: return "https://www.youtube.com/embed/\(videoRef)"
        case .vimeo: return "https://player.vimeo.com/video/\(videoRef)"
        case .none: return ""
        }
    }

    /// Grid thumbnail. YouTube exposes a static thumbnail URL; Vimeo does not
    /// (it needs an API call), so it falls back to a CSS placeholder tile.
    var thumbURL: String? {
        switch VideoProvider(rawValue: provider) {
        case .youtube: return "https://img.youtube.com/vi/\(videoRef)/hqdefault.jpg"
        case .vimeo, .none: return nil
        }
    }

    /// A canonical watch URL rebuilt from provider + ref, used to pre-fill the
    /// admin "edit URL" field.
    var canonicalURL: String {
        switch VideoProvider(rawValue: provider) {
        case .youtube: return "https://www.youtube.com/watch?v=\(videoRef)"
        case .vimeo: return "https://vimeo.com/\(videoRef)"
        case .none: return ""
        }
    }
}
