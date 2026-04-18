import AppIntents
import SwiftUI
import WidgetKit

private enum MeerkatTripRecordingAction: String {
    case start
    case stop
    case toggle

    var title: String {
        switch self {
        case .start:
            return "Start Trip"
        case .stop:
            return "Stop Trip"
        case .toggle:
            return "Toggle Trip"
        }
    }
}

private enum MeerkatWidgetBridge {
    static let appGroupID = "group.com.miletracker.app.Meerkat---Milage-Tracker"
    static let snapshotKey = "meerkat.widget.snapshot"
    static let urlScheme = "meerkat-mileage-tracker"

    static var openAppURL: URL {
        URL(string: "\(urlScheme)://open")!
    }

    static func tripTypeURL(rawValue: String) -> URL {
        URL(string: "\(urlScheme)://trip-type?value=\(rawValue)")!
    }

    static func tripRecordingURL(action: MeerkatTripRecordingAction) -> URL {
        URL(string: "\(urlScheme)://trip-recording?action=\(action.rawValue)")!
    }
}

private struct MeerkatWidgetSnapshot: Codable, Equatable {
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
        .result(opensIntent: OpenURLIntent(MeerkatWidgetBridge.tripTypeURL(rawValue: tripTypeRawValue)))
    }
}

@available(iOS 17.0, *)
private struct SetTripRecordingFromWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Trip Recording"
    static var description = IntentDescription("Starts or stops trip recording in Meerkat.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Action")
    var actionRawValue: String

    init() {
        actionRawValue = MeerkatTripRecordingAction.toggle.rawValue
    }

    init(action: MeerkatTripRecordingAction) {
        actionRawValue = action.rawValue
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        let action = MeerkatTripRecordingAction(rawValue: actionRawValue) ?? .toggle
        return .result(opensIntent: OpenURLIntent(MeerkatWidgetBridge.tripRecordingURL(action: action)))
    }
}

private struct MeerkatWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MeerkatWidgetSnapshot
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
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }

    private func loadSnapshot() -> MeerkatWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: MeerkatWidgetBridge.appGroupID),
              let data = defaults.data(forKey: MeerkatWidgetBridge.snapshotKey)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MeerkatWidgetSnapshot.self, from: data)
    }
}

private struct MeerkatGaugeTrack: View {
    var body: some View {
        Circle()
            .trim(from: 0.17, to: 0.83)
            .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 9, lineCap: .round))
            .rotationEffect(.degrees(90))
    }
}

private struct MeerkatGaugeHighlight: View {
    var body: some View {
        Circle()
            .trim(from: 0.17, to: 0.61)
            .stroke(
                AngularGradient(
                    colors: [Color.cyan, Color.green, Color.yellow, Color.orange],
                    center: .center,
                    startAngle: .degrees(-120),
                    endAngle: .degrees(120)
                ),
                style: StrokeStyle(lineWidth: 9, lineCap: .round)
            )
            .rotationEffect(.degrees(90))
    }
}

private struct MeerkatWidgetPrimaryEntryView: View {
    let entry: MeerkatWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var nextTripTypeRaw: String {
        entry.snapshot.tripTypeRawValue == "business" ? "personal" : "business"
    }

    private var nextTripTypeTitle: String {
        nextTripTypeRaw == "business" ? "Business" : "Personal"
    }

    private var recordingAction: MeerkatTripRecordingAction {
        entry.snapshot.isRecording ? .stop : .start
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(MeerkatWidgetBridge.openAppURL)
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
        VStack(alignment: .leading, spacing: 8) {
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

            HStack(spacing: 6) {
                switchTripTypeControl
                tripRecordingControl
            }
        }
    }

    private var mediumContent: some View {
        HStack(spacing: 12) {
            ZStack {
                MeerkatGaugeTrack()
                MeerkatGaugeHighlight()
                VStack(spacing: 2) {
                    Text(entry.snapshot.speedText)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(entry.snapshot.elapsedText)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.snapshot.odometerText)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    statusPill
                }

                HStack(spacing: 8) {
                    telemetryCard(title: "Trip", value: entry.snapshot.tripTypeTitle)
                    telemetryCard(title: "Distance", value: entry.snapshot.distanceText)
                }

                HStack(spacing: 10) {
                    Label(entry.snapshot.vehicleName, systemImage: "car.fill")
                        .lineLimit(1)
                    Label(entry.snapshot.driverName, systemImage: "person.fill")
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.84))

                HStack(spacing: 7) {
                    switchTripTypeControl
                    tripRecordingControl
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var accessoryContent: some View {
        HStack {
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
            Spacer(minLength: 6)
            Image(systemName: entry.snapshot.isRecording ? "record.circle.fill" : "pause.circle.fill")
                .foregroundStyle(entry.snapshot.isRecording ? Color.green : Color.white.opacity(0.8))
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
                chipLabel(systemName: "arrow.left.arrow.right", text: nextTripTypeTitle)
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: MeerkatWidgetBridge.tripTypeURL(rawValue: nextTripTypeRaw)) {
                chipLabel(systemName: "arrow.left.arrow.right", text: nextTripTypeTitle)
            }
        }
    }

    @ViewBuilder
    private var tripRecordingControl: some View {
        if #available(iOS 17.0, *) {
            Button(intent: SetTripRecordingFromWidgetIntent(action: recordingAction)) {
                chipLabel(systemName: entry.snapshot.isRecording ? "stop.fill" : "play.fill", text: recordingAction.title)
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: MeerkatWidgetBridge.tripRecordingURL(action: recordingAction)) {
                chipLabel(systemName: entry.snapshot.isRecording ? "stop.fill" : "play.fill", text: recordingAction.title)
            }
        }
    }

    private func chipLabel(systemName: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
            Text(text)
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

private struct MeerkatWidgetCompactEntryView: View {
    let entry: MeerkatWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.snapshot.isRecording ? "REC" : "READY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(entry.snapshot.isRecording ? Color.green : Color.white.opacity(0.82))
                Spacer(minLength: 8)
                Text(entry.snapshot.tripTypeTitle.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
            }

            Text(entry.snapshot.odometerText)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(entry.snapshot.vehicleName)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)

            Text(entry.snapshot.driverName)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(entry.snapshot.speedText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(entry.snapshot.distanceText)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(MeerkatWidgetBridge.openAppURL)
    }
}

private struct MeerkatWidgetBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.11, blue: 0.17), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.cyan.opacity(0.24), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 220
            )
        }
    }
}

struct MeerkatWidgetExtension: Widget {
    let kind: String = "MeerkatStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeerkatWidgetProvider()) { entry in
            MeerkatWidgetPrimaryEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    MeerkatWidgetBackground()
                }
        }
        .configurationDisplayName("Meerkat Status")
        .description("Odometer, trip status, vehicle/driver, and quick trip controls.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

struct MeerkatWidgetCompact: Widget {
    let kind: String = "MeerkatStatusCompactWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MeerkatWidgetProvider()) { entry in
            MeerkatWidgetCompactEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    MeerkatWidgetBackground()
                }
        }
        .configurationDisplayName("Meerkat Compact")
        .description("Compact odometer and trip status widget.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private extension MeerkatWidgetSnapshot {
    static let widgetPlaceholder = MeerkatWidgetSnapshot(
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

#Preview(as: .systemSmall) {
    MeerkatWidgetExtension()
} timeline: {
    MeerkatWidgetEntry(date: .now, snapshot: .widgetPlaceholder)
}
