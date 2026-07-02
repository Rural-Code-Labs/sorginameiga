import Fluent

/// Inserts the legacy production data (dogs, galleries, visit counter) loaded
/// from `Resources/seed/legacy.json`. Puppies are intentionally not seeded —
/// the legacy `cachorros` table is currently empty.
struct SeedLegacyData: AsyncMigration {
    let seed: LegacySeed

    func prepare(on database: any Database) async throws {
        for dog in seed.dogs {
            try await Dog(id: dog.id, name: dog.name, sex: dog.sex, pedigree: dog.ancestors, position: dog.id)
                .create(on: database)
        }

        for gallery in seed.galleries {
            try await Gallery(id: gallery.id, name: gallery.name, position: gallery.id)
                .create(on: database)
        }

        try await VisitCounter(count: seed.counter)
            .create(on: database)
    }

    func revert(on database: any Database) async throws {
        try await VisitCounter.query(on: database).delete()
        try await Gallery.query(on: database).delete()
        try await Dog.query(on: database).delete()
    }
}
