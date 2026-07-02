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
        dogs.post(":dogID", "subir", use: moveUp)
        dogs.post(":dogID", "bajar", use: moveDown)
    }

    @Sendable
    func list(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        let dogs = try await Dog.query(on: req.db).sort(\.$position).all()
        func rows(_ sex: Sex) -> [AdminDogRow] {
            dogs.filter { $0.sex == sex.rawValue }
                .orderedRows { dog, isFirst, isLast in
                    AdminDogRow(id: dog.id ?? 0, name: dog.name, isFirst: isFirst, isLast: isLast)
                }
        }
        return try await req.view.render("admin/dogs", AdminDogsContext(
            username: admin.username,
            males: rows(.male),
            females: rows(.female)
        ))
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
        // New dogs go last within their sex.
        let maxPosition = try await Dog.query(on: req.db)
            .filter(\.$sex == form.sex).max(\.$position) ?? 0
        let dog = Dog(id: maxID + 1, name: form.name, sex: form.sex, pedigree: form.pedigree, position: maxPosition + 1)
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

    // MARK: - Reordering

    @Sendable func moveUp(req: Request) async throws -> Response { try await move(.up, on: req) }
    @Sendable func moveDown(req: Request) async throws -> Response { try await move(.down, on: req) }

    /// Swaps the dog's position with its neighbour of the same sex, moving it one
    /// step up or down in that sex's listing. No-op at the ends.
    private func move(_ direction: ReorderDirection, on req: Request) async throws -> Response {
        guard let id = req.parameters.get("dogID", as: Int.self),
              let dog = try await Dog.find(id, on: req.db) else {
            throw Abort(.notFound)
        }
        let neighbours = Dog.query(on: req.db).filter(\.$sex == dog.sex)
        let neighbour: Dog?
        switch direction {
        case .up:
            neighbour = try await neighbours.filter(\.$position < dog.position)
                .sort(\.$position, .descending).first()
        case .down:
            neighbour = try await neighbours.filter(\.$position > dog.position)
                .sort(\.$position, .ascending).first()
        }
        if let neighbour {
            (dog.position, neighbour.position) = (neighbour.position, dog.position)
            try await dog.save(on: req.db)
            try await neighbour.save(on: req.db)
        }
        return req.redirect(to: "/admin/perros")
    }
}
