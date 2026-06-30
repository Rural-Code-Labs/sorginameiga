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
