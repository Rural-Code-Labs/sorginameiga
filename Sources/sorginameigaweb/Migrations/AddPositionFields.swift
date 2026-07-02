import Fluent
import FluentSQL

/// Phase 9a: adds a `position` column to dogs, puppies and galleries so their
/// display order can be arranged from the admin. Existing rows are backfilled
/// with `position = id`, which preserves the previous id-based ordering.
///
/// Registered before `SeedLegacyData` so that, on a fresh database, the column
/// already exists when the seed inserts rows (which now carry a position).
struct AddPositionFields: AsyncMigration {
    private static let schemas = [Dog.schema, Puppy.schema, Gallery.schema]

    func prepare(on database: any Database) async throws {
        for schema in Self.schemas {
            try await database.schema(schema)
                .field("position", .int, .required, .sql(.default(0)))
                .update()
        }
        // Backfill existing rows so the initial order matches the legacy one.
        // (No-op on a fresh DB, where the seed runs afterwards.)
        if let sql = database as? any SQLDatabase {
            for schema in Self.schemas {
                try await sql.raw("UPDATE \(unsafeRaw: schema) SET position = id").run()
            }
        }
    }

    func revert(on database: any Database) async throws {
        for schema in Self.schemas {
            try await database.schema(schema).deleteField("position").update()
        }
    }
}
