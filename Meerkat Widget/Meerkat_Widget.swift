import SwiftUI
import WidgetKit

private enum WidgetConfiguration {
    static let appGroupID = "group.com.miletracker.app.Meerkat---Milage-Tracker"
    static let snapshotKey = "meerkat.widget.snapshot"
    static let urlScheme = "meerkat-mileage-tracker"

    static var openAppURL: URL {
        URL(string: "\(urlScheme)://open")!
    }

    static func tripTypeURL(_ rawValue: String) -> URL {
        URL(string: "\(urlScheme)://trip-type?value=\(rawValue)")!
    }
}

private struct WidgetSnapshot: Codable {
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

    static let placeholder = WidgetSnapshot(
        lastUpdated: .now,
        isRecording: false,
        tripTypeRawValue: "business",
        tripTypeTitle: "Business",
        speedText: "0 km/h",
        distanceText: "0.0 km",
        elapsedText: "00:00:00",
        elapsedTimeInterval: 0,
        tripStartDate: nil,
        odometerText: "0.0 km",
        vehicleName: "No vehicle selected",
        driverName: "No driver selected",
        statusText: "Ready to drive"
    )
}

private struct MeerkatWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

private struct MeerkatWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MeerkatWidgetEntry {
        MeerkatWidgetEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MeerkatWidgetEntry) -> Void) {
        completion(MeerkatWidgetEntry(date: .now, snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MeerkatWidgetEntry>) -> Void) {
        let entry = MeerkatWidgetEntry(date: .now, snapshot: loadSnapshot())
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 1, to: .now) ?? .now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func loadSnapshot() -> WidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: WidgetConfiguration.appGroupID),
            let data = defaults.data(forKey: WidgetConfiguration.snapshotKey)
        else {
            return .placeholder
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .placeholder
    }
}

private struct MeerkatWidgetView: View {
    let entry: MeerkatWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metrics
            details
            tripTypeLinks
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetConfiguration.openAppURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Meerkat")
                    .font(.headline.weight(.bold))
                Text(entry.snapshot.statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.snapshot.isRecording ? .red : .green)
            }

            Spacer()

            Text(entry.snapshot.tripTypeTitle)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.16), in: Capsule())
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metricBlock(title: "Speed", value: entry.snapshot.speedText)
            metricBlock(title: "Distance", value: entry.snapshot.distanceText)
            metricBlock(title: "Elapsed", value: elapsedView)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow(title: "Odometer", value: entry.snapshot.odometerText)
            if family != .systemSmall {
                detailRow(title: "Vehicle", value: entry.snapshot.vehicleName)
                detailRow(title: "Driver", value: entry.snapshot.driverName)
            }
        }
    }

    private var tripTypeLinks: some View {
        HStack(spacing: 8) {
            tripTypeLink(title: "Business", rawValue: "business", systemImage: "briefcase.fill")
            tripTypeLink(title: "Personal", rawValue: "personal", systemImage: "figure.walk")
        }
    }

    private var elapsedView: some View {
        Group {
            if entry.snapshot.isRecording, let tripStartDate = entry.snapshot.tripStartDate {
                Text(timerInterval: tripStartDate...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            } else {
                Text(entry.snapshot.elapsedText)
                    .monospacedDigit()
            }
        }
        .font(.headline.weight(.bold))
    }

    private func metricBlock(title: String, value: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metricBlock(title: String, value: String) -> some View {
        metricBlock(title: title, value: Text(value).font(.headline.weight(.bold)).monospacedDigit())
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
    }

    private func tripTypeLink(title: String, rawValue: String, systemImage: String) -> some View {
        let isSelected = entry.snapshot.tripTypeRawValue == rawValue
        return Link(destination: WidgetConfiguration.tripTypeURL(rawValue)) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? .orange : .background.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct MeerkatStatusWidget: Widget {
    let kind = "MeerkatStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeerkatWidgetProvider()) { entry in
            MeerkatWidgetView(entry: entry)
        }
        .configurationDisplayName("Trip Status")
        .description("See active trip progress, selected trip type, vehicle, and driver at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct MeerkatWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeerkatStatusWidget()
    }
}
