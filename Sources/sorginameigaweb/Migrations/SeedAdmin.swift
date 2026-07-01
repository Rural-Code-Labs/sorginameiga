import Fluent
import Vapor

/// Seeds the initial administrator, hashing the password with bcrypt.
///
/// The password comes from the `ADMIN_PASSWORD` environment variable (see
/// `configure`), so no real password is ever stored in the repository. The
/// legacy plain-text password is intentionally not migrated; the owners set a
/// fresh one. To change it later, use the admin UI (or revert + re-run this).
struct SeedAdmin: AsyncMigration {
    let username: String
    let password: String

    func prepare(on database: any Database) async throws {
        let hash = try Bcrypt.hash(password)
        try await Admin(username: username, passwordHash: hash).create(on: database)
    }

    func revert(on database: any Database) async throws {
        try await Admin.query(on: database).filter(\.$username == username).delete()
    }
}
