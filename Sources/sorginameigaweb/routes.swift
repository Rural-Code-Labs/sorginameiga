import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: HomeController())
    try app.register(collection: DogController())
}
