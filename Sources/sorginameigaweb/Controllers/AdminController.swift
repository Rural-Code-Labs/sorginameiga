import Fluent
import Vapor

/// Admin area: session-based login/logout and the dashboard.
///
/// Replaces the legacy `admin/` auth (plain-text password compared against the
/// `administracion` table, plus a 2-hour `usuario_sorgina` cookie). Here the
/// password is verified with bcrypt and the session is server-side. Routes
/// under `/admin` (except `/admin/login`) are protected by a redirect middleware.
final class AdminController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        let admin = routes.grouped("admin").grouped(Admin.sessionAuthenticator())

        // Public: login form + submit.
        admin.get("login", use: loginForm)
        admin.post("login", use: login)

        // Protected: everything else under /admin.
        let protected = admin.grouped(Admin.redirectMiddleware(path: "/admin/login"))
        protected.get(use: dashboard)
        protected.post("logout", use: logout)
    }

    @Sendable
    func loginForm(req: Request) async throws -> Response {
        // Already logged in → go straight to the dashboard.
        if req.auth.has(Admin.self) {
            return req.redirect(to: "/admin")
        }
        let view = try await req.view.render("admin/login", AdminLoginContext(error: false))
        return try await view.encodeResponse(for: req)
    }

    @Sendable
    func login(req: Request) async throws -> Response {
        let input = try req.content.decode(LoginInput.self)
        guard
            let admin = try await Admin.query(on: req.db)
                .filter(\.$username == input.username)
                .first(),
            try Bcrypt.verify(input.password, created: admin.passwordHash)
        else {
            let view = try await req.view.render("admin/login", AdminLoginContext(error: true))
            return try await view.encodeResponse(status: .unauthorized, for: req)
        }
        // Log in for this request; the session authenticator middleware persists
        // it to the session on the response.
        req.auth.login(admin)
        return req.redirect(to: "/admin")
    }

    @Sendable
    func logout(req: Request) async throws -> Response {
        req.auth.logout(Admin.self)
        return req.redirect(to: "/admin/login")
    }

    @Sendable
    func dashboard(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        return try await req.view.render("admin/dashboard", AdminDashboardContext(username: admin.username))
    }
}

/// Login form submission.
struct LoginInput: Content {
    let username: String
    let password: String
}
