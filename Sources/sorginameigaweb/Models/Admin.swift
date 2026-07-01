import Fluent
import Vapor

/// An administrator account. Replaces the legacy `administracion` table, but
/// stores a **bcrypt hash** instead of the legacy plain-text password, and is
/// authenticated via server-side sessions rather than a 2-hour cookie.
final class Admin: Model, @unchecked Sendable {
    static let schema = "admins"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "password_hash")
    var passwordHash: String

    init() {}

    init(id: UUID? = nil, username: String, passwordHash: String) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
    }
}

/// Persists the logged-in admin in the session (by id).
extension Admin: ModelSessionAuthenticatable {}
