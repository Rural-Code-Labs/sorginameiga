import Foundation
import Vapor

/// Discovers the numbered photos in a public image directory.
///
/// The legacy site stored photos as `1.jpg`, `2.jpg`, … alongside generated
/// thumbnails such as `1t.jpg`. This scans a directory once and returns the
/// public URLs of the real photos (whose file name is a plain integer),
/// sorted ascending, skipping the thumbnails.
enum PhotoDirectory {
    /// - Parameter subpath: directory relative to `Public/`, e.g. `images/galerias/7`.
    /// - Returns: URLs like `/images/galerias/7/1.jpg?v=…`, sorted by number.
    static func photos(in subpath: String, on req: Request) -> [String] {
        indices(in: subpath, on: req).map { url(in: subpath, index: $0, on: req) }
    }

    /// Public URL for a single photo, with a `?v=<mtime>` cache-buster. Because
    /// reordering swaps file *contents* while keeping the same file names, the
    /// URLs must change or browsers would keep showing the cached image (phase 9b).
    static func url(in subpath: String, index: Int, on req: Request) -> String {
        let path = req.application.directory.publicDirectory + subpath + "/\(index).jpg"
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = (attrs?[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970) }
        return "/\(subpath)/\(index).jpg" + (mtime.map { "?v=\($0)" } ?? "")
    }

    /// The photo numbers in a directory, sorted ascending. Display order follows
    /// this order, so it also drives the admin ↑/↓ reordering (phase 9b).
    static func indices(in subpath: String, on req: Request) -> [Int] {
        let base = req.application.directory.publicDirectory + subpath
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: base) else {
            return []
        }
        return files
            .compactMap { name -> Int? in
                guard name.hasSuffix(".jpg") else { return nil }
                return Int(name.dropLast(4)) // "1.jpg" -> 1; "1t.jpg" -> nil
            }
            .sorted()
    }
}
