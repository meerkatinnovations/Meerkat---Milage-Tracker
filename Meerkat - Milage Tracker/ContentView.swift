//
//  ContentView.swift
//  Meerkat - Milage Tracker
//
//  Created by Rheeder Greeff on 2026-03-15.
//

import CoreLocation
import Observation
import SwiftUI

struct ContentView: View {
    @State private var store = MileageStore()
    @State private var tripTracker = TripTracker()

    var body: some View {
        TabView {
            NavigationStack {
                TripsView(store: store, tripTracker: tripTracker)
            }
            .tabItem {
                Label("Trips", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }

            NavigationStack {
                FuelView(store: store)
            }
            .tabItem {
                Label("Fuel", systemImage: "fuelpump")
            }

            NavigationStack {
                MaintenanceView(store: store)
            }
            .tabItem {
                Label("Maintenance", systemImage: "wrench.and.screwdriver")
            }

            NavigationStack {
                LogsView(store: store)
            }
            .tabItem {
                Label("Logs", systemImage: "doc.text")
            }

            NavigationStack {
                SettingsView(store: store, tripTracker: tripTracker)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(.orange)
        .background(Color(.systemGroupedBackground))
    }
}

private struct TripsView: View {
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                activeTripCard
                summaryGrid
                recentTripsSection
            }
            .padding()
        }
        .navigationTitle("Trips")
    }

    private var activeTripCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(tripTracker.isTracking ? "Trip in progress" : "Ready to drive", systemImage: "location.fill")
                .font(.headline)

            Text(store.unitSystem.distanceString(for: tripTracker.currentTripDistance))
                .font(.system(size: 40, weight: .bold, design: .rounded))

            HStack {
                statPill(title: "Elapsed", value: tripTracker.elapsedTimeString)
                statPill(title: "Speed", value: store.unitSystem.speedString(for: tripTracker.currentSpeed))
            }

            Text(tripTracker.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                if tripTracker.isTracking {
                    if let trip = tripTracker.stopTracking() {
                        store.addTrip(trip)
                    }
                } else {
                    startTracking()
                }
            } label: {
                Label(tripTracker.isTracking ? "Stop Trip" : "Start Trip", systemImage: tripTracker.isTracking ? "stop.circle.fill" : "play.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.orange.opacity(0.95), .brown.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .foregroundStyle(.white)
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            summaryCard(title: "Today", value: store.unitSystem.distanceString(for: store.distanceToday))
            summaryCard(title: "This week", value: store.unitSystem.distanceString(for: store.distanceThisWeek))
            summaryCard(title: "Fuel spend", value: store.currencyString(for: store.totalFuelSpend))
            summaryCard(title: "Maintenance", value: "\(store.maintenanceRecords.count) open items")
        }
    }

    private var recentTripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Trips")
                .font(.title3.weight(.semibold))

            ForEach(store.trips.prefix(5)) { trip in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(trip.name)
                            .font(.headline)
                        Spacer()
                        Text(store.unitSystem.distanceString(for: trip.distanceMeters))
                            .font(.subheadline.weight(.semibold))
                    }

                    HStack {
                        Label(trip.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        Spacer()
                        Label(trip.duration.formattedDuration, systemImage: "clock")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .opacity(0.85)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func startTracking() {
        switch tripTracker.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            tripTracker.startTracking()
            store.addLog("Trip tracking started")
        case .notDetermined:
            tripTracker.requestAuthorization()
            store.addLog("Requested location permission")
        case .denied, .restricted:
            store.addLog("Location permission blocked")
        @unknown default:
            store.addLog("Unknown location permission state")
        }
    }
}

private struct FuelView: View {
    @Bindable var store: MileageStore
    @State private var isPresentingAddFuel = false
    @State private var stationName = ""
    @State private var liters = ""
    @State private var cost = ""
    @State private var odometer = ""

