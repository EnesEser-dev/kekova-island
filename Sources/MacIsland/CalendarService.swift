import AppKit
import EventKit

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let color: NSColor
    let meetingURL: URL?
}

/// Upcoming calendar events plus a heads-up shortly before each one starts.
final class CalendarService: ObservableObject {
    @Published private(set) var upcoming: [CalendarEvent] = []
    @Published private(set) var hasAccess = false

    var onReminder: ((CalendarEvent) -> Void)?

    static let reminderLeadTime: TimeInterval = 5 * 60
    private static let lookAhead: TimeInterval = 24 * 60 * 60
    private static let pollInterval: TimeInterval = 30
    private static let maxEvents = 3

    // Matches the join links of the common video call services.
    private static let meetingLinkPattern = try! NSRegularExpression(
        pattern: #"https://[\w.-]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|facetime\.apple\.com)/[^\s<>"]*"#,
        options: .caseInsensitive
    )

    private let store = EKEventStore()
    private var pollTimer: Timer?
    private var remindedEventIDs: Set<String> = []

    func start() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.hasAccess = granted
                guard granted else { return }
                self?.beginWatching()
            }
        }
    }

    func join(_ event: CalendarEvent) {
        guard let url = event.meetingURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }

    private func beginWatching() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func refresh() {
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now,
            end: now.addingTimeInterval(Self.lookAhead),
            calendars: nil
        )
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(Self.maxEvents)
            .map(Self.makeEvent)
        if events != upcoming {
            upcoming = events
        }
        remindIfDue(at: now)
    }

    private func remindIfDue(at now: Date) {
        for event in upcoming where !remindedEventIDs.contains(event.id) {
            let untilStart = event.startDate.timeIntervalSince(now)
            guard untilStart > 0, untilStart <= Self.reminderLeadTime else { continue }
            remindedEventIDs.insert(event.id)
            onReminder?(event)
        }
    }

    private static func makeEvent(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            // Recurring events share an identifier, so include the start to tell them apart.
            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            color: event.calendar?.color ?? .systemBlue,
            meetingURL: findMeetingURL(in: event)
        )
    }

    private static func findMeetingURL(in event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in candidates {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingLinkPattern.firstMatch(in: text, range: range),
               let matchRange = Range(match.range, in: text) {
                return URL(string: String(text[matchRange]))
            }
        }
        return nil
    }
}
