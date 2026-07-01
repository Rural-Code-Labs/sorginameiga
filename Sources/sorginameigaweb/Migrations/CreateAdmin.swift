import Fluent

/// Creates the `admins` table (username + bcrypt password hash).
struct CreateAdmin: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(Admin.schema)
            .id()
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .unique(on: "username")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(Admin.schema).delete()
    }
}
