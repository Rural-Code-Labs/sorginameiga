@testable import sorginameigaweb
import Foundation
import Testing

/// Unit tests for the GA4 Data API response parsing and aggregation (phase 14).
/// Pure functions — no network, no property/token needed.
@Suite("Analytics reports")
struct AnalyticsReportsTests {

    private func decode(_ json: String) throws -> RunReportResponse {
        try JSONDecoder().decode(RunReportResponse.self, from: Data(json.utf8))
    }

    @Test("Parses the GA4 date/sessions runReport response into a sorted daily series")
    func parsesDaily() throws {
        // Deliberately out of order to check sorting.
        let json = """
        { "rows": [
          { "dimensionValues": [{"value":"20260712"}], "metricValues": [{"value":"7"}] },
          { "dimensionValues": [{"value":"20260710"}], "metricValues": [{"value":"3"}] },
          { "dimensionValues": [{"value":"20260711"}], "metricValues": [{"value":"5"}] }
        ] }
        """
        let daily = AnalyticsReports.parseDaily(try decode(json))
        #expect(daily == [
            DailyPoint(date: "20260710", sessions: 3),
            DailyPoint(date: "20260711", sessions: 5),
            DailyPoint(date: "20260712", sessions: 7),
        ])
    }

    @Test("Empty / missing rows parse to an empty series and zero scalar")
    func parsesEmpty() throws {
        #expect(AnalyticsReports.parseDaily(try decode("{}")).isEmpty)
        #expect(AnalyticsReports.parseScalar(try decode("{}")) == 0)
    }

    @Test("Realtime activeUsers is read as a scalar")
    func parsesScalar() throws {
        let json = """
        { "rows": [ { "metricValues": [{"value":"4"}] } ] }
        """
        #expect(AnalyticsReports.parseScalar(try decode(json)) == 4)
    }

    @Test("Parses (label, count) rows preserving order; maps device names")
    func parsesPairs() throws {
        let json = """
        { "rows": [
          { "dimensionValues": [{"value":"mobile"}], "metricValues": [{"value":"20"}] },
          { "dimensionValues": [{"value":"desktop"}], "metricValues": [{"value":"12"}] }
        ] }
        """
        let pairs = AnalyticsReports.parsePairs(try decode(json))
        #expect(pairs == [LabelCount(label: "mobile", value: 20), LabelCount(label: "desktop", value: 12)])
        #expect(AnalyticsReports.prettyDevice("mobile") == "Móvil")
        #expect(AnalyticsReports.prettyDevice("desktop") == "Escritorio")
    }

    @Test("Overview totals: 30-day sum, 7-day sum, today by date match")
    func aggregatesOverview() {
        // 10 days, 1 session each; today is the last date.
        let daily = (1...10).map { DailyPoint(date: String(format: "202607%02d", $0), sessions: 1) }
        let o = AnalyticsReports.overview(daily: daily, today: "20260710", activeNow: 2)
        #expect(o.last30 == 10)          // sum of all
        #expect(o.last7 == 7)            // last 7 days
        #expect(o.today == 1)            // the row dated today
        #expect(o.activeNow == 2)
    }

    @Test("today = 0 when GA has no row for today yet")
    func todayMissing() {
        let daily = [DailyPoint(date: "20260708", sessions: 5), DailyPoint(date: "20260709", sessions: 6)]
        let o = AnalyticsReports.overview(daily: daily, today: "20260710", activeNow: 0)
        #expect(o.today == 0)
        #expect(o.last30 == 11)
    }

    @Test("Chart SVG renders one bar per day with a tooltip and is well-formed")
    func chartSVG() {
        let daily = [DailyPoint(date: "20260709", sessions: 4), DailyPoint(date: "20260710", sessions: 8)]
        let svg = StatsChart.bars(daily)
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.hasSuffix("</svg>"))
        #expect(svg.contains("máx 8"))
        #expect(svg.contains("10/07: 8 visitas"))
        // one <rect> bar per day
        #expect(svg.components(separatedBy: "<rect").count - 1 == 2)
    }

    @Test("Parses the yearMonth/sessions response into a sorted monthly series")
    func parsesMonthly() throws {
        let json = """
        { "rows": [
          { "dimensionValues": [{"value":"202607"}], "metricValues": [{"value":"7"}] },
          { "dimensionValues": [{"value":"202605"}], "metricValues": [{"value":"3"}] },
          { "dimensionValues": [{"value":"202606"}], "metricValues": [{"value":"5"}] }
        ] }
        """
        #expect(AnalyticsReports.parseMonthly(try decode(json)) == [
            MonthlyPoint(month: "202605", sessions: 3),
            MonthlyPoint(month: "202606", sessions: 5),
            MonthlyPoint(month: "202607", sessions: 7),
        ])
    }

    @Test("Year total is the sum of the monthly series")
    func aggregatesYear() {
        let daily = [DailyPoint(date: "20260710", sessions: 1)]
        let monthly = [MonthlyPoint(month: "202606", sessions: 40), MonthlyPoint(month: "202607", sessions: 60)]
        let o = AnalyticsReports.overview(daily: daily, monthly: monthly, today: "20260710", activeNow: 0)
        #expect(o.lastYear == 100)
    }

    @Test("Countries get a flag + Spanish name from the ISO code")
    func parsesCountries() throws {
        let json = """
        { "rows": [
          { "dimensionValues": [{"value":"Spain"},{"value":"ES"}], "metricValues": [{"value":"30"}] },
          { "dimensionValues": [{"value":"Ruritania"},{"value":"(not set)"}], "metricValues": [{"value":"2"}] }
        ] }
        """
        let rows = AnalyticsReports.parseCountries(try decode(json))
        #expect(rows == [
            LabelCount(label: "🇪🇸 España", value: 30),
            LabelCount(label: "Ruritania", value: 2),   // invalid code → no flag, GA name kept
        ])
    }

    @Test("Flag emoji and channel names map as expected")
    func flagsAndChannels() {
        #expect(AnalyticsReports.flagEmoji("ES") == "🇪🇸")
        #expect(AnalyticsReports.flagEmoji("us") == "🇺🇸")
        #expect(AnalyticsReports.flagEmoji("ZZ") == "")
        #expect(AnalyticsReports.flagEmoji("(not set)") == "")
        #expect(AnalyticsReports.prettyChannel("Organic Search") == "Búsquedas en Google")
        #expect(AnalyticsReports.prettyChannel("Direct") == "Directo")
        #expect(AnalyticsReports.prettyChannel("Organic Social") == "Redes sociales")
    }

    @Test("Monthly chart SVG renders one bar per month with month labels")
    func monthlyChartSVG() {
        let monthly = [MonthlyPoint(month: "202606", sessions: 4), MonthlyPoint(month: "202607", sessions: 8)]
        let svg = StatsChart.monthlyBars(monthly)
        #expect(svg.hasPrefix("<svg"))
        #expect(svg.hasSuffix("</svg>"))
        #expect(svg.contains("máx 8"))
        #expect(svg.contains("jul 2026: 8 visitas"))
        #expect(svg.components(separatedBy: "<rect").count - 1 == 2)
    }
}
