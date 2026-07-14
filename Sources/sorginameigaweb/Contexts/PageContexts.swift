/// Home page ("¿Quiénes Somos?"). The body reads `layout.t.presentation`.
struct HomeContext: Encodable {
    let layout: LayoutContext
}

/// A dog's thumbnail card in a listing.
struct DogCard: Encodable {
    let id: Int
    let name: String
    /// Main photo URL, e.g. `/images/22/0.jpg`.
    let photo: String
    /// Detail page URL, e.g. `/perro/22` or `/en/dog/22`.
    let url: String
}

/// Dogs listing page (`/machos`, `/hembras` and English equivalents).
struct DogsPageContext: Encodable {
    let layout: LayoutContext
    /// Section heading ("Machos" / "Hembras" / "Males" / "Females").
    let title: String
    let dogs: [DogCard]
}

/// Single dog detail page with media and the four-generation pedigree.
struct DogDetailContext: Encodable {
    let layout: LayoutContext
    let name: String
    /// The large cover: always the dog's first photo (matches the listing card).
    /// nil only if the dog has no photos at all.
    let cover: MediaItem?
    /// Remaining photos and videos, interleaved and ordered, shown as thumbs.
    let thumbs: [MediaItem]
    let pedigree: Pedigree
    /// "Volver" link back to the dog's sex listing.
    let backURL: String
}

/// One cell in a media block: a photo or an embedded video. Puppies only ever
/// produce photos; galleries can mix in videos (phase 2.3).
struct MediaItem: Encodable {
    /// "photo" or "video" — drives the template branch.
    let kind: String
    /// Lightbox target: the photo URL, or the video embed URL.
    let href: String
    /// Image shown in the grid: the photo, or a video thumbnail. Empty for a
    /// video without a provider thumbnail (rendered as a placeholder tile).
    let thumb: String
    /// Embed URL for videos (mounted in an `<iframe>` by the lightbox); nil for
    /// photos.
    let embed: String?
    let alt: String

    static func photo(url: String, alt: String) -> MediaItem {
        MediaItem(kind: "photo", href: url, thumb: url, embed: nil, alt: alt)
    }

    static func video(_ video: MediaVideo, alt: String) -> MediaItem {
        MediaItem(kind: "video", href: video.embedURL, thumb: video.thumbURL ?? "", embed: video.embedURL, alt: alt)
    }
}

/// A named block with a grid of media items (a gallery, or a puppy litter).
struct MediaBlock: Encodable {
    let title: String
    /// Optional badge shown after the title (e.g. availability for puppies).
    let badge: String?
    let items: [MediaItem]
}

/// Galleries page (`/galeria`, `/en/gallery`) and puppies page
/// (`/cachorros`, `/en/puppies`): a heading and a list of media blocks.
struct MediaPageContext: Encodable {
    let layout: LayoutContext
    /// Section heading ("Galeria de fotos" / "Cachorros" / …).
    let title: String
    let blocks: [MediaBlock]
    /// Message shown when there are no blocks.
    let emptyMessage: String
}

/// Contact page (`/contacto`, `/en/contact`): contact details only, matching
/// the current production site (the legacy form was removed).
struct ContactContext: Encodable {
    let layout: LayoutContext
    let title: String
    /// Intro text ("write us by email, call us or contact us via WhatsApp").
    let text: String
    let email: String
    let phones: [String]
}
