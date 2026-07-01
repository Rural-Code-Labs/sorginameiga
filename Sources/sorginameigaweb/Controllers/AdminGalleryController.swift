import Fluent
import Vapor

/// Admin CRUD for photo galleries, under `/admin/galerias`. Replaces the legacy
/// `editar_galerias*.php`. Photo management is handled in phase 6d.
final class AdminGalleryController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        let galleries = routes.grouped("galerias")
        galleries.get(use: list)
        galleries.get("nueva", use: newForm)
        galleries.post(use: create)
        galleries.get(":galleryID", "editar", use: editForm)
        galleries.post(":galleryID", use: update)
        galleries.post(":galleryID", "borrar", use: delete)
    }

    @Sendable
    func list(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        let galleries = try await Gallery.query(on: req.db).sort(\.$id).all()
        let rows = galleries.map { AdminGalleryRow(id: $0.id ?? 0, name: $0.name) }
        return try await req.view.render("admin/galleries", AdminGalleriesContext(username: admin.username, galleries: rows))
    }

    @Sendable
    func newForm(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        return try await req.view.render("admin/gallery_form", AdminGalleryFormContext(
            username: admin.username,
            isNew: true,
            action: "/admin/galerias",
            name: ""
        ))
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let form = try req.content.decode(GalleryForm.self)
        let maxID = try await Gallery.query(on: req.db).max(\.$id) ?? 0
        try await Gallery(id: maxID + 1, name: form.name).create(on: req.db)
        return req.redirect(to: "/admin/galerias")
    }

    @Sendable
    func editForm(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        guard let id = req.parameters.get("galleryID", as: Int.self),
              let gallery = try await Gallery.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return try await req.view.render("admin/gallery_form", AdminGalleryFormContext(
            username: admin.username,
            isNew: false,
            action: "/admin/galerias/\(id)",
            name: gallery.name
        ))
    }

    @Sendable
    func update(req: Request) async throws -> Response {
        guard let id = req.parameters.get("galleryID", as: Int.self),
              let gallery = try await Gallery.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        let form = try req.content.decode(GalleryForm.self)
        gallery.name = form.name
        try await gallery.save(on: req.db)
        return req.redirect(to: "/admin/galerias")
    }

    @Sendable
    func delete(req: Request) async throws -> Response {
        guard let id = req.parameters.get("galleryID", as: Int.self),
              let gallery = try await Gallery.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        try await gallery.delete(on: req.db)
        PhotoStorage.removeFolder(PhotoKind.galleries.subpath(id: id), on: req)
        return req.redirect(to: "/admin/galerias")
    }
}
