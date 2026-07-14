import Foundation

/// One item in an owner's combined display order: either a file-based photo
/// (identified by its numeric file index) or an embedded video.
enum MediaLayoutItem {
    case photo(index: Int)
    case video(MediaVideo)
}

/// Identifies an item to move when reordering, decoded from a form value such
/// as `photo-3` or `video-7`.
enum MediaHandle: Equatable {
    case photo(index: Int)
    case video(id: Int)

    init?(_ raw: String) {
        let parts = raw.split(separator: "-", maxSplits: 1)
        guard parts.count == 2, let value = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "photo": self = .photo(index: value)
        case "video": self = .video(id: value)
        default: return nil
        }
    }
}

/// The persistence change a single reorder step implies. Kept as data (rather
/// than performing it) so the decision logic stays pure and unit-testable.
enum ReorderAction: Equatable {
    /// Swap two photos by exchanging their file names.
    case swapPhotos(Int, Int)
    /// Set a video's `photosBefore` (it crossed a photo boundary).
    case setVideoPhotosBefore(videoID: Int, value: Int)
    /// Swap two videos' `sortOrder` (they share the same photo gap).
    case swapVideoOrder(Int, Int)
    case none
}

/// Merges an owner's file-based photos with its embedded videos into a single
/// ordered list, and decides how a one-step ←/→ reorder should mutate storage.
/// Owner-agnostic: works for dogs, puppies and galleries alike.
enum MediaLayout {
    /// Interleaves photos and videos. Videos are placed after `photosBefore`
    /// photos (clamped to the real photo count), ties broken by `sortOrder`.
    static func merge(photoIndices: [Int], videos: [MediaVideo]) -> [MediaLayoutItem] {
        let photoCount = photoIndices.count
        func slot(_ v: MediaVideo) -> Int { min(max(v.photosBefore, 0), photoCount) }
        let sorted = videos.sorted { a, b in
            slot(a) != slot(b) ? slot(a) < slot(b) : a.sortOrder < b.sortOrder
        }

        var result: [MediaLayoutItem] = []
        var vi = 0
        for k in 0...photoCount {
            while vi < sorted.count, slot(sorted[vi]) == k {
                result.append(.video(sorted[vi]))
                vi += 1
            }
            if k < photoCount { result.append(.photo(index: photoIndices[k])) }
        }
        return result
    }

    /// Given the current merged order, decides the storage mutation for moving
    /// `handle` one step in `direction` (`.up` = left, `.down` = right).
    static func reorderAction(
        in merged: [MediaLayoutItem],
        moving handle: MediaHandle,
        _ direction: ReorderDirection
    ) -> ReorderAction {
        guard let pos = merged.firstIndex(where: { $0.matches(handle) }) else { return .none }
        let neighbourPos = direction == .up ? pos - 1 : pos + 1
        guard merged.indices.contains(neighbourPos) else { return .none }

        switch (merged[pos], merged[neighbourPos]) {
        case let (.photo(a), .photo(b)):
            return .swapPhotos(a, b)
        case let (.video(v), .photo):
            // The video crosses the neighbouring photo.
            let delta = direction == .up ? -1 : 1
            return .setVideoPhotosBefore(videoID: v.id ?? -1, value: v.photosBefore + delta)
        case let (.photo, .video(w)):
            // The photo crosses the video, so the video gains/loses a photo before it.
            let delta = direction == .up ? 1 : -1
            return .setVideoPhotosBefore(videoID: w.id ?? -1, value: w.photosBefore + delta)
        case let (.video(v), .video(w)):
            return .swapVideoOrder(v.id ?? -1, w.id ?? -1)
        }
    }
}

extension MediaLayoutItem {
    func matches(_ handle: MediaHandle) -> Bool {
        switch (self, handle) {
        case let (.photo(a), .photo(b)): return a == b
        case let (.video(v), .video(id)): return v.id == id
        default: return false
        }
    }
}
