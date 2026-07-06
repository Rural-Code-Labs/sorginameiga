# Sorgiña Meiga

Website for **Sorgiña-Meiga**, a Lhasa Apso dog kennel run by Pilar Díaz and
Estíbaliz Domínguez (breeders since 1994). This repository is the modern rewrite
of the kennel's website, built with [Vapor](https://vapor.codes) (server-side
Swift).

## Background

The original site (`old_web/` in the parent repository) was written ~13 years
ago in procedural PHP and ran **live in production until 2026-07-06**, when this
rewrite took over the domain and the legacy PHP/MySQL host was decommissioned.
Its sanitized source is archived at
[Rural-Code-Labs/sorginameiga_old](https://github.com/Rural-Code-Labs/sorginameiga_old).
The legacy code was severely outdated: it used the `mysql_*` extension (removed
in PHP 7.0), had SQL injection throughout, stored the admin password in plain
text, and had no build system, tests, CI, or version control.

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
- **Content ordering.** Dogs, puppies and galleries carry a `position` and their
  photos are ordered by file name; the admin reorders both with ↑/↓ (lists) and
  ←/→ (photos). Because reordering swaps file contents under the same URL, photo
  URLs carry a `?v=` cache-buster so browsers reload the changed image.
- **Social links & lightbox.** The header shows Instagram/Facebook icons
  (`SocialLinks`, overridable via `INSTAGRAM_URL` / `FACEBOOK_URL`). Public photos
  open in an on-page overlay (`Public/lightbox.js`, vanilla JS) with prev/next
  navigation within the same group.
- **Analytics (opt-in, consent-gated).** When `GA_MEASUREMENT_ID` is set, the
  public site loads Google Analytics 4 behind **Google Consent Mode v2** — every
  storage is denied until the visitor accepts a bilingual cookie banner
  (`Analytics` service, banner in `base.leaf`). With the variable unset, no tag
  or banner is emitted; the admin area is never tracked.

### Data model

| Model | Table | Notes |
|---|---|---|
| `Dog` | `dogs` | `name`, `sex` (`macho`/`hembra`), `pedigree` (JSON), `position` |
| `Puppy` | `puppies` | `name`, `available`, `position` |
| `Gallery` | `galleries` | `name`, `position` |
| `VisitCounter` | `visit_counter` | single row; site-wide visit count |

`position` is the admin-controlled display order (lower shows first). Photos
are numbered files (`0.jpg`, `1.jpg`, …) and reordered by swapping their names;
for dogs `0.jpg` is the cover photo.

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
| `/admin/{perros,cachorros,galerias}` | CRUD + reorder (protected) |
| `/admin/fotos/:kind/:id` | Photo management + reorder (protected) |

## Project structure

```
Sources/sorginameigaweb/
├── Models/          Fluent models + Pedigree, Language, Translation
├── Migrations/      schema + legacy data seed
├── Seed/            LegacySeed loader (reads Resources/seed/legacy.json)
├── Services/        LocalizationService, PageLayout, PhotoStorage, PhotoDirectory, SocialLinks
├── Controllers/     public (Home, Dog, Gallery, Puppy, Contact) + admin (Dog, Puppy, Gallery, Photo)
├── Contexts/        Encodable view contexts
├── configure.swift  app/DB/migrations wiring
└── routes.swift
Resources/
├── Views/           Leaf templates (base, partials, pages)
└── seed/legacy.json production data snapshot
Public/              style.css, admin.css, lightbox.js, images/ (served statically)
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

In production a single `DATABASE_URL` (the Neon pooled connection string, with
`sslmode=require`) takes precedence over the individual `DATABASE_*` vars.
Optional overrides: `ADMIN_PASSWORD` (seeds the admin password on first migrate),
`INSTAGRAM_URL` / `FACEBOOK_URL` (header social links), and `GA_MEASUREMENT_ID`
(a GA4 Measurement ID, e.g. `G-XXXXXXXXXX`, that enables Google Analytics on the
public site behind a cookie-consent banner; analytics is off when it is unset).

## Database & seed data

The production content (dogs, galleries, visit counter) is shipped as a seed in
`Resources/seed/legacy.json`, extracted from the live MySQL database with a
Latin1 → UTF-8 correction. Because the site's content changes rarely, the data
is seeded rather than imported live, so the app is self-contained and needs no
MySQL connection to stand up. At the final cutover the content was already the
source of truth in Postgres, so only the live visit counter was re-synced from
the legacy database (now decommissioned).

## Migration phases

| Phase | Scope | Status |
|---|---|---|
| 1 | Home page — presentation text, menu, language switch | ✅ Done |
| 2 | Data layer — Postgres + Fluent models, legacy data seed, visit counter | ✅ Done |
| 3 | Dogs — listings by sex + detail with 4-generation pedigree | ✅ Done |
| 4 | Puppies + photo galleries | ✅ Done |
| 5 | Contact page (details only, matching current production) | ✅ Done |
| 6 | Admin area — CRUD + photo management, with security fixes (bcrypt, sessions, validated uploads) | ✅ Done |
| 7 | Visual redesign — modern responsive layout, light/dark theme (public + admin) | ✅ Done |
| 8 | Deployment — Cloud Run + Neon + GCS images bucket, 301 redirects; **live** | ✅ Done |
| 9 | Features (v2.1) — manual ordering of content & photos, Instagram/Facebook links, on-page photo lightbox | ✅ Done |
| 10 | Production backups — daily database `pg_dump` to GCS + image bucket versioning | ✅ Done |
| 11 | Domain + DNS cutover to `sorginameiga.com` (managed HTTPS, legacy decommissioned) | ✅ Done |
| 12 | Analytics (v2.2) — Google Analytics 4 behind a cookie-consent banner (Consent Mode v2); site-wide orthography review | ✅ Done |

The site is **live in production** at **https://sorginameiga.com** on Google
Cloud Run (`europe-west1`), with Google-managed SSL. The legacy PHP/MySQL host
has been decommissioned. Deployment details are in
[`deploy/DEPLOY.md`](deploy/DEPLOY.md).

## Deployment target

The production target is **Google Cloud Run** (containerized, scales to zero)
with a **Neon** serverless PostgreSQL database and a **GCS** bucket for images
(mounted as a volume). All in an EU region; the container image is built in the
cloud (Cloud Build, native amd64) and pushed to Artifact Registry. The container
runs `serve` only — schema migrations are applied to Neon out-of-band.

## See more

- [Vapor Documentation](https://docs.vapor.codes)
- [Vapor GitHub](https://github.com/vapor)
