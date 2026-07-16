import Vapor

extension Array {
    /// Maps each element to a row, tagging whether it is first/last so the admin
    /// views can hide the ↑/↓ reorder buttons at the ends of the list.
    func orderedRows<Row>(_ make: (Element, _ isFirst: Bool, _ isLast: Bool) -> Row) -> [Row] {
        enumerated().map { index, element in
            make(element, index == 0, index == count - 1)
        }
    }
}

/// Admin login page. `error` is true after a failed attempt.
struct AdminLoginContext: Encodable {
    let error: Bool
}

/// Admin dashboard landing page.
struct AdminDashboardContext: Encodable {
    let username: String
}

/// A row in the admin dog list. `isFirst`/`isLast` drive the ↑/↓ reorder
/// buttons (hidden at the ends of the list).
struct AdminDogRow: Encodable {
    let id: Int
    let name: String
    let isFirst: Bool
    let isLast: Bool
}

/// Admin dog list page. Dogs are grouped by sex because the public site lists
/// them separately, so reordering happens within each group.
struct AdminDogsContext: Encodable {
    let username: String
    let males: [AdminDogRow]
    let females: [AdminDogRow]
}

/// New / edit dog form. `action` is where the form posts; `isNew` toggles the
/// heading. For a new dog the fields are empty.
struct AdminDogFormContext: Encodable {
    let username: String
    let isNew: Bool
    let action: String
    let name: String
    let sex: String
    let pedigree: Pedigree
}

// MARK: - Puppies

struct AdminPuppyRow: Encodable {
    let id: Int
    let name: String
    let available: Bool
    let isFirst: Bool
    let isLast: Bool
}

struct AdminPuppiesContext: Encodable {
    let username: String
    let puppies: [AdminPuppyRow]
}

struct AdminPuppyFormContext: Encodable {
    let username: String
    let isNew: Bool
    let action: String
    let name: String
    let available: Bool
}

/// Submitted puppy form. `available` arrives as the select value "1" / "0".
struct PuppyForm: Content {
    var name: String
    var available: String

    var isAvailable: Bool { available == "1" }
}

// MARK: - Galleries

struct AdminGalleryRow: Encodable {
    let id: Int
    let name: String
    let isFirst: Bool
    let isLast: Bool
}

struct AdminGalleriesContext: Encodable {
    let username: String
    let galleries: [AdminGalleryRow]
}

struct AdminGalleryFormContext: Encodable {
    let username: String
    let isNew: Bool
    let action: String
    let name: String
}

struct GalleryForm: Content {
    var name: String
}

// MARK: - Photos & videos

/// Media management page (`/admin/fotos/:kind/:id`) for dogs, puppies and
/// galleries: one combined, reorderable grid of photos and videos.
struct AdminPhotosContext: Encodable {
    let username: String
    let kind: String
    let id: Int
    let title: String
    let backURL: String
    let error: String?
    let mediaItems: [AdminMediaItem]
}

/// A cell in the combined photo+video admin grid.
struct AdminMediaItem: Encodable {
    let kind: String          // "photo" | "video"
    /// Reorder handle, e.g. "photo-3" / "video-7".
    let handle: String
    /// Thumbnail URL (empty for a video without a provider thumbnail).
    let thumb: String
    /// True for a dog's main/cover photo (the first one).
    let isMain: Bool
    /// Where the per-item delete form posts.
    let deleteAction: String
    /// Photos only: where the "replace file" form posts (empty for videos).
    let replaceAction: String
    /// Videos only: canonical URL used to pre-fill the "edit URL" form (empty
    /// for photos) — also the POST target for the edit.
    let editAction: String
    let editURL: String
    let isFirst: Bool
    let isLast: Bool
}

/// A single-file photo upload (also used to replace an existing photo).
struct PhotoUpload: Content {
    var file: File
}

/// Submitted "add / edit video" form: a pasted YouTube/Vimeo URL.
struct VideoForm: Content {
    var url: String
}

// MARK: - Stats

/// Admin stats page (`/admin/estadisticas`): Google Analytics visit data.
struct AdminStatsContext: Encodable {
    let username: String
    /// False when `GA_PROPERTY_ID` is unset (local/dev) → shows a notice.
    let configured: Bool
    /// Friendly message when a fetch fails (403, network); nil on success.
    let error: String?
    /// True when we have real data to show (configured, no error).
    let hasData: Bool
    /// Legacy site-wide visit counter (the number shown in the public footer):
    /// total page views accumulated since the site's birth. nil if the DB read
    /// fails. Independent from the Google Analytics figures below.
    let legacyCount: Int?
    let today: Int
    let last7: Int
    let last30: Int
    /// Total sessions over the last 12 months (sum of the monthly series).
    let lastYear: Int
    let activeNow: Int
    /// Pre-rendered inline SVG of the 30-day trend (output with `#unsafeHTML`).
    let chartSVG: String
    /// Pre-rendered inline SVG of the 12-month trend.
    let monthlyChartSVG: String
    /// Breakdowns (last 30 days). Countries carry a flag emoji in `label`.
    let countries: [LabelCount]
    let channels: [LabelCount]
    let devices: [LabelCount]
}

// MARK: - Dogs

/// Submitted dog form. HTML always sends every named field (empty = ""), so the
/// pedigree fields are plain (non-optional) strings.
struct DogForm: Content {
    var name: String
    var sex: String
    var a: String, b: String
    var aa: String, ab: String, ba: String, bb: String
    var aaa: String, aab: String, aba: String, abb: String
    var baa: String, bab: String, bba: String, bbb: String

    var pedigree: Pedigree {
        Pedigree(
            a: a, b: b,
            aa: aa, ab: ab, ba: ba, bb: bb,
            aaa: aaa, aab: aab, aba: aba, abb: abb,
            baa: baa, bab: bab, bba: bba, bbb: bbb
        )
    }
}
