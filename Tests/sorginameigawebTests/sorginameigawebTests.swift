@testable import sorginameigaweb
import Fluent
import Foundation
import VaporTesting
import Testing

// Serialized: several admin tests create/delete rows and assert on table counts,
// which would race if run in parallel (they share one Postgres database).
@Suite("Home page", .serialized)
struct sorginameigawebTests {
    private func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await test(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Spanish home renders at / and /es")
    func spanishHome() async throws {
        try await withApp { app in
            for path in ["/", "/es"] {
                try await app.testing().test(.GET, path, afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.body.string.contains("Criadero Lhasa Apso"))
                    #expect(res.body.string.contains("Pilar Díaz"))
                    #expect(res.body.string.contains("¿Quiénes Somos?"))
                })
            }
        }
    }

    @Test("English home renders at /en")
    func englishHome() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "en", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Lhasa Apso Kennel"))
                #expect(res.body.string.contains("About Us"))
            })
        }
    }

    @Test("Analytics is disabled by default: no Google tag or cookie banner")
    func analyticsDisabledByDefault() async throws {
        unsetenv("GA_MEASUREMENT_ID")
        try await withApp { app in
            try await app.testing().test(.GET, "/", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(!res.body.string.contains("googletagmanager"))
                #expect(!res.body.string.contains("cookie-banner"))
            })
        }
    }

    @Test("Analytics + consent banner render when GA_MEASUREMENT_ID is set")
    func analyticsEnabledWithMeasurementId() async throws {
        setenv("GA_MEASUREMENT_ID", "G-TEST12345", 1)
        defer { unsetenv("GA_MEASUREMENT_ID") }
        try await withApp { app in
            try await app.testing().test(.GET, "/", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("googletagmanager.com/gtag/js?id=G-TEST12345"))
                #expect(res.body.string.contains("gtag('consent', 'default'"))
                #expect(res.body.string.contains("id=\"cookie-banner\""))
            })
            // The admin area does not extend the public layout, so it is never tracked.
            try await app.testing().test(.GET, "admin/login", afterResponse: { res async in
                #expect(!res.body.string.contains("googletagmanager"))
            })
        }
    }

    @Test("Legacy .php URLs redirect (301) to the new clean routes")
    func legacyRedirects() async throws {
        try await withApp { app in
            let cases: [(String, String)] = [
                ("/index.php", "/"),
                ("/index.php?idioma=ing", "/en"),
                ("/perros.php?sexo=macho", "/machos"),
                ("/perros.php?sexo=hembra&idioma=ing", "/en/females"),
                ("/verperro.php?id=27", "/perro/27"),
                ("/verperro.php?id=27&idioma=ing", "/en/dog/27"),
                ("/cachorros.php", "/cachorros"),
                ("/galeria.php?idioma=ing", "/en/gallery"),
                ("/contactos.php", "/contacto"),
            ]
            for (from, to) in cases {
                try await app.testing().test(.GET, from, afterResponse: { res async in
                    #expect(res.status == .permanentRedirect || res.status == .movedPermanently)
                    #expect(res.headers.first(name: .location) == to)
                })
            }
        }
    }

    @Test("Legacy seed decodes with correct counts and UTF-8 encoding")
    func legacySeed() async throws {
        try await withApp { app in
            let seed = try LegacySeed.load(from: app)
            #expect(seed.dogs.count == 20)
            #expect(seed.galleries.count == 7)
            #expect(seed.counter == 445682)
            // Latin1 → UTF-8 correction must have been applied at extraction time.
            #expect(seed.dogs.contains { $0.name.contains("SORGIÑA-MEIGA") })
            #expect(seed.galleries.contains { $0.name == "PEQUEÑINES" })
            // Sex values are the preserved legacy strings.
            #expect(Set(seed.dogs.map(\.sex)) == ["macho", "hembra"])
        }
    }

    // The following are integration tests that require the local Postgres
    // (docker compose up -d db) seeded via `migrate --yes`.

    @Test("Dog listings render filtered by sex")
    func dogListings() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "machos", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Machos"))
                #expect(res.body.string.contains("/perro/27"))
            })
            try await app.testing().test(.GET, "en/females", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Females"))
                #expect(res.body.string.contains("/en/dog/"))
            })
        }
    }

    @Test("Dog detail renders pedigree and back link")
    func dogDetail() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "perro/27", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("SUNTORY ADONIS"))
                #expect(res.body.string.contains("pedigree-table"))
                #expect(res.body.string.contains("/machos")) // back link
            })
        }
    }

    @Test("Unknown dog id returns 404")
    func unknownDog() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "perro/999999", afterResponse: { res async in
                #expect(res.status == .notFound)
            })
        }
    }

    @Test("Galleries page renders seeded galleries with photos")
    func galleries() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "galeria", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("PEQUEÑINES"))
                #expect(res.body.string.contains("/images/galerias/"))
            })
            try await app.testing().test(.GET, "en/gallery", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Photo Gallery"))
            })
        }
    }

    @Test("Header shows the Instagram and Facebook links")
    func socialLinks() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "/", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("https://www.instagram.com/sorginameiga/"))
                #expect(res.body.string.contains("https://www.facebook.com/sorginameiga.lhasas"))
                #expect(res.body.string.contains("aria-label=\"Instagram\""))
            })
        }
    }

    @Test("Public photos open in the on-page lightbox")
    func lightbox() async throws {
        try await withApp { app in
            // Dog detail: photo links are tagged, and the overlay + script are present.
            try await app.testing().test(.GET, "perro/27", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("data-lightbox"))
                #expect(res.body.string.contains("id=\"lightbox\""))
                #expect(res.body.string.contains("/lightbox.js"))
            })
            // Galleries page too.
            try await app.testing().test(.GET, "galeria", afterResponse: { res async in
                #expect(res.body.string.contains("data-lightbox"))
            })
        }
    }

    @Test("Puppies page shows empty state when there are no puppies")
    func puppiesEmpty() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "cachorros", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Cachorros"))
                #expect(res.body.string.contains("No hay cachorros"))
            })
        }
    }

    @Test("Contact page shows contact details in both languages")
    func contact() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "contacto", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("sorginameiga@hotmail.com"))
                #expect(res.body.string.contains("696 214 610"))
            })
            try await app.testing().test(.GET, "en/contact", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("through WhatsApp"))
            })
        }
    }

    // Admin auth (requires local Postgres migrated; admin password = "changeme").

    @Test("Admin area redirects to login when unauthenticated")
    func adminRequiresLogin() async throws {
        try await withApp { app in
            try await app.testing().test(.GET, "admin", afterResponse: { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/admin/login")
            })
            try await app.testing().test(.GET, "admin/login", afterResponse: { res async in
                #expect(res.status == .ok)
            })
        }
    }

    @Test("Admin login rejects a wrong password")
    func adminWrongPassword() async throws {
        try await withApp { app in
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "wrong"], as: .urlEncodedForm)
            }, afterResponse: { res async in
                #expect(res.status == .unauthorized)
            })
        }
    }

    @Test("Admin login grants access to the dashboard")
    func adminLoginSucceeds() async throws {
        final class CookieBox: @unchecked Sendable { var cookies: HTTPCookies? }
        let box = CookieBox()
        try await withApp { app in
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "changeme"], as: .urlEncodedForm)
            }, afterResponse: { res async in
                #expect(res.status == .seeOther)
                #expect(res.headers.first(name: .location) == "/admin")
                box.cookies = res.headers.setCookie
            })
            try await app.testing().test(.GET, "admin", beforeRequest: { req in
                if let cookies = box.cookies { req.headers.cookie = cookies }
            }, afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Panel de administración"))
            })
        }
    }

    @Test("Admin dog CRUD is protected and creates/deletes a dog")
    func adminDogCrud() async throws {
        final class Box: @unchecked Sendable { var cookies: HTTPCookies?; var newID: Int? }
        let box = Box()
        try await withApp { app in
            // Protected without a session.
            try await app.testing().test(.GET, "admin/perros", afterResponse: { res async in
                #expect(res.status == .seeOther)
            })
            // Log in.
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "changeme"], as: .urlEncodedForm)
            }, afterResponse: { res async in box.cookies = res.headers.setCookie })

            let before = try await Dog.query(on: app.db).count()

            // Create.
            var form = ["name": "TEST CRUD", "sex": "macho"]
            for key in ["a", "b", "aa", "ab", "ba", "bb", "aaa", "aab", "aba", "abb", "baa", "bab", "bba", "bbb"] {
                form[key] = ""
            }
            try await app.testing().test(.POST, "admin/perros", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
                try req.content.encode(form, as: .urlEncodedForm)
            }, afterResponse: { res async in #expect(res.status == .seeOther) })

            let created = try await Dog.query(on: app.db).filter(\.$name == "TEST CRUD").first()
            #expect(created != nil)
            box.newID = created?.id

            // Delete (cleanup).
            if let id = box.newID {
                try await app.testing().test(.POST, "admin/perros/\(id)/borrar", beforeRequest: { req in
                    if let c = box.cookies { req.headers.cookie = c }
                }, afterResponse: { res async in #expect(res.status == .seeOther) })
            }
            #expect(try await Dog.query(on: app.db).count() == before)
        }
    }

    @Test("Admin puppy CRUD creates, updates and deletes a puppy")
    func adminPuppyCrud() async throws {
        final class Box: @unchecked Sendable { var cookies: HTTPCookies?; var newID: Int? }
        let box = Box()
        try await withApp { app in
            try await app.testing().test(.GET, "admin/cachorros", afterResponse: { res async in
                #expect(res.status == .seeOther) // protected
            })
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "changeme"], as: .urlEncodedForm)
            }, afterResponse: { res async in box.cookies = res.headers.setCookie })

            let before = try await Puppy.query(on: app.db).count()
            try await app.testing().test(.POST, "admin/cachorros", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
                try req.content.encode(["name": "TEST LITTER", "available": "1"], as: .urlEncodedForm)
            }, afterResponse: { res async in #expect(res.status == .seeOther) })

            let created = try await Puppy.query(on: app.db).filter(\.$name == "TEST LITTER").first()
            #expect(created?.available == true)
            box.newID = created?.id

            if let id = box.newID {
                try await app.testing().test(.POST, "admin/cachorros/\(id)/borrar", beforeRequest: { req in
                    if let c = box.cookies { req.headers.cookie = c }
                }, afterResponse: { res async in #expect(res.status == .seeOther) })
            }
            #expect(try await Puppy.query(on: app.db).count() == before)
        }
    }

    @Test("Admin gallery CRUD creates and deletes a gallery")
    func adminGalleryCrud() async throws {
        final class Box: @unchecked Sendable { var cookies: HTTPCookies?; var newID: Int? }
        let box = Box()
        try await withApp { app in
            try await app.testing().test(.GET, "admin/galerias", afterResponse: { res async in
                #expect(res.status == .seeOther) // protected
            })
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "changeme"], as: .urlEncodedForm)
            }, afterResponse: { res async in box.cookies = res.headers.setCookie })

            let before = try await Gallery.query(on: app.db).count()
            try await app.testing().test(.POST, "admin/galerias", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
                try req.content.encode(["name": "TEST GALLERY"], as: .urlEncodedForm)
            }, afterResponse: { res async in #expect(res.status == .seeOther) })

            let created = try await Gallery.query(on: app.db).filter(\.$name == "TEST GALLERY").first()
            #expect(created != nil)
            box.newID = created?.id

            if let id = box.newID {
                try await app.testing().test(.POST, "admin/galerias/\(id)/borrar", beforeRequest: { req in
                    if let c = box.cookies { req.headers.cookie = c }
                }, afterResponse: { res async in #expect(res.status == .seeOther) })
            }
            #expect(try await Gallery.query(on: app.db).count() == before)
        }
    }

    @Test("Admin can reorder dogs within a sex (↑/↓ swap positions)")
    func adminReorderDogs() async throws {
        final class Box: @unchecked Sendable { var cookies: HTTPCookies? }
        let box = Box()
        try await withApp { app in
            // Reordering is protected.
            let firstMale = try await Dog.query(on: app.db)
                .filter(\.$sex == Sex.male.rawValue).sort(\.$position).first()
            let secondMale = try await Dog.query(on: app.db)
                .filter(\.$sex == Sex.male.rawValue).sort(\.$position).range(1..<2).first()
            guard let a = firstMale, let b = secondMale else { return } // needs seeded data
            try await app.testing().test(.POST, "admin/perros/\(b.id ?? 0)/subir", afterResponse: { res async in
                #expect(res.status == .seeOther) // redirected to login
            })

            // Log in.
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "changeme"], as: .urlEncodedForm)
            }, afterResponse: { res async in box.cookies = res.headers.setCookie })

            let (posA, posB) = (a.position, b.position)

            // Move the second male up: it should now precede the first.
            try await app.testing().test(.POST, "admin/perros/\(b.id ?? 0)/subir", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
            }, afterResponse: { res async in #expect(res.status == .seeOther) })
            #expect(try await Dog.find(a.id, on: app.db)?.position == posB)
            #expect(try await Dog.find(b.id, on: app.db)?.position == posA)

            // Move it back down to restore the original order (keep DB clean).
            try await app.testing().test(.POST, "admin/perros/\(b.id ?? 0)/bajar", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
            }, afterResponse: { res async in #expect(res.status == .seeOther) })
            #expect(try await Dog.find(a.id, on: app.db)?.position == posA)
            #expect(try await Dog.find(b.id, on: app.db)?.position == posB)
        }
    }

    @Test("Admin can reorder photos (↑/↓ swaps the files on disk)")
    func adminReorderPhotos() async throws {
        final class Box: @unchecked Sendable { var cookies: HTTPCookies?; var id: Int? }
        let box = Box()
        try await withApp { app in
            // Log in and create a throwaway gallery to hold the photos.
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "changeme"], as: .urlEncodedForm)
            }, afterResponse: { res async in box.cookies = res.headers.setCookie })
            try await app.testing().test(.POST, "admin/galerias", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
                try req.content.encode(["name": "TEST PHOTOS ORDER"], as: .urlEncodedForm)
            }, afterResponse: { res async in #expect(res.status == .seeOther) })
            let gallery = try await Gallery.query(on: app.db).filter(\.$name == "TEST PHOTOS ORDER").first()
            box.id = gallery?.id
            guard let id = box.id else { return }

            // Two distinct valid JPEGs (magic bytes FF D8 FF + a marker).
            let jpegA: [UInt8] = [0xFF, 0xD8, 0xFF] + Array("AAAA".utf8)
            let jpegB: [UInt8] = [0xFF, 0xD8, 0xFF] + Array("BBBBBBBB".utf8)
            for bytes in [jpegA, jpegB] {
                try await app.testing().test(.POST, "admin/fotos/galerias/\(id)", beforeRequest: { req in
                    if let c = box.cookies { req.headers.cookie = c }
                    try req.content.encode(PhotoUpload(file: File(data: ByteBuffer(bytes: bytes), filename: "x.jpg")), as: .formData)
                }, afterResponse: { res async in #expect(res.status == .seeOther) })
            }

            // Galleries start at index 1 → 1.jpg = A, 2.jpg = B.
            let dir = app.directory.publicDirectory + "images/galerias/\(id)/"
            #expect(Array(try Data(contentsOf: URL(fileURLWithPath: dir + "1.jpg"))) == jpegA)

            // Photo URLs carry a ?v= cache-buster (so a swap forces a browser reload).
            try await app.testing().test(.GET, "admin/fotos/galerias/\(id)", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
            }, afterResponse: { res async in
                #expect(res.body.string.contains("/images/galerias/\(id)/1.jpg?v="))
            })

            // Move photo 1 right → swap 1 and 2. Now 1.jpg = B, 2.jpg = A.
            try await app.testing().test(.POST, "admin/fotos/galerias/\(id)/derecha/1", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
            }, afterResponse: { res async in #expect(res.status == .seeOther) })
            #expect(Array(try Data(contentsOf: URL(fileURLWithPath: dir + "1.jpg"))) == jpegB)
            #expect(Array(try Data(contentsOf: URL(fileURLWithPath: dir + "2.jpg"))) == jpegA)

            // Cleanup: deleting the gallery removes its photo folder.
            try await app.testing().test(.POST, "admin/galerias/\(id)/borrar", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
            }, afterResponse: { res async in #expect(res.status == .seeOther) })
            #expect(!FileManager.default.fileExists(atPath: dir))
        }
    }

    @Test("Photo management is protected, renders, and rejects non-JPEG uploads")
    func adminPhotos() async throws {
        final class Box: @unchecked Sendable { var cookies: HTTPCookies? }
        let box = Box()
        try await withApp { app in
            // Protected without a session.
            try await app.testing().test(.GET, "admin/fotos/perros/27", afterResponse: { res async in
                #expect(res.status == .seeOther)
            })
            try await app.testing().test(.POST, "admin/login", beforeRequest: { req in
                try req.content.encode(["username": "Pilar&Estibaliz", "password": "changeme"], as: .urlEncodedForm)
            }, afterResponse: { res async in box.cookies = res.headers.setCookie })

            // Manage page for an existing dog.
            try await app.testing().test(.GET, "admin/fotos/perros/27", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
            }, afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.body.string.contains("Subir foto"))
            })

            // Unknown entity → 404.
            try await app.testing().test(.GET, "admin/fotos/galerias/999999", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
            }, afterResponse: { res async in
                #expect(res.status == .notFound)
            })

            // A non-JPEG upload is rejected (and no file is written).
            try await app.testing().test(.POST, "admin/fotos/galerias/2", beforeRequest: { req in
                if let c = box.cookies { req.headers.cookie = c }
                try req.content.encode(PhotoUpload(file: File(data: "not a jpeg", filename: "x.jpg")), as: .formData)
            }, afterResponse: { res async in
                #expect(res.status == .unprocessableEntity)
            })
        }
    }
}
