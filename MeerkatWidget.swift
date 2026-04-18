#if WIDGET_EXTENSION
import SwiftUI
import WidgetKit
import AppIntents

private struct MeerkatWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AppWidgetSnapshot
}

@available(iOS 17.0, *)
private struct SwitchTripTypeFromWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Trip Type"
    static var description = IntentDescription("Switches the selected trip type in Meerkat.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Trip Type")
    var tripTypeRawValue: String

    init() {
        tripTypeRawValue = "business"
    }

    init(tripTypeRawValue: String) {
        self.tripTypeRawValue = tripTypeRawValue
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetBridge.tripTypeURL(rawValue: tripTypeRawValue)))
    }
}

private struct MeerkatWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MeerkatWidgetEntry {
        MeerkatWidgetEntry(date: .now, snapshot: .widgetPlaceholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (MeerkatWidgetEntry) -> Void) {
        completion(MeerkatWidgetEntry(date: .now, snapshot: loadSnapshot() ?? .widgetPlaceholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MeerkatWidgetEntry>) -> Void) {
        let snapshot = loadSnapshot() ?? .widgetPlaceholder
        let entry = MeerkatWidgetEntry(date: .now, snapshot: snapshot)
        let nextRefreshDate = Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(nextRefreshDate)))
    }

    private func loadSnapshot() -> AppWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: WidgetBridge.appGroupID),
              let data = defaults.data(forKey: WidgetBridge.snapshotKey)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppWidgetSnapshot.self, from: data)
    }
}

private struct MeerkatWidgetView: View {
    let entry: MeerkatWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var nextTripTypeRaw: String {
        entry.snapshot.tripTypeRawValue == "business" ? "personal" : "business"
    }

    private var nextTripTypeTitle: String {
        nextTripTypeRaw == "business" ? "Business" : "Personal"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.11, blue: 0.17), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            content
                .padding(12)
        }
        .widgetURL(WidgetBridge.openAppURL)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallContent
        case .systemMedium, .systemLarge:
            mediumContent
        case .accessoryRectangular:
            accessoryContent
        default:
            smallContent
        }
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusPill
            Text(entry.snapshot.odometerText)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(entry.snapshot.vehicleName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)

            Text(entry.snapshot.driverName)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 0)

            switchTripTypeControl
        }
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.snapshot.odometerText)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 10)
                statusPill
            }

            HStack(spacing: 8) {
                telemetryCard(title: "Trip", value: entry.snapshot.tripTypeTitle)
                telemetryCard(title: "Speed", value: entry.snapshot.speedText)
                telemetryCard(title: "Distance", value: entry.snapshot.distanceText)
            }

            HStack(spacing: 10) {
                Label(entry.snapshot.vehicleName, systemImage: "car.fill")
                    .lineLimit(1)
                Label(entry.snapshot.driverName, systemImage: "person.fill")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.85))

            Spacer(minLength: 0)

            HStack {
                switchTripTypeControl
                Spacer(minLength: 8)
                Text(entry.snapshot.statusText)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
    }

    private var accessoryContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.snapshot.odometerText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
            Text(entry.snapshot.isRecording ? "Recording" : "Ready")
                .font(.caption2)
                .foregroundStyle(entry.snapshot.isRecording ? Color.green : Color.white.opacity(0.75))
                .lineLimit(1)
            Text(entry.snapshot.tripTypeTitle)
                .font(.caption2)
                .lineLimit(1)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(entry.snapshot.isRecording ? Color.green : Color.white.opacity(0.55))
                .frame(width: 7, height: 7)
            Text(entry.snapshot.isRecording ? "Recording" : "Ready")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.12)))
    }

    @ViewBuilder
    private var switchTripTypeControl: some View {
        if #available(iOS 17.0, *) {
            Button(intent: SwitchTripTypeFromWidgetIntent(tripTypeRawValue: nextTripTypeRaw)) {
                switchTripTypeLabel
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: WidgetBridge.tripTypeURL(rawValue: nextTripTypeRaw)) {
                switchTripTypeLabel
            }
        }
    }

    private var switchTripTypeLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.left.arrow.right")
            Text("Switch to \(nextTripTypeTitle)")
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.16))
        )
    }

    private func telemetryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.7))
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }
}

@main
struct MeerkatWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeerkatStatusWidget()
    }
}

private struct MeerkatStatusWidget: Widget {
    let kind = "MeerkatStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeerkatWidgetProvider()) { entry in
            MeerkatWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Meerkat Status")
        .description("View odometer, trip status, active vehicle and driver, and quickly switch trip type.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

private extension AppWidgetSnapshot {
    static let widgetPlaceholder = AppWidgetSnapshot(
        lastUpdated: .now,
        isRecording: true,
        tripTypeRawValue: "business",
        tripTypeTitle: "Business",
        speedText: "55 mph",
        distanceText: "12.4 mi",
        elapsedText: "00:22:14",
        elapsedTimeInterval: 1_334,
        tripStartDate: .now.addingTimeInterval(-1_334),
        odometerText: "42,350.7 mi",
        vehicleName: "Ford Ranger",
        driverName: "Alex Driver",
        statusText: "Recording • Good GPS"
    )
}
#endif
