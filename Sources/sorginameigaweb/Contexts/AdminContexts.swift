import Vapor

/// Admin login page. `error` is true after a failed attempt.
struct AdminLoginContext: Encodable {
    let error: Bool
}

/// Admin dashboard landing page.
struct AdminDashboardContext: Encodable {
    let username: String
}

/// A row in the admin dog list.
struct AdminDogRow: Encodable {
    let id: Int
    let name: String
}

/// Admin dog list page.
struct AdminDogsContext: Encodable {
    let username: String
    let dogs: [AdminDogRow]
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

// MARK: - Photos

struct AdminPhotoItem: Encodable {
    let index: Int
    let url: String
    /// True for a dog's main photo (index 0).
    let isMain: Bool
}

struct AdminPhotosContext: Encodable {
    let username: String
    let kind: String
    let id: Int
    let title: String
    let photos: [AdminPhotoItem]
    let backURL: String
    let error: String?
}

/// A single-file photo upload.
struct PhotoUpload: Content {
    var file: File
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
