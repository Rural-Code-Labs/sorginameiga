import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: HomeController())
    try app.register(collection: DogController())
    try app.register(collection: GalleryController())
    try app.register(collection: PuppyController())
    try app.register(collection: ContactController())
    try app.register(collection: AdminController())
}
