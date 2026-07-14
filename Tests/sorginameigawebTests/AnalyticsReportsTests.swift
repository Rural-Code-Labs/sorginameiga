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
}
