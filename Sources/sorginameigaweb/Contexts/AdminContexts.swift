/// Admin login page. `error` is true after a failed attempt.
struct AdminLoginContext: Encodable {
    let error: Bool
}

/// Admin dashboard landing page.
struct AdminDashboardContext: Encodable {
    let username: String
}
