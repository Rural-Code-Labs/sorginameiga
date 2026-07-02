import Fluent

/// A puppy offered for sale. Maps to the legacy `cachorros` table, where
/// `disponible` was an integer flag (now a `Bool`). The legacy `id` is
/// preserved because puppy photos live under `images/cachorros/<id>/`.
final class Puppy: Model, @unchecked Sendable {
    static let schema = "puppies"

    @ID(custom: "id", generatedBy: .user)
    var id: Int?

    @Field(key: "name")
    var name: String

    @Field(key: "available")
    var available: Bool

    /// Display order on the puppies page (lower shows first). Added in phase 9a.
    @Field(key: "position")
    var position: Int

    init() {}

    init(id: Int, name: String, available: Bool, position: Int) {
        self.id = id
        self.name = name
        self.available = available
        self.position = position
    }
}
