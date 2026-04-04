//
//  Item.swift
//  Meerkat - Milage Tracker
//
//  Created by Rheeder Greeff on 2026-03-15.
//

import CoreLocation
import Observation
import SwiftUI

enum DistanceUnitSystem: String, CaseIterable, Identifiable {
    case miles
    case kilometers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .miles:
            return "Miles"
        case .kilometers:
            return "Kilometers"
        }
    }

    func convertedDistance(for meters: Double) -> Double {
        switch self {
        case .miles:
            return meters / 1_609.344
        case .kilometers:
            return meters / 1_000
        }
    }

    func meters(forDisplayedDistance displayedDistance: Double) -> Double {
        switch self {
        case .miles:
            return displayedDistance * 1_609.344
        case .kilometers:
            return displayedDistance * 1_000
        }
    }

    func distanceString(for meters: Double) -> String {
        let value = convertedDistance(for: meters)
        let unit = self == .miles ? "mi" : "km"
        return "\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }

    func speedString(for metersPerSecond: Double) -> String {
        let converted = convertedDistance(for: metersPerSecond * 3_600)
        let unit = self == .miles ? "mph" : "km/h"
        return "\(converted.formatted(.number.precision(.fractionLength(0)))) \(unit)"
    }
}

enum TripType: String, CaseIterable, Identifiable {
    case business
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .business:
            return "Business"
        case .personal:
            return "Personal"
        }
    }

    var systemImage: String {
        switch self {
        case .business:
            return "briefcase.fill"
        case .personal:
            return "figure.walk"
        }
    }
}

enum VehicleOwnershipType: String, CaseIterable, Identifiable {
    case personal
    case company
    case rental

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal:
            return "Personal"
        case .company:
            return "Company"
        case .rental:
            return "Rental"
        }
    }
}

struct VehicleProfile: Identifiable {
    let id = UUID()
    let profileName: String
    let make: String
    let model: String
    let color: String
    let numberPlate: String
    let startingOdometerReading: Double
    let ownershipType: VehicleOwnershipType

    var displayName: String {
        profileName.isEmpty ? "\(make) \(model)" : profileName
    }

    var subtitle: String {
        "\(make) \(model) • \(numberPlate)"
    }
}

struct DriverProfile: Identifiable {
    let id = UUID()
    let name: String
    let dateOfBirth: Date
    let licenceNumber: String

    var subtitle: String {
        "\(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) • \(licenceNumber)"
    }
}

struct Trip: Identifiable {
    var id = UUID()
    var name: String
    var type: TripType
    var vehicleID: UUID?
    var vehicleProfileName: String
    var driverID: UUID?
    var driverName: String
    var startAddress: String
    var endAddress: String
    var details: String
    var odometerStart: Double
    var odometerEnd: Double
    var distanceMeters: Double
    var duration: TimeInterval
    var date: Date

