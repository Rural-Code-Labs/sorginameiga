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

        let activeNow = Self.parseScalar(try await runRealtime(
            RunRealtimeRequest(metrics: [.init(name: "activeUsers")]), token: token, on: client))

        let overview = Self.overview(daily: daily, today: Self.todayString(), activeNow: activeNow)
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

    /// Builds the overview from the daily series. `today` is `yyyyMMdd` in the
    /// property's timezone; if GA has no row for it yet (no visits), today = 0.
    static func overview(daily: [DailyPoint], today: String, activeNow: Int) -> AnalyticsOverview {
        AnalyticsOverview(
            daily: daily,
            today: daily.first(where: { $0.date == today })?.sessions ?? 0,
            last7: daily.suffix(7).reduce(0) { $0 + $1.sessions },
            last30: daily.reduce(0) { $0 + $1.sessions },
            activeNow: activeNow
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

struct AnalyticsOverview {
    let daily: [DailyPoint]
    let today: Int
    let last7: Int
    let last30: Int
    let activeNow: Int
}

// MARK: - GA4 Data API request/response shapes

struct RunReportRequest: Content {
    struct DateRange: Content { let startDate: String; let endDate: String }
    struct Dimension: Content { let name: String }
    struct Metric: Content { let name: String }
    struct OrderBy: Content {
        struct Dim: Content { let dimensionName: String }
        let dimension: Dim
    }
    let dateRanges: [DateRange]
    let dimensions: [Dimension]
    let metrics: [Metric]
    var orderBys: [OrderBy]? = nil
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
