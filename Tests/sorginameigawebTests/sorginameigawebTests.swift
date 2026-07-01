@testable import sorginameigaweb
import VaporTesting
import Testing

@Suite("Home page")
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
                    #expect(res.body.string.contains("¿Quienes Somos?"))
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
                #expect(res.body.string.contains("nombrepedigree"))
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
}