    var body: some View {
        List {
            Section("Summary") {
                statRow("Entries", "\(store.fuelEntries.count)")
                statRow("Total spend", store.currencyString(for: store.totalFuelSpend))
                statRow("Average fill", store.averageFuelVolumeText)
            }

            Section("Recent Fuel Stops") {
                ForEach(store.fuelEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.station)
                                .font(.headline)
                            Spacer()
                            Text(store.currencyString(for: entry.totalCost))
                                .font(.subheadline.weight(.semibold))
                        }

                        Text("\(entry.volumeText) • Odometer \(entry.odometerText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Fuel")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddFuel = true
                } label: {
                    Label("Add Fuel", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddFuel) {
            NavigationStack {
                Form {
                    TextField("Station", text: $stationName)
                    TextField("Volume", text: $liters)
                        .keyboardType(.decimalPad)
                    TextField("Cost", text: $cost)
                        .keyboardType(.decimalPad)
                    TextField("Odometer", text: $odometer)
                        .keyboardType(.numberPad)
                }
                .navigationTitle("New Fuel Entry")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismissFuelSheet()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveFuelEntry()
                        }
                        .disabled(!canSaveFuelEntry)
                    }
                }
            }
        }
    }

    private var canSaveFuelEntry: Bool {
        !stationName.isEmpty && Double(liters) != nil && Double(cost) != nil && Double(odometer) != nil
    }

    private func saveFuelEntry() {
        guard
            let volume = Double(liters),
            let totalCost = Double(cost),
            let mileage = Double(odometer)
        else {
            return
        }

        store.addFuelEntry(
            FuelEntry(
                station: stationName,
                volume: volume,
                totalCost: totalCost,
                odometer: mileage,
                date: .now
            )
        )
        dismissFuelSheet()
    }

    private func dismissFuelSheet() {
        isPresentingAddFuel = false
        stationName = ""
        liters = ""
        cost = ""
        odometer = ""
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MaintenanceView: View {
    @Bindable var store: MileageStore
    @State private var isPresentingAddMaintenance = false
    @State private var serviceTitle = ""
    @State private var dueMileage = ""
    @State private var notes = ""

    var body: some View {
        List {
            ForEach(store.maintenanceRecords) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(record.title)
                            .font(.headline)
                        Spacer()
                        Text(record.priority.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(record.priority.color.opacity(0.16), in: Capsule())
                            .foregroundStyle(record.priority.color)
                    }

                    Text("Due at \(record.dueMileageText)")
                        .foregroundStyle(.secondary)

                    if !record.notes.isEmpty {
                        Text(record.notes)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Maintenance")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingAddMaintenance = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddMaintenance) {
            NavigationStack {
                Form {
                    TextField("Service", text: $serviceTitle)
                    TextField("Due Mileage", text: $dueMileage)
                        .keyboardType(.numberPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                .navigationTitle("Maintenance Task")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismissMaintenanceSheet()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveMaintenanceRecord()
                        }
                        .disabled(serviceTitle.isEmpty || Double(dueMileage) == nil)
                    }
                }
            }
        }
    }

    private func saveMaintenanceRecord() {
        guard let mileage = Double(dueMileage) else {
            return
        }

        store.addMaintenanceRecord(
            MaintenanceRecord(
                title: serviceTitle,
                dueMileage: mileage,
                notes: notes,
                priority: .upcoming
            )
        )
        dismissMaintenanceSheet()
    }

    private func dismissMaintenanceSheet() {
        isPresentingAddMaintenance = false
        serviceTitle = ""
        dueMileage = ""
        notes = ""
    }
}

private struct LogsView: View {
    @Bindable var store: MileageStore

    var body: some View {
        List(store.logs) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.headline)
                Text(entry.date.formatted(date: .abbreviated, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Logs")
    }
}

private struct SettingsView: View {
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker

    var body: some View {
        Form {
            Section("Units") {
                Picker("Distance", selection: $store.unitSystem) {
                    ForEach(DistanceUnitSystem.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
            }

            Section("Tracking") {
                Toggle("Auto-start reminders", isOn: $store.autoStartReminders)
                Toggle("Keep screen awake on trip", isOn: $store.preventAutoLock)
                HStack {
                    Text("Location access")
                    Spacer()
                    Text(tripTracker.authorizationLabel)
                        .foregroundStyle(.secondary)
                }
                Button("Request Location Access") {
                    tripTracker.requestAuthorization()
                    store.addLog("Manual location permission request")
                }
            }

            Section("About") {
                LabeledContent("Tracked trips", value: "\(store.trips.count)")
                LabeledContent("Last sync", value: "Local only")
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    ContentView()
}
