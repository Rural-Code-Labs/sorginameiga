import Fluent
import Vapor

/// Admin CRUD for dogs, under `/admin/perros` (registered on the protected
/// admin group). Replaces the legacy `editar_perros*.php`.
///
/// Photo management is handled separately (phase 6d); this covers the record
/// and its four-generation pedigree only.
final class AdminDogController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        let dogs = routes.grouped("perros")
        dogs.get(use: list)
        dogs.get("nuevo", use: newForm)
        dogs.post(use: create)
        dogs.get(":dogID", "editar", use: editForm)
        dogs.post(":dogID", use: update)
        dogs.post(":dogID", "borrar", use: delete)
    }

    @Sendable
    func list(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        let dogs = try await Dog.query(on: req.db).sort(\.$id).all()
        let rows = dogs.map { AdminDogRow(id: $0.id ?? 0, name: $0.name) }
        return try await req.view.render("admin/dogs", AdminDogsContext(username: admin.username, dogs: rows))
    }

    @Sendable
    func newForm(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        return try await req.view.render("admin/dog_form", AdminDogFormContext(
            username: admin.username,
            isNew: true,
            action: "/admin/perros",
            name: "",
            sex: Sex.male.rawValue,
            pedigree: .empty
        ))
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let form = try req.content.decode(DogForm.self)
        let maxID = try await Dog.query(on: req.db).max(\.$id) ?? 0
        let dog = Dog(id: maxID + 1, name: form.name, sex: form.sex, pedigree: form.pedigree)
        try await dog.create(on: req.db)
        return req.redirect(to: "/admin/perros")
    }

    @Sendable
    func editForm(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        guard let id = req.parameters.get("dogID", as: Int.self),
              let dog = try await Dog.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        return try await req.view.render("admin/dog_form", AdminDogFormContext(
            username: admin.username,
            isNew: false,
            action: "/admin/perros/\(id)",
            name: dog.name,
            sex: dog.sex,
            pedigree: dog.pedigree
        ))
    }

    @Sendable
    func update(req: Request) async throws -> Response {
        guard let id = req.parameters.get("dogID", as: Int.self),
              let dog = try await Dog.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        let form = try req.content.decode(DogForm.self)
        dog.name = form.name
        dog.sex = form.sex
        dog.pedigree = form.pedigree
        try await dog.save(on: req.db)
        return req.redirect(to: "/admin/perros")
    }

    @Sendable
    func delete(req: Request) async throws -> Response {
        guard let id = req.parameters.get("dogID", as: Int.self),
              let dog = try await Dog.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        try await dog.delete(on: req.db)
        PhotoStorage.removeFolder(PhotoKind.dogs.subpath(id: id), on: req)
        return req.redirect(to: "/admin/perros")
    }
}
