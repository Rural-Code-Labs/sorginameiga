import Foundation
import Vapor

/// The three kinds of entity that own a photo folder, and where those folders
/// live under `Public/`.
enum PhotoKind: String, Sendable {
    case dogs = "perros"
    case puppies = "cachorros"
    case galleries = "galerias"

    /// Public subpath of an entity's photo folder.
    func subpath(id: Int) -> String {
        switch self {
        case .dogs: return "images/\(id)"
        case .puppies: return "images/cachorros/\(id)"
        case .galleries: return "images/galerias/\(id)"
        }
    }

    /// First photo number when the folder is empty. Dogs start at 0 (0.jpg is
    /// the main photo); puppies and galleries start at 1 (legacy convention).
    var startIndex: Int { self == .dogs ? 0 : 1 }
}

/// Reads and writes entity photos on disk, with upload validation.
enum PhotoStorage {
    static let maxBytes = 10 * 1024 * 1024 // 10 MB

    enum UploadError: Error, CustomStringConvertible {
        case empty, tooLarge, notJPEG

        var description: String {
            switch self {
            case .empty: return "El archivo está vacío."
            case .tooLarge: return "La imagen supera el tamaño máximo (10 MB)."
            case .notJPEG: return "El archivo debe ser una imagen JPEG."
            }
        }
    }

    /// Next free photo number in a folder (max existing + 1, or `startAt`).
    static func nextIndex(in subpath: String, startAt: Int, on req: Request) -> Int {
        let base = req.application.directory.publicDirectory + subpath
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: base) else { return startAt }
        let numbers = files.compactMap { $0.hasSuffix(".jpg") ? Int($0.dropLast(4)) : nil }
        return numbers.max().map { $0 + 1 } ?? startAt
    }

    /// Validates a JPEG upload and writes it as `<index>.jpg` in the folder.
    static func save(_ file: File, in subpath: String, index: Int, on req: Request) throws {
        guard file.data.readableBytes > 0 else { throw UploadError.empty }
        guard file.data.readableBytes <= maxBytes else { throw UploadError.tooLarge }
        // Verify JPEG magic bytes (FF D8 FF) — don't trust the extension.
        let magic = file.data.getBytes(at: file.data.readerIndex, length: 3)
        guard magic == [0xFF, 0xD8, 0xFF] else { throw UploadError.notJPEG }

        let dir = req.application.directory.publicDirectory + subpath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let bytes = file.data.getBytes(at: file.data.readerIndex, length: file.data.readableBytes) ?? []
        try Data(bytes).write(to: URL(fileURLWithPath: dir + "/\(index).jpg"))
    }

    /// Deletes a single photo (best-effort).
    static func deletePhoto(in subpath: String, index: Int, on req: Request) {
        let path = req.application.directory.publicDirectory + subpath + "/\(index).jpg"
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Removes an entity's whole photo folder (used when the record is deleted).
    static func removeFolder(_ subpath: String, on req: Request) {
        let dir = req.application.directory.publicDirectory + subpath
        try? FileManager.default.removeItem(atPath: dir)
    }
}
