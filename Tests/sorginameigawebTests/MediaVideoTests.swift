@testable import sorginameigaweb
import Testing

/// Unit tests for the phase-2.3 video feature: URL parsing and the combined
/// photo+video ordering/reordering logic (owner-agnostic: dogs/puppies/
/// galleries). These are pure functions — no app or database needed.
@Suite("Media videos")
struct MediaVideoTests {

    // MARK: - URL parsing

    @Test("Parses the common YouTube URL shapes")
    func parsesYouTube() {
        let id = "dQw4w9WgXcQ"
        let urls = [
            "https://www.youtube.com/watch?v=\(id)",
            "https://youtu.be/\(id)",
            "youtu.be/\(id)?t=42",
            "https://www.youtube.com/embed/\(id)",
            "https://www.youtube.com/shorts/\(id)",
            "https://m.youtube.com/watch?v=\(id)&feature=share",
        ]
        for url in urls {
            #expect(VideoEmbed.parse(url) == VideoEmbed(provider: .youtube, ref: id), "failed for \(url)")
        }
    }

    @Test("Parses the common Vimeo URL shapes")
    func parsesVimeo() {
        #expect(VideoEmbed.parse("https://vimeo.com/123456789") == VideoEmbed(provider: .vimeo, ref: "123456789"))
        #expect(VideoEmbed.parse("player.vimeo.com/video/123456789") == VideoEmbed(provider: .vimeo, ref: "123456789"))
    }

    @Test("Rejects non-video and malformed URLs")
    func rejectsInvalid() {
        for url in ["", "https://example.com/watch?v=abc", "not a url", "https://youtube.com/watch?v=tooshort"] {
            #expect(VideoEmbed.parse(url) == nil, "should reject \(url)")
        }
    }

    @Test("Derives embed, thumbnail and canonical URLs")
    func derivesURLs() {
        let yt = MediaVideo(kind: "perros", entityID: 5, provider: "youtube", videoRef: "abc12345678", photosBefore: 0, sortOrder: 1)
        #expect(yt.embedURL == "https://www.youtube.com/embed/abc12345678")
        #expect(yt.thumbURL == "https://img.youtube.com/vi/abc12345678/hqdefault.jpg")
        #expect(yt.canonicalURL == "https://www.youtube.com/watch?v=abc12345678")

        let vimeo = MediaVideo(kind: "cachorros", entityID: 3, provider: "vimeo", videoRef: "555", photosBefore: 0, sortOrder: 1)
        #expect(vimeo.embedURL == "https://player.vimeo.com/video/555")
        #expect(vimeo.thumbURL == nil) // no static thumbnail → placeholder tile
        #expect(vimeo.canonicalURL == "https://vimeo.com/555")
    }

    @Test("editVideo round-trips: a canonical URL re-parses to the same ref")
    func canonicalRoundTrips() {
        let yt = MediaVideo(kind: "galerias", entityID: 1, provider: "youtube", videoRef: "abc12345678", photosBefore: 0, sortOrder: 1)
        #expect(VideoEmbed.parse(yt.canonicalURL) == VideoEmbed(provider: .youtube, ref: "abc12345678"))
    }

    // MARK: - Merge

    private func describe(_ items: [MediaLayoutItem]) -> String {
        items.map {
            switch $0 {
            case .photo(let i): return "p\(i)"
            case .video(let v): return "v\(v.id ?? 0)"
            }
        }.joined(separator: ",")
    }

    /// Videos default to a dog owner here; the merge logic is owner-agnostic.
    private func video(_ id: Int, before: Int, order: Int = 0) -> MediaVideo {
        MediaVideo(id: id, kind: "perros", entityID: 5, provider: "youtube", videoRef: "x", photosBefore: before, sortOrder: order)
    }

    @Test("Interleaves videos among photos by photosBefore (works for any owner)")
    func mergeInterleaves() {
        let photos = [1, 2, 3]
        #expect(describe(MediaLayout.merge(photoIndices: photos, videos: [video(7, before: 1)])) == "p1,v7,p2,p3")
        #expect(describe(MediaLayout.merge(photoIndices: photos, videos: [video(7, before: 0)])) == "v7,p1,p2,p3")
        #expect(describe(MediaLayout.merge(photoIndices: photos, videos: [video(7, before: 3)])) == "p1,p2,p3,v7")
    }

    @Test("Dogs: cover photo (index 0) stays first, a video interleaves after it")
    func mergeDogCover() {
        // Dogs number photos from 0; index 0 is the cover.
        #expect(describe(MediaLayout.merge(photoIndices: [0, 1, 2], videos: [video(7, before: 1)])) == "p0,v7,p1,p2")
    }

    @Test("Clamps out-of-range photosBefore to the real photo count")
    func mergeClamps() {
        #expect(describe(MediaLayout.merge(photoIndices: [1, 2], videos: [video(7, before: 99)])) == "p1,p2,v7")
        #expect(describe(MediaLayout.merge(photoIndices: [], videos: [video(7, before: 5)])) == "v7")
    }

    @Test("Orders videos in the same gap by sortOrder")
    func mergeTiebreak() {
        let videos = [video(8, before: 1, order: 2), video(7, before: 1, order: 1)]
        #expect(describe(MediaLayout.merge(photoIndices: [1, 2], videos: videos)) == "p1,v7,v8,p2")
    }

    // MARK: - Reorder

    @Test("Moving a video across a photo updates photosBefore")
    func reorderVideoAcrossPhoto() {
        let v = video(7, before: 1)
        let merged = MediaLayout.merge(photoIndices: [1, 2], videos: [v]) // p1, v7, p2
        #expect(MediaLayout.reorderAction(in: merged, moving: .video(id: 7), .up) == .setVideoPhotosBefore(videoID: 7, value: 0))
        #expect(MediaLayout.reorderAction(in: merged, moving: .video(id: 7), .down) == .setVideoPhotosBefore(videoID: 7, value: 2))
    }

    @Test("Moving a photo across a video updates the video's photosBefore")
    func reorderPhotoAcrossVideo() {
        let v = video(7, before: 1)
        let merged = MediaLayout.merge(photoIndices: [1, 2], videos: [v]) // p1, v7, p2
        #expect(MediaLayout.reorderAction(in: merged, moving: .photo(index: 1), .down) == .setVideoPhotosBefore(videoID: 7, value: 0))
        #expect(MediaLayout.reorderAction(in: merged, moving: .photo(index: 2), .up) == .setVideoPhotosBefore(videoID: 7, value: 2))
    }

    @Test("Swaps two photos / two videos that are adjacent")
    func reorderSwaps() {
        let photosOnly = MediaLayout.merge(photoIndices: [1, 2], videos: []) // p1, p2
        #expect(MediaLayout.reorderAction(in: photosOnly, moving: .photo(index: 1), .down) == .swapPhotos(1, 2))

        let twoVideos = MediaLayout.merge(photoIndices: [], videos: [video(7, before: 0, order: 1), video(8, before: 0, order: 2)])
        #expect(MediaLayout.reorderAction(in: twoVideos, moving: .video(id: 7), .down) == .swapVideoOrder(7, 8))
    }

    @Test("No-op at the ends of the list")
    func reorderEdges() {
        let merged = MediaLayout.merge(photoIndices: [1, 2], videos: []) // p1, p2
        #expect(MediaLayout.reorderAction(in: merged, moving: .photo(index: 1), .up) == .none)
        #expect(MediaLayout.reorderAction(in: merged, moving: .photo(index: 2), .down) == .none)
    }
}
