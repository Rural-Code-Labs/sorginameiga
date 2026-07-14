import Fluent

/// Creates the `media_videos` table: embedded YouTube/Vimeo videos that can be
/// interleaved with the photos of a dog, puppy or gallery (phase 2.3).
struct CreateMediaVideos: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(MediaVideo.schema)
            .field("id", .int, .identifier(auto: true))
            .field("kind", .string, .required)
            .field("entity_id", .int, .required)
            .field("provider", .string, .required)
            .field("video_ref", .string, .required)
            .field("photos_before", .int, .required)
            .field("sort_order", .int, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(MediaVideo.schema).delete()
    }
}
