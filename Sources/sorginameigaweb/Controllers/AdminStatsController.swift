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
            return try await req.view.render("admin/stats", AdminStatsContext.empty(
                username: admin.username, legacyCount: legacyCount, configured: false, error: nil))
        }

        do {
            let v = try await service.stats(month: req.query["month"], year: req.query["year"],
                                            on: req.client, logger: req.logger)
            return try await req.view.render("admin/stats", AdminStatsContext(
                username: admin.username, configured: true, error: nil, hasData: true,
                legacyCount: legacyCount,
                today: v.today, last7: v.last7, last30: v.last30, lastYear: v.lastYear, activeNow: v.activeNow,
                chartSVG: StatsChart.bars(v.daily),
                monthlyChartSVG: StatsChart.monthlyBars(v.monthly, selectedMonth: v.selectedMonth, year: v.selectedYear),
                rangeLabel: v.rangeLabel, rangeTotal: v.rangeTotal, selectedMonth: v.selectedMonth,
                selectedYear: v.selectedYear,
                years: v.years.map { YearOption(year: $0, selected: $0 == v.selectedYear) },
                countries: v.countries, channels: v.channels, devices: v.devices))
        } catch {
            req.logger.report(error: error)
            return try await req.view.render("admin/stats", AdminStatsContext.empty(
                username: admin.username, legacyCount: legacyCount, configured: true,
                error: "No se pudieron cargar los datos de Google Analytics. Inténtalo de nuevo en unos minutos."))
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

    /// Bar chart for a calendar year's monthly series. Each bar is a link that
    /// drills into that month (`?month=yyyyMM&year=…`); the selected month is
    /// highlighted. Fewer bars → a label under every month.
    static func monthlyBars(_ monthly: [MonthlyPoint], selectedMonth: String?, year: Int) -> String {
        let w = 720.0, h = 200.0
        let padL = 8.0, padR = 8.0, padT = 18.0, padB = 22.0
        let baseline = h - padB
        let plotH = baseline - padT
        let plotW = w - padL - padR
        let n = max(monthly.count, 1)
        let slot = plotW / Double(n)
        let barW = max(slot - 8, 1)
        let maxVal = max(monthly.map(\.sessions).max() ?? 0, 1)

        var svg = #"<svg class="stats-chart" viewBox="0 0 \#(Int(w)) \#(Int(h))" role="img" preserveAspectRatio="none" aria-label="Visitas por mes en \#(year)">"#
        svg += #"<line x1="\#(padL)" y1="\#(baseline)" x2="\#(w - padR)" y2="\#(baseline)" class="chart-axis"/>"#
        svg += #"<text x="\#(padL)" y="\#(padT - 5)" class="chart-max">máx \#(maxVal)</text>"#

        for (i, point) in monthly.enumerated() {
            let barH = Double(point.sessions) / Double(maxVal) * plotH
            let x = padL + Double(i) * slot + (slot - barW) / 2
            let y = baseline - barH
            let selected = point.month == selectedMonth
            let cls = selected ? "chart-bar chart-bar--selected" : "chart-bar"
            let href = "/admin/estadisticas?month=\(point.month)&year=\(year)"
            // Full-height hit area so short/empty months are still clickable.
            svg += #"<a href="\#(href)" class="chart-link">"#
            svg += #"<rect x="\#(round2(x))" y="\#(round2(padT))" width="\#(round2(barW))" height="\#(round2(plotH))" class="chart-hit"/>"#
            svg += #"<rect x="\#(round2(x))" y="\#(round2(y))" width="\#(round2(barW))" height="\#(round2(barH))" rx="2" class="\#(cls)"><title>\#(monthLabel(point.month)): \#(point.sessions) visitas</title></rect>"#
            svg += "</a>"
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
