import Fluent
import Vapor

/// Serves the photo galleries page (`/galeria`, `/en/gallery`) in both
/// languages. Each gallery is shown as a titled block with its photo grid.
/// Replaces the legacy `galeria.php`.
final class GalleryController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("galeria", use: spanish)
        routes.get("en", "gallery", use: english)
    }

    @Sendable func spanish(req: Request) async throws -> View { try await render(.esp, on: req) }
    @Sendable func english(req: Request) async throws -> View { try await render(.ing, on: req) }

    private func render(_ language: Language, on req: Request) async throws -> View {
        let galleries = try await Gallery.query(on: req.db).sort(\.$position).all()
        var blocks: [MediaBlock] = []
        for gallery in galleries {
            let gid = gallery.id ?? 0
            let subpath = "images/galerias/\(gid)"
            let photoIndices = PhotoDirectory.indices(in: subpath, on: req)
            let videos = try await MediaVideo.query(on: req.db)
                .filter(\.$kind == PhotoKind.galleries.rawValue)
                .filter(\.$entityID == gid)
                .all()
            let items = MediaLayout.merge(photoIndices: photoIndices, videos: videos).map { item -> MediaItem in
                switch item {
                case .photo(let index):
                    return .photo(url: PhotoDirectory.url(in: subpath, index: index, on: req), alt: gallery.name)
                case .video(let video):
                    return .video(video, alt: gallery.name)
                }
            }
            blocks.append(MediaBlock(title: gallery.name, badge: nil, items: items))
        }

        let translation = req.localization.translation(for: language)
        let layout = await PageLayout.build(
            for: language,
            spanishURL: "/galeria",
            englishURL: "/en/gallery",
            on: req
        )
        return try await req.view.render(
            "media",
            MediaPageContext(
                layout: layout,
                title: translation.gallery,
                blocks: blocks,
                emptyMessage: translation.noGalleries
            )
        )
    }
}
