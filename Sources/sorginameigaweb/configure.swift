import Fluent
import FluentPostgresDriver
import Leaf
import Vapor

/// Configures the application.
///
/// Phase 2 introduces the data layer: Postgres + Fluent models for the legacy
/// tables, with the production data shipped as a seed (see `LegacySeed`).
func configure(_ app: Application) async throws {
    // Serve static files (CSS, images) from the /Public folder.
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Database. In production, set DATABASE_URL to the (pooled) Neon connection
    // string — it carries `sslmode=require`, which Neon enforces. Locally, the
    // individual DATABASE_* vars target the docker-compose Postgres (no TLS).
    let postgresConfiguration: SQLPostgresConfiguration
    if let databaseURL = Environment.get("DATABASE_URL") {
        postgresConfiguration = try SQLPostgresConfiguration(url: databaseURL)
    } else {
        postgresConfiguration = SQLPostgresConfiguration(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
            password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
            database: Environment.get("DATABASE_NAME") ?? "vapor_database",
            tls: .prefer(try .init(configuration: .clientDefault))
        )
    }
    app.databases.use(.postgres(configuration: postgresConfiguration), as: .psql)

    // Sessions, persisted in Postgres so admin logins survive across Cloud Run
    // instances / restarts.
    app.sessions.use(.fluent)
    app.middleware.use(app.sessions.middleware)

    // Migrations: schema + legacy data seed, then sessions and admin.
    app.migrations.add(CreateInitialSchema())
    app.migrations.add(AddPositionFields())
    app.migrations.add(SeedLegacyData(seed: try LegacySeed.load(from: app)))
    app.migrations.add(SessionRecord.migration)
    app.migrations.add(CreateAdmin())
    app.migrations.add(SeedAdmin(
        username: "Pilar&Estibaliz",
        password: Environment.get("ADMIN_PASSWORD") ?? "changeme"
    ))

    // Shared, request-independent localization service.
    app.localization = LocalizationService()

    app.views.use(.leaf)

    // CLI: set/rotate the admin password (used after the placeholder seed).
    app.asyncCommands.use(AdminPasswordCommand(), as: "admin-password")

    // Register routes.
    try routes(app)
}
