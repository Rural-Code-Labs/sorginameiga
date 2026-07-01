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

/// Single dog detail page with photos and the four-generation pedigree.
struct DogDetailContext: Encodable {
    let layout: LayoutContext
    let name: String
    /// Photo URLs; the first is the main photo, the rest are extras.
    let photos: [String]
    let pedigree: Pedigree
    /// "Volver" link back to the dog's sex listing.
    let backURL: String
}

/// A named block with a grid of photos (a gallery, or a puppy litter).
struct MediaBlock: Encodable {
    let title: String
    /// Optional badge shown after the title (e.g. availability for puppies).
    let badge: String?
    let photos: [String]
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
