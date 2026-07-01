import Fluent
import Vapor

/// Creates or updates an admin account's bcrypt password.
///
/// The password comes from `--password` or the `ADMIN_PASSWORD` env var, so the
/// plain text never has to be stored. Used to set the real admin password after
/// the initial seed (which used a placeholder), and to rotate it later.
///
///     swift run sorginameigaweb admin-password "Pilar&Estibaliz" --password "…"
struct AdminPasswordCommand: AsyncCommand {
    struct Signature: CommandSignature {
        @Argument(name: "username", help: "Admin username")
        var username: String

        @Option(name: "password", help: "New password (or set ADMIN_PASSWORD)")
        var password: String?
    }

    var help: String { "Create or update an admin's bcrypt password." }

    func run(using context: CommandContext, signature: Signature) async throws {
        let db = context.application.db
        guard let password = signature.password ?? Environment.get("ADMIN_PASSWORD"), !password.isEmpty else {
            context.console.error("Provide --password or set ADMIN_PASSWORD.")
            return
        }
        let hash = try Bcrypt.hash(password)

        if let admin = try await Admin.query(on: db).filter(\.$username == signature.username).first() {
            admin.passwordHash = hash
            try await admin.save(on: db)
            context.console.success("Updated password for '\(signature.username)'.")
        } else {
            try await Admin(username: signature.username, passwordHash: hash).create(on: db)
            context.console.success("Created admin '\(signature.username)'.")
        }
    }
}
