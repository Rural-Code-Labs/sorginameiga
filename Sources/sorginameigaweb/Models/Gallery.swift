import Fluent

/// A photo gallery. Maps to the legacy `galerias` table. The legacy `id` is
/// preserved because the gallery's images live under `images/galerias/<id>/`.
final class Gallery: Model, @unchecked Sendable {
    static let schema = "galleries"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "name")
    var name: String

    /// Display order on the galleries page (lower shows first). Added in phase 9a.
    @Field(key: "position")
    var position: Int

    init() {}

    init(id: Int, name: String, position: Int) {
        self.id = id
        self.name = name
        self.position = position
    }
}
