import SwiftUI

/// Five steps from the track to the full data accent, by quantile of the
/// non-zero values (so a few huge days don't wash out the rest).
struct HeatScale {
    private let thresholds: [Double]

    init(_ values: [Double]) {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { thresholds = []; return }
        thresholds = [0.25, 0.5, 0.75, 0.9].map { sorted[min(sorted.count - 1, Int(Double(sorted.count) * $0))] }
    }

    /// 0 (none) … 4 (top).
    func level(_ value: Double) -> Int {
        guard value > 0 else { return 0 }
        guard !thresholds.isEmpty else { return 4 }
        return 1 + thresholds.filter { value > $0 }.count.clamped(to: 0...3)
    }

    static func color(_ level: Int) -> Color {
        level == 0 ? Color.track : Color.dataAccent.opacity([0, 0.28, 0.5, 0.74, 1][level])
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// "Less ▢▢▢▢ More".
struct HeatLegend: View {
    var body: some View {
        HStack(spacing: 3) {
            Text("Less")
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(HeatScale.color(level))
                    .frame(width: 10, height: 10)
            }
            Text("More")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
    }
}

/// Magpie's usage heatmap: one cell per day for the last 53 weeks, weeks as
/// columns, Monday on top, month names above.
struct DailyHeatmap: View {
    /// Day start → value.
    let values: [Date: Double]
    let describe: (Double) -> String
    var weeks = 53

    var body: some View {
        let calendar = Self.mondayCalendar
        let today = calendar.startOfDay(for: Date())
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        let scale = HeatScale(Array(values.values))
        GeometryReader { geo in
            let labelWidth: CGFloat = 30
            let gap: CGFloat = 3
            let cell = max(6, min(16, (geo.size.width - labelWidth - gap * CGFloat(weeks - 1)) / CGFloat(weeks)))
            VStack(alignment: .leading, spacing: gap) {
                // Month names over the week a month starts in.
                ZStack(alignment: .topLeading) {
                    ForEach(0..<weeks, id: \.self) { column in
                        let weekStart = calendar.date(byAdding: .weekOfYear, value: column, to: firstWeek)!
                        if let monthStart = Self.monthStart(inWeekOf: weekStart, calendar: calendar) {
                            Text(monthStart.formatted(.dateTime.month(.abbreviated)))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .offset(x: labelWidth + CGFloat(column) * (cell + gap))
                        }
                    }
                }
                .frame(height: 13)
                HStack(alignment: .top, spacing: gap) {
                    VStack(alignment: .leading, spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            Text(["Mon", "", "Wed", "", "Fri", "", "Sun"][row])
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .frame(width: labelWidth - gap, height: cell, alignment: .leading)
                        }
                    }
                    ForEach(0..<weeks, id: \.self) { column in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let day = calendar.date(byAdding: .day, value: column * 7 + row, to: firstWeek)!
                                let value = values[day] ?? 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(day > today ? Color.clear : HeatScale.color(scale.level(value)))
                                    .frame(width: cell, height: cell)
                                    .help(day > today ? "" : "\(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(describe(value))")
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 13 + 3 + 7 * 13 + 6 * 3)
    }

    /// Weeks start on Monday, as Magpie draws them.
    static var mondayCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    private static func monthStart(inWeekOf weekStart: Date, calendar: Calendar) -> Date? {
        for offset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            if calendar.component(.day, from: day) == 1 { return day }
        }
        return nil
    }
}

/// Weekday × hour: when you work (Magpie's "By hour"), Monday on top.
struct HourHeatmap: View {
    /// [weekday 0 = Monday][hour 0…23] → value.
    let grid: [[Double]]
    let describe: (Double) -> String

    var body: some View {
        let scale = HeatScale(grid.flatMap { $0 })
        GeometryReader { geo in
            let labelWidth: CGFloat = 30
            let gap: CGFloat = 3
            let cell = max(8, (geo.size.width - labelWidth - gap * 23) / 24)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<7, id: \.self) { day in
                    HStack(spacing: gap) {
                        Text(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][day])
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(width: labelWidth - gap, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let value = grid[day][hour]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(HeatScale.color(scale.level(value)))
                                .frame(width: cell, height: min(cell, 16))
                                .help("\(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][day]) \(hour):00 – \(hour + 1):00: \(describe(value))")
                        }
                    }
                }
                HStack(spacing: 0) {
                    Spacer().frame(width: labelWidth)
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text("\(hour)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(width: (cell + gap) * 6, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: 7 * 16 + 6 * 3 + 16)
    }
}
