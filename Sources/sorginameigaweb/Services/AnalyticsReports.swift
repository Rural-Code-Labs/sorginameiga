import Foundation
import Vapor

/// Reads visit data from the **Google Analytics 4 Data API** so it can be shown
/// in the admin panel (phase 14 / v2.4). The owners don't use
/// analytics.google.com, so the numbers are brought into the admin instead.
///
/// Disabled unless `GA_PROPERTY_ID` (the numeric GA4 property id) is set — with
/// it unset (local/dev, tests) the stats page shows a "not configured" notice
/// and nothing here runs. Auth uses an OAuth token for the read-only Analytics
/// scope obtained from, in order: the `GA_ACCESS_TOKEN` env override (local
/// smoke tests), or the Cloud Run metadata server (production; the service
/// account must be a Viewer on the GA property). No key files.
final class AnalyticsReports: Sendable {
    let propertyID: String
    var enabled: Bool { !propertyID.isEmpty }

    private let tokens = TokenCache()
    private let cache = OverviewCache()

    init(propertyID: String) {
        self.propertyID = propertyID.trimmingCharacters(in: .whitespaces)
    }

    static func fromEnvironment() -> AnalyticsReports {
        AnalyticsReports(propertyID: Environment.get("GA_PROPERTY_ID") ?? "")
    }

    // MARK: - Public API

    /// Visits overview: a 30-day daily series plus today / 7-day / 30-day totals
    /// and the current real-time active users. Cached ~10 min.
    func overview(on client: any Client, logger: Logger) async throws -> AnalyticsOverview {
        if let cached = await cache.value() { return cached }

        let token = try await tokens.token(on: client, logger: logger)
        let daily = Self.parseDaily(try await runReport(
            RunReportRequest(
                dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
                dimensions: [.init(name: "date")],
                metrics: [.init(name: "sessions")],
                orderBys: [.init(dimension: .init(dimensionName: "date"))]
            ), token: token, on: client))

        // Monthly series for the last 12 months (also the source of the year total).
        let monthly = Self.parseMonthly(try await runReport(
            RunReportRequest(
                dateRanges: [.init(startDate: "365daysAgo", endDate: "today")],
                dimensions: [.init(name: "yearMonth")],
                metrics: [.init(name: "sessions")],
                orderBys: [.init(dimension: .init(dimensionName: "yearMonth"))]
            ), token: token, on: client))

        let activeNow = Self.parseScalar(try await runRealtime(
            RunRealtimeRequest(metrics: [.init(name: "activeUsers")]), token: token, on: client))

        // Countries: request the ISO code alongside the name so we can show a flag.
        let countries = Self.parseCountries(try await runReport(RunReportRequest(
            dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
            dimensions: [.init(name: "country"), .init(name: "countryId")],
            metrics: [.init(name: "sessions")],
            orderBys: [.init(metric: .init(metricName: "sessions"), desc: true)],
            limit: 6), token: token, on: client))

        func top(_ dimension: String, metric: String, limit: Int) async throws -> [LabelCount] {
            Self.parsePairs(try await runReport(RunReportRequest(
                dateRanges: [.init(startDate: "30daysAgo", endDate: "today")],
                dimensions: [.init(name: dimension)],
                metrics: [.init(name: metric)],
                orderBys: [.init(metric: .init(metricName: metric), desc: true)],
                limit: limit), token: token, on: client))
        }
        let channels = try await top("sessionDefaultChannelGroup", metric: "sessions", limit: 6)
            .map { LabelCount(label: Self.prettyChannel($0.label), value: $0.value) }
        let devices = try await top("deviceCategory", metric: "sessions", limit: 4)
            .map { LabelCount(label: Self.prettyDevice($0.label), value: $0.value) }

        let overview = Self.overview(daily: daily, monthly: monthly, today: Self.todayString(),
                                     activeNow: activeNow, countries: countries,
                                     channels: channels, devices: devices)
        await cache.store(overview)
        return overview
    }

    // MARK: - HTTP

    private func runReport(_ body: RunReportRequest, token: String, on client: any Client) async throws -> RunReportResponse {
        try await post("properties/\(propertyID):runReport", body: body, token: token, on: client)
    }

    private func runRealtime(_ body: RunRealtimeRequest, token: String, on client: any Client) async throws -> RunReportResponse {
        try await post("properties/\(propertyID):runRealtimeReport", body: body, token: token, on: client)
    }

    private func post<Body: Content>(_ path: String, body: Body, token: String, on client: any Client) async throws -> RunReportResponse {
        let uri = URI(string: "https://analyticsdata.googleapis.com/v1beta/\(path)")
        var headers = HTTPHeaders()
        headers.bearerAuthorization = .init(token: token)
        let res = try await client.post(uri, headers: headers) { req in
            try req.content.encode(body, as: .json)
        }
        guard res.status == .ok else {
            let detail = res.body.map { String(buffer: $0) } ?? ""
            throw Abort(.badGateway, reason: "GA Data API \(res.status.code): \(detail.prefix(300))")
        }
        return try res.content.decode(RunReportResponse.self)
    }

