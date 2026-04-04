import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum WidgetBridge {
    static let appGroupID = "group.com.miletracker.app.Meerkat---Milage-Tracker"
    static let snapshotKey = "meerkat.widget.snapshot"
    static let lastReloadDateKey = "meerkat.widget.lastReloadDate"
    static let urlScheme = "meerkat-mileage-tracker"
    static let reloadInterval: TimeInterval = 15

    static var openAppURL: URL {
        URL(string: "\(urlScheme)://open")!
    }

    static func tripTypeURL(_ tripType: TripType) -> URL {
        URL(string: "\(urlScheme)://trip-type?value=\(tripType.rawValue)")!
    }

    static func save(snapshot: AppWidgetSnapshot, forceReload: Bool = false) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let encodedSnapshot = try? encoder.encode(snapshot) else {
            return
        }

        let previousSnapshotData = defaults.data(forKey: snapshotKey)
        guard forceReload || previousSnapshotData != encodedSnapshot else {
            return
        }

        defaults.set(encodedSnapshot, forKey: snapshotKey)
        reloadAllTimelinesIfNeeded(force: forceReload, defaults: defaults)
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }

        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: lastReloadDateKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private static func reloadAllTimelinesIfNeeded(force: Bool, defaults: UserDefaults) {
        #if canImport(WidgetKit)
        let now = Date()
        let lastReloadDate = defaults.object(forKey: lastReloadDateKey) as? Date
        let shouldReload = force || lastReloadDate == nil || now.timeIntervalSince(lastReloadDate!) >= reloadInterval

        guard shouldReload else {
            return
        }

        defaults.set(now, forKey: lastReloadDateKey)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

struct AppWidgetSnapshot: Codable, Equatable {
    var lastUpdated: Date
    var isRecording: Bool
    var tripTypeRawValue: String
    var tripTypeTitle: String
    var speedText: String
    var distanceText: String
    var elapsedText: String
    var elapsedTimeInterval: TimeInterval
    var tripStartDate: Date?
    var odometerText: String
    var vehicleName: String
    var driverName: String
    var statusText: String
}
