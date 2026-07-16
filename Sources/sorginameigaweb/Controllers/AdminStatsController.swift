import Fluent
import Vapor

/// Admin stats page (`/admin/estadisticas`): shows Google Analytics visit data
/// inside the panel so the owners don't need analytics.google.com (phase 14).
/// Degrades gracefully: a "not configured" notice when `GA_PROPERTY_ID` is
/// unset, and a friendly error (logged) if the GA Data API call fails.
final class AdminStatsController: RouteCollection, Sendable {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("estadisticas", use: stats)
    }

    @Sendable
    func stats(req: Request) async throws -> View {
        let admin = try req.auth.require(Admin.self)
        let service = req.analyticsReports

        // Legacy site-wide counter (public footer total). Best-effort read: the
        // page still renders if the DB is unavailable.
        let legacyCount = try? await VisitCounter.find(VisitCounter.singletonID, on: req.db)?.count

        guard service.enabled else {
            return try await req.view.render("admin/stats", AdminStatsContext(
                username: admin.username, configured: false, error: nil, hasData: false,
                legacyCount: legacyCount,
                today: 0, last7: 0, last30: 0, lastYear: 0, activeNow: 0,
                chartSVG: "", monthlyChartSVG: "", countries: [], channels: [], devices: []))
        }

        do {
            let o = try await service.overview(on: req.client, logger: req.logger)
            return try await req.view.render("admin/stats", AdminStatsContext(
                username: admin.username, configured: true, error: nil, hasData: true,
                legacyCount: legacyCount,
                today: o.today, last7: o.last7, last30: o.last30, lastYear: o.lastYear, activeNow: o.activeNow,
                chartSVG: StatsChart.bars(o.daily),
                monthlyChartSVG: StatsChart.monthlyBars(o.monthly),
                countries: o.countries, channels: o.channels, devices: o.devices))
        } catch {
            req.logger.report(error: error)
            return try await req.view.render("admin/stats", AdminStatsContext(
                username: admin.username, configured: true,
                error: "No se pudieron cargar los datos de Google Analytics. Inténtalo de nuevo en unos minutos.",
                hasData: false, legacyCount: legacyCount,
                today: 0, last7: 0, last30: 0, lastYear: 0, activeNow: 0,
                chartSVG: "", monthlyChartSVG: "", countries: [], channels: [], devices: []))
        }
    }
}

/// Builds the 30-day trend as a self-contained inline SVG bar chart (single
/// series → brand accent, no legend). Theme-aware: bars use `var(--accent)` and
/// text uses the admin ink tokens, so it works in light and dark. Each bar
/// carries a native `<title>` tooltip. No external libraries → CSP-safe.
enum StatsChart {
    static func bars(_ daily: [DailyPoint]) -> String {
        let w = 720.0, h = 200.0
        let padL = 8.0, padR = 8.0, padT = 18.0, padB = 22.0
        let baseline = h - padB
        let plotH = baseline - padT
        let plotW = w - padL - padR
        let n = max(daily.count, 1)
        let slot = plotW / Double(n)
        let barW = max(slot - 2, 1)
        let maxVal = max(daily.map(\.sessions).max() ?? 0, 1)

        var svg = #"<svg class="stats-chart" viewBox="0 0 \#(Int(w)) \#(Int(h))" role="img" preserveAspectRatio="none" aria-label="Visitas por día en los últimos 30 días">"#
        // Baseline.
        svg += #"<line x1="\#(padL)" y1="\#(baseline)" x2="\#(w - padR)" y2="\#(baseline)" class="chart-axis"/>"#
        // Max reference label.
        svg += #"<text x="\#(padL)" y="\#(padT - 5)" class="chart-max">máx \#(maxVal)</text>"#

        for (i, point) in daily.enumerated() {
            let barH = Double(point.sessions) / Double(maxVal) * plotH
            let x = padL + Double(i) * slot + (slot - barW) / 2
            let y = baseline - barH
            let label = dayLabel(point.date)
            svg += #"<rect x="\#(round2(x))" y="\#(round2(y))" width="\#(round2(barW))" height="\#(round2(barH))" rx="2" class="chart-bar"><title>\#(label): \#(point.sessions) visitas</title></rect>"#
        }

        // A few x-axis date labels (first, ~middle, last).
        if !daily.isEmpty {
            let idxs = Set([0, daily.count / 2, daily.count - 1])
            for i in idxs.sorted() {
                let x = padL + Double(i) * slot + slot / 2
                svg += #"<text x="\#(round2(x))" y="\#(h - 6)" class="chart-xlabel" text-anchor="middle">\#(dayLabel(daily[i].date))</text>"#
            }
        }
        svg += "</svg>"
        return svg
    }

    /// Same bar chart for the 12-month yearly series. Fewer bars → a label under
    /// every month.
    static func monthlyBars(_ monthly: [MonthlyPoint]) -> String {
        let w = 720.0, h = 200.0
        let padL = 8.0, padR = 8.0, padT = 18.0, padB = 22.0
        let baseline = h - padB
        let plotH = baseline - padT
        let plotW = w - padL - padR
        let n = max(monthly.count, 1)
        let slot = plotW / Double(n)
        let barW = max(slot - 8, 1)
        let maxVal = max(monthly.map(\.sessions).max() ?? 0, 1)

        var svg = #"<svg class="stats-chart" viewBox="0 0 \#(Int(w)) \#(Int(h))" role="img" preserveAspectRatio="none" aria-label="Visitas por mes en los últimos 12 meses">"#
        svg += #"<line x1="\#(padL)" y1="\#(baseline)" x2="\#(w - padR)" y2="\#(baseline)" class="chart-axis"/>"#
        svg += #"<text x="\#(padL)" y="\#(padT - 5)" class="chart-max">máx \#(maxVal)</text>"#

        for (i, point) in monthly.enumerated() {
            let barH = Double(point.sessions) / Double(maxVal) * plotH
            let x = padL + Double(i) * slot + (slot - barW) / 2
            let y = baseline - barH
            svg += #"<rect x="\#(round2(x))" y="\#(round2(y))" width="\#(round2(barW))" height="\#(round2(barH))" rx="2" class="chart-bar"><title>\#(monthLabel(point.month)): \#(point.sessions) visitas</title></rect>"#
            let lx = padL + Double(i) * slot + slot / 2
            svg += #"<text x="\#(round2(lx))" y="\#(h - 6)" class="chart-xlabel" text-anchor="middle">\#(monthShort(point.month))</text>"#
        }
        svg += "</svg>"
        return svg
    }

    /// "yyyyMMdd" → "dd/MM".
    private static func dayLabel(_ yyyymmdd: String) -> String {
        guard yyyymmdd.count == 8 else { return yyyymmdd }
        let m = yyyymmdd.dropFirst(4).prefix(2)
        let d = yyyymmdd.suffix(2)
        return "\(d)/\(m)"
    }

    /// "yyyyMM" → "jul 2026".
    private static func monthLabel(_ yyyymm: String) -> String {
        guard yyyymm.count == 6 else { return yyyymm }
        return "\(monthName(Int(yyyymm.suffix(2)) ?? 0)) \(yyyymm.prefix(4))"
    }

    /// "yyyyMM" → "jul".
    private static func monthShort(_ yyyymm: String) -> String {
        guard yyyymm.count == 6 else { return yyyymm }
        return monthName(Int(yyyymm.suffix(2)) ?? 0)
    }

    private static func monthName(_ m: Int) -> String {
        let names = ["", "ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
        return (1...12).contains(m) ? names[m] : ""
    }

    private static func round2(_ x: Double) -> String {
        String(format: "%.1f", x)
    }
}