    // MARK: - Pure parsing / aggregation (unit-tested)

    static func parseDaily(_ resp: RunReportResponse) -> [DailyPoint] {
        (resp.rows ?? []).compactMap { row in
            guard let date = row.dimensionValues?.first?.value,
                  let raw = row.metricValues?.first?.value, let value = Int(raw) else { return nil }
            return DailyPoint(date: date, sessions: value)
        }.sorted { $0.date < $1.date }
    }

    static func parseScalar(_ resp: RunReportResponse) -> Int {
        Int(resp.rows?.first?.metricValues?.first?.value ?? "0") ?? 0
    }

    /// Rows of (dimension label, metric value), preserving the API's order.
    static func parsePairs(_ resp: RunReportResponse) -> [LabelCount] {
        (resp.rows ?? []).compactMap { row in
            guard let label = row.dimensionValues?.first?.value,
                  let raw = row.metricValues?.first?.value, let value = Int(raw) else { return nil }
            return LabelCount(label: label, value: value)
        }
    }

    static func parseMonthly(_ resp: RunReportResponse) -> [MonthlyPoint] {
        (resp.rows ?? []).compactMap { row in
            guard let month = row.dimensionValues?.first?.value,
                  let raw = row.metricValues?.first?.value, let value = Int(raw) else { return nil }
            return MonthlyPoint(month: month, sessions: value)
        }.sorted { $0.month < $1.month }
    }

    /// Rows of (country name, countryId, sessions) → a flag + Spanish name label.
    static func parseCountries(_ resp: RunReportResponse) -> [LabelCount] {
        (resp.rows ?? []).compactMap { row in
            let dims = row.dimensionValues ?? []
            guard dims.count >= 2,
                  let raw = row.metricValues?.first?.value, let value = Int(raw) else { return nil }
            let display = spanishCountry(dims[1].value) ?? dims[0].value
            let flag = flagEmoji(dims[1].value)
            return LabelCount(label: flag.isEmpty ? display : "\(flag) \(display)", value: value)
        }
    }

    static func prettyDevice(_ category: String) -> String {
        switch category.lowercased() {
        case "desktop": return "Escritorio"
        case "mobile": return "Móvil"
        case "tablet": return "Tablet"
        default: return category.capitalized
        }
    }

    /// GA4 default channel group → owner-friendly Spanish.
    static func prettyChannel(_ channel: String) -> String {
        switch channel.lowercased() {
        case "organic search": return "Búsquedas en Google"
        case "direct": return "Directo"
        case "organic social", "social": return "Redes sociales"
        case "referral": return "Enlaces de otras webs"
        case "email": return "Correo electrónico"
        case "paid search": return "Búsquedas de pago"
        case "organic video", "video": return "Vídeo"
        case "unassigned": return "Sin asignar"
        default: return channel.capitalized
        }
    }

    /// Regional-indicator flag emoji for a 2-letter ISO country code
    /// ("ES" → 🇪🇸). Empty for missing/invalid codes ("(not set)", "ZZ").
    static func flagEmoji(_ iso: String) -> String {
        let code = iso.uppercased()
        guard code.count == 2, code != "ZZ", code.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "" }
        var flag = ""
        for scalar in code.unicodeScalars {
            guard let indicator = Unicode.Scalar(0x1F1E6 - 65 + scalar.value) else { return "" }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }

    /// Spanish name for the most likely visitor countries; nil → fall back to
    /// GA's (English) country name.
    static func spanishCountry(_ iso: String) -> String? {
        switch iso.uppercased() {
        case "ES": return "España"
        case "US": return "Estados Unidos"
        case "GB": return "Reino Unido"
        case "FR": return "Francia"
        case "DE": return "Alemania"
        case "PT": return "Portugal"
        case "IT": return "Italia"
        case "MX": return "México"
        case "AR": return "Argentina"
        case "CO": return "Colombia"
        case "CL": return "Chile"
        case "PE": return "Perú"
        case "VE": return "Venezuela"
        case "BR": return "Brasil"
        case "NL": return "Países Bajos"
        case "BE": return "Bélgica"
        case "IE": return "Irlanda"
        case "CH": return "Suiza"
        case "AT": return "Austria"
        case "PL": return "Polonia"
        case "SE": return "Suecia"
        case "NO": return "Noruega"
        case "DK": return "Dinamarca"
        case "FI": return "Finlandia"
        case "CA": return "Canadá"
        case "AU": return "Australia"
        case "MA": return "Marruecos"
        case "AD": return "Andorra"
        default: return nil
        }
    }

