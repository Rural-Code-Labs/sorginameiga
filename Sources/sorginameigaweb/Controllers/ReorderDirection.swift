/// Direction for the admin ↑/↓ reorder actions (phase 9a). Shared by the dog,
/// puppy and gallery controllers, which each swap an item's `position` with the
/// adjacent neighbour in the chosen direction.
enum ReorderDirection {
    case up
    case down
}
