import Fluent
import Vapor

/// Admin CRUD for puppies, under `/admin/cachorros`. Replaces the legacy
/// `editar_cachorros*.php`. Photo management is handled in phase 6d.
final class AdminPuppyController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        let puppies = routes.grouped("cachorros")
        puppies.get(use: list)
        puppies.get("nuevo", use: newForm)
        puppies.post(use: create)
        puppies.get(":puppyID", "editar", use: editForm)
        puppies.post(":puppyID", use: update)
        puppies.post(":puppyID", "borrar", use: delete)
    }

    @Sendable
    func list(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        let puppies = try await Puppy.query(on: req.db).sort(\.$id).all()
        let rows = puppies.map { AdminPuppyRow(id: $0.id ?? 0, name: $0.name, available: $0.available) }
        return try await req.view.render("admin/puppies", AdminPuppiesContext(username: admin.username, puppies: rows))
    }

    @Sendable
    func newForm(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        return try await req.view.render("admin/puppy_form", AdminPuppyFormContext(
            username: admin.username,
            isNew: true,
            action: "/admin/cachorros",
            name: "",
            available: true
        ))
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let form = try req.content.decode(PuppyForm.self)
        let maxID = try await Puppy.query(on: req.db).max(\.$id) ?? 0
        try await Puppy(id: maxID + 1, name: form.name, available: form.isAvailable).create(on: req.db)
        return req.redirect(to: "/admin/cachorros")
    }

    @Sendable
    func editForm(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        guard let id = req.parameters.get("puppyID", as: Int.self),
              let puppy = try await Puppy.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return try await req.view.render("admin/puppy_form", AdminPuppyFormContext(
            username: admin.username,
            isNew: false,
            action: "/admin/cachorros/\(id)",
            name: puppy.name,
            available: puppy.available
        ))
    }

    @Sendable
    func update(req: Request) async throws -> Response {
        guard let id = req.parameters.get("puppyID", as: Int.self),
              let puppy = try await Puppy.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        let form = try req.content.decode(PuppyForm.self)
        puppy.name = form.name
        puppy.available = form.isAvailable
        try await puppy.save(on: req.db)
        return req.redirect(to: "/admin/cachorros")
    }

    @Sendable
    func delete(req: Request) async throws -> Response {
        guard let id = req.parameters.get("puppyID", as: Int.self),
              let puppy = try await Puppy.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        try await puppy.delete(on: req.db)
        PhotoStorage.removeFolder(PhotoKind.puppies.subpath(id: id), on: req)
        return req.redirect(to: "/admin/cachorros")
    }
}
