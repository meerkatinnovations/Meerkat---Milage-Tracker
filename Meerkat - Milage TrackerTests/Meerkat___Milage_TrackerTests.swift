import Testing
import Foundation
@testable import Meerkat___Milage_Tracker

struct MeerkatMilageTrackerTests {
    @Test
    func milesConversionUsesExpectedScale() {
        #expect(abs(DistanceUnitSystem.miles.convertedDistance(for: 1_609.344) - 1) < 0.0001)
    }

    @Test
    func kilometersConversionUsesExpectedScale() {
        #expect(abs(DistanceUnitSystem.kilometers.convertedDistance(for: 1_000) - 1) < 0.0001)
    }

    @Test
    func fuelVolumeUnitUsesExpectedConversions() {
        #expect(abs(FuelVolumeUnit.liters.displayedVolume(for: 10) - 10) < 0.0001)
        #expect(abs(FuelVolumeUnit.gallons.displayedVolume(for: 3.785_411_784) - 1) < 0.0001)
        #expect(abs(FuelVolumeUnit.gallons.liters(forDisplayedVolume: 1) - 3.785_411_784) < 0.0001)
    }

    @MainActor
    @Test
    func persistenceSnapshotRestoresAccountSetupAndPreferences() {
        let store = MileageStore()
        store.selectedCountry = .canada
        store.userName = "Rheeder Greeff"
        store.emailAddress = "rheeder@example.com"
        store.preferredCurrency = .cad
        store.unitSystem = .kilometers
        store.fuelVolumeUnit = .liters
        store.preventAutoLock = true
        store.hasCompletedOnboarding = true
        store.hasAcceptedPrivacyPolicy = true
        store.hasAcceptedLegalNotice = true

        let restoredStore = MileageStore()
        restoredStore.applyPersistenceSnapshot(store.persistenceSnapshot)

        #expect(restoredStore.selectedCountry == .canada)
        #expect(restoredStore.userName == "Rheeder Greeff")
        #expect(restoredStore.emailAddress == "rheeder@example.com")
        #expect(restoredStore.preferredCurrency == .cad)
        #expect(restoredStore.unitSystem == .kilometers)
        #expect(restoredStore.fuelVolumeUnit == .liters)
        #expect(restoredStore.preventAutoLock)
        #expect(restoredStore.hasCompletedOnboarding)
        #expect(restoredStore.hasAcceptedPrivacyPolicy)
        #expect(restoredStore.hasAcceptedLegalNotice)
    }

    @MainActor
    @Test
    func vehicleProfileDecodesLegacyPayloadWithoutScheduledFields() throws {
        let payload = """
        {
          "id": "B8F1E0C0-65F8-45E2-AD7F-C2D3E4F5A6B7",
          "profileName": "Work Car",
          "make": "Toyota",
          "model": "Corolla",
          "color": "White",
          "numberPlate": "ABC123",
          "startingOdometerReading": 12000,
          "ownershipType": "personal"
        }
        """.data(using: .utf8)!

        let vehicle = try JSONDecoder().decode(VehicleProfile.self, from: payload)

        #expect(vehicle.allowancePlan == nil)
        #expect(vehicle.paymentPlan == nil)
        #expect(vehicle.insurancePlan == nil)
        #expect(vehicle.otherScheduledExpenses.isEmpty)
    }

