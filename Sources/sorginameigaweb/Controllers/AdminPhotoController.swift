import Fluent
import Vapor

/// Photo management for dogs, puppies and galleries, under
/// `/admin/fotos/:kind/:id`. Shows the current photos with per-photo delete and
/// an upload form. Improves on the legacy `subirFoto.php` (upload only) by also
/// allowing individual deletion.
final class AdminPhotoController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        let photos = routes.grouped("fotos", ":kind", ":id")
        photos.get(use: manage)
        photos.on(.POST, body: .collect(maxSize: "10mb"), use: upload)
        photos.post("borrar", ":index", use: deletePhoto)
    }

    @Sendable
    func manage(req: Request) async throws -> View {
        let (kind, id) = try params(req)
        return try await renderManage(kind: kind, id: id, error: nil, on: req)
    }

    @Sendable
    func upload(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard try await entityName(kind: kind, id: id, on: req) != nil else {
            throw Abort(.notFound)
        }
        let subpath = kind.subpath(id: id)
        do {
            let form = try req.content.decode(PhotoUpload.self)
            let index = PhotoStorage.nextIndex(in: subpath, startAt: kind.startIndex, on: req)
            try PhotoStorage.save(form.file, in: subpath, index: index, on: req)
        } catch let error as PhotoStorage.UploadError {
            let view = try await renderManage(kind: kind, id: id, error: error.description, on: req)
            return try await view.encodeResponse(status: .unprocessableEntity, for: req)
        }
        return req.redirect(to: "/admin/fotos/\(kind.rawValue)/\(id)")
    }

    @Sendable
    func deletePhoto(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard let index = req.parameters.get("index", as: Int.self) else {
            throw Abort(.badRequest)
        }
        PhotoStorage.deletePhoto(in: kind.subpath(id: id), index: index, on: req)
        return req.redirect(to: "/admin/fotos/\(kind.rawValue)/\(id)")
    }

    // MARK: - Helpers

    private func params(_ req: Request) throws -> (PhotoKind, Int) {
        guard let raw = req.parameters.get("kind"), let kind = PhotoKind(rawValue: raw),
              let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.notFound)
        }
        return (kind, id)
    }

    private func renderManage(kind: PhotoKind, id: Int, error: String?, on req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        guard let name = try await entityName(kind: kind, id: id, on: req) else {
            throw Abort(.notFound)
        }
        let subpath = kind.subpath(id: id)
        let photos = PhotoDirectory.photos(in: subpath, on: req).enumerated().map { _, url -> AdminPhotoItem in
            // Recover the index from the file name (…/<index>.jpg).
            let index = Int(url.split(separator: "/").last?.dropLast(4) ?? "0") ?? 0
            return AdminPhotoItem(index: index, url: url, isMain: kind == .dogs && index == 0)
        }
        return try await req.view.render("admin/photos", AdminPhotosContext(
            username: admin.username,
            kind: kind.rawValue,
            id: id,
            title: name,
            photos: photos,
            backURL: "/admin/\(kind.rawValue)",
            error: error
        ))
    }

    private func entityName(kind: PhotoKind, id: Int, on req: Request) async throws -> String? {
        switch kind {
        case .dogs: return try await Dog.find(id, on: req.db)?.name
        case .puppies: return try await Puppy.find(id, on: req.db)?.name
        case .galleries: return try await Gallery.find(id, on: req.db)?.name
        }
    }
}
