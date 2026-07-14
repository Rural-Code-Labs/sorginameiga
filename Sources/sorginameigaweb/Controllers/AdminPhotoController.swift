import Fluent
import Foundation
import Vapor

/// Media management for dogs, puppies and galleries, under
/// `/admin/fotos/:kind/:id`. Shows one combined, reorderable grid of the owner's
/// photos (file-based) and embedded videos (YouTube/Vimeo), with per-item
/// upload/add, replace/edit, delete and ←/→ reorder. Improves on the legacy
/// `subirFoto.php` (upload only).
final class AdminPhotoController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        let photos = routes.grouped("fotos", ":kind", ":id")
        photos.get(use: manage)
        photos.on(.POST, body: .collect(maxSize: "10mb"), use: upload)
        photos.post("borrar", ":index", use: deletePhoto)
        // Replace a photo's file in place, keeping its position (phase 2.3).
        photos.on(.POST, "reemplazar", ":index", body: .collect(maxSize: "10mb"), use: replacePhoto)
        // Embedded videos (phase 2.3): add / edit URL / delete.
        photos.post("video", use: addVideo)
        photos.post("video", ":videoID", use: editVideo)
        photos.post("video", ":videoID", "borrar", use: deleteVideo)
        // Combined photo+video reorder (a video can be moved across the photos).
        photos.post("mover", ":handle", ":dir", use: moveCombined)
    }

    @Sendable
    func manage(req: Request) async throws -> View {
        let (kind, id) = try params(req)
        return try await renderManage(kind: kind, id: id, error: nil, on: req)
    }

    // MARK: - Photos

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
        return req.redirect(to: manageURL(kind, id))
    }

    /// Replaces an existing photo's bytes in place (same file name → same
    /// position). Writing new content bumps the file mtime, so the `?v=`
    /// cache-buster changes and browsers reload the image.
    @Sendable
    func replacePhoto(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard let index = req.parameters.get("index", as: Int.self) else {
            throw Abort(.badRequest)
        }
        let subpath = kind.subpath(id: id)
        guard PhotoDirectory.indices(in: subpath, on: req).contains(index) else {
            throw Abort(.notFound)
        }
        do {
            let form = try req.content.decode(PhotoUpload.self)
            try PhotoStorage.save(form.file, in: subpath, index: index, on: req)
        } catch let error as PhotoStorage.UploadError {
            let view = try await renderManage(kind: kind, id: id, error: error.description, on: req)
            return try await view.encodeResponse(status: .unprocessableEntity, for: req)
        }
        return req.redirect(to: manageURL(kind, id))
    }

    @Sendable
    func deletePhoto(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard let index = req.parameters.get("index", as: Int.self) else {
            throw Abort(.badRequest)
        }
        PhotoStorage.deletePhoto(in: kind.subpath(id: id), index: index, on: req)
        return req.redirect(to: manageURL(kind, id))
    }

    // MARK: - Videos

    /// Adds an embedded video from a pasted YouTube/Vimeo URL. New videos land
    /// after all photos; the admin can then reorder them in.
    @Sendable
    func addVideo(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard try await entityName(kind: kind, id: id, on: req) != nil else {
            throw Abort(.notFound)
        }
        guard let embed = VideoEmbed.parse(try req.content.decode(VideoForm.self).url) else {
            return try await invalidURL(kind: kind, id: id, on: req)
        }
        let photoCount = PhotoDirectory.indices(in: kind.subpath(id: id), on: req).count
        let maxSort = try await videoQuery(kind: kind, id: id, on: req).max(\.$sortOrder) ?? 0
        try await MediaVideo(
            kind: kind.rawValue,
            entityID: id,
            provider: embed.provider.rawValue,
            videoRef: embed.ref,
            photosBefore: photoCount,
            sortOrder: maxSort + 1
        ).create(on: req.db)
        return req.redirect(to: manageURL(kind, id))
    }

    /// Changes a video's URL in place, keeping its position.
    @Sendable
    func editVideo(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard let video = try await findVideo(req, kind: kind, id: id) else { throw Abort(.notFound) }
        guard let embed = VideoEmbed.parse(try req.content.decode(VideoForm.self).url) else {
            return try await invalidURL(kind: kind, id: id, on: req)
        }
        video.provider = embed.provider.rawValue
        video.videoRef = embed.ref
        try await video.save(on: req.db)
        return req.redirect(to: manageURL(kind, id))
    }

    @Sendable
    func deleteVideo(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard let video = try await findVideo(req, kind: kind, id: id) else { throw Abort(.notFound) }
        try await video.delete(on: req.db)
        return req.redirect(to: manageURL(kind, id))
    }

    // MARK: - Reordering

    /// Moves a photo or video one step left/right in the combined order,
    /// applying the mutation decided by `MediaLayout.reorderAction`.
    @Sendable
    func moveCombined(req: Request) async throws -> Response {
        let (kind, id) = try params(req)
        guard let raw = req.parameters.get("handle"), let handle = MediaHandle(raw),
              let dir = req.parameters.get("dir") else {
            throw Abort(.badRequest)
        }
        let direction: ReorderDirection = (dir == "izquierda") ? .up : .down

        let subpath = kind.subpath(id: id)
        let photoIndices = PhotoDirectory.indices(in: subpath, on: req)
        let videos = try await videoQuery(kind: kind, id: id, on: req).all()
        let merged = MediaLayout.merge(photoIndices: photoIndices, videos: videos)

        switch MediaLayout.reorderAction(in: merged, moving: handle, direction) {
        case let .swapPhotos(a, b):
            PhotoStorage.swap(in: subpath, a, b, on: req)
        case let .setVideoPhotosBefore(videoID, value):
            if let video = videos.first(where: { $0.id == videoID }) {
                video.photosBefore = min(max(value, 0), photoIndices.count)
                try await video.save(on: req.db)
            }
        case let .swapVideoOrder(aID, bID):
            if let a = videos.first(where: { $0.id == aID }),
               let b = videos.first(where: { $0.id == bID }) {
                (a.sortOrder, b.sortOrder) = (b.sortOrder, a.sortOrder)
                try await a.save(on: req.db)
                try await b.save(on: req.db)
            }
        case .none:
            break
        }
        return req.redirect(to: manageURL(kind, id))
    }

    // MARK: - Helpers

    private func params(_ req: Request) throws -> (PhotoKind, Int) {
        guard let raw = req.parameters.get("kind"), let kind = PhotoKind(rawValue: raw),
              let id = req.parameters.get("id", as: Int.self) else {
            throw Abort(.notFound)
        }
        return (kind, id)
    }

    private func manageURL(_ kind: PhotoKind, _ id: Int) -> String {
        "/admin/fotos/\(kind.rawValue)/\(id)"
    }

    private func videoQuery(kind: PhotoKind, id: Int, on req: Request) -> QueryBuilder<MediaVideo> {
        MediaVideo.query(on: req.db)
            .filter(\.$kind == kind.rawValue)
            .filter(\.$entityID == id)
    }

    /// Loads the `:videoID` for this owner, scoped to (kind, id) so a video
    /// can't be touched from another owner's URL.
    private func findVideo(_ req: Request, kind: PhotoKind, id: Int) async throws -> MediaVideo? {
        guard let videoID = req.parameters.get("videoID", as: Int.self),
              let video = try await MediaVideo.find(videoID, on: req.db),
              video.kind == kind.rawValue, video.entityID == id else {
            return nil
        }
        return video
    }

    private func invalidURL(kind: PhotoKind, id: Int, on req: Request) async throws -> Response {
        let view = try await renderManage(kind: kind, id: id,
            error: "La URL no es un vídeo de YouTube o Vimeo válido.", on: req)
        return try await view.encodeResponse(status: .unprocessableEntity, for: req)
    }

    private func renderManage(kind: PhotoKind, id: Int, error: String?, on req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        guard let name = try await entityName(kind: kind, id: id, on: req) else {
            throw Abort(.notFound)
        }
        let subpath = kind.subpath(id: id)
        // Admin thumbnails use a fresh per-render cache-buster instead of the
        // file's mtime: on the production GCS-mounted volume (gcsfuse) the mtime
        // can lag behind a write for a few seconds, so an mtime-based `?v=` would
        // show the cached image until a manual refresh. Admin is low-traffic.
        let bust = Int(Date().timeIntervalSince1970)
        let base = "/admin/fotos/\(kind.rawValue)/\(id)"
        let photoIndices = PhotoDirectory.indices(in: subpath, on: req)
        let videos = try await videoQuery(kind: kind, id: id, on: req).all()

        let mediaItems = MediaLayout.merge(photoIndices: photoIndices, videos: videos)
            .orderedRows { item, isFirst, isLast in
                switch item {
                case let .photo(index):
                    return AdminMediaItem(
                        kind: "photo", handle: "photo-\(index)",
                        thumb: "/\(subpath)/\(index).jpg?v=\(bust)",
                        isMain: kind == .dogs && index == 0,
                        deleteAction: "\(base)/borrar/\(index)",
                        replaceAction: "\(base)/reemplazar/\(index)",
                        editAction: "", editURL: "",
                        isFirst: isFirst, isLast: isLast
                    )
                case let .video(video):
                    return AdminMediaItem(
                        kind: "video", handle: "video-\(video.id ?? 0)",
                        thumb: video.thumbURL ?? "",
                        isMain: false,
                        deleteAction: "\(base)/video/\(video.id ?? 0)/borrar",
                        replaceAction: "",
                        editAction: "\(base)/video/\(video.id ?? 0)",
                        editURL: video.canonicalURL,
                        isFirst: isFirst, isLast: isLast
                    )
                }
            }

        return try await req.view.render("admin/photos", AdminPhotosContext(
            username: admin.username,
            kind: kind.rawValue,
            id: id,
            title: name,
            backURL: "/admin/\(kind.rawValue)",
            error: error,
            mediaItems: mediaItems
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
