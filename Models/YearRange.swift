import Foundation

/// 西暦の年境界 [start, end) を与えるユーティリティ
struct YearRange {
    let start: Date
    let end: Date

    init(year: Int, calendar: Calendar = .current) {
        var c = DateComponents()
        c.calendar = calendar
        c.year = year
        c.month = 1
        c.day = 1
        c.hour = 0
        c.minute = 0
        c.second = 0
        self.start = calendar.date(from: c)! // 年始

        var n = DateComponents()
        n.calendar = calendar
        n.year = year + 1
        n.month = 1
        n.day = 1
        n.hour = 0
        n.minute = 0
        n.second = 0
        self.end = calendar.date(from: n)!   // 翌年の年始（半開区間の上限）
    }
}