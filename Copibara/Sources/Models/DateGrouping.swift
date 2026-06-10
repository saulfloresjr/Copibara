import Foundation

// MARK: - Date Section

struct DateSection: Identifiable {
    let id: String   // e.g. "today", "yesterday"
    let title: String // e.g. "Today", "Yesterday"
    let items: [CopibaraItem]
}

// MARK: - Date Grouping

enum DateGrouping {

    /// Groups items into chronological date sections, newest first.
    /// Empty sections are omitted.
    static func group(_ items: [CopibaraItem]) -> [DateSection] {
        let calendar = Calendar.current
        let now = Date()

        let startOfToday = calendar.startOfDay(for: now)

        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday),
              let startOfThisWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday),
              let startOfThisMonth = calendar.date(byAdding: .day, value: -30, to: startOfToday)
        else { return [] }

        var today: [CopibaraItem] = []
        var yesterday: [CopibaraItem] = []
        var thisWeek: [CopibaraItem] = []
        var thisMonth: [CopibaraItem] = []
        var older: [CopibaraItem] = []

        for item in items {
            let date = item.createdAt
            if date >= startOfToday {
                today.append(item)
            } else if date >= startOfYesterday {
                yesterday.append(item)
            } else if date >= startOfThisWeek {
                thisWeek.append(item)
            } else if date >= startOfThisMonth {
                thisMonth.append(item)
            } else {
                older.append(item)
            }
        }

        // Build sections in order, skip empty ones
        var sections: [DateSection] = []

        let buckets: [(id: String, title: String, items: [CopibaraItem])] = [
            ("today",      "Today",      today),
            ("yesterday",  "Yesterday",  yesterday),
            ("this_week",  "This Week",  thisWeek),
            ("this_month", "This Month", thisMonth),
            ("older",      "Older",      older),
        ]

        for bucket in buckets {
            if !bucket.items.isEmpty {
                sections.append(DateSection(
                    id: bucket.id,
                    title: bucket.title,
                    items: bucket.items
                ))
            }
        }

        return sections
    }
}
