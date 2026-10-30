import Foundation
import Observation
import UserNotifications

/// A notification the app wants delivered.
struct ReminderNotification: Hashable {
    var identifier: String
    var taskID: Int64
    var fireDate: Date
    var title: String
    var body: String
}

/// What the user did with a delivered notification.
enum ReminderResponse: Equatable {
    case open(taskID: Int64)
    case complete(taskID: Int64)
}

/// Delivers reminder notifications. Abstracted so tests can run without the notification centre,
/// which is only available inside an app bundle.
@MainActor
protocol ReminderScheduling: AnyObject {
    /// Replaces every pending notification with `notifications`.
    func schedule(_ notifications: [ReminderNotification])
    var onResponse: ((ReminderResponse) -> Void)? { get set }
    /// The user has turned notifications off for the app.
    var isBlocked: Bool { get }
}

@Observable
@MainActor
final class ReminderNotifier: NSObject, ReminderScheduling, UNUserNotificationCenterDelegate {
    private static let category = "task-reminder"
    nonisolated private static let completeAction = "complete"

    var onResponse: ((ReminderResponse) -> Void)? {
        didSet { deliverPendingResponse() }
    }
    private(set) var isBlocked = false

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var scheduled: [ReminderNotification] = []
    /// Each update waits for the one before, so they can't interleave.
    @ObservationIgnored private var update: Task<Void, Never>?
    /// A response that arrived before anyone was listening, e.g. the one that launched the app.
    @ObservationIgnored private var pendingResponse: ReminderResponse?

    /// `nil` when running outside an app bundle (`swift run`, tests), where notifications aren't available.
    static func makeIfAvailable() -> ReminderNotifier? {
        Bundle.main.bundleIdentifier == nil ? nil : ReminderNotifier()
    }

    private override init() {
        super.init()
        center.delegate = self
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "Complete")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [complete], intentIdentifiers: [])
        ])
    }

    func schedule(_ notifications: [ReminderNotification]) {
        guard notifications != scheduled else { return }
        scheduled = notifications
        let previous = update
        update = Task {
            await previous?.value
            await replacePending(with: notifications)
        }
    }

    private func replacePending(with notifications: [ReminderNotification]) async {
        if !notifications.isEmpty {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        isBlocked = await center.notificationSettings().authorizationStatus == .denied
        center.removeAllPendingNotificationRequests()
        for notification in notifications {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = ["taskID": NSNumber(value: notification.taskID)]
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: notification.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger))
        }
    }

    private func deliverPendingResponse() {
        guard let pendingResponse, let onResponse else { return }
        self.pendingResponse = nil
        onResponse(pendingResponse)
    }

    private func receive(_ response: ReminderResponse) {
        pendingResponse = response
        deliverPendingResponse()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let taskID = (response.notification.request.content.userInfo["taskID"] as? NSNumber)?.int64Value else {
            return
        }
        let isComplete = response.actionIdentifier == Self.completeAction
        await MainActor.run {
            receive(isComplete ? .complete(taskID: taskID) : .open(taskID: taskID))
        }
    }
}