    @MainActor
    @Test
    func allowanceBalanceSummaryIncludesAllowanceAndLoggedSpend() {
        let store = MileageStore()
        let startDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day], from: Date.now)) ?? .now
        let vehicle = VehicleProfile(
            profileName: "Fleet",
            make: "Ford",
            model: "Ranger",
            color: "Blue",
            numberPlate: "XYZ789",
            startingOdometerReading: 5000,
            ownershipType: .company,
            allowancePlan: VehicleAllowancePlan(
                amount: 500,
                schedule: VehicleRecurringSchedule(frequency: .monthly, startDate: startDate)
            ),
            paymentPlan: VehiclePaymentPlan(
                kind: .finance,
                amount: 150,
                schedule: VehicleRecurringSchedule(frequency: .monthly, startDate: startDate)
            )
        )

        store.addVehicle(vehicle)
        store.addFuelEntry(
            FuelEntry(
                vehicleID: vehicle.id,
                vehicleProfileName: vehicle.displayName,
                station: "Station",
                volume: 20,
                totalCost: 75,
                odometer: 5100,
                date: .now
            )
        )

        let summary = store.allowanceBalanceSummary(for: vehicle.id)

        #expect(summary?.receivedAllowance == 500)
        #expect(summary?.manualAdjustments == 0)
        #expect(summary?.scheduledExpenses == 150)
        #expect(summary?.fuelSpend == 75)
        #expect(summary?.remainingBalance == 275)
    }

    @MainActor
    @Test
    func allowanceBalanceSummaryIncludesManualAdjustments() {
        let store = MileageStore()
        let startDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day], from: Date.now)) ?? .now
        let vehicle = VehicleProfile(
            profileName: "Allowance Car",
            make: "Toyota",
            model: "Hilux",
            color: "White",
            numberPlate: "TOPUP1",
            startingOdometerReading: 10_000,
            ownershipType: .company,
            allowancePlan: VehicleAllowancePlan(
                amount: 400,
                schedule: VehicleRecurringSchedule(frequency: .monthly, startDate: startDate)
            )
        )

        store.addVehicle(vehicle)
        store.addAllowanceAdjustment(vehicleID: vehicle.id, amount: 125, reason: "Manager top-up")
        store.addAllowanceAdjustment(vehicleID: vehicle.id, amount: -25, reason: "Correction")

        let summary = store.allowanceBalanceSummary(for: vehicle.id)

        #expect(summary?.receivedAllowance == 400)
        #expect(summary?.manualAdjustments == 100)
        #expect(summary?.remainingBalance == 500)
    }

    @MainActor
    @Test
    func logExportUsesSelectedRangeForTaxMetadata() {
        let store = MileageStore()
        store.applyCountryPreferences(.uk)
        let start = Calendar.current.date(from: DateComponents(year: 2025, month: 4, day: 6))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 5))!

        let payload = store.entriesForLogExport(vehicleID: nil, driverID: nil, dateRange: start ... end)

        #expect(payload.taxAuthorityName == "HM Revenue and Customs")
        #expect(payload.taxYearCoverage == ["Tax Year Apr 6, 2025 - Apr 5, 2026"])
        #expect(Calendar.current.isDate(payload.exportDateRange.lowerBound, inSameDayAs: start))
        #expect(Calendar.current.isDate(payload.exportDateRange.upperBound, inSameDayAs: end))
    }

    @MainActor
    @Test
    func financialLogExportIncludesAllowancesAndExpenses() {
        let store = MileageStore()
        let startDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day], from: Date.now)) ?? .now
        let vehicle = VehicleProfile(
            profileName: "Finance Car",
            make: "Mazda",
            model: "CX-5",
            color: "Grey",
            numberPlate: "FIN123",
            startingOdometerReading: 1000,
            ownershipType: .company,
            allowancePlan: VehicleAllowancePlan(
                amount: 600,
                schedule: VehicleRecurringSchedule(frequency: .monthly, startDate: startDate)
            ),
            paymentPlan: VehiclePaymentPlan(
                kind: .finance,
                amount: 200,
                schedule: VehicleRecurringSchedule(frequency: .monthly, startDate: startDate)
            )
        )

        store.addVehicle(vehicle)
        store.addAllowanceAdjustment(vehicleID: vehicle.id, amount: 75, reason: "Extra travel")
        store.addFuelEntry(
            FuelEntry(
                vehicleID: vehicle.id,
                vehicleProfileName: vehicle.displayName,
                station: "Shell",
                volume: 30,
                totalCost: 90,
                odometer: 1100,
                date: .now
            )
        )

        let payload = store.entriesForFinancialLogExport(vehicleID: vehicle.id, driverID: nil, dateRange: store.defaultLogDateRange())

        #expect(payload.taxAuthorityName == "Internal Revenue Service")
        #expect(payload.entries.contains(where: { $0.recordType == "allowance" && $0.amount == 600 }))
        #expect(payload.entries.contains(where: { $0.recordType == "payment" && $0.amount == -200 }))
        #expect(payload.entries.contains(where: { $0.recordType == "allowance_adjustment" && $0.amount == 75 }))
        #expect(payload.entries.contains(where: { $0.recordType == "fuel" && $0.amount == -90 }))
    }

    @MainActor
    @Test
    func financialLogExportExcludesFutureScheduledPayments() {
        let store = MileageStore()
        let futureStartDate = Calendar.current.date(byAdding: .month, value: 1, to: Date.now) ?? Date.now
        let vehicle = VehicleProfile(
            profileName: "Future Payment Car",
            make: "BMW",
            model: "X3",
            color: "Black",
            numberPlate: "FUTURE1",
            startingOdometerReading: 2000,
            ownershipType: .company,
            paymentPlan: VehiclePaymentPlan(
                kind: .finance,
                amount: 350,
                schedule: VehicleRecurringSchedule(frequency: .monthly, startDate: futureStartDate)
            )
        )

        store.addVehicle(vehicle)

        let payload = store.entriesForFinancialLogExport(vehicleID: vehicle.id, driverID: nil, dateRange: store.defaultLogDateRange())

        #expect(!payload.entries.contains(where: { $0.recordType == "payment" }))
    }

    @MainActor
    @Test
    func countryPreferencesApplyCurrencyDistanceAndFuelVolumeDefaults() {
        let store = MileageStore()

        store.applyCountryPreferences(.canada)

        #expect(store.preferredCurrency == .cad)
        #expect(store.unitSystem == .kilometers)
        #expect(store.fuelVolumeUnit == .liters)

        store.applyCountryPreferences(.usa)

        #expect(store.preferredCurrency == .usd)
        #expect(store.unitSystem == .miles)
        #expect(store.fuelVolumeUnit == .gallons)
    }

    @MainActor
    @Test
    func fuelVolumeStringRespectsSelectedFuelVolumePreference() {
        let store = MileageStore()
        store.fuelVolumeUnit = .liters
        #expect(store.fuelVolumeString(for: 20, fractionDigits: 1) == "20.0 L")

        store.fuelVolumeUnit = .gallons
        #expect(store.fuelVolumeString(for: 3.785_411_784, fractionDigits: 1) == "1.0 gal")
    }

    @MainActor
    @Test
    func archiveVehicleMovesVehicleToArchiveButKeepsLookup() {
        let store = MileageStore()
        let vehicle = VehicleProfile(
            profileName: "Work Truck",
            make: "Ford",
            model: "F-150",
            color: "Black",
            numberPlate: "KEEP123",
            startingOdometerReading: 1000,
            ownershipType: .company
        )

        store.addVehicle(vehicle)
        store.archiveVehicle(id: vehicle.id, reason: "Sold")

        #expect(store.vehicles.isEmpty)
        #expect(store.archivedVehicles.count == 1)
        #expect(store.vehicle(for: vehicle.id)?.displayName == "Work Truck")
        #expect(store.archivedVehicles.first?.archiveReason == "Sold")
    }

    @MainActor
    @Test
    func archivedDriverKeepsDriverDetailsOnTrips() {
        let store = MileageStore()
        let vehicle = VehicleProfile(
            profileName: "Daily",
            make: "Honda",
            model: "Civic",
            color: "Silver",
            numberPlate: "DRIVE1",
            startingOdometerReading: 100,
            ownershipType: .personal
        )
        let driver = DriverProfile(
            name: "Alex Doe",
            dateOfBirth: Date(timeIntervalSince1970: 1_000_000),
            licenceNumber: "LIC-1234"
        )

        store.addVehicle(vehicle)
        store.addDriver(driver)
        store.addTrip(
            Trip(
                name: "Client Visit",
                type: .business,
                vehicleID: vehicle.id,
                vehicleProfileName: vehicle.displayName,
                driverID: driver.id,
                driverName: driver.name,
                driverDateOfBirth: driver.dateOfBirth,
                driverLicenceNumber: driver.licenceNumber,
                startAddress: "A",
                endAddress: "B",
                details: "Meeting",
                odometerStart: 100,
                odometerEnd: 120,
                distanceMeters: 32_186.88,
                duration: 600,
                date: .now
            )
        )

        store.archiveDriver(id: driver.id)

        #expect(store.drivers.isEmpty)
        #expect(store.archivedDrivers.count == 1)
        #expect(store.trips.first?.driverName == "Alex Doe")
        #expect(store.trips.first?.driverLicenceNumber == "LIC-1234")
        #expect(store.trips.first?.driverDateOfBirth == driver.dateOfBirth)
    }

    @MainActor
    @Test
    func deletingDriverRemovesItFromDriverListButKeepsTripDetails() {
        let store = MileageStore()
        let vehicle = VehicleProfile(
            profileName: "Daily",
            make: "Honda",
            model: "Civic",
            color: "Silver",
            numberPlate: "DRIVE1",
            startingOdometerReading: 100,
            ownershipType: .personal
        )
        let driver = DriverProfile(
            name: "Alex Doe",
            dateOfBirth: Date(timeIntervalSince1970: 1_000_000),
            licenceNumber: "LIC-1234"
        )

        store.addVehicle(vehicle)
        store.addDriver(driver)
        store.activeDriverID = driver.id
        store.addTrip(
            Trip(
                name: "Client Visit",
                type: .business,
                vehicleID: vehicle.id,
                vehicleProfileName: vehicle.displayName,
                driverID: driver.id,
                driverName: driver.name,
                driverDateOfBirth: driver.dateOfBirth,
                driverLicenceNumber: driver.licenceNumber,
                startAddress: "A",
                endAddress: "B",
                details: "Meeting",
                odometerStart: 100,
                odometerEnd: 120,
                distanceMeters: 32_186.88,
                duration: 600,
                date: .now
            )
        )

        store.deleteDriver(id: driver.id)

        #expect(store.drivers.isEmpty)
        #expect(store.activeDriverID == nil)
        #expect(store.trips.first?.driverName == "Alex Doe")
        #expect(store.trips.first?.driverLicenceNumber == "LIC-1234")
        #expect(store.trips.first?.driverDateOfBirth == driver.dateOfBirth)
    }

    @MainActor
    @Test
    func tripsForActiveVehicleOnlyReturnsTripsForSelectedVehicle() {
        let store = MileageStore()
        let firstVehicle = VehicleProfile(
            profileName: "Work Car",
            make: "Toyota",
            model: "Corolla",
            color: "White",
            numberPlate: "WORK1",
            startingOdometerReading: 1000,
            ownershipType: .personal
        )
        let secondVehicle = VehicleProfile(
            profileName: "Home Car",
            make: "Honda",
            model: "Civic",
            color: "Blue",
            numberPlate: "HOME1",
            startingOdometerReading: 2000,
            ownershipType: .personal
        )

        store.addVehicle(firstVehicle)
        store.addVehicle(secondVehicle)

        store.activeVehicleID = firstVehicle.id
        store.addTrip(
            Trip(
                name: "Work Trip",
                type: .business,
                vehicleID: firstVehicle.id,
                vehicleProfileName: firstVehicle.displayName,
                driverID: nil,
                driverName: "",
                startAddress: "A",
                endAddress: "B",
                details: "",
                odometerStart: 1000,
                odometerEnd: 1010,
                distanceMeters: 16_093.44,
                duration: 600,
                date: .now.addingTimeInterval(-3600)
            )
        )

        store.activeVehicleID = secondVehicle.id
        store.addTrip(
            Trip(
                name: "Home Trip",
                type: .personal,
                vehicleID: secondVehicle.id,
                vehicleProfileName: secondVehicle.displayName,
                driverID: nil,
                driverName: "",
                startAddress: "C",
                endAddress: "D",
                details: "",
                odometerStart: 2000,
                odometerEnd: 2010,
                distanceMeters: 16_093.44,
                duration: 600,
                date: .now
            )
        )

        let activeTrips = store.tripsForActiveVehicle()

        #expect(activeTrips.count == 1)
        #expect(activeTrips.first?.vehicleID == secondVehicle.id)
        #expect(activeTrips.first?.name == "Home Trip")
    }

    @MainActor
    @Test
    func updatingVehicleStartingOdometerReconcilesVehicleTripChain() {
        let store = MileageStore()
        let vehicle = VehicleProfile(
            profileName: "Fleet",
            make: "Ford",
            model: "Ranger",
            color: "Grey",
            numberPlate: "CHAIN1",
            startingOdometerReading: 1000,
            ownershipType: .company
        )

        store.addVehicle(vehicle)
        store.addTrip(
            Trip(
                name: "Morning Route",
                type: .business,
                vehicleID: vehicle.id,
                vehicleProfileName: vehicle.displayName,
                driverID: nil,
                driverName: "",
                startAddress: "A",
                endAddress: "B",
                details: "",
                odometerStart: 1000,
                odometerEnd: 1010,
                distanceMeters: 16_093.44,
                duration: 600,
                date: .now.addingTimeInterval(-3600)
            )
        )

        store.updateVehicle(
            VehicleProfile(
                id: vehicle.id,
                profileName: vehicle.profileName,
                make: vehicle.make,
                model: vehicle.model,
                color: vehicle.color,
                numberPlate: vehicle.numberPlate,
                startingOdometerReading: 1500,
                ownershipType: vehicle.ownershipType
            )
        )

        #expect(store.trips.first?.odometerStart == 1500)
        #expect(store.trips.first?.odometerEnd == 1510)
        #expect(store.currentBaseOdometerReading() == 1510)
    }

    @MainActor
    @Test
    func updatingTripOdometerPreservesNextTripEndForSameVehicle() {
        let store = MileageStore()
        let vehicleA = VehicleProfile(
            profileName: "Vehicle A",
            make: "Toyota",
            model: "Corolla",
            color: "White",
            numberPlate: "AAA111",
            startingOdometerReading: 1000,
            ownershipType: .personal
        )
        let vehicleB = VehicleProfile(
            profileName: "Vehicle B",
            make: "Honda",
            model: "Civic",
            color: "Blue",
            numberPlate: "BBB222",
            startingOdometerReading: 5000,
            ownershipType: .personal
        )

        store.addVehicle(vehicleA)
        store.addVehicle(vehicleB)
        store.activeVehicleID = vehicleA.id

        let oldestTrip = Trip(
            id: UUID(),
            name: "Oldest",
            type: .business,
            vehicleID: vehicleA.id,
            vehicleProfileName: vehicleA.displayName,
            driverID: nil,
            driverName: "",
            startAddress: "A",
            endAddress: "B",
            details: "",
            odometerStart: 1000,
            odometerEnd: 1010,
            distanceMeters: 16_093.44,
            duration: 600,
            date: Date(timeIntervalSince1970: 1_000)
        )
        let middleTrip = Trip(
            id: UUID(),
            name: "Middle",
            type: .business,
            vehicleID: vehicleA.id,
            vehicleProfileName: vehicleA.displayName,
            driverID: nil,
            driverName: "",
            startAddress: "C",
            endAddress: "D",
            details: "",
            odometerStart: 1010,
            odometerEnd: 1020,
            distanceMeters: 16_093.44,
            duration: 600,
            date: Date(timeIntervalSince1970: 2_000)
        )
        let newestTrip = Trip(
            id: UUID(),
            name: "Newest",
            type: .business,
            vehicleID: vehicleA.id,
            vehicleProfileName: vehicleA.displayName,
            driverID: nil,
            driverName: "",
            startAddress: "E",
            endAddress: "F",
            details: "",
            odometerStart: 1020,
            odometerEnd: 1030,
            distanceMeters: 16_093.44,
            duration: 600,
            date: Date(timeIntervalSince1970: 3_000)
        )
        let otherVehicleTrip = Trip(
            id: UUID(),
            name: "Other Vehicle",
            type: .personal,
            vehicleID: vehicleB.id,
            vehicleProfileName: vehicleB.displayName,
            driverID: nil,
            driverName: "",
            startAddress: "X",
            endAddress: "Y",
            details: "",
            odometerStart: 5000,
            odometerEnd: 5010,
            distanceMeters: 16_093.44,
            duration: 600,
            date: Date(timeIntervalSince1970: 2_500)
        )

        store.addTrip(oldestTrip)
        store.addTrip(middleTrip)
        store.addTrip(newestTrip)
        store.addTrip(otherVehicleTrip)

        store.updateTrip(
            Trip(
                id: middleTrip.id,
                name: middleTrip.name,
                type: middleTrip.type,
                vehicleID: middleTrip.vehicleID,
                vehicleProfileName: middleTrip.vehicleProfileName,
                driverID: middleTrip.driverID,
                driverName: middleTrip.driverName,
                startAddress: middleTrip.startAddress,
                endAddress: middleTrip.endAddress,
                details: middleTrip.details,
                odometerStart: 1012,
                odometerEnd: 1025,
                distanceMeters: store.unitSystem.meters(forDisplayedDistance: 13),
                duration: middleTrip.duration,
                date: middleTrip.date
            )
        )

        let updatedOldest = store.trips.first(where: { $0.id == oldestTrip.id })
        let updatedMiddle = store.trips.first(where: { $0.id == middleTrip.id })
        let updatedNewest = store.trips.first(where: { $0.id == newestTrip.id })
        let untouchedOtherVehicleTrip = store.trips.first(where: { $0.id == otherVehicleTrip.id })
        let expectedNewestEnd = 1030.0
        let expectedNewestDistance = store.unitSystem.meters(forDisplayedDistance: 5)

        #expect(updatedOldest?.odometerEnd == 1012)
        #expect(updatedMiddle?.odometerStart == 1012)
        #expect(updatedMiddle?.odometerEnd == 1025)
        #expect(updatedNewest?.odometerStart == 1025)
        #expect(updatedNewest?.odometerEnd == expectedNewestEnd)
        #expect(updatedNewest?.distanceMeters == expectedNewestDistance)
        #expect(untouchedOtherVehicleTrip?.odometerStart == 5000)
        #expect(untouchedOtherVehicleTrip?.odometerEnd == 5010)
    }

    @MainActor
    @Test
    func updatingLatestTripEndUpdatesCurrentVehicleOdometer() {
        let store = MileageStore()
        let vehicle = VehicleProfile(
            profileName: "Daily",
            make: "Mazda",
            model: "3",
            color: "Red",
            numberPlate: "ODO123",
            startingOdometerReading: 1000,
            ownershipType: .personal
        )

        store.addVehicle(vehicle)
        store.activeVehicleID = vehicle.id

        let firstTrip = Trip(
            id: UUID(),
            name: "First",
            type: .personal,
            vehicleID: vehicle.id,
            vehicleProfileName: vehicle.displayName,
            driverID: nil,
            driverName: "",
            startAddress: "A",
            endAddress: "B",
            details: "",
            odometerStart: 1000,
            odometerEnd: 1010,
            distanceMeters: 16_093.44,
            duration: 600,
            date: Date(timeIntervalSince1970: 1_000)
        )
        let latestTrip = Trip(
            id: UUID(),
            name: "Latest",
            type: .personal,
            vehicleID: vehicle.id,
            vehicleProfileName: vehicle.displayName,
            driverID: nil,
            driverName: "",
            startAddress: "C",
            endAddress: "D",
            details: "",
            odometerStart: 1010,
            odometerEnd: 1020,
            distanceMeters: 16_093.44,
            duration: 600,
            date: Date(timeIntervalSince1970: 2_000)
        )

        store.addTrip(firstTrip)
        store.addTrip(latestTrip)

        store.updateTrip(
            Trip(
                id: latestTrip.id,
                name: latestTrip.name,
                type: latestTrip.type,
                vehicleID: latestTrip.vehicleID,
                vehicleProfileName: latestTrip.vehicleProfileName,
                driverID: latestTrip.driverID,
                driverName: latestTrip.driverName,
                startAddress: latestTrip.startAddress,
                endAddress: latestTrip.endAddress,
                details: latestTrip.details,
                odometerStart: 1010,
                odometerEnd: 1040,
                distanceMeters: store.unitSystem.meters(forDisplayedDistance: 30),
                duration: latestTrip.duration,
                date: latestTrip.date
            )
        )

        #expect(store.trips.first(where: { $0.id == latestTrip.id })?.odometerStart == 1010)
        #expect(store.trips.first(where: { $0.id == latestTrip.id })?.odometerEnd == 1040)
        #expect(store.currentBaseOdometerReading() == 1040)
        #expect(store.currentOdometerReading(for: vehicle.id) == 1040)
    }

    @MainActor
    @Test
    func compliantLogImportCreatesVehicleDriverTripAndFuelRecords() throws {
        let csv = """
        "CRA COMPLIANT LOG"

        "TYPE","DATE","VEHICLE","DRIVER","OPENING KM","CLOSING KM","TOTAL KM","REASON","END ADDRESS","TRIP TYPE"
        "TRIP","2026-02-02 08:47","Toyota (CXD-1988)","Rheeder Greeff","38564.66","38649.67","85.01","Sales Meeting","11520 101 Ave, Fairview, AB T0H 1L0, Canada","Work"

        "TRIP SUMMARY"
        "Total Work KM","85.01"
        "Total Personal KM","0.00"
        "Total Combined KM","85.01"

        "EXPENSE LOG (COMPLIANT)"
        "CATEGORY","DATE","VEHICLE","DRIVER","ODO (km)","DESCRIPTION","AMOUNT","PROVIDER/STATION"
        "FUEL","2026-02-03 08:18","Toyota (CXD-1988)","Rheeder Greeff","38750.00","56.04L fuel up","68.87","7613 100 Ave, Peace River, AB T8S 1M5, Canada"
        """

        let payload = try LogCSVCodec.parse(csv)

        #expect(payload.vehicles.count == 1)
        #expect(payload.drivers.count == 1)
        #expect(payload.trips.count == 1)
        #expect(payload.fuelEntries.count == 1)
        #expect(payload.vehicles.first?.displayName == "Toyota (CXD-1988)")
        #expect(payload.drivers.first?.name == "Rheeder Greeff")
        #expect(payload.trips.first?.type == .business)
        #expect(payload.trips.first?.vehicleID == payload.vehicles.first?.id)
        #expect(payload.trips.first?.driverID == payload.drivers.first?.id)
        #expect(abs((payload.trips.first?.distanceMeters ?? 0) - 85_010) < 0.001)
        #expect(abs((payload.fuelEntries.first?.volume ?? 0) - 56.04) < 0.001)
    }

    @MainActor
    @Test
    func exportedMileageLogRoundTripsBackIntoImportPayload() throws {
        let store = MileageStore()
        store.selectedCountry = .canada
        store.unitSystem = .kilometers
        store.fuelVolumeUnit = .liters
        store.userName = "Rheeder Greeff"
        store.emailAddress = "admin@meerkatinnovations.ca"

        let vehicle = VehicleProfile(
            profileName: "Toyota (CXD-1988)",
            make: "Toyota",
            model: "Tacoma",
            color: "White",
            numberPlate: "CXD-1988",
            startingOdometerReading: 38_564.66,
            ownershipType: .personal
        )
        let driver = DriverProfile(
            name: "Rheeder Greeff",
            dateOfBirth: Date(timeIntervalSince1970: 1_000_000),
            licenceNumber: "LIC-1"
        )
        store.addVehicle(vehicle)
        store.addDriver(driver)
        store.activeVehicleID = vehicle.id
        store.activeDriverID = driver.id

        store.addTrip(
            Trip(
                name: "Imported Trip",
                type: .business,
                vehicleID: vehicle.id,
                vehicleProfileName: vehicle.displayName,
                driverID: driver.id,
                driverName: driver.name,
                startAddress: "",
                endAddress: "11520 101 Ave, Fairview, AB T0H 1L0, Canada",
                details: "Sales Meeting",
                odometerStart: 38_564.66,
                odometerEnd: 38_649.67,
                distanceMeters: 85_010,
                duration: 0,
                date: Date(timeIntervalSince1970: 1_000)
            )
        )
        store.addFuelEntry(
            FuelEntry(
                vehicleID: vehicle.id,
                vehicleProfileName: vehicle.displayName,
                station: "7613 100 Ave, Peace River, AB T8S 1M5, Canada",
                volume: 56.04,
                totalCost: 68.87,
                odometer: 38_750,
                date: Date(timeIntervalSince1970: 2_000)
            )
        )

        let payload = store.entriesForLogExport(vehicleID: vehicle.id, driverID: nil, dateRange: Date(timeIntervalSince1970: 0) ... Date(timeIntervalSince1970: 10_000))
        let csv = LogCSVCodec.makeCSV(from: payload)
        let parsed = try LogCSVCodec.parse(csv)

        #expect(parsed.trips.count == 1)
        #expect(parsed.fuelEntries.count == 1)
        #expect(parsed.trips.first?.odometerStart == 38_564.66)
        #expect(parsed.trips.first?.odometerEnd == 38_649.67)
        #expect(parsed.fuelEntries.first?.odometer == 38_750)
    }

    @MainActor
    @Test
    func importingCompliantLogReusesExistingVehicleAndDriverByName() throws {
        let store = MileageStore()
        let vehicle = VehicleProfile(
            profileName: "Toyota (CXD-1988)",
            make: "Toyota",
            model: "Tacoma",
            color: "White",
            numberPlate: "CXD-1988",
            startingOdometerReading: 35_000,
            ownershipType: .personal
        )
        let driver = DriverProfile(
            name: "Rheeder Greeff",
            dateOfBirth: Date(timeIntervalSince1970: 1_000_000),
            licenceNumber: "LIC-1"
        )
        store.addVehicle(vehicle)
        store.addDriver(driver)

        let csv = """
        "CRA COMPLIANT LOG"
        "TYPE","DATE","VEHICLE","DRIVER","OPENING KM","CLOSING KM","TOTAL KM","REASON","END ADDRESS","TRIP TYPE"
        "TRIP","2026-02-02 08:47","Toyota (CXD-1988)","Rheeder Greeff","38564.66","38649.67","85.01","Sales Meeting","11520 101 Ave, Fairview, AB T0H 1L0, Canada","Work"
        """

        let payload = try LogCSVCodec.parse(csv)
        store.importLogPayload(payload)

        #expect(store.vehicles.count == 1)
        #expect(store.drivers.count == 1)
        #expect(store.trips.count == 1)
        #expect(store.trips.first?.vehicleID == vehicle.id)
        #expect(store.trips.first?.driverID == driver.id)
    }

    @MainActor
    @Test
    func importingLogPreservesImportedTripOdometerReadings() throws {
        let store = MileageStore()
        let csv = """
        "record_type","country","account_name","account_email","currency","tax_authority","export_range_start","export_range_end","tax_year_label","tax_year_coverage","distance_unit","tax_year_start","tax_year_end","exported_at","record_id","vehicle_id","vehicle_name","driver_id","driver_name","date","trip_name","trip_type","start_address","end_address","trip_details","odometer_start","odometer_end","distance_meters","duration_seconds","station_or_shop","volume_liters","total_cost","odometer","maintenance_type","other_description","notes","reminder_enabled","next_service_odometer","next_service_date","receipt_base64"
        "trip","canada","","","","","2026-01-01T00:00:00Z","2026-12-31T23:59:59Z","2026","2026","kilometers","2026-01-01T00:00:00Z","2027-01-01T00:00:00Z","2026-12-31T23:59:59Z","11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222","Toyota (CXD-1988)","33333333-3333-3333-3333-333333333333","Rheeder Greeff","2026-02-02T08:47:00Z","Trip 1","business","","","Sales Meeting","38564.66","38649.67","85010","0","","","","","","","","","",""
        "trip","canada","","","","","2026-01-01T00:00:00Z","2026-12-31T23:59:59Z","2026","2026","kilometers","2026-01-01T00:00:00Z","2027-01-01T00:00:00Z","2026-12-31T23:59:59Z","44444444-4444-4444-4444-444444444444","22222222-2222-2222-2222-222222222222","Toyota (CXD-1988)","33333333-3333-3333-3333-333333333333","Rheeder Greeff","2026-02-03T08:47:00Z","Trip 2","business","","","Client Visit","39000.00","39020.00","20000","0","","","","","","","","","",""
        """

        let payload = try LogCSVCodec.parse(csv)
        store.importLogPayload(payload)

        let importedTrips = store.trips.sorted { $0.date < $1.date }
        #expect(importedTrips.count == 2)
        #expect(importedTrips[0].odometerStart == 38564.66)
        #expect(importedTrips[0].odometerEnd == 38649.67)
        #expect(importedTrips[1].odometerStart == 39000.00)
        #expect(importedTrips[1].odometerEnd == 39020.00)
    }

    @MainActor
    @Test
    func importingLogUpdatesMatchedVehicleStartingOdometerAndDashboardReading() throws {
        let store = MileageStore()
        let existingVehicle = VehicleProfile(
            profileName: "Toyota (CXD-1988)",
            make: "Toyota",
            model: "Tacoma",
            color: "White",
            numberPlate: "CXD-1988",
            startingOdometerReading: 50_000,
            ownershipType: .personal
        )
        store.addVehicle(existingVehicle)
        store.activeVehicleID = existingVehicle.id

        let csv = """
        "record_type","country","account_name","account_email","currency","tax_authority","export_range_start","export_range_end","tax_year_label","tax_year_coverage","distance_unit","tax_year_start","tax_year_end","exported_at","record_id","vehicle_id","vehicle_name","driver_id","driver_name","date","trip_name","trip_type","start_address","end_address","trip_details","odometer_start","odometer_end","distance_meters","duration_seconds","station_or_shop","volume_liters","total_cost","odometer","maintenance_type","other_description","notes","reminder_enabled","next_service_odometer","next_service_date","receipt_base64"
        "trip","canada","","","","","2026-01-01T00:00:00Z","2026-12-31T23:59:59Z","2026","2026","kilometers","2026-01-01T00:00:00Z","2027-01-01T00:00:00Z","2026-12-31T23:59:59Z","11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222","Toyota (CXD-1988)","33333333-3333-3333-3333-333333333333","Rheeder Greeff","2026-02-02T08:47:00Z","Trip 1","business","","","Sales Meeting","38564.66","38649.67","85010","0","","","","","","","","","",""
        """

        let payload = try LogCSVCodec.parse(csv)
        store.importLogPayload(payload)

        let importedTrip = try #require(store.trips.first)
        let updatedVehicle = try #require(store.vehicles.first(where: { $0.id == existingVehicle.id }))
        #expect(importedTrip.vehicleID == existingVehicle.id)
        #expect(importedTrip.odometerStart == 38564.66)
        #expect(importedTrip.odometerEnd == 38649.67)
        #expect(updatedVehicle.startingOdometerReading == 38564.66)
        #expect(store.currentBaseOdometerReading() == 38649.67)
    }

    @MainActor
    @Test
    func importingLogUsesLowestStartingOdometerAcrossRowsAndSwitchesDashboardToLatestImportedVehicle() throws {
        let store = MileageStore()
        let existingVehicle = VehicleProfile(
            profileName: "Existing Vehicle",
            make: "Ford",
            model: "Escape",
            color: "Black",
            numberPlate: "OLD123",
            startingOdometerReading: 90_000,
            ownershipType: .personal
        )
        store.addVehicle(existingVehicle)
        store.activeVehicleID = existingVehicle.id

        let csv = """
        "record_type","country","account_name","account_email","currency","tax_authority","export_range_start","export_range_end","tax_year_label","tax_year_coverage","distance_unit","tax_year_start","tax_year_end","exported_at","record_id","vehicle_id","vehicle_name","driver_id","driver_name","date","trip_name","trip_type","start_address","end_address","trip_details","odometer_start","odometer_end","distance_meters","duration_seconds","station_or_shop","volume_liters","total_cost","odometer","maintenance_type","other_description","notes","reminder_enabled","next_service_odometer","next_service_date","receipt_base64"
        "trip","canada","","","","","2026-01-01T00:00:00Z","2026-12-31T23:59:59Z","2026","2026","kilometers","2026-01-01T00:00:00Z","2027-01-01T00:00:00Z","2026-12-31T23:59:59Z","11111111-1111-1111-1111-111111111111","22222222-2222-2222-2222-222222222222","Imported Vehicle","33333333-3333-3333-3333-333333333333","Rheeder Greeff","2026-02-03T08:47:00Z","Trip 2","business","","","Client Visit","39000.00","39020.00","20000","0","","","","","","","","","",""
        "trip","canada","","","","","2026-01-01T00:00:00Z","2026-12-31T23:59:59Z","2026","2026","kilometers","2026-01-01T00:00:00Z","2027-01-01T00:00:00Z","2026-12-31T23:59:59Z","44444444-4444-4444-4444-444444444444","22222222-2222-2222-2222-222222222222","Imported Vehicle","33333333-3333-3333-3333-333333333333","Rheeder Greeff","2026-02-02T08:47:00Z","Trip 1","business","","","Sales Meeting","38564.66","38649.67","85010","0","","","","","","","","","",""
        """

        let payload = try LogCSVCodec.parse(csv)
        store.importLogPayload(payload)

        let importedVehicle = try #require(store.vehicles.first(where: { $0.displayName == "Imported Vehicle" }))
        #expect(importedVehicle.startingOdometerReading == 38564.66)
        #expect(store.activeVehicleID == importedVehicle.id)
        #expect(store.currentBaseOdometerReading() == 39020.00)
    }

    @MainActor
    @Test
    func updatingFuelEntryKeepsItsOriginalVehicleAssociation() {
        let store = MileageStore()
        let firstVehicle = VehicleProfile(
            profileName: "Work Truck",
            make: "Ford",
            model: "F-150",
            color: "Black",
            numberPlate: "FUEL1",
            startingOdometerReading: 1_000,
            ownershipType: .company
        )
        let secondVehicle = VehicleProfile(
            profileName: "Personal Car",
            make: "Honda",
            model: "Civic",
            color: "Blue",
            numberPlate: "FUEL2",
            startingOdometerReading: 2_000,
            ownershipType: .personal
        )

        store.addVehicle(firstVehicle)
        store.addVehicle(secondVehicle)
        store.activeVehicleID = firstVehicle.id

        let entry = FuelEntry(
            vehicleID: firstVehicle.id,
            vehicleProfileName: firstVehicle.displayName,
            station: "Shell",
            volume: 20,
            totalCost: 60,
            odometer: 1_050,
            date: .now
        )
        store.addFuelEntry(entry)
        store.activeVehicleID = secondVehicle.id

        store.updateFuelEntry(
            FuelEntry(
                id: store.fuelEntries[0].id,
                vehicleID: firstVehicle.id,
                vehicleProfileName: firstVehicle.displayName,
                station: "Co-op",
                volume: 22,
                totalCost: 65,
                odometer: 1_075,
                date: entry.date
            )
        )

        #expect(store.fuelEntries[0].vehicleID == firstVehicle.id)
        #expect(store.fuelEntries[0].vehicleProfileName == firstVehicle.displayName)
    }

    @MainActor
    @Test
    func updatingMaintenanceRecordKeepsItsOriginalVehicleAssociation() {
        let store = MileageStore()
        let firstVehicle = VehicleProfile(
            profileName: "Service Van",
            make: "Toyota",
            model: "HiAce",
            color: "White",
            numberPlate: "MAIN1",
            startingOdometerReading: 5_000,
            ownershipType: .company
        )
        let secondVehicle = VehicleProfile(
            profileName: "Spare Car",
            make: "Mazda",
            model: "3",
            color: "Red",
            numberPlate: "MAIN2",
            startingOdometerReading: 8_000,
            ownershipType: .personal
        )

        store.addVehicle(firstVehicle)
        store.addVehicle(secondVehicle)
        store.activeVehicleID = firstVehicle.id

        let record = MaintenanceRecord(
            vehicleID: firstVehicle.id,
            vehicleProfileName: firstVehicle.displayName,
            shopName: "Garage",
            odometer: 5_100,
            date: .now,
            type: .oilChange,
            totalCost: 120
        )
        store.addMaintenanceRecord(record)
        store.activeVehicleID = secondVehicle.id

        store.updateMaintenanceRecord(
            MaintenanceRecord(
                id: store.maintenanceRecords[0].id,
                vehicleID: firstVehicle.id,
                vehicleProfileName: firstVehicle.displayName,
                shopName: "Dealer",
                odometer: 5_150,
                date: record.date,
                type: .oilChange,
                totalCost: 140
            )
        )

        #expect(store.maintenanceRecords[0].vehicleID == firstVehicle.id)
        #expect(store.maintenanceRecords[0].vehicleProfileName == firstVehicle.displayName)
    }

}
