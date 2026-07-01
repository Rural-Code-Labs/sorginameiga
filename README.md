# Sorgiña Meiga

Website for **Sorgiña-Meiga**, a Lhasa Apso dog kennel run by Pilar Díaz and
Estíbaliz Domínguez (breeders since 1994). This repository is the modern rewrite
of the kennel's website, built with [Vapor](https://vapor.codes) (server-side
Swift).

## Background

The original site (`old_web/` in the parent repository) was written ~13 years
ago in procedural PHP and is **still live and in production**. It is severely
outdated: it uses the `mysql_*` extension (removed in PHP 7.0), has SQL
injection throughout, stores the admin password in plain text, and has no build
system, tests, CI, or version control.

This project is a from-scratch reimplementation in a containerized, modern stack.
It is **not** a line-by-line port: the behaviour and content are preserved, but
the known problems of the legacy code are deliberately **not** reproduced.

| | Legacy | New |
|---|---|---|
| Language | PHP (procedural) | Swift |
| Framework | — | Vapor + Leaf + Fluent |
| Database | MySQL (`mysql_*`, hardcoded creds) | PostgreSQL |
| URLs | `index.php?idioma=esp` | clean routes (`/`, `/en`) |
| Code language | Spanish | English |
| Build / tests / CI | none | SwiftPM + Swift Testing |

## Stack

- **Swift / Vapor** — web framework
- **Leaf** — HTML templating
- **Fluent** + **FluentPostgresDriver** — ORM
- **PostgreSQL** — database
- **Docker** — local Postgres and (eventually) production container

## Architecture

- **Internationalization.** Spanish (default) and English. The language is
  resolved from the URL (`/`, `/es` → Spanish; `/en` → English). Strings live in
  `LocalizationService` (the Swift counterpart to the legacy `languajes/*.php`),
  which vends a `Translation` value per language. The language switcher in the
  header preserves the current page.
- **Layout.** A shared `LayoutContext` (menu, language-switch URLs, footer visit
  counter, translations) is built by `PageLayout` and embedded by every page
  context. Leaf templates compose `base.leaf` + `partials/{header,footer}.leaf`.
- **Data.** Fluent models with the legacy integer ids preserved (dog/puppy/
  gallery photos live under `images/<id>/`). The four-generation pedigree is
  stored as a JSON column (14 free-text ancestor names), matching how the legacy
  `perros` table held ancestry as plain strings rather than relations.
- **Design choice — classes vs structs.** Services and controllers are classes
  (reference semantics, mirroring the legacy PHP classes); data carried to the
  templates is value-type `Encodable` structs.

### Data model

| Model | Table | Notes |
|---|---|---|
| `Dog` | `dogs` | `name`, `sex` (`macho`/`hembra`), `pedigree` (JSON) |
| `Puppy` | `puppies` | `name`, `available` |
| `Gallery` | `galleries` | `name` |
| `VisitCounter` | `visit_counter` | single row; site-wide visit count |

### Routes

| Route | Description |
|---|---|
| `/`, `/es`, `/en` | Home ("About Us") |
| `/machos`, `/hembras` · `/en/males`, `/en/females` | Dog listings by sex |
| `/perro/:id` · `/en/dog/:id` | Dog detail + pedigree |
| `/cachorros` · `/en/puppies` | Puppies with availability |
| `/galeria` · `/en/gallery` | Photo galleries |
| `/contacto` · `/en/contact` | Contact details |
| `/admin/login` · `/admin` | Admin login + dashboard |
| `/admin/{perros,cachorros,galerias}` | CRUD (protected) |
| `/admin/fotos/:kind/:id` | Photo management (protected) |

## Project structure

```
Sources/sorginameigaweb/
├── Models/          Fluent models + Pedigree, Language, Translation
├── Migrations/      schema + legacy data seed
├── Seed/            LegacySeed loader (reads Resources/seed/legacy.json)
├── Services/        LocalizationService, PageLayout
├── Controllers/     HomeController, DogController
├── Contexts/        Encodable view contexts
├── configure.swift  app/DB/migrations wiring
└── routes.swift
Resources/
├── Views/           Leaf templates (base, partials, pages)
└── seed/legacy.json production data snapshot
Public/              style.css, images/ (served statically)
```

## Getting started

### Prerequisites

- Swift 6.x toolchain
- Docker (for local PostgreSQL)

### Run locally

```bash
# 1. Start PostgreSQL (defined in docker-compose.yml)
docker compose up -d db

# 2. Apply migrations and seed the legacy production data
swift run sorginameigaweb migrate --yes

# 3. Start the server
swift run sorginameigaweb serve --hostname 127.0.0.1 --port 8080
```

Then open http://localhost:8080/.

### Tests

```bash
swift test
```

Some tests are integration tests and require the local Postgres to be up and
migrated (steps 1–2 above).

### Configuration

The database connection is read from environment variables (defaults match the
`db` service in `docker-compose.yml`):

| Variable | Default |
|---|---|
| `DATABASE_HOST` | `localhost` |
| `DATABASE_PORT` | `5432` |
| `DATABASE_USERNAME` | `vapor_username` |
| `DATABASE_PASSWORD` | `vapor_password` |
| `DATABASE_NAME` | `vapor_database` |

## Database & seed data

The production content (dogs, galleries, visit counter) is shipped as a seed in
`Resources/seed/legacy.json`, extracted from the live MySQL database with a
Latin1 → UTF-8 correction. Because the site's content changes rarely, the data
is seeded rather than imported live, so the app is self-contained and needs no
MySQL connection to stand up. Re-extract the seed before the final cutover to
pick up any recent changes.

## Migration phases

| Phase | Scope | Status |
|---|---|---|
| 1 | Home page — presentation text, menu, language switch | ✅ Done |
| 2 | Data layer — Postgres + Fluent models, legacy data seed, visit counter | ✅ Done |
| 3 | Dogs — listings by sex + detail with 4-generation pedigree | ✅ Done |
| 4 | Puppies + photo galleries | ✅ Done |
| 5 | Contact page (details only, matching current production) | ✅ Done |
| 6 | Admin area — CRUD + photo management, with security fixes (bcrypt, sessions, validated uploads) | ✅ Done |
| 7 | Deployment / cutover — container + managed DB, 301 redirects from legacy URLs | ⬜ Planned |

## Deployment target

The production target is **Google Cloud Run** (containerized, scales to zero)
with a **Neon** serverless PostgreSQL database. Both in an EU region; the
container is built in CI and pushed to a registry. Finalized in Phase 7.

## See more

- [Vapor Documentation](https://docs.vapor.codes)
- [Vapor GitHub](https://github.com/vapor)
