import Fluent
import Vapor

func routes(_ app: Application) throws {
    // Public site.
    try app.register(collection: HomeController())
    try app.register(collection: DogController())
    try app.register(collection: GalleryController())
    try app.register(collection: PuppyController())
    try app.register(collection: ContactController())

    // Admin: auth + dashboard.
    try app.register(collection: AdminController())

    // Admin: protected CRUD sections (session + redirect-to-login guard).
    let admin = app.grouped("admin").grouped(
        Admin.sessionAuthenticator(),
        Admin.redirectMiddleware(path: "/admin/login")
    )
    try admin.register(collection: AdminDogController())
    try admin.register(collection: AdminPuppyController())
    try admin.register(collection: AdminGalleryController())
    try admin.register(collection: AdminPhotoController())
}