    var requiresBusinessDetailsAttention: Bool {
        type == .business && details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct FuelEntry: Identifiable {
    let id = UUID()
    let station: String
    let volume: Double
    let totalCost: Double
    let odometer: Double
    let date: Date

    var volumeText: String {
        "\(volume.formatted(.number.precision(.fractionLength(1)))) L"
    }

    var odometerText: String {
        "\(Int(odometer))"
    }
}

struct MaintenanceRecord: Identifiable {
    enum Priority: String {
        case upcoming = "Upcoming"
        case soon = "Soon"
        case urgent = "Urgent"

        var color: Color {
            switch self {
            case .upcoming:
                return .blue
            case .soon:
                return .orange
            case .urgent:
                return .red
            }
        }
    }

    let id = UUID()
    let title: String
    let dueMileage: Double
    let notes: String
    let priority: Priority

    var dueMileageText: String {
        "\(Int(dueMileage)) mi"
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
}

@MainActor
@Observable
final class MileageStore {
    var unitSystem: DistanceUnitSystem = .miles
    var preventAutoLock = false
    var vehicles: [VehicleProfile] = []
    var activeVehicleID: UUID?
    var drivers: [DriverProfile] = []
    var activeDriverID: UUID?
    var trips: [Trip] = []
    var fuelEntries: [FuelEntry] = []
    var maintenanceRecords: [MaintenanceRecord] = []
    var logs: [LogEntry] = []

    var activeVehicle: VehicleProfile? {
        guard let activeVehicleID else {
            return nil
        }

        return vehicles.first { $0.id == activeVehicleID }
    }

    var activeDriver: DriverProfile? {
        guard let activeDriverID else {
            return nil
        }

        return drivers.first { $0.id == activeDriverID }
    }

    var isReadyToDrive: Bool {
        activeVehicle != nil && activeDriver != nil
    }

    func trip(for id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    func vehicle(for id: UUID?) -> VehicleProfile? {
        guard let id else { return nil }
        return vehicles.first { $0.id == id }
    }

    func driver(for id: UUID?) -> DriverProfile? {
        guard let id else { return nil }
        return drivers.first { $0.id == id }
    }

    func currentOdometerReading(activeTripDistanceMeters: Double) -> Double {
        guard let vehicle = activeVehicle else {
            return 0
        }

        let latestRecordedOdometer = trips
            .filter { $0.vehicleID == vehicle.id }
            .sorted { $0.date > $1.date }
            .first?
            .odometerEnd ?? vehicle.startingOdometerReading

        return latestRecordedOdometer + unitSystem.convertedDistance(for: activeTripDistanceMeters)
    }

    func currentBaseOdometerReading() -> Double {
        currentOdometerReading(activeTripDistanceMeters: 0)
    }

    var totalFuelSpend: Double {
        fuelEntries.reduce(0) { $0 + $1.totalCost }
    }

    var averageFuelVolumeText: String {
        guard !fuelEntries.isEmpty else {
            return "0.0 L"
        }

        let average = fuelEntries.reduce(0) { $0 + $1.volume } / Double(fuelEntries.count)
        return "\(average.formatted(.number.precision(.fractionLength(1)))) L"
    }

    func currencyString(for amount: Double) -> String {
        amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    func addTrip(_ trip: Trip) {
        let preparedTrip = prepareTripForInsertion(trip)
        trips.insert(preparedTrip, at: 0)
        sortTripsDescending()
        reconcileTripChain(for: preparedTrip.vehicleID, anchorTripID: preparedTrip.id, preferredStart: preparedTrip.odometerStart, preferredEnd: preparedTrip.odometerEnd)
        addLog("Completed trip: \(preparedTrip.name)")
    }

    func updateTrip(_ updatedTrip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == updatedTrip.id }) else {
            return
        }

        let originalTrip = trips[index]
        trips[index] = prepareTripForUpdate(updatedTrip)
        sortTripsDescending()

        let affectedVehicleIDs = Set([originalTrip.vehicleID, trips[index].vehicleID].compactMap { $0 })
        for vehicleID in affectedVehicleIDs {
            if vehicleID == trips[index].vehicleID {
                reconcileTripChain(
                    for: vehicleID,
                    anchorTripID: trips[index].id,
                    preferredStart: trips[index].odometerStart,
                    preferredEnd: trips[index].odometerEnd
                )
            } else {
                reconcileTripChain(for: vehicleID, anchorTripID: nil, preferredStart: nil, preferredEnd: nil)
            }
        }

        addLog("Updated trip: \(trips[index].name)")
    }

    func addFuelEntry(_ entry: FuelEntry) {
        fuelEntries.insert(entry, at: 0)
        addLog("Fuel entry added for \(entry.station)")
    }

    func addMaintenanceRecord(_ record: MaintenanceRecord) {
        maintenanceRecords.insert(record, at: 0)
        addLog("Maintenance task scheduled: \(record.title)")
    }

    func addVehicle(_ vehicle: VehicleProfile) {
        vehicles.append(vehicle)

        if activeVehicleID == nil {
            activeVehicleID = vehicle.id
        }

        addLog("Vehicle added: \(vehicle.displayName)")
    }

    func addDriver(_ driver: DriverProfile) {
        drivers.append(driver)

        if activeDriverID == nil {
            activeDriverID = driver.id
        }

        addLog("Driver added: \(driver.name)")
    }

    func addLog(_ title: String) {
        logs.insert(LogEntry(title: title, date: .now), at: 0)
    }

    private func prepareTripForInsertion(_ trip: Trip) -> Trip {
        var preparedTrip = trip
        if let vehicle = activeVehicle {
            preparedTrip.vehicleID = vehicle.id
            preparedTrip.vehicleProfileName = vehicle.displayName
        }
        if let driver = activeDriver {
            preparedTrip.driverID = driver.id
            preparedTrip.driverName = driver.name
        }
        preparedTrip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(preparedTrip.odometerEnd - preparedTrip.odometerStart, 0))
        return preparedTrip
    }

    private func prepareTripForUpdate(_ trip: Trip) -> Trip {
        var preparedTrip = trip
        if let vehicle = vehicle(for: trip.vehicleID) {
            preparedTrip.vehicleProfileName = vehicle.displayName
        }
        if let driver = driver(for: trip.driverID) {
            preparedTrip.driverName = driver.name
        }
        preparedTrip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(preparedTrip.odometerEnd - preparedTrip.odometerStart, 0))
        return preparedTrip
    }

    private func sortTripsDescending() {
        trips.sort { $0.date > $1.date }
    }

    private func reconcileTripChain(for vehicleID: UUID?, anchorTripID: UUID?, preferredStart: Double?, preferredEnd: Double?) {
        guard let vehicleID, let vehicle = vehicle(for: vehicleID) else {
            return
        }

        let sortedIndices = trips.indices
            .filter { trips[$0].vehicleID == vehicleID }
            .sorted { trips[$0].date < trips[$1].date }

        guard !sortedIndices.isEmpty else {
            return
        }

        let anchorPosition = anchorTripID.flatMap { id in
            sortedIndices.firstIndex { trips[$0].id == id }
        }

        if let anchorPosition {
            let anchorIndex = sortedIndices[anchorPosition]
            var anchorTrip = trips[anchorIndex]
            anchorTrip.odometerStart = preferredStart ?? anchorTrip.odometerStart
            anchorTrip.odometerEnd = max(preferredEnd ?? anchorTrip.odometerEnd, anchorTrip.odometerStart)
            anchorTrip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(anchorTrip.odometerEnd - anchorTrip.odometerStart, 0))
            trips[anchorIndex] = anchorTrip

            var runningStart = anchorTrip.odometerStart
            if anchorPosition > 0 {
                for position in stride(from: anchorPosition - 1, through: 0, by: -1) {
                    let index = sortedIndices[position]
                    var trip = trips[index]
                    trip.odometerEnd = runningStart
                    trip.odometerStart = min(trip.odometerStart, trip.odometerEnd)
                    trip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(trip.odometerEnd - trip.odometerStart, 0))
                    trips[index] = trip
                    runningStart = trip.odometerStart
                }
            }

            var runningEnd = anchorTrip.odometerEnd
            if anchorPosition < sortedIndices.count - 1 {
                for position in (anchorPosition + 1) ..< sortedIndices.count {
                    let index = sortedIndices[position]
                    var trip = trips[index]
                    let displayedDistance = unitSystem.convertedDistance(for: trip.distanceMeters)
                    trip.odometerStart = runningEnd
                    trip.odometerEnd = trip.odometerStart + displayedDistance
                    trip.distanceMeters = unitSystem.meters(forDisplayedDistance: displayedDistance)
                    trips[index] = trip
                    runningEnd = trip.odometerEnd
                }
            }
        } else {
            var runningEnd = vehicle.startingOdometerReading
            for position in sortedIndices.indices {
                let index = sortedIndices[position]
                var trip = trips[index]
                let displayedDistance = unitSystem.convertedDistance(for: trip.distanceMeters)
                trip.odometerStart = position == 0 ? trip.odometerStart : runningEnd
                if position == 0 && trip.odometerStart == 0 {
                    trip.odometerStart = vehicle.startingOdometerReading
                }
                if position == 0 && trip.odometerStart < vehicle.startingOdometerReading {
                    trip.odometerStart = vehicle.startingOdometerReading
                }
                trip.odometerEnd = trip.odometerStart + displayedDistance
                trip.distanceMeters = unitSystem.meters(forDisplayedDistance: displayedDistance)
                trips[index] = trip
                runningEnd = trip.odometerEnd
            }
        }