    /// Builds the overview from the daily + monthly series. `today` is
    /// `yyyyMMdd` in the property's timezone; if GA has no row for it yet (no
    /// visits), today = 0. The year total is the sum of the monthly series.
    static func overview(daily: [DailyPoint], monthly: [MonthlyPoint] = [], today: String,
                         activeNow: Int, countries: [LabelCount] = [],
                         channels: [LabelCount] = [], devices: [LabelCount] = []) -> AnalyticsOverview {
        AnalyticsOverview(
            daily: daily,
            monthly: monthly,
            today: daily.first(where: { $0.date == today })?.sessions ?? 0,
            last7: daily.suffix(7).reduce(0) { $0 + $1.sessions },
            last30: daily.reduce(0) { $0 + $1.sessions },
            lastYear: monthly.reduce(0) { $0 + $1.sessions },
            activeNow: activeNow,
            countries: countries, channels: channels, devices: devices
        )
    }

    static func todayString(timeZone: String = "Europe/Madrid") -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: timeZone)
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}

// MARK: - Value types

/// One day of the trend series. `date` is `yyyyMMdd` (GA4 `date` dimension).
struct DailyPoint: Encodable, Equatable {
    let date: String
    let sessions: Int
}

/// One month of the yearly series. `month` is `yyyyMM` (GA4 `yearMonth`).
struct MonthlyPoint: Encodable, Equatable {
    let month: String
    let sessions: Int
}

/// A dimension value with its count (top pages, countries, devices).
struct LabelCount: Encodable, Equatable {
    let label: String
    let value: Int
}

struct AnalyticsOverview {
    let daily: [DailyPoint]
    var monthly: [MonthlyPoint] = []
    let today: Int
    let last7: Int
    let last30: Int
    var lastYear: Int = 0
    let activeNow: Int
    var countries: [LabelCount] = []
    var channels: [LabelCount] = []
    var devices: [LabelCount] = []
}

// MARK: - GA4 Data API request/response shapes

struct RunReportRequest: Content {
    struct DateRange: Content { let startDate: String; let endDate: String }
    struct Dimension: Content { let name: String }
    struct Metric: Content { let name: String }
    struct OrderBy: Content {
        struct Dim: Content { let dimensionName: String }
        struct Met: Content { let metricName: String }
        var dimension: Dim? = nil
        var metric: Met? = nil
        var desc: Bool? = nil
    }
    let dateRanges: [DateRange]
    let dimensions: [Dimension]
    let metrics: [Metric]
    var orderBys: [OrderBy]? = nil
    var limit: Int? = nil
}

struct RunRealtimeRequest: Content {
    struct Metric: Content { let name: String }
    let metrics: [Metric]
}

struct RunReportResponse: Content {
    struct Value: Content { let value: String }
    struct Row: Content {
        var dimensionValues: [Value]? = nil
        var metricValues: [Value]? = nil
    }
    var rows: [Row]? = nil
}

// MARK: - Token + report caches

/// Caches the OAuth access token until shortly before it expires.
private actor TokenCache {
    private var token: String?
    private var expiry: Date = .distantPast

    func token(on client: any Client, logger: Logger) async throws -> String {
        // Local/testing override — a manually supplied token, always used as-is.
        if let override = Environment.get("GA_ACCESS_TOKEN"),
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return override
        }
        if let token, expiry > Date() { return token }

        // Cloud Run metadata server → the runtime service account's token.
        let uri = URI(string: "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token?scopes=https://www.googleapis.com/auth/analytics.readonly")
        var headers = HTTPHeaders()
        headers.add(name: "Metadata-Flavor", value: "Google")
        let res = try await client.get(uri, headers: headers)
        guard res.status == .ok else {
            throw Abort(.badGateway, reason: "metadata token \(res.status.code)")
        }
        let meta = try res.content.decode(MetadataToken.self)
        token = meta.access_token
        expiry = Date().addingTimeInterval(TimeInterval(max(meta.expires_in - 60, 30)))
        return meta.access_token
    }

    private struct MetadataToken: Content {
        let access_token: String
        let expires_in: Int
    }
}

/// Caches the overview for a few minutes (the admin is low-traffic; avoid
/// hitting the API on every page load).
private actor OverviewCache {
    private var cached: AnalyticsOverview?
    private var expiry: Date = .distantPast
    private let ttl: TimeInterval = 600

    func value() -> AnalyticsOverview? { expiry > Date() ? cached : nil }
    func store(_ overview: AnalyticsOverview) {
        cached = overview
        expiry = Date().addingTimeInterval(ttl)
    }
}

// MARK: - Application storage

extension Application {
    private struct AnalyticsReportsKey: StorageKey { typealias Value = AnalyticsReports }

    var analyticsReports: AnalyticsReports {
        get {
            guard let service = storage[AnalyticsReportsKey.self] else {
                fatalError("AnalyticsReports not configured. Set app.analyticsReports in configure(_:).")
            }
            return service
        }
        set { storage[AnalyticsReportsKey.self] = newValue }
    }
}

extension Request {
    var analyticsReports: AnalyticsReports { application.analyticsReports }
}
