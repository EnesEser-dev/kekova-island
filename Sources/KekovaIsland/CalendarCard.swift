import SwiftUI

struct CalendarCard: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        Group {
            if !calendar.hasAccess {
                placeholder(
                    symbol: "calendar.badge.exclamationmark",
                    text: "Calendar access is off",
                    action: ("Open Privacy settings", calendar.openCalendarPrivacySettings)
                )
            } else if calendar.upcoming.isEmpty {
                placeholder(symbol: "calendar", text: "Nothing coming up in the next 24 hours", action: nil)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 6) {
                        ForEach(calendar.upcoming) { event in
                            EventRow(event: event, now: context.date) { calendar.join(event) }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func placeholder(symbol: String, text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            if let (title, perform) = action {
                Button(title, action: perform)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let onJoin: () -> Void

    private var isSoon: Bool {
        event.startDate > now && event.startDate.timeIntervalSince(now) <= CalendarService.reminderLeadTime
    }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(Color(nsColor: event.color))
                .frame(width: 4, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(timeRange)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(relativeStart)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSoon ? .orange : .white.opacity(0.5))
            if event.meetingURL != nil {
                Button(action: onJoin) {
                    Text("Join")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeRange: String {
        let start = event.startDate.formatted(date: .omitted, time: .shortened)
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    private var relativeStart: String {
        if event.startDate <= now { return "Now" }
        let minutes = Int((event.startDate.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "in \(minutes) min" }
        if Calendar.current.isDateInToday(event.startDate) {
            return "in \(minutes / 60) h \(minutes % 60) min"
        }
        return "Tomorrow"
    }
}