        sortTripsDescending()
    }
}

@MainActor
@Observable
final class TripTracker: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var startLocation: CLLocation?
    @ObservationIgnored private var endLocation: CLLocation?
    @ObservationIgnored private var tripStartDate: Date?
    @ObservationIgnored private var tripStartOdometerReading: Double?
    @ObservationIgnored private let tripTypeGracePeriod: TimeInterval = 15 * 60

    var authorizationStatus: CLAuthorizationStatus
    var autoStartEnabled = true
    var autoStartSpeedThresholdKilometersPerHour = 10.0
    var canRecordTrips = false
    var isTracking = false
    var selectedTripType: TripType = .business
    var currentTripDistance: Double = 0
    var currentSpeed: Double = 0

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = true
        refreshLocationMonitoring()
    }

    var statusMessage: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard canRecordTrips else {
                return "Not ready to drive. Add and select a vehicle and driver before recording."
            }
            if isTracking {
                return "Using GPS updates to calculate your live mileage."
            }
            if autoStartEnabled {
                return "Monitoring for speeds above \(autoStartSpeedThresholdKilometersPerHour.formatted(.number.precision(.fractionLength(0)))) km/h to auto-start a trip."
            }
            return "Location access is ready."
        case .notDetermined:
            return "Allow location access to start trip tracking."
        case .denied, .restricted:
            return "Enable location access in Settings to track mileage."
        @unknown default:
            return "Location state unavailable."
        }
    }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .authorizedAlways:
            return "Always"
        case .authorizedWhenInUse:
            return "When In Use"
        case .notDetermined:
            return "Not Set"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }

    var elapsedTimeString: String {
        guard let tripStartDate else {
            return "00:00"
        }

        return Date.now.timeIntervalSince(tripStartDate).formattedDuration
    }

    var canChangeTripTypeWithoutSplitting: Bool {
        guard let tripStartDate, isTracking else {
            return true
        }

        return Date.now.timeIntervalSince(tripStartDate) <= tripTypeGracePeriod
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startTracking(startOdometerReading: Double? = nil) {
        guard !isTracking, canRecordTrips else {
            return
        }

        isTracking = true
        currentTripDistance = 0
        lastLocation = nil
        tripStartDate = .now
        tripStartOdometerReading = startOdometerReading
        startLocation = lastLocation
        endLocation = lastLocation
        refreshLocationMonitoring()
    }

    func stopTracking() async -> Trip? {
        guard isTracking else {
            return nil
        }

        isTracking = false
        refreshLocationMonitoring()

        let trip = await completedTrip()

        currentTripDistance = 0
        currentSpeed = 0
        lastLocation = nil
        startLocation = nil
        endLocation = nil
        tripStartDate = nil
        tripStartOdometerReading = nil

        return trip
    }

    func selectTripType(_ tripType: TripType, nextTripStartOdometerReading: Double? = nil) async -> Trip? {
        guard tripType != selectedTripType else {
            return nil
        }

        guard isTracking else {
            selectedTripType = tripType
            return nil
        }

        if canChangeTripTypeWithoutSplitting {
            selectedTripType = tripType
            return nil
        }

        let completedTrip = await completedTrip()
        selectedTripType = tripType
        currentTripDistance = 0
        lastLocation = nil
        startLocation = endLocation
        tripStartDate = .now
        tripStartOdometerReading = nextTripStartOdometerReading

        return completedTrip
    }

    func setTripStartOdometerReadingIfNeeded(_ reading: Double) {
        guard isTracking, tripStartOdometerReading == nil else {
            return
        }

        tripStartOdometerReading = reading
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        refreshLocationMonitoring()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 40 {
            currentSpeed = max(location.speed, 0)
            let shouldAutoStart = autoStartEnabled && !isTracking && currentSpeed >= autoStartSpeedThresholdMetersPerSecond

            if shouldAutoStart {
                startTracking()
            }

            defer { lastLocation = location }

            guard isTracking else {
                continue
            }

            if startLocation == nil {
                startLocation = location
            }
            endLocation = location

            guard let previousLocation = lastLocation else {
                continue
            }

            let delta = location.distance(from: previousLocation)
            if delta > 0 && delta < 500 {
                currentTripDistance += delta
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        currentSpeed = 0
        print("Location tracking failed: \(error.localizedDescription)")
    }

    private var autoStartSpeedThresholdMetersPerSecond: Double {
        autoStartSpeedThresholdKilometersPerHour / 3.6
    }

    private func completedTrip() async -> Trip {
        let tripDate = Date.now
        let duration = tripDate.timeIntervalSince(tripStartDate ?? tripDate)
        let displayedDistance = DistanceUnitSystem.miles.convertedDistance(for: currentTripDistance)
        let odometerStart = tripStartOdometerReading ?? 0
        let odometerEnd = odometerStart + displayedDistance

        return Trip(
            name: "\(selectedTripType.title) trip on \(tripDate.formatted(date: .abbreviated, time: .omitted))",
            type: selectedTripType,
            vehicleID: nil,
            vehicleProfileName: "",
            driverID: nil,
            driverName: "",
            startAddress: await resolveAddress(for: startLocation),
            endAddress: await resolveAddress(for: endLocation ?? lastLocation),
            details: "",
            odometerStart: odometerStart,
            odometerEnd: odometerEnd,
            distanceMeters: currentTripDistance,
            duration: duration,
            date: tripDate
        )
    }

    private func resolveAddress(for location: CLLocation?) async -> String {
        guard let location else {
            return "Unknown location"
        }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let parts = [
                    placemark.name,
                    placemark.locality,
                    placemark.administrativeArea
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }

                if !parts.isEmpty {
                    return parts.joined(separator: ", ")
                }
            }
        } catch {
            return coordinateString(for: location)
        }

        return coordinateString(for: location)
    }

    private func coordinateString(for location: CLLocation) -> String {
        let latitude = location.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))
        let longitude = location.coordinate.longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(latitude), \(longitude)"
    }

    private func refreshLocationMonitoring() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .notDetermined, .denied, .restricted:
            locationManager.stopUpdatingLocation()
        @unknown default:
            locationManager.stopUpdatingLocation()
        }
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = self >= 3_600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: self) ?? "00:00"
    }
}
