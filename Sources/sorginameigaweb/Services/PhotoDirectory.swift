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
    /// - Returns: URLs like `/images/galerias/7/1.jpg`, sorted by number.
    static func photos(in subpath: String, on req: Request) -> [String] {
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
            .map { "/\(subpath)/\($0).jpg" }
    }
}
