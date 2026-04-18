//
//  Item.swift
//  Meerkat - Milage Tracker
//
//  Created by Rheeder Greeff on 2026-03-15.
//

import CoreLocation
import CoreMotion
import CoreBluetooth
import Compression
import CryptoKit
import Foundation
import AuthenticationServices
import AVFAudio
import CarPlay
import CloudKit
import LocalAuthentication
import MapKit
import Network
import Observation
import Security
import StoreKit
import SwiftUI
import UIKit
import UserNotifications
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif
#if canImport(FirebaseStorage)
import FirebaseStorage
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppFeatureFlags {
    // Set to true when shipping the business subscription portal.
    static let businessSubscriptionsEnabled = false
}

enum DistanceUnitSystem: String, CaseIterable, Identifiable, Codable, Equatable {
    case miles
    case kilometers

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
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

    func fuelEconomyString(distance: Double, liters: Double, format: FuelEconomyFormat) -> String {
        let resolvedFormat = format.compatibleFormat(for: self)

        guard liters > 0 else {
            return resolvedFormat.zeroValueText
        }

        switch resolvedFormat {
        case .milesPerGallon:
            let gallons = liters / 3.785_411_784
            let economy = distance / gallons
            return "\(economy.formatted(.number.precision(.fractionLength(1)))) mpg"
        case .kilometersPerLiter:
            let economy = distance / liters
            return "\(economy.formatted(.number.precision(.fractionLength(1)))) km/L"
        case .litersPer100Kilometers:
            guard distance > 0 else {
                return resolvedFormat.zeroValueText
            }
            let consumption = (liters / distance) * 100
            return "\(consumption.formatted(.number.precision(.fractionLength(1)))) L/100 km"
        }
    }
}

enum FuelEconomyFormat: String, CaseIterable, Identifiable, Codable, Equatable {
    case milesPerGallon
    case kilometersPerLiter
    case litersPer100Kilometers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .milesPerGallon:
            return "MPG"
        case .kilometersPerLiter:
            return "km/L"
        case .litersPer100Kilometers:
            return "L/100 km"
        }
    }

    nonisolated var zeroValueText: String {
        switch self {
        case .milesPerGallon:
            return "0.0 mpg"
        case .kilometersPerLiter:
            return "0.0 km/L"
        case .litersPer100Kilometers:
            return "0.0 L/100 km"
        }
    }

    nonisolated func compatibleFormat(for unitSystem: DistanceUnitSystem) -> FuelEconomyFormat {
        switch unitSystem {
        case .miles:
            return .milesPerGallon
        case .kilometers:
            switch self {
            case .milesPerGallon:
                return .kilometersPerLiter
            case .kilometersPerLiter, .litersPer100Kilometers:
                return self
            }
        }
    }

    nonisolated static func defaultFormat(for unitSystem: DistanceUnitSystem) -> FuelEconomyFormat {
        switch unitSystem {
        case .miles:
            return .milesPerGallon
        case .kilometers:
            return .kilometersPerLiter
        }
    }
}

enum SupportedCountry: String, CaseIterable, Identifiable, Codable, Equatable {
    case canada = "Canada"
    case usa = "USA"
    case mexico = "Mexico"
    case southAfrica = "South Africa"
    case uk = "UK"
    case australia = "Australia"
    case newZealand = "New Zealand"
    case other = "Other"

    var id: String { rawValue }

    var defaultDistanceUnit: DistanceUnitSystem {
        switch self {
        case .usa, .uk:
            return .miles
        case .canada, .mexico, .southAfrica, .australia, .newZealand, .other:
            return .kilometers
        }
    }

    var defaultCurrency: PreferredCurrency {
        switch self {
        case .canada:
            return .cad
        case .usa:
            return .usd
        case .mexico:
            return .mxn
        case .southAfrica:
            return .zar
        case .uk:
            return .gbp
        case .australia:
            return .aud
        case .newZealand:
            return .nzd
        case .other:
            return .usd
        }
    }

    nonisolated var defaultFuelVolumeUnit: FuelVolumeUnit {
        switch self {
        case .usa:
            return .gallons
        case .canada, .mexico, .southAfrica, .uk, .australia, .newZealand, .other:
            return .liters
        }
    }

    var taxAuthorityName: String {
        switch self {
        case .canada:
            return "Canada Revenue Agency"
        case .usa:
            return "Internal Revenue Service"
        case .mexico:
            return "Servicio de Administracion Tributaria"
        case .southAfrica:
            return "South African Revenue Service"
        case .uk:
            return "HM Revenue and Customs"
        case .australia:
            return "Australian Taxation Office"
        case .newZealand:
            return "Inland Revenue"
        case .other:
            return "Local Tax Authority"
        }
    }

    var taxYearRuleDescription: String {
        switch self {
        case .southAfrica:
            return "Year of assessment runs from 1 March to the last day of February."
        case .uk:
            return "Self Assessment tax year runs from 6 April to 5 April."
        case .australia:
            return "Income year runs from 1 July to 30 June."
        case .newZealand:
            return "Tax year runs from 1 April to 31 March."
        case .canada, .usa, .mexico:
            return "Default export uses the calendar tax year from 1 January to 31 December."
        case .other:
            return "Review local tax-year rules before filing."
        }
    }

    var taxExportGuidance: [String] {
        switch self {
        case .uk:
            return [
                "Use exact journey dates and odometer readings for each business trip.",
                "Keep supporting fuel and maintenance receipts alongside any apportioned expense claims."
            ]
        case .southAfrica, .australia, .newZealand:
            return [
                "Export is aligned to the selected country's tax year boundaries.",
                "Retain receipts and supporting records for expense claims and reimbursements."
            ]
        case .canada, .usa, .mexico:
            return [
                "Export is aligned to the calendar tax year.",
                "Business-use percentages are included on financial rows where spending may need apportionment."
            ]
        case .other:
            return [
                "Verify the selected date range and local filing rules before submission."
            ]
        }
    }
}

enum PreferredCurrency: String, CaseIterable, Identifiable, Codable, Equatable {
    case usd = "USD"
    case cad = "CAD"
    case mxn = "MXN"
    case zar = "ZAR"
    case gbp = "GBP"
    case aud = "AUD"
    case nzd = "NZD"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usd:
            return "US Dollar"
        case .cad:
            return "Canadian Dollar"
        case .mxn:
            return "Mexican Peso"
        case .zar:
            return "South African Rand"
        case .gbp:
            return "British Pound"
        case .aud:
            return "Australian Dollar"
        case .nzd:
            return "New Zealand Dollar"
        }
    }
}

enum FuelVolumeUnit: String, CaseIterable, Identifiable, Codable, Equatable {
    case liters
    case gallons

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liters:
            return "Liters"
        case .gallons:
            return "Gallons"
        }
    }

    var symbol: String {
        switch self {
        case .liters:
            return "L"
        case .gallons:
            return "gal"
        }
    }

    func displayedVolume(for liters: Double) -> Double {
        switch self {
        case .liters:
            return liters
        case .gallons:
            return liters / 3.785_411_784
        }
    }

    func liters(forDisplayedVolume displayedVolume: Double) -> Double {
        switch self {
        case .liters:
            return displayedVolume
        case .gallons:
            return displayedVolume * 3.785_411_784
        }
    }
}

enum TripType: String, CaseIterable, Identifiable, Codable, Equatable {
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

enum VehicleOwnershipType: String, CaseIterable, Identifiable, Codable, Equatable {
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

nonisolated enum AccountSubscriptionType: String, CaseIterable, Identifiable, Codable, Equatable {
    case personal
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal:
            return "Personal"
        case .business:
            return "Business"
        }
    }
}

nonisolated struct BusinessAccountProfile: Codable, Equatable {
    var accountManagerName: String
    var accountManagerEmail: String
    var accountManagerPhone: String
    var businessName: String
    var legalEntityName: String
    var taxRegistrationNumber: String
    var vatRegistrationNumber: String
    var billingAddressLine1: String
    var billingAddressLine2: String
    var city: String
    var stateOrProvince: String
    var postalCode: String
    var country: String

    static let empty = BusinessAccountProfile(
        accountManagerName: "",
        accountManagerEmail: "",
        accountManagerPhone: "",
        businessName: "",
        legalEntityName: "",
        taxRegistrationNumber: "",
        vatRegistrationNumber: "",
        billingAddressLine1: "",
        billingAddressLine2: "",
        city: "",
        stateOrProvince: "",
        postalCode: "",
        country: ""
    )
}

nonisolated enum VehicleConnectionSource: String, CaseIterable, Identifiable, Codable, Equatable {
    case carPlay
    case audioRoute
    case bluetoothPeripheral

    var id: String { rawValue }

    var title: String {
        switch self {
        case .carPlay:
            return "CarPlay"
        case .audioRoute:
            return "Connected Car Audio"
        case .bluetoothPeripheral:
            return "Bluetooth Peripheral / Beacon"
        }
    }
}

nonisolated struct VehicleDetectionProfile: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case allowedSources
        case bluetoothPeripheralIdentifier
        case bluetoothPeripheralName
        case audioRouteIdentifier
        case audioRouteName
    }

    var isEnabled: Bool
    var allowedSources: Set<VehicleConnectionSource>
    var bluetoothPeripheralIdentifier: String?
    var bluetoothPeripheralName: String
    var audioRouteIdentifier: String?
    var audioRouteName: String

    init(
        isEnabled: Bool = false,
        allowedSources: Set<VehicleConnectionSource> = [],
        bluetoothPeripheralIdentifier: String? = nil,
        bluetoothPeripheralName: String = "",
        audioRouteIdentifier: String? = nil,
        audioRouteName: String = ""
    ) {
        self.isEnabled = isEnabled
        self.allowedSources = allowedSources
        self.bluetoothPeripheralIdentifier = bluetoothPeripheralIdentifier
        self.bluetoothPeripheralName = bluetoothPeripheralName
        self.audioRouteIdentifier = audioRouteIdentifier
        self.audioRouteName = audioRouteName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        allowedSources = Set(
            try container.decodeIfPresent([VehicleConnectionSource].self, forKey: .allowedSources) ?? []
        )
        bluetoothPeripheralIdentifier = try container.decodeIfPresent(String.self, forKey: .bluetoothPeripheralIdentifier)
        bluetoothPeripheralName = try container.decodeIfPresent(String.self, forKey: .bluetoothPeripheralName) ?? ""
        audioRouteIdentifier = try container.decodeIfPresent(String.self, forKey: .audioRouteIdentifier)
        audioRouteName = try container.decodeIfPresent(String.self, forKey: .audioRouteName) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(Array(allowedSources), forKey: .allowedSources)
        try container.encodeIfPresent(bluetoothPeripheralIdentifier, forKey: .bluetoothPeripheralIdentifier)
        try container.encode(bluetoothPeripheralName, forKey: .bluetoothPeripheralName)
        try container.encodeIfPresent(audioRouteIdentifier, forKey: .audioRouteIdentifier)
        try container.encode(audioRouteName, forKey: .audioRouteName)
    }

    var usesCarPlay: Bool {
        allowedSources.contains(.carPlay)
    }

    var usesAudioRoute: Bool {
        allowedSources.contains(.audioRoute)
    }

    var usesBluetoothPeripheral: Bool {
        allowedSources.contains(.bluetoothPeripheral)
    }

    var bluetoothPeripheralUUID: UUID? {
        guard let bluetoothPeripheralIdentifier else {
            return nil
        }

        return UUID(uuidString: bluetoothPeripheralIdentifier)
    }

    var summaryText: String {
        guard isEnabled else {
            return "Off"
        }

        let sourceText = allowedSources
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.title)
            .joined(separator: " + ")

        if usesAudioRoute, !audioRouteName.isEmpty {
            if usesBluetoothPeripheral, !bluetoothPeripheralName.isEmpty {
                return "\(sourceText) • \(audioRouteName) • \(bluetoothPeripheralName)"
            }
            return "\(sourceText) • \(audioRouteName)"
        }

        if usesBluetoothPeripheral, !bluetoothPeripheralName.isEmpty {
            return "\(sourceText) • \(bluetoothPeripheralName)"
        }

        return sourceText
    }
}

nonisolated enum VehicleScheduleFrequency: String, CaseIterable, Identifiable, Codable, Equatable {
    case weekly
    case biweekly
    case semimonthly
    case monthly
    case lastDayOfMonth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .biweekly:
            return "Bi-Weekly"
        case .semimonthly:
            return "Bi-Monthly"
        case .monthly:
            return "Monthly"
        case .lastDayOfMonth:
            return "Last Day of Month"
        }
    }
}

nonisolated struct VehicleRecurringSchedule: Codable, Equatable {
    var frequency: VehicleScheduleFrequency
    var startDate: Date
}

nonisolated struct VehicleAllowancePlan: Codable, Equatable {
    var amount: Double
    var schedule: VehicleRecurringSchedule
}

nonisolated enum VehiclePaymentKind: String, CaseIterable, Identifiable, Codable, Equatable {
    case finance
    case lease

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finance:
            return "Finance Payment"
        case .lease:
            return "Lease Payment"
        }
    }
}

nonisolated struct VehiclePaymentPlan: Codable, Equatable {
    var kind: VehiclePaymentKind
    var amount: Double
    var schedule: VehicleRecurringSchedule
}

nonisolated struct VehicleRecurringExpense: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var amount: Double
    var schedule: VehicleRecurringSchedule
}

nonisolated struct VehicleProfile: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case profileName
        case make
        case model
        case color
        case numberPlate
        case fleetNumber
        case startingOdometerReading
        case ownershipType
        case allowancePlan
        case paymentPlan
        case insurancePlan
        case otherScheduledExpenses
        case detectionProfile
        case archivedAt
        case archiveReason
    }

    var id = UUID()
    let profileName: String
    let make: String
    let model: String
    let color: String
    let numberPlate: String
    let fleetNumber: String
    let startingOdometerReading: Double
    let ownershipType: VehicleOwnershipType
    let allowancePlan: VehicleAllowancePlan?
    let paymentPlan: VehiclePaymentPlan?
    let insurancePlan: VehicleAllowancePlan?
    let otherScheduledExpenses: [VehicleRecurringExpense]
    var detectionProfile: VehicleDetectionProfile
    var archivedAt: Date?
    var archiveReason: String?

    init(
        id: UUID = UUID(),
        profileName: String,
        make: String,
        model: String,
        color: String,
        numberPlate: String,
        fleetNumber: String = "",
        startingOdometerReading: Double,
        ownershipType: VehicleOwnershipType,
        allowancePlan: VehicleAllowancePlan? = nil,
        paymentPlan: VehiclePaymentPlan? = nil,
        insurancePlan: VehicleAllowancePlan? = nil,
        otherScheduledExpenses: [VehicleRecurringExpense] = [],
        detectionProfile: VehicleDetectionProfile = VehicleDetectionProfile(),
        archivedAt: Date? = nil,
        archiveReason: String? = nil
    ) {
        self.id = id
        self.profileName = profileName
        self.make = make
        self.model = model
        self.color = color
        self.numberPlate = numberPlate
        self.fleetNumber = fleetNumber
        self.startingOdometerReading = startingOdometerReading
        self.ownershipType = ownershipType
        self.allowancePlan = allowancePlan
        self.paymentPlan = paymentPlan
        self.insurancePlan = insurancePlan
        self.otherScheduledExpenses = otherScheduledExpenses
        self.detectionProfile = detectionProfile
        self.archivedAt = archivedAt
        self.archiveReason = archiveReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName) ?? ""
        make = try container.decode(String.self, forKey: .make)
        model = try container.decode(String.self, forKey: .model)
        color = try container.decode(String.self, forKey: .color)
        numberPlate = try container.decode(String.self, forKey: .numberPlate)
        fleetNumber = try container.decodeIfPresent(String.self, forKey: .fleetNumber) ?? ""
        startingOdometerReading = try container.decode(Double.self, forKey: .startingOdometerReading)
        ownershipType = try container.decode(VehicleOwnershipType.self, forKey: .ownershipType)
        allowancePlan = try container.decodeIfPresent(VehicleAllowancePlan.self, forKey: .allowancePlan)
        paymentPlan = try container.decodeIfPresent(VehiclePaymentPlan.self, forKey: .paymentPlan)
        insurancePlan = try container.decodeIfPresent(VehicleAllowancePlan.self, forKey: .insurancePlan)
        otherScheduledExpenses = try container.decodeIfPresent([VehicleRecurringExpense].self, forKey: .otherScheduledExpenses) ?? []
        detectionProfile = try container.decodeIfPresent(VehicleDetectionProfile.self, forKey: .detectionProfile) ?? VehicleDetectionProfile()
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        archiveReason = try container.decodeIfPresent(String.self, forKey: .archiveReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(profileName, forKey: .profileName)
        try container.encode(make, forKey: .make)
        try container.encode(model, forKey: .model)
        try container.encode(color, forKey: .color)
        try container.encode(numberPlate, forKey: .numberPlate)
        try container.encode(fleetNumber, forKey: .fleetNumber)
        try container.encode(startingOdometerReading, forKey: .startingOdometerReading)
        try container.encode(ownershipType, forKey: .ownershipType)
        try container.encodeIfPresent(allowancePlan, forKey: .allowancePlan)
        try container.encodeIfPresent(paymentPlan, forKey: .paymentPlan)
        try container.encodeIfPresent(insurancePlan, forKey: .insurancePlan)
        try container.encode(otherScheduledExpenses, forKey: .otherScheduledExpenses)
        try container.encode(detectionProfile, forKey: .detectionProfile)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(archiveReason, forKey: .archiveReason)
    }

    var displayName: String {
        profileName.isEmpty ? "\(make) \(model)" : profileName
    }

    var subtitle: String {
        "\(make) \(model) • \(numberPlate)"
    }
}

nonisolated struct DriverProfile: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case dateOfBirth
        case licenceNumber
        case licenceClass
        case emailAddress
        case phoneNumber
        case permissions
        case archivedAt
    }

    var id = UUID()
    let name: String
    let dateOfBirth: Date
    let licenceNumber: String
    let licenceClass: String
    let emailAddress: String
    let phoneNumber: String
    let permissions: [OrganizationPermission]
    var archivedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        dateOfBirth: Date,
        licenceNumber: String,
        licenceClass: String = "",
        emailAddress: String = "",
        phoneNumber: String = "",
        permissions: [OrganizationPermission] = [],
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.dateOfBirth = dateOfBirth
        self.licenceNumber = licenceNumber
        self.licenceClass = licenceClass
        self.emailAddress = emailAddress
        self.phoneNumber = phoneNumber
        self.permissions = permissions
        self.archivedAt = archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        dateOfBirth = try container.decode(Date.self, forKey: .dateOfBirth)
        licenceNumber = try container.decode(String.self, forKey: .licenceNumber)
        licenceClass = try container.decodeIfPresent(String.self, forKey: .licenceClass) ?? ""
        emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress) ?? ""
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        permissions = try container.decodeIfPresent([OrganizationPermission].self, forKey: .permissions) ?? []
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(dateOfBirth, forKey: .dateOfBirth)
        try container.encode(licenceNumber, forKey: .licenceNumber)
        try container.encode(licenceClass, forKey: .licenceClass)
        try container.encode(emailAddress, forKey: .emailAddress)
        try container.encode(phoneNumber, forKey: .phoneNumber)
        try container.encode(permissions, forKey: .permissions)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
    }

    var subtitle: String {
        let licenceClassText = licenceClass.trimmingCharacters(in: .whitespacesAndNewlines)
        if licenceClassText.isEmpty {
            return "\(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) • \(licenceNumber)"
        }
        return "\(dateOfBirth.formatted(date: .abbreviated, time: .omitted)) • \(licenceNumber) • \(licenceClassText)"
    }
}

nonisolated enum OrganizationSubscriptionPlan: String, Codable, CaseIterable, Identifiable {
    case businessMonthly = "corporateMonthly"
    case businessYearly = "corporateYearly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .businessMonthly:
            return "Business Monthly"
        case .businessYearly:
            return "Business Yearly"
        }
    }
}

nonisolated enum OrganizationBillingStatus: String, Codable, CaseIterable, Identifiable {
    case pendingPayment
    case active
    case pastDue
    case canceled
    case trial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pendingPayment:
            return "Pending Payment"
        case .active:
            return "Active"
        case .pastDue:
            return "Past Due"
        case .canceled:
            return "Canceled"
        case .trial:
            return "Trial"
        }
    }
}

nonisolated enum OrganizationMemberRole: String, Codable, CaseIterable, Identifiable {
    case accountManager
    case employee

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accountManager:
            return "Account Manager"
        case .employee:
            return "Employee / Driver"
        }
    }
}

nonisolated enum OrganizationMemberStatus: String, Codable, CaseIterable, Identifiable {
    case invited
    case active
    case removed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .invited:
            return "Invited"
        case .active:
            return "Active"
        case .removed:
            return "Removed"
        }
    }
}

nonisolated enum OrganizationPermission: String, Codable, CaseIterable, Identifiable {
    case deleteTrips
    case deleteFuelEntries
    case deleteMaintenanceRecords
    case exportLogs
    case viewLogs
    case manageVehicles
    case manageDrivers
    case manageMembers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deleteTrips:
            return "Delete Trips"
        case .deleteFuelEntries:
            return "Delete Fuel-Ups"
        case .deleteMaintenanceRecords:
            return "Delete Maintenance"
        case .exportLogs:
            return "Download Logs"
        case .viewLogs:
            return "View Logs"
        case .manageVehicles:
            return "Manage Vehicles"
        case .manageDrivers:
            return "Manage Drivers"
        case .manageMembers:
            return "Manage Members"
        }
    }
}

nonisolated struct OrganizationProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var plan: OrganizationSubscriptionPlan
    var createdAt: Date = .now
    var billingStatus: OrganizationBillingStatus = .pendingPayment
    var expiresAt: Date?

    var hasActiveBilling: Bool {
        switch billingStatus {
        case .active, .trial:
            if let expiresAt {
                return expiresAt >= .now
            }
            return true
        case .pendingPayment, .pastDue, .canceled:
            return false
        }
    }
}

nonisolated struct OrganizationMembership: Identifiable, Codable, Equatable {
    var id = UUID()
    var organizationID: UUID
    var emailAddress: String
    var displayName: String
    var role: OrganizationMemberRole
    var status: OrganizationMemberStatus
    var assignedVehicleIDs: [UUID] = []
    var assignedDriverID: UUID?
    var permissions: [OrganizationPermission] = []
    var invitedAt: Date = .now
    var activatedAt: Date?
    var removedAt: Date?

    var normalizedEmailAddress: String {
        emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var isActive: Bool {
        status == .active
    }

    func hasPermission(_ permission: OrganizationPermission) -> Bool {
        role == .accountManager || permissions.contains(permission)
    }
}

nonisolated struct Trip: Identifiable, Codable, Equatable {
    struct RoutePoint: Codable, Equatable {
        var latitude: Double
        var longitude: Double

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }

        init(coordinate: CLLocationCoordinate2D) {
            latitude = coordinate.latitude
            longitude = coordinate.longitude
        }
    }

    private enum Constants {
        static let unknownLocationLabel = "Unknown location"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case vehicleID
        case vehicleProfileName
        case driverID
        case driverName
        case driverDateOfBirth
        case driverLicenceNumber
        case startAddress
        case endAddress
        case details
        case odometerStart
        case odometerEnd
        case distanceMeters
        case duration
        case date
        case routePoints
        case manuallyEntered
    }

    var id = UUID()
    var name: String
    var type: TripType
    var vehicleID: UUID?
    var vehicleProfileName: String
    var driverID: UUID?
    var driverName: String
    var driverDateOfBirth: Date?
    var driverLicenceNumber: String
    var startAddress: String
    var endAddress: String
    var details: String
    var odometerStart: Double
    var odometerEnd: Double
    var distanceMeters: Double
    var duration: TimeInterval
    var date: Date
    var routePoints: [RoutePoint] = []
    var manuallyEntered = false

    var effectiveStartAddress: String {
        resolvedAddress(primary: startAddress, fallbackPoint: routePoints.first)
    }

    var effectiveEndAddress: String {
        resolvedAddress(primary: endAddress, fallbackPoint: routePoints.last)
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: TripType,
        vehicleID: UUID?,
        vehicleProfileName: String,
        driverID: UUID?,
        driverName: String,
        driverDateOfBirth: Date? = nil,
        driverLicenceNumber: String = "",
        startAddress: String,
        endAddress: String,
        details: String,
        odometerStart: Double,
        odometerEnd: Double,
        distanceMeters: Double,
        duration: TimeInterval,
        date: Date,
        routePoints: [RoutePoint] = [],
        manuallyEntered: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.vehicleID = vehicleID
        self.vehicleProfileName = vehicleProfileName
        self.driverID = driverID
        self.driverName = driverName
        self.driverDateOfBirth = driverDateOfBirth
        self.driverLicenceNumber = driverLicenceNumber
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.details = details
        self.odometerStart = odometerStart
        self.odometerEnd = odometerEnd
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.date = date
        self.routePoints = routePoints
        self.manuallyEntered = manuallyEntered
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(TripType.self, forKey: .type)
        vehicleID = try container.decodeIfPresent(UUID.self, forKey: .vehicleID)
        vehicleProfileName = try container.decode(String.self, forKey: .vehicleProfileName)
        driverID = try container.decodeIfPresent(UUID.self, forKey: .driverID)
        driverName = try container.decode(String.self, forKey: .driverName)
        driverDateOfBirth = try container.decodeIfPresent(Date.self, forKey: .driverDateOfBirth)
        driverLicenceNumber = try container.decodeIfPresent(String.self, forKey: .driverLicenceNumber) ?? ""
        startAddress = try container.decode(String.self, forKey: .startAddress)
        endAddress = try container.decode(String.self, forKey: .endAddress)
        details = try container.decode(String.self, forKey: .details)
        odometerStart = try container.decode(Double.self, forKey: .odometerStart)
        odometerEnd = try container.decode(Double.self, forKey: .odometerEnd)
        distanceMeters = try container.decode(Double.self, forKey: .distanceMeters)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        date = try container.decode(Date.self, forKey: .date)
        routePoints = try container.decodeIfPresent([RoutePoint].self, forKey: .routePoints) ?? []
        manuallyEntered = try container.decodeIfPresent(Bool.self, forKey: .manuallyEntered) ?? false
    }

    var requiresBusinessDetailsAttention: Bool {
        type == .business && details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func resolvedAddress(primary: String, fallbackPoint: RoutePoint?) -> String {
        let trimmedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrimary.isEmpty, trimmedPrimary.caseInsensitiveCompare(Constants.unknownLocationLabel) != .orderedSame {
            return trimmedPrimary
        }

        guard let fallbackPoint else {
            return trimmedPrimary.isEmpty ? "Not recorded" : trimmedPrimary
        }

        let latitude = fallbackPoint.latitude.formatted(.number.precision(.fractionLength(5)))
        let longitude = fallbackPoint.longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(latitude), \(longitude)"
    }

    var driverDetailsSummary: String {
        guard driverDateOfBirth != nil || !driverLicenceNumber.isEmpty else {
            return "No driver details saved"
        }

        let birthDateText = driverDateOfBirth?.formatted(date: .abbreviated, time: .omitted) ?? "DOB not saved"
        let licenceText = driverLicenceNumber.isEmpty ? "Licence not saved" : driverLicenceNumber
        return "\(birthDateText) • \(licenceText)"
    }
}

nonisolated struct FuelEntry: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case vehicleID
        case vehicleProfileName
        case station
        case volume
        case totalCost
        case odometer
        case date
        case receiptImageData
    }

    var id = UUID()
    var vehicleID: UUID?
    var vehicleProfileName: String
    var station: String
    var volume: Double
    var totalCost: Double
    var odometer: Double
    var date: Date
    var receiptImageData: Data?

    init(
        id: UUID = UUID(),
        vehicleID: UUID? = nil,
        vehicleProfileName: String = "",
        station: String,
        volume: Double,
        totalCost: Double,
        odometer: Double,
        date: Date,
        receiptImageData: Data? = nil
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.vehicleProfileName = vehicleProfileName
        self.station = station
        self.volume = volume
        self.totalCost = totalCost
        self.odometer = odometer
        self.date = date
        self.receiptImageData = receiptImageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        vehicleID = try container.decodeIfPresent(UUID.self, forKey: .vehicleID)
        vehicleProfileName = try container.decodeIfPresent(String.self, forKey: .vehicleProfileName) ?? ""
        station = try container.decode(String.self, forKey: .station)
        volume = try container.decode(Double.self, forKey: .volume)
        totalCost = try container.decode(Double.self, forKey: .totalCost)
        odometer = try container.decode(Double.self, forKey: .odometer)
        date = try container.decode(Date.self, forKey: .date)
        receiptImageData = try container.decodeIfPresent(Data.self, forKey: .receiptImageData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(vehicleID, forKey: .vehicleID)
        try container.encode(vehicleProfileName, forKey: .vehicleProfileName)
        try container.encode(station, forKey: .station)
        try container.encode(volume, forKey: .volume)
        try container.encode(totalCost, forKey: .totalCost)
        try container.encode(odometer, forKey: .odometer)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(receiptImageData, forKey: .receiptImageData)
    }

    var volumeText: String {
        "\(volume.formatted(.number.precision(.fractionLength(1)))) L"
    }

    var odometerText: String {
        "\(Int(odometer))"
    }
}

nonisolated enum MaintenanceType: String, CaseIterable, Identifiable, Codable, Equatable {
    case scheduledMaintenance = "Scheduled Maintenance"
    case oilChange = "Oil Change"
    case tyres = "Tyres"
    case repairs = "Repairs"
    case other = "Other"

    var id: String { rawValue }

    nonisolated var title: String { rawValue }

    var supportsReminder: Bool {
        self == .scheduledMaintenance || self == .oilChange
    }
}

enum MaintenanceReminderThreshold: Double, CaseIterable {
    case thousand = 1_000
    case twoHundred = 200

    var title: String {
        switch self {
        case .thousand:
            return "Upcoming Service Reminder"
        case .twoHundred:
            return "Service Due Soon"
        }
    }
}

nonisolated struct MaintenanceRecord: Identifiable, Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case id
        case vehicleID
        case vehicleProfileName
        case shopName
        case odometer
        case date
        case type
        case otherDescription
        case notes
        case totalCost
        case receiptImageData
        case reminderEnabled
        case nextServiceOdometer
        case nextServiceDate
        case hasSentThousandReminder
        case hasSentTwoHundredReminder
        case title
        case dueMileage
    }

    var id = UUID()
    var vehicleID: UUID?
    var vehicleProfileName: String
    var shopName: String
    var odometer: Double
    var date: Date
    var type: MaintenanceType
    var otherDescription: String
    var notes: String
    var totalCost: Double
    var receiptImageData: Data?
    var reminderEnabled: Bool
    var nextServiceOdometer: Double?
    var nextServiceDate: Date?
    var hasSentThousandReminder: Bool
    var hasSentTwoHundredReminder: Bool

    init(
        id: UUID = UUID(),
        vehicleID: UUID? = nil,
        vehicleProfileName: String = "",
        shopName: String,
        odometer: Double,
        date: Date,
        type: MaintenanceType,
        otherDescription: String = "",
        notes: String = "",
        totalCost: Double,
        receiptImageData: Data? = nil,
        reminderEnabled: Bool = false,
        nextServiceOdometer: Double? = nil,
        nextServiceDate: Date? = nil,
        hasSentThousandReminder: Bool = false,
        hasSentTwoHundredReminder: Bool = false
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.vehicleProfileName = vehicleProfileName
        self.shopName = shopName
        self.odometer = odometer
        self.date = date
        self.type = type
        self.otherDescription = otherDescription
        self.notes = notes
        self.totalCost = totalCost
        self.receiptImageData = receiptImageData
        self.reminderEnabled = reminderEnabled
        self.nextServiceOdometer = nextServiceOdometer
        self.nextServiceDate = nextServiceDate
        self.hasSentThousandReminder = hasSentThousandReminder
        self.hasSentTwoHundredReminder = hasSentTwoHundredReminder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        if let type = try container.decodeIfPresent(MaintenanceType.self, forKey: .type) {
            vehicleID = try container.decodeIfPresent(UUID.self, forKey: .vehicleID)
            vehicleProfileName = try container.decodeIfPresent(String.self, forKey: .vehicleProfileName) ?? ""
            shopName = try container.decodeIfPresent(String.self, forKey: .shopName) ?? ""
            odometer = try container.decodeIfPresent(Double.self, forKey: .odometer) ?? 0
            date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now
            self.type = type
            otherDescription = try container.decodeIfPresent(String.self, forKey: .otherDescription) ?? ""
            notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
            totalCost = try container.decodeIfPresent(Double.self, forKey: .totalCost) ?? 0
            receiptImageData = try container.decodeIfPresent(Data.self, forKey: .receiptImageData)
            reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
            nextServiceOdometer = try container.decodeIfPresent(Double.self, forKey: .nextServiceOdometer)
            nextServiceDate = try container.decodeIfPresent(Date.self, forKey: .nextServiceDate)
            hasSentThousandReminder = try container.decodeIfPresent(Bool.self, forKey: .hasSentThousandReminder) ?? false
            hasSentTwoHundredReminder = try container.decodeIfPresent(Bool.self, forKey: .hasSentTwoHundredReminder) ?? false
        } else {
            vehicleID = nil
            vehicleProfileName = ""
            let legacyTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? "Other"
            let legacyDueMileage = try container.decodeIfPresent(Double.self, forKey: .dueMileage)
            let legacyNotes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""

            shopName = ""
            odometer = 0
            date = .now
            type = legacyTitle.localizedCaseInsensitiveContains("oil") ? .oilChange : .other
            otherDescription = type == .other ? legacyTitle : ""
            notes = legacyNotes
            totalCost = 0
            receiptImageData = nil
            reminderEnabled = legacyDueMileage != nil
            nextServiceOdometer = legacyDueMileage
            nextServiceDate = nil
            hasSentThousandReminder = false
            hasSentTwoHundredReminder = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(vehicleID, forKey: .vehicleID)
        try container.encode(vehicleProfileName, forKey: .vehicleProfileName)
        try container.encode(shopName, forKey: .shopName)
        try container.encode(odometer, forKey: .odometer)
        try container.encode(date, forKey: .date)
        try container.encode(type, forKey: .type)
        try container.encode(otherDescription, forKey: .otherDescription)
        try container.encode(notes, forKey: .notes)
        try container.encode(totalCost, forKey: .totalCost)
        try container.encodeIfPresent(receiptImageData, forKey: .receiptImageData)
        try container.encode(reminderEnabled, forKey: .reminderEnabled)
        try container.encodeIfPresent(nextServiceOdometer, forKey: .nextServiceOdometer)
        try container.encodeIfPresent(nextServiceDate, forKey: .nextServiceDate)
        try container.encode(hasSentThousandReminder, forKey: .hasSentThousandReminder)
        try container.encode(hasSentTwoHundredReminder, forKey: .hasSentTwoHundredReminder)
    }

    var title: String {
        switch type {
        case .other:
            let trimmed = otherDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? type.title : trimmed
        default:
            return type.title
        }
    }

    var reminderSummary: String {
        guard reminderEnabled, let nextServiceOdometer else {
            return "No reminder"
        }

        return "Next service at \(Int(nextServiceOdometer.rounded()))"
    }

    func distanceRemaining(from currentOdometer: Double) -> Double? {
        guard reminderEnabled, let nextServiceOdometer else {
            return nil
        }

        return nextServiceOdometer - currentOdometer
    }

    mutating func markReminderSent(_ threshold: MaintenanceReminderThreshold) {
        switch threshold {
        case .thousand:
            hasSentThousandReminder = true
        case .twoHundred:
            hasSentTwoHundredReminder = true
        }
    }

    func hasSentReminder(for threshold: MaintenanceReminderThreshold) -> Bool {
        switch threshold {
        case .thousand:
            return hasSentThousandReminder
        case .twoHundred:
            return hasSentTwoHundredReminder
        }
    }
}

struct MaintenanceReminderNotification: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

struct CSVPreviewTable {
    let headers: [String]
    let rows: [[String]]
}

struct LogExportPayload {
    let country: SupportedCountry
    let userName: String
    let emailAddress: String
    let vehicleDescription: String
    let preferredCurrency: PreferredCurrency
    let distanceUnit: DistanceUnitSystem
    let exportDateRange: ClosedRange<Date>
    let taxYearInterval: DateInterval
    let taxYearLabel: String
    let taxAuthorityName: String
    let taxYearCoverage: [String]
    let complianceNotes: [String]
    let vehicleDescriptions: [UUID: String]
    let trips: [Trip]
    let fuelEntries: [FuelEntry]
    let maintenanceRecords: [MaintenanceRecord]
}

struct FinancialLogEntry: Identifiable, Equatable {
    var id = UUID()
    let recordType: String
    let vehicleID: UUID?
    let vehicleName: String
    let date: Date
    let category: String
    let description: String
    let amount: Double
    let businessUsePercent: Double?
    let businessPortionAmount: Double?
    let notes: String
}

struct FinancialLogExportPayload {
    let country: SupportedCountry
    let userName: String
    let emailAddress: String
    let vehicleDescription: String
    let preferredCurrency: PreferredCurrency
    let exportDateRange: ClosedRange<Date>
    let taxYearLabel: String
    let taxAuthorityName: String
    let taxYearCoverage: [String]
    let complianceNotes: [String]
    let entries: [FinancialLogEntry]
}

struct LogImportPayload {
    var vehicles: [VehicleProfile]
    var drivers: [DriverProfile]
    var trips: [Trip]
    var fuelEntries: [FuelEntry]
    var maintenanceRecords: [MaintenanceRecord]
}

struct TaxYearStatusSummary {
    let totalTrips: Int
    let totalBusinessTrips: Int
    let totalPersonalTrips: Int
    let totalBusinessDistanceMeters: Double
    let totalPersonalDistanceMeters: Double
    let totalCombinedDistanceMeters: Double
    let totalFuelSpend: Double
    let totalMaintenanceSpend: Double
    let totalCombinedSpend: Double
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A high-confidence mapping from a foreign mileage log CSV format into the app's log schema.")
private struct AIImportMapping {
    @Guide(description: "Whether the file contains a real header row with column names.")
    var hasHeaderRow: Bool

    @Guide(description: "Default record type for imported rows when there is no explicit record type column. Use trip, fuel, maintenance, or unknown.")
    var recordType: String

    @Guide(description: "Distance unit used by the imported distance column. Use miles, kilometers, meters, or unknown.")
    var distanceUnit: String

    @Guide(description: "Overall confidence in the mapping. Use high, medium, or low.")
    var confidence: String

    var mappings: [AIImportColumnMapping]
}

@available(iOS 26.0, *)
@Generable(description: "A mapping from one source CSV column to one destination field in the app schema.")
private struct AIImportColumnMapping {
    var sourceHeader: String

    @Guide(description: "Destination field name from the app schema, or ignore when there is no safe match.")
    var targetField: String
}
#endif

enum LogCSVError: LocalizedError {
    case invalidHeader
    case invalidRecordType
    case invalidDate(String)
    case aiAssistanceLowConfidence
    case aiAssistanceUnavailable
    case aiAssistanceInputTooLarge
    case spreadsheetImportUnsupported

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "The CSV file does not have a valid log header."
        case .invalidRecordType:
            return "The CSV file contains an unknown record type."
        case .invalidDate(let value):
            return "The CSV file contains an invalid date: \(value)"
        case .aiAssistanceLowConfidence:
            return "The CSV file format is too different for a safe AI-assisted import. Review or standardize the file and try again."
        case .aiAssistanceUnavailable:
            return "Apple Intelligence is unavailable, so the app could not interpret this CSV format automatically."
        case .aiAssistanceInputTooLarge:
            return "The file is too large for Apple Intelligence-assisted import. Remove receipt data columns or split the CSV into smaller files and try again."
        case .spreadsheetImportUnsupported:
            return "This spreadsheet format could not be read. Export it as Excel (.xlsx) or CSV and try again."
        }
    }
}

enum LogImportFileDecoder {
    static func text(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "xlsx":
            return try XLSXImportCodec.csvString(from: url)
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }
}

private enum XLSXImportCodec {
    static func csvString(from url: URL) throws -> String {
        let archive = try ZIPArchive(data: Data(contentsOf: url))
        let worksheetPath = try workbookWorksheetPath(in: archive)
        let sharedStrings = try sharedStrings(in: archive)
        let rows = try worksheetRows(at: worksheetPath, in: archive, sharedStrings: sharedStrings)
        guard rows.contains(where: { $0.contains(where: { !$0.isEmpty }) }) else {
            throw LogCSVError.invalidHeader
        }
        return rows
            .map { $0.map(escapeCSVField).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private static func workbookWorksheetPath(in archive: ZIPArchive) throws -> String {
        let workbookData = try archive.entryData(named: "xl/workbook.xml")
        let workbook = try WorkbookParser.parse(workbookData)
        guard let firstSheetRelationshipID = workbook.firstSheetRelationshipID else {
            throw LogCSVError.spreadsheetImportUnsupported
        }

        let relationshipsData = try archive.entryData(named: "xl/_rels/workbook.xml.rels")
        let relationships = try WorkbookRelationshipsParser.parse(relationshipsData)
        guard let target = relationships[firstSheetRelationshipID] else {
            throw LogCSVError.spreadsheetImportUnsupported
        }

        if target.hasPrefix("/") {
            return String(target.dropFirst())
        }
        if target.hasPrefix("xl/") {
            return target
        }
        return "xl/\(target)"
    }

    private static func sharedStrings(in archive: ZIPArchive) throws -> [String] {
        guard let sharedStringsData = try archive.optionalEntryData(named: "xl/sharedStrings.xml") else {
            return []
        }
        return try SharedStringsParser.parse(sharedStringsData)
    }

    private static func worksheetRows(at path: String, in archive: ZIPArchive, sharedStrings: [String]) throws -> [[String]] {
        let worksheetData = try archive.entryData(named: path)
        return try WorksheetParser.parse(worksheetData, sharedStrings: sharedStrings)
    }

    nonisolated private static func escapeCSVField(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escapedValue.contains(",") || escapedValue.contains("\"") || escapedValue.contains("\n") || escapedValue.contains("\r") {
            return "\"\(escapedValue)\""
        }
        return escapedValue
    }

    private struct ZIPArchive {
        private struct Entry {
            let name: String
            let compressionMethod: UInt16
            let compressedSize: Int
            let localHeaderOffset: Int
        }

        private let data: Data
        private let entries: [String: Entry]

        init(data: Data) throws {
            self.data = data
            self.entries = try Self.parseEntries(from: data)
        }

        func optionalEntryData(named name: String) throws -> Data? {
            guard let entry = entries[name] else {
                return nil
            }
            return try extractedData(for: entry)
        }

        func entryData(named name: String) throws -> Data {
            guard let data = try optionalEntryData(named: name) else {
                throw LogCSVError.spreadsheetImportUnsupported
            }
            return data
        }

        private func extractedData(for entry: Entry) throws -> Data {
            let localHeaderOffset = entry.localHeaderOffset
            guard data.readUInt32LE(at: localHeaderOffset) == 0x04034b50 else {
                throw LogCSVError.spreadsheetImportUnsupported
            }

            let fileNameLength = Int(data.readUInt16LE(at: localHeaderOffset + 26))
            let extraFieldLength = Int(data.readUInt16LE(at: localHeaderOffset + 28))
            let dataOffset = localHeaderOffset + 30 + fileNameLength + extraFieldLength
            let dataEndOffset = dataOffset + entry.compressedSize
            guard dataEndOffset <= data.count else {
                throw LogCSVError.spreadsheetImportUnsupported
            }

            let compressedData = data.subdata(in: dataOffset ..< dataEndOffset)
            switch entry.compressionMethod {
            case 0:
                return compressedData
            case 8:
                return try decompressDeflate(compressedData)
            default:
                throw LogCSVError.spreadsheetImportUnsupported
            }
        }

        private static func parseEntries(from data: Data) throws -> [String: Entry] {
            guard let endOfCentralDirectoryOffset = data.lastRange(of: Data([0x50, 0x4b, 0x05, 0x06]))?.lowerBound else {
                throw LogCSVError.spreadsheetImportUnsupported
            }

            let centralDirectoryOffset = Int(data.readUInt32LE(at: endOfCentralDirectoryOffset + 16))
            let totalEntryCount = Int(data.readUInt16LE(at: endOfCentralDirectoryOffset + 10))
            var entries: [String: Entry] = [:]
            var cursor = centralDirectoryOffset

            for _ in 0 ..< totalEntryCount {
                guard data.readUInt32LE(at: cursor) == 0x02014b50 else {
                    throw LogCSVError.spreadsheetImportUnsupported
                }

                let compressionMethod = data.readUInt16LE(at: cursor + 10)
                let compressedSize = Int(data.readUInt32LE(at: cursor + 20))
                let fileNameLength = Int(data.readUInt16LE(at: cursor + 28))
                let extraFieldLength = Int(data.readUInt16LE(at: cursor + 30))
                let fileCommentLength = Int(data.readUInt16LE(at: cursor + 32))
                let localHeaderOffset = Int(data.readUInt32LE(at: cursor + 42))
                let fileNameStart = cursor + 46
                let fileNameEnd = fileNameStart + fileNameLength
                guard fileNameEnd <= data.count else {
                    throw LogCSVError.spreadsheetImportUnsupported
                }

                let fileNameData = data.subdata(in: fileNameStart ..< fileNameEnd)
                guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                    throw LogCSVError.spreadsheetImportUnsupported
                }

                entries[fileName] = Entry(
                    name: fileName,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    localHeaderOffset: localHeaderOffset
                )

                cursor = fileNameEnd + extraFieldLength + fileCommentLength
            }

            return entries
        }
    }

    private final class WorkbookParser: NSObject, XMLParserDelegate {
        private var sheetRelationshipIDs: [String] = []

        static func parse(_ data: Data) throws -> WorkbookParser {
            let parser = WorkbookParser()
            try parser.run(with: data)
            return parser
        }

        var firstSheetRelationshipID: String? {
            sheetRelationshipIDs.first
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "sheet" {
                if let relationshipID = attributeDict["r:id"] ?? attributeDict["id"] {
                    sheetRelationshipIDs.append(relationshipID)
                }
            }
        }

        private func run(with data: Data) throws {
            let parser = XMLParser(data: data)
            parser.delegate = self
            guard parser.parse() else {
                throw parser.parserError ?? LogCSVError.spreadsheetImportUnsupported
            }
        }
    }

    private final class WorkbookRelationshipsParser: NSObject, XMLParserDelegate {
        private var relationships: [String: String] = [:]

        static func parse(_ data: Data) throws -> [String: String] {
            let parser = WorkbookRelationshipsParser()
            try parser.run(with: data)
            return parser.relationships
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
            guard elementName == "Relationship",
                  let id = attributeDict["Id"],
                  let target = attributeDict["Target"]
            else {
                return
            }
            relationships[id] = target
        }

        private func run(with data: Data) throws {
            let parser = XMLParser(data: data)
            parser.delegate = self
            guard parser.parse() else {
                throw parser.parserError ?? LogCSVError.spreadsheetImportUnsupported
            }
        }
    }

    private final class SharedStringsParser: NSObject, XMLParserDelegate {
        private var strings: [String] = []
        private var currentValue = ""
        private var isInsideTextNode = false
        private var isInsideSharedString = false

        static func parse(_ data: Data) throws -> [String] {
            let parser = SharedStringsParser()
            try parser.run(with: data)
            return parser.strings
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes _: [String: String] = [:]) {
            switch elementName {
            case "si":
                isInsideSharedString = true
                currentValue = ""
            case "t":
                if isInsideSharedString {
                    isInsideTextNode = true
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isInsideTextNode {
                currentValue.append(string)
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName _: String?) {
            switch elementName {
            case "t":
                isInsideTextNode = false
            case "si":
                strings.append(currentValue)
                currentValue = ""
                isInsideSharedString = false
            default:
                break
            }
        }

        private func run(with data: Data) throws {
            let parser = XMLParser(data: data)
            parser.delegate = self
            guard parser.parse() else {
                throw parser.parserError ?? LogCSVError.spreadsheetImportUnsupported
            }
        }
    }

    private final class WorksheetParser: NSObject, XMLParserDelegate {
        private let sharedStrings: [String]
        private var rows: [[String]] = []
        private var currentRow: [Int: String] = [:]
        private var currentColumnIndex: Int?
        private var currentCellType = ""
        private var currentCellValue = ""
        private var isReadingValue = false

        init(sharedStrings: [String]) {
            self.sharedStrings = sharedStrings
        }

        static func parse(_ data: Data, sharedStrings: [String]) throws -> [[String]] {
            let parser = WorksheetParser(sharedStrings: sharedStrings)
            try parser.run(with: data)
            return parser.rows
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName _: String?, attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "row":
                currentRow = [:]
            case "c":
                currentCellType = attributeDict["t"] ?? ""
                currentCellValue = ""
                currentColumnIndex = Self.columnIndex(from: attributeDict["r"])
            case "v", "t":
                isReadingValue = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isReadingValue {
                currentCellValue.append(string)
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName _: String?) {
            switch elementName {
            case "v", "t":
                isReadingValue = false
            case "c":
                if let currentColumnIndex {
                    currentRow[currentColumnIndex] = resolvedCellValue()
                }
                currentColumnIndex = nil
                currentCellType = ""
                currentCellValue = ""
            case "row":
                let maxIndex = currentRow.keys.max() ?? -1
                if maxIndex >= 0 {
                    rows.append((0 ... maxIndex).map { currentRow[$0] ?? "" })
                } else {
                    rows.append([])
                }
            default:
                break
            }
        }

        private func resolvedCellValue() -> String {
            let trimmedValue = currentCellValue.trimmingCharacters(in: .newlines)
            switch currentCellType {
            case "s":
                guard let sharedStringIndex = Int(trimmedValue), sharedStringIndex < sharedStrings.count else {
                    return ""
                }
                return sharedStrings[sharedStringIndex]
            default:
                return trimmedValue
            }
        }

        private func run(with data: Data) throws {
            let parser = XMLParser(data: data)
            parser.delegate = self
            guard parser.parse() else {
                throw parser.parserError ?? LogCSVError.spreadsheetImportUnsupported
            }
        }

        private static func columnIndex(from reference: String?) -> Int? {
            guard let reference else {
                return nil
            }

            let letters = reference.prefix { $0.isLetter }.uppercased()
            guard !letters.isEmpty else {
                return nil
            }

            var result = 0
            for scalar in letters.unicodeScalars {
                result = (result * 26) + Int(scalar.value) - 64
            }
            return result - 1
        }
    }

    private static func decompressDeflate(_ data: Data) throws -> Data {
        var index = 0
        let inputFilter: InputFilter<Data> = try InputFilter(.decompress, using: .zlib) { requestedByteCount in
            guard index < data.count else {
                return nil
            }
            let chunkSize = min(requestedByteCount, data.count - index)
            let chunk = data.subdata(in: index ..< index + chunkSize)
            index += chunkSize
            return chunk
        }

        var decompressedData = Data()
        while let chunk = try inputFilter.readData(ofLength: 32_768) {
            decompressedData.append(chunk)
        }
        return decompressedData
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        let subdata = self.subdata(in: offset ..< offset + 2)
        return subdata.withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let subdata = self.subdata(in: offset ..< offset + 4)
        return subdata.withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
    }
}

enum LogCSVCodec {
    private static let header = [
        "record_type",
        "country",
        "account_name",
        "account_email",
        "currency",
        "tax_authority",
        "export_range_start",
        "export_range_end",
        "tax_year_label",
        "tax_year_coverage",
        "distance_unit",
        "tax_year_start",
        "tax_year_end",
        "exported_at",
        "record_id",
        "vehicle_id",
        "vehicle_name",
        "driver_id",
        "driver_name",
        "date",
        "trip_name",
        "trip_type",
        "start_address",
        "end_address",
        "trip_details",
        "odometer_start",
        "odometer_end",
        "distance_meters",
        "duration_seconds",
        "station_or_shop",
        "volume_liters",
        "total_cost",
        "odometer",
        "maintenance_type",
        "other_description",
        "notes",
        "reminder_enabled",
        "next_service_odometer",
        "next_service_date",
        "receipt_base64"
    ]
    private static let displayHeaderMapping = [
        "record_type",
        "date",
        "driver_name",
        "trip_name",
        "trip_type",
        "start_address",
        "end_address",
        "trip_details",
        "odometer_start",
        "odometer_end",
        "distance_meters",
        "duration_seconds",
        "station_or_shop",
        "volume_liters",
        "total_cost",
        "odometer",
        "maintenance_type",
        "other_description",
        "notes",
        "reminder_enabled",
        "next_service_odometer",
        "next_service_date",
        "receipt_base64"
    ]

    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    static func makeCSV(from payload: LogExportPayload) -> String {
        let profile = countryProfile(for: payload.country, distanceUnit: payload.distanceUnit)
        let sortedTrips = payload.trips.sorted { $0.date < $1.date }
        let sortedExpenseEntries = expenseRows(from: payload).sorted { lhs, rhs in
            guard lhs.date != rhs.date else {
                return lhs.category < rhs.category
            }
            return lhs.date < rhs.date
        }

        var rows: [[String]] = []
        rows.append([profile.logTitle])
        rows.append([])
        rows.append(profile.tripHeader)
        rows.append(contentsOf: sortedTrips.map { tripRow($0, payload: payload, profile: profile) })
        rows.append([])
        rows.append([profile.tripSummaryTitle])
        rows.append([profile.totalBusinessDistanceLabel, formattedDistanceValue(profile.tripTypeLabel(.business) == "Work" ? sortedTrips.filter { $0.type == .business }.reduce(0) { $0 + $1.distanceMeters } : sortedTrips.filter { $0.type == .business }.reduce(0) { $0 + $1.distanceMeters }, unit: payload.distanceUnit)])
        rows.append([profile.totalPersonalDistanceLabel, formattedDistanceValue(sortedTrips.filter { $0.type == .personal }.reduce(0) { $0 + $1.distanceMeters }, unit: payload.distanceUnit)])
        rows.append([profile.totalCombinedDistanceLabel, formattedDistanceValue(sortedTrips.reduce(0) { $0 + $1.distanceMeters }, unit: payload.distanceUnit)])
        rows.append([])
        rows.append([profile.expenseLogTitle])
        rows.append(profile.expenseHeader)
        rows.append(contentsOf: sortedExpenseEntries.map { expenseRow($0, profile: profile) })
        return rows.map { row in row.map(escaped).joined(separator: ",") }.joined(separator: "\n")
    }

    static func previewTable(from payload: LogExportPayload) -> CSVPreviewTable {
        var rows: [[String]] = []
        let metadataColumns = [
            payload.country.rawValue,
            payload.userName,
            payload.emailAddress,
            payload.preferredCurrency.rawValue,
            payload.taxAuthorityName,
            isoFormatter.string(from: payload.exportDateRange.lowerBound),
            isoFormatter.string(from: payload.exportDateRange.upperBound),
            payload.taxYearLabel,
            payload.taxYearCoverage.joined(separator: " | "),
            payload.distanceUnit.rawValue,
            isoFormatter.string(from: payload.taxYearInterval.start),
            isoFormatter.string(from: payload.taxYearInterval.end),
            isoFormatter.string(from: .now)
        ]

        rows.append(contentsOf: payload.trips.map { trip in
            [
                "trip",
            ] + metadataColumns + [
                trip.id.uuidString,
                trip.vehicleID?.uuidString ?? "",
                trip.vehicleProfileName,
                trip.driverID?.uuidString ?? "",
                trip.driverName,
                isoFormatter.string(from: trip.date),
                trip.name,
                trip.type.rawValue,
                trip.startAddress,
                trip.endAddress,
                trip.details,
                string(trip.odometerStart),
                string(trip.odometerEnd),
                string(trip.distanceMeters),
                string(trip.duration),
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                ""
            ]
        })

        rows.append(contentsOf: payload.fuelEntries.map { entry in
            [
                "fuel",
            ] + metadataColumns + [
                entry.id.uuidString,
                entry.vehicleID?.uuidString ?? "",
                entry.vehicleProfileName,
                "",
                "",
                isoFormatter.string(from: entry.date),
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                entry.station,
                string(entry.volume),
                string(entry.totalCost),
                string(entry.odometer),
                "",
                "",
                "",
                "",
                "",
                "",
                entry.receiptImageData?.base64EncodedString() ?? ""
            ]
        })

        rows.append(contentsOf: payload.maintenanceRecords.map { record in
            [
                "maintenance",
            ] + metadataColumns + [
                record.id.uuidString,
                record.vehicleID?.uuidString ?? "",
                record.vehicleProfileName,
                "",
                "",
                isoFormatter.string(from: record.date),
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                record.shopName,
                "",
                string(record.totalCost),
                string(record.odometer),
                record.type.rawValue,
                record.otherDescription,
                record.notes,
                record.reminderEnabled ? "true" : "false",
                record.nextServiceOdometer.map(string) ?? "",
                record.nextServiceDate.map { isoFormatter.string(from: $0) } ?? "",
                record.receiptImageData?.base64EncodedString() ?? ""
            ]
        })

        return CSVPreviewTable(headers: header, rows: rows)
    }

    static func parse(_ csv: String) throws -> LogImportPayload {
        let rows = parseCSVRows(csv)
        if let compliantPayload = try parseCompliantSectionedLog(rows) {
            return compliantPayload
        }
        let displayHeadersByUnit: [(DistanceUnitSystem, [String])] = [
            (.miles, displayHeader(for: .miles)),
            (.kilometers, displayHeader(for: .kilometers))
        ]
        guard let headerIndex = rows.firstIndex(where: { row in
            row == header || displayHeadersByUnit.contains(where: { $0.1 == row })
        }) else {
            throw LogCSVError.invalidHeader
        }
        let headerRow = rows[headerIndex]
        let metadata = metadataRows(from: Array(rows.prefix(headerIndex)))
        let matchedDisplayUnit = displayHeadersByUnit.first(where: { $0.1 == headerRow })?.0
        let activeHeader = matchedDisplayUnit == nil ? header : displayHeaderMapping

        var vehiclesByID: [UUID: VehicleProfile] = [:]
        var driversByID: [UUID: DriverProfile] = [:]
        var trips: [Trip] = []
        var fuelEntries: [FuelEntry] = []
        var maintenanceRecords: [MaintenanceRecord] = []

        for row in rows.dropFirst(headerIndex + 1) where !row.allSatisfy(\.isEmpty) {
            let record = Dictionary(uniqueKeysWithValues: zip(activeHeader, row + Array(repeating: "", count: max(0, activeHeader.count - row.count))))
            let recordType = record["record_type"] ?? ""
            let recordID = UUID(uuidString: record["record_id"] ?? "") ?? UUID()
            let vehicleID = UUID(uuidString: record["vehicle_id"] ?? "")
            let metadataVehicleDescription = metadata["Vehicle Description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let vehicleName = record["vehicle_name"]
                ?? ((metadataVehicleDescription.isEmpty || metadataVehicleDescription == "Multiple vehicles") ? "" : metadataVehicleDescription)
            let date = try parseDate(record["date"] ?? "")
            let receiptData = Data(base64Encoded: record["receipt_base64"] ?? "")

            if let vehicleID, !vehicleName.isEmpty {
                let odometerCandidates = [
                    doubleValue(record["odometer_start"]),
                    doubleValue(record["odometer"])
                ].compactMap { $0 }
                let startingOdometer = odometerCandidates.min() ?? 0
                if let existingVehicle = vehiclesByID[vehicleID] {
                    if startingOdometer < existingVehicle.startingOdometerReading {
                        vehiclesByID[vehicleID] = VehicleProfile(
                            id: existingVehicle.id,
                            profileName: existingVehicle.profileName,
                            make: existingVehicle.make,
                            model: existingVehicle.model,
                            color: existingVehicle.color,
                            numberPlate: existingVehicle.numberPlate,
                            startingOdometerReading: startingOdometer,
                            ownershipType: existingVehicle.ownershipType,
                            allowancePlan: existingVehicle.allowancePlan,
                            paymentPlan: existingVehicle.paymentPlan,
                            insurancePlan: existingVehicle.insurancePlan,
                            otherScheduledExpenses: existingVehicle.otherScheduledExpenses,
                            archivedAt: existingVehicle.archivedAt,
                            archiveReason: existingVehicle.archiveReason
                        )
                    }
                } else {
                    vehiclesByID[vehicleID] = VehicleProfile(
                        id: vehicleID,
                        profileName: vehicleName,
                        make: "",
                        model: "",
                        color: "",
                        numberPlate: "",
                        startingOdometerReading: startingOdometer,
                        ownershipType: .personal
                    )
                }
            }

            switch recordType {
            case "trip":
                let driverID = UUID(uuidString: record["driver_id"] ?? "")
                let driverName = record["driver_name"] ?? ""
                let importedDriver = driverID.flatMap { driversByID[$0] }
                if let driverID, !driverName.isEmpty {
                    driversByID[driverID] = driversByID[driverID] ?? DriverProfile(
                        id: driverID,
                        name: driverName,
                        dateOfBirth: .now,
                        licenceNumber: ""
                    )
                }

                trips.append(
                    Trip(
                        id: recordID,
                        name: record["trip_name"] ?? "",
                        type: TripType(rawValue: record["trip_type"] ?? "") ?? .business,
                        vehicleID: vehicleID,
                        vehicleProfileName: vehicleName,
                        driverID: driverID,
                        driverName: driverName,
                        driverDateOfBirth: importedDriver?.dateOfBirth,
                        driverLicenceNumber: importedDriver?.licenceNumber ?? "",
                        startAddress: record["start_address"] ?? "",
                        endAddress: record["end_address"] ?? "",
                        details: record["trip_details"] ?? "",
                        odometerStart: doubleValue(record["odometer_start"]) ?? 0,
                        odometerEnd: doubleValue(record["odometer_end"]) ?? 0,
                        distanceMeters: displayDistanceMeters(from: record["distance_meters"], unit: matchedDisplayUnit),
                        duration: parseDuration(record["duration_seconds"] ?? ""),
                        date: date
                    )
                )
            case "fuel":
                fuelEntries.append(
                    FuelEntry(
                        id: recordID,
                        vehicleID: vehicleID,
                        vehicleProfileName: vehicleName,
                        station: record["station_or_shop"] ?? "",
                        volume: doubleValue(record["volume_liters"]) ?? 0,
                        totalCost: doubleValue(record["total_cost"]) ?? 0,
                        odometer: doubleValue(record["odometer"]) ?? 0,
                        date: date,
                        receiptImageData: receiptData
                    )
                )
            case "maintenance":
                let maintenanceType = MaintenanceType(rawValue: record["maintenance_type"] ?? "") ?? .other
                maintenanceRecords.append(
                    MaintenanceRecord(
                        id: recordID,
                        vehicleID: vehicleID,
                        vehicleProfileName: vehicleName,
                        shopName: record["station_or_shop"] ?? "",
                        odometer: doubleValue(record["odometer"]) ?? 0,
                        date: date,
                        type: maintenanceType,
                        otherDescription: record["other_description"] ?? "",
                        notes: record["notes"] ?? "",
                        totalCost: doubleValue(record["total_cost"]) ?? 0,
                        receiptImageData: receiptData,
                        reminderEnabled: (record["reminder_enabled"] ?? "").lowercased() == "true",
                        nextServiceOdometer: doubleValue(record["next_service_odometer"]),
                        nextServiceDate: try parseOptionalDate(record["next_service_date"] ?? "")
                    )
                )
            default:
                throw LogCSVError.invalidRecordType
            }
        }

        return LogImportPayload(
            vehicles: Array(vehiclesByID.values),
            drivers: Array(driversByID.values),
            trips: trips,
            fuelEntries: fuelEntries,
            maintenanceRecords: maintenanceRecords
        )
    }

    static func parseWithAIAssistanceIfNeeded(_ csv: String) async throws -> (payload: LogImportPayload, usedAIAssistance: Bool) {
        do {
            return (try parse(csv), false)
        } catch let error as LogCSVError {
            switch error {
            case .invalidHeader, .invalidRecordType:
                if let normalizedCSV = normalizedCSVUsingHeuristicHeaderMapping(from: csv) {
                    return (try parse(normalizedCSV), false)
                }
                let normalizedCSV = try await normalizedCSVUsingAIAssistance(from: csv)
                return (try parse(normalizedCSV), true)
            default:
                throw error
            }
        }
    }

    private static func makeDisplayRows(from table: CSVPreviewTable, payload: LogExportPayload) -> [[String]] {
        table.rows.map { row in
            let record = Dictionary(uniqueKeysWithValues: zip(table.headers, row + Array(repeating: "", count: max(0, table.headers.count - row.count))))
            return displayHeaderMapping.map { key in
                switch key {
                case "distance_meters":
                    let meters = doubleValue(record[key]) ?? 0
                    return string(payload.distanceUnit.convertedDistance(for: meters))
                case "duration_seconds":
                    return formatDuration(record[key] ?? "")
                default:
                    return record[key] ?? ""
                }
            }
        }
    }

    private static func displayHeader(for distanceUnit: DistanceUnitSystem) -> [String] {
        [
            "Record Type",
            "Date",
            "Driver Name",
            "Trip Name",
            "Trip Type",
            "Start Address",
            "End Address",
            "Trip Reason",
            "Start Odometer",
            "End Odometer",
            "Distance (\(distanceUnit == .kilometers ? "KM" : "Miles"))",
            "Trip Duration",
            "Station or Shop",
            "Volume (Liters)",
            "Total Cost",
            "Odometer",
            "Maintenance Type",
            "Other Description",
            "Notes",
            "Reminder Enabled",
            "Next Service Odometer",
            "Next Service Date",
            "Receipt Data"
        ]
    }

    private static func formatDuration(_ value: String) -> String {
        let totalSeconds = Int((doubleValue(value) ?? 0).rounded())
        let normalizedSeconds = max(totalSeconds, 0)
        let totalMinutes = normalizedSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let seconds = normalizedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func parseDuration(_ value: String) -> TimeInterval {
        if let rawSeconds = doubleValue(value) {
            return rawSeconds
        }

        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2 || parts.count == 3 else {
            return 0
        }

        if parts.count == 3 {
            return (parts[0] * 3_600) + (parts[1] * 60) + parts[2]
        }

        return (parts[0] * 3_600) + (parts[1] * 60)
    }

    private static func parseCompliantSectionedLog(_ rows: [[String]]) throws -> LogImportPayload? {
        let sanitizedRows = rows.map { row in
            row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard let tripHeaderIndex = sanitizedRows.firstIndex(where: { row in
            isCompliantTripHeader(row)
        }) else {
            return nil
        }

        let tripDistanceUnit = compliantDistanceUnit(from: sanitizedRows[tripHeaderIndex]) ?? .kilometers
        var vehicleIDsByKey: [String: UUID] = [:]
        var vehicleNamesByKey: [String: String] = [:]
        var vehicleStartingOdometers: [String: Double] = [:]
        var driverIDsByKey: [String: UUID] = [:]
        var driverNamesByKey: [String: String] = [:]
        var trips: [Trip] = []
        var fuelEntries: [FuelEntry] = []
        var maintenanceRecords: [MaintenanceRecord] = []

        enum Section {
            case trips
            case summary
            case awaitingExpenseHeader
            case expenses
        }

        var section: Section = .trips
        for row in sanitizedRows.dropFirst(tripHeaderIndex + 1) {
            guard row.contains(where: { !$0.isEmpty }) else {
                continue
            }

            if isCompliantExpenseHeader(row) {
                section = .expenses
                continue
            }

            let firstCell = row.first?.uppercased() ?? ""
            switch firstCell {
            case "TRIP SUMMARY":
                section = .summary
                continue
            case "EXPENSE LOG (COMPLIANT)":
                section = .awaitingExpenseHeader
                continue
            default:
                break
            }

            switch section {
            case .trips:
                guard firstCell == "TRIP" else {
                    continue
                }

                let trip = try compliantTrip(
                    from: row,
                    distanceUnit: tripDistanceUnit,
                    vehicleIDsByKey: &vehicleIDsByKey,
                    vehicleNamesByKey: &vehicleNamesByKey,
                    vehicleStartingOdometers: &vehicleStartingOdometers,
                    driverIDsByKey: &driverIDsByKey,
                    driverNamesByKey: &driverNamesByKey
                )
                trips.append(trip)
            case .summary, .awaitingExpenseHeader:
                continue
            case .expenses:
                let expenseCategory = firstCell
                switch expenseCategory {
                case "FUEL":
                    let entry = try compliantFuelEntry(
                        from: row,
                        vehicleIDsByKey: &vehicleIDsByKey,
                        vehicleNamesByKey: &vehicleNamesByKey,
                        vehicleStartingOdometers: &vehicleStartingOdometers
                    )
                    fuelEntries.append(entry)
                case "MAINTENANCE":
                    let record = try compliantMaintenanceRecord(
                        from: row,
                        vehicleIDsByKey: &vehicleIDsByKey,
                        vehicleNamesByKey: &vehicleNamesByKey,
                        vehicleStartingOdometers: &vehicleStartingOdometers
                    )
                    maintenanceRecords.append(record)
                default:
                    continue
                }
            }
        }

        let vehicles = vehicleNamesByKey.keys.sorted().map { key in
            let name = vehicleNamesByKey[key] ?? ""
            let plate = extractedPlateNumber(from: name)
            return VehicleProfile(
                id: vehicleIDsByKey[key] ?? stableUUID(seed: "vehicle:\(key)"),
                profileName: name,
                make: name,
                model: "",
                color: "",
                numberPlate: plate,
                startingOdometerReading: vehicleStartingOdometers[key] ?? 0,
                ownershipType: .personal
            )
        }
        let drivers = driverNamesByKey.keys.sorted().map { key in
            DriverProfile(
                id: driverIDsByKey[key] ?? stableUUID(seed: "driver:\(key)"),
                name: driverNamesByKey[key] ?? "",
                dateOfBirth: .now,
                licenceNumber: ""
            )
        }

        guard !trips.isEmpty || !fuelEntries.isEmpty || !maintenanceRecords.isEmpty else {
            return nil
        }

        return LogImportPayload(
            vehicles: vehicles,
            drivers: drivers,
            trips: trips,
            fuelEntries: fuelEntries,
            maintenanceRecords: maintenanceRecords
        )
    }

    private static func compliantTrip(
        from row: [String],
        distanceUnit: DistanceUnitSystem,
        vehicleIDsByKey: inout [String: UUID],
        vehicleNamesByKey: inout [String: String],
        vehicleStartingOdometers: inout [String: Double],
        driverIDsByKey: inout [String: UUID],
        driverNamesByKey: inout [String: String]
    ) throws -> Trip {
        let vehicleName = value(at: 2, in: row)
        let openingOdometer = doubleValue(value(at: 4, in: row)) ?? 0
        let closingOdometer = doubleValue(value(at: 5, in: row)) ?? openingOdometer
        let displayedDistance = doubleValue(value(at: 6, in: row)) ?? max(closingOdometer - openingOdometer, 0)
        let details = value(at: 7, in: row)
        let endAddress = value(at: 8, in: row)
        let driverName = value(at: 3, in: row)
        let vehicleID = registerImportedVehicle(
            named: vehicleName,
            startingOdometer: openingOdometer,
            vehicleIDsByKey: &vehicleIDsByKey,
            vehicleNamesByKey: &vehicleNamesByKey,
            vehicleStartingOdometers: &vehicleStartingOdometers
        )
        let driverID = registerImportedDriver(
            named: driverName,
            driverIDsByKey: &driverIDsByKey,
            driverNamesByKey: &driverNamesByKey
        )

        return Trip(
            id: stableUUID(seed: "trip:\(row.joined(separator: "|"))"),
            name: details.isEmpty ? "Imported Trip" : details,
            type: compliantTripType(from: value(at: 9, in: row)),
            vehicleID: vehicleID,
            vehicleProfileName: vehicleName,
            driverID: driverID,
            driverName: driverName,
            startAddress: "",
            endAddress: endAddress,
            details: details,
            odometerStart: openingOdometer,
            odometerEnd: closingOdometer,
            distanceMeters: distanceUnit.meters(forDisplayedDistance: displayedDistance),
            duration: 0,
            date: try parseCompliantDate(value(at: 1, in: row)),
            manuallyEntered: true
        )
    }

    private static func compliantFuelEntry(
        from row: [String],
        vehicleIDsByKey: inout [String: UUID],
        vehicleNamesByKey: inout [String: String],
        vehicleStartingOdometers: inout [String: Double]
    ) throws -> FuelEntry {
        let vehicleName = value(at: 2, in: row)
        let odometer = doubleValue(value(at: 4, in: row)) ?? 0
        let description = value(at: 5, in: row)
        let vehicleID = registerImportedVehicle(
            named: vehicleName,
            startingOdometer: odometer,
            vehicleIDsByKey: &vehicleIDsByKey,
            vehicleNamesByKey: &vehicleNamesByKey,
            vehicleStartingOdometers: &vehicleStartingOdometers
        )

        return FuelEntry(
            id: stableUUID(seed: "fuel:\(row.joined(separator: "|"))"),
            vehicleID: vehicleID,
            vehicleProfileName: vehicleName,
            station: value(at: 7, in: row),
            volume: fuelVolumeInLiters(from: description),
            totalCost: doubleValue(value(at: 6, in: row)) ?? 0,
            odometer: odometer,
            date: try parseCompliantDate(value(at: 1, in: row))
        )
    }

    private static func compliantMaintenanceRecord(
        from row: [String],
        vehicleIDsByKey: inout [String: UUID],
        vehicleNamesByKey: inout [String: String],
        vehicleStartingOdometers: inout [String: Double]
    ) throws -> MaintenanceRecord {
        let vehicleName = value(at: 2, in: row)
        let odometer = doubleValue(value(at: 4, in: row)) ?? 0
        let description = value(at: 5, in: row)
        let vehicleID = registerImportedVehicle(
            named: vehicleName,
            startingOdometer: odometer,
            vehicleIDsByKey: &vehicleIDsByKey,
            vehicleNamesByKey: &vehicleNamesByKey,
            vehicleStartingOdometers: &vehicleStartingOdometers
        )

        return MaintenanceRecord(
            id: stableUUID(seed: "maintenance:\(row.joined(separator: "|"))"),
            vehicleID: vehicleID,
            vehicleProfileName: vehicleName,
            shopName: value(at: 7, in: row),
            odometer: odometer,
            date: try parseCompliantDate(value(at: 1, in: row)),
            type: .other,
            otherDescription: description,
            totalCost: doubleValue(value(at: 6, in: row)) ?? 0
        )
    }

    private static func isCompliantTripHeader(_ row: [String]) -> Bool {
        row.count >= 10
            && row[0].uppercased() == "TYPE"
            && row[1].uppercased() == "DATE"
            && row[2].uppercased() == "VEHICLE"
            && row[3].uppercased() == "DRIVER"
            && row[4].uppercased().hasPrefix("OPENING ")
            && row[5].uppercased().hasPrefix("CLOSING ")
            && row[6].uppercased().hasPrefix("TOTAL ")
            && row[7].uppercased() == "REASON"
            && row[8].uppercased() == "END ADDRESS"
            && row[9].uppercased() == "TRIP TYPE"
    }

    private static func isCompliantExpenseHeader(_ row: [String]) -> Bool {
        row.count >= 8
            && row[0].uppercased() == "CATEGORY"
            && row[1].uppercased() == "DATE"
            && row[2].uppercased() == "VEHICLE"
            && row[3].uppercased() == "DRIVER"
            && row[4].uppercased().hasPrefix("ODO ")
            && row[5].uppercased() == "DESCRIPTION"
            && row[6].uppercased() == "AMOUNT"
            && row[7].uppercased() == "PROVIDER/STATION"
    }

    private static func compliantDistanceUnit(from row: [String]) -> DistanceUnitSystem? {
        let unitLabel = value(at: 4, in: row).uppercased()
        if unitLabel.contains("MI") {
            return .miles
        }
        if unitLabel.contains("KM") {
            return .kilometers
        }
        return nil
    }

    private static func compliantTripType(from value: String) -> TripType {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "work", "business":
            return .business
        default:
            return .personal
        }
    }

    private static func parseCompliantDate(_ value: String) throws -> Date {
        if let date = compliantDateFormatter.date(from: value) {
            return date
        }
        return try parseDate(value)
    }

    private static func registerImportedVehicle(
        named name: String,
        startingOdometer: Double,
        vehicleIDsByKey: inout [String: UUID],
        vehicleNamesByKey: inout [String: String],
        vehicleStartingOdometers: inout [String: Double]
    ) -> UUID? {
        let key = normalizedImportKey(name)
        guard !key.isEmpty else {
            return nil
        }
        let id = vehicleIDsByKey[key] ?? stableUUID(seed: "vehicle:\(key)")
        vehicleIDsByKey[key] = id
        vehicleNamesByKey[key] = name
        let currentMinimum = vehicleStartingOdometers[key] ?? startingOdometer
        vehicleStartingOdometers[key] = min(currentMinimum, startingOdometer)
        return id
    }

    private static func registerImportedDriver(
        named name: String,
        driverIDsByKey: inout [String: UUID],
        driverNamesByKey: inout [String: String]
    ) -> UUID? {
        let key = normalizedImportKey(name)
        guard !key.isEmpty else {
            return nil
        }
        let id = driverIDsByKey[key] ?? stableUUID(seed: "driver:\(key)")
        driverIDsByKey[key] = id
        driverNamesByKey[key] = name
        return id
    }

    private static func fuelVolumeInLiters(from description: String) -> Double {
        guard let amount = firstDecimalNumber(in: description) else {
            return 0
        }
        if description.localizedCaseInsensitiveContains("gal") {
            return FuelVolumeUnit.gallons.liters(forDisplayedVolume: amount)
        }
        return amount
    }

    private static func firstDecimalNumber(in value: String) -> Double? {
        guard let range = value.range(of: #"[-+]?[0-9]*\.?[0-9]+"#, options: .regularExpression) else {
            return nil
        }
        return Double(String(value[range]))
    }

    private static func extractedPlateNumber(from vehicleName: String) -> String {
        guard
            let opening = vehicleName.lastIndex(of: "("),
            let closing = vehicleName.lastIndex(of: ")"),
            opening < closing
        else {
            return ""
        }
        let plateRange = vehicleName.index(after: opening) ..< closing
        return vehicleName[plateRange].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedImportKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func value(at index: Int, in row: [String]) -> String {
        guard index < row.count else {
            return ""
        }
        return row[index]
    }

    private static func stableUUID(seed: String) -> UUID {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let bytes = Array(digest)
        let uuidBytes = Array(bytes.prefix(16))
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    private static func displayDistanceMeters(from value: String?, unit: DistanceUnitSystem?) -> Double {
        guard let distance = doubleValue(value) else {
            return 0
        }

        guard let unit else {
            return distance
        }

        return unit.meters(forDisplayedDistance: distance)
    }

    private static func metadataRows(from rows: [[String]]) -> [String: String] {
        rows.reduce(into: [String: String]()) { partialResult, row in
            guard row.count >= 2 else {
                return
            }

            let key = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                return
            }

            partialResult[key] = row[1]
        }
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func valueOrDash(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? "—" : trimmedValue
    }

    private static func parseCSVRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        let characters = Array(csv)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                if isInsideQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    currentField.append("\"")
                    index += 1
                } else {
                    isInsideQuotes.toggle()
                }
            } else if character == "," && !isInsideQuotes {
                currentRow.append(currentField)
                currentField = ""
            } else if character == "\n" && !isInsideQuotes {
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
            } else if character != "\r" {
                currentField.append(character)
            }
            index += 1
        }

        currentRow.append(currentField)
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private static func normalizedCSVUsingAIAssistance(from csv: String) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            throw LogCSVError.aiAssistanceUnavailable
        }

        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw LogCSVError.aiAssistanceUnavailable
        }

        let rows = parseCSVRows(csv).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard let sourceHeader = rows.first else {
            throw LogCSVError.invalidHeader
        }

        let sampleRows = Array(rows.dropFirst().prefix(1))
        let compactSourceHeader = sourceHeader.map(compactAIAssistanceValue)
        let compactSampleRows = sampleRows.map { row in
            row.map(compactAIAssistanceValue)
        }
        let schemaDescription = header.joined(separator: ", ")
        let prompt = """
        Map this imported vehicle log CSV into the app schema.
        Only return high-confidence matches.

        Destination fields:
        \(schemaDescription)

        Rules:
        - Use only destination fields from the provided list.
        - Use targetField = ignore when there is no safe match.
        - recordType must be trip, fuel, maintenance, or unknown.
        - distanceUnit must be miles, kilometers, meters, or unknown.
        - Confidence must be high, medium, or low.
        - Assume the first row is the source header unless the sample clearly proves otherwise.

        Source headers:
        \(compactSourceHeader.joined(separator: " | "))

        Sample rows:
        \(compactSampleRows.enumerated().map { "\($0.offset + 1): \($0.element.joined(separator: " | "))" }.joined(separator: "\n"))
        """

        let session = LanguageModelSession(
            model: .default,
            instructions: "You convert foreign mileage log CSV headers into this app's schema with conservative, high-signal mappings."
        )
        let response: AIImportMapping
        do {
            response = try await session.respond(to: prompt, generating: AIImportMapping.self).content
        } catch {
            let description = error.localizedDescription.lowercased()
            if description.contains("context window") || description.contains("exceeded model context window size") {
                throw LogCSVError.aiAssistanceInputTooLarge
            }
            throw LogCSVError.aiAssistanceUnavailable
        }
        let mapping = response

        guard mapping.hasHeaderRow else {
            throw LogCSVError.aiAssistanceLowConfidence
        }

        let confidence = mapping.confidence.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        guard confidence == "high" || confidence == "medium" else {
            throw LogCSVError.aiAssistanceLowConfidence
        }

        let destinationFields = Set(header)
        let sourceIndexByHeader = Dictionary(uniqueKeysWithValues: sourceHeader.enumerated().map { ($0.element, $0.offset) })
        let inferredRecordType = normalizedRecordType(from: mapping.recordType)
        let inferredDistanceUnit = normalizedDistanceUnit(from: mapping.distanceUnit)
        let normalizedRows = rows.dropFirst().map { row -> [String] in
            var record = Dictionary(uniqueKeysWithValues: header.map { ($0, "") })
            record["record_type"] = inferredRecordType

            for columnMapping in mapping.mappings {
                let targetField = columnMapping.targetField.trimmingCharacters(in: .whitespacesAndNewlines)
                guard destinationFields.contains(targetField) else {
                    continue
                }
                guard let sourceIndex = sourceIndexByHeader[columnMapping.sourceHeader], sourceIndex < row.count else {
                    continue
                }

                let value = row[sourceIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else {
                    continue
                }

                if targetField == "record_type" {
                    record[targetField] = normalizedRecordType(from: value)
                } else {
                    record[targetField] = value
                }
            }

            if
                let distanceValue = record["distance_meters"],
                let parsedDistance = doubleValue(distanceValue)
            {
                switch inferredDistanceUnit {
                case .miles:
                    record["distance_meters"] = string(DistanceUnitSystem.miles.meters(forDisplayedDistance: parsedDistance))
                case .kilometers:
                    record["distance_meters"] = string(DistanceUnitSystem.kilometers.meters(forDisplayedDistance: parsedDistance))
                case .meters, .unknown:
                    break
                }
            }

            return header.map { record[$0] ?? "" }
        }

        let normalizedHeader = header.map(escaped).joined(separator: ",")
        let normalizedBody = normalizedRows
            .map { row in row.map(escaped).joined(separator: ",") }
            .joined(separator: "\n")
        return normalizedBody.isEmpty ? normalizedHeader : "\(normalizedHeader)\n\(normalizedBody)"
        #else
        throw LogCSVError.aiAssistanceUnavailable
        #endif
    }

    private static func normalizedCSVUsingHeuristicHeaderMapping(from csv: String) -> String? {
        let rows = parseCSVRows(csv).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        guard let sourceHeader = rows.first, !sourceHeader.isEmpty else {
            return nil
        }

        let mappedFields = heuristicHeaderMapping(for: sourceHeader)
        guard !mappedFields.isEmpty else {
            return nil
        }

        let inferredRecordType = heuristicRecordType(from: sourceHeader)
        let inferredDistanceUnit = heuristicDistanceUnit(from: sourceHeader)
        let normalizedRows = rows.dropFirst().map { row -> [String] in
            var record = Dictionary(uniqueKeysWithValues: header.map { ($0, "") })
            record["record_type"] = inferredRecordType

            for (targetField, sourceIndex) in mappedFields where sourceIndex < row.count {
                let value = row[sourceIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else {
                    continue
                }
                record[targetField] = targetField == "record_type" ? normalizedRecordType(from: value) : value
            }

            if
                let distanceValue = record["distance_meters"],
                let parsedDistance = doubleValue(distanceValue)
            {
                switch inferredDistanceUnit {
                case .miles:
                    record["distance_meters"] = string(DistanceUnitSystem.miles.meters(forDisplayedDistance: parsedDistance))
                case .kilometers:
                    record["distance_meters"] = string(DistanceUnitSystem.kilometers.meters(forDisplayedDistance: parsedDistance))
                case .meters, .unknown:
                    break
                }
            }

            return header.map { record[$0] ?? "" }
        }

        let normalizedHeader = header.map(escaped).joined(separator: ",")
        let normalizedBody = normalizedRows
            .map { row in row.map(escaped).joined(separator: ",") }
            .joined(separator: "\n")
        return normalizedBody.isEmpty ? normalizedHeader : "\(normalizedHeader)\n\(normalizedBody)"
    }

    private static func normalizedRecordType(from value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "trip", "trips", "mileage":
            return "trip"
        case "fuel", "fuel-up", "fuelup", "fuelups", "fuel-ups", "refuel":
            return "fuel"
        case "maintenance", "service", "repair":
            return "maintenance"
        default:
            return "trip"
        }
    }

    private static func normalizedDistanceUnit(from value: String) -> AIAssistedDistanceUnit {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "miles", "mile", "mi":
            return .miles
        case "kilometers", "kilometres", "kilometer", "kilometre", "km":
            return .kilometers
        case "meters", "metres", "meter", "metre", "m":
            return .meters
        default:
            return .unknown
        }
    }

    private enum AIAssistedDistanceUnit {
        case miles
        case kilometers
        case meters
        case unknown
    }

    private static func heuristicHeaderMapping(for sourceHeader: [String]) -> [String: Int] {
        let normalizedHeaders = sourceHeader.enumerated().map { ($0.offset, normalizedHeaderToken($0.element)) }
        var mapping: [String: Int] = [:]

        func assign(_ targetField: String, matching candidates: [String]) {
            guard mapping[targetField] == nil else {
                return
            }

            if let match = normalizedHeaders.first(where: { _, normalizedHeader in
                candidates.contains(where: { normalizedHeader.contains($0) })
            }) {
                mapping[targetField] = match.0
            }
        }

        assign("record_type", matching: ["recordtype", "type", "category"])
        assign("date", matching: ["date", "tripdate", "servicedate"])
        assign("vehicle_name", matching: ["vehicle", "vehiclename", "car", "unit"])
        assign("driver_name", matching: ["driver", "drivername", "employee"])
        assign("trip_name", matching: ["tripname", "name", "journey"])
        assign("trip_type", matching: ["triptype", "purpose", "classification"])
        assign("start_address", matching: ["startaddress", "fromaddress", "origin", "pickup"])
        assign("end_address", matching: ["endaddress", "toaddress", "destination", "dropoff"])
        assign("trip_details", matching: ["tripdetails", "reason", "description", "details", "purpose"])
        assign("odometer_start", matching: ["odometerstart", "startodometer", "openingodo", "openingodometer", "startodo", "beginodometer"])
        assign("odometer_end", matching: ["odometerend", "endodometer", "closingodo", "closingodometer", "endodo", "finishodometer"])
        assign("distance_meters", matching: ["distance", "totalkm", "totalmi", "mileage", "miles", "kilometers", "kilometres", "km"])
        assign("duration_seconds", matching: ["duration", "tripduration", "elapsed", "time"])
        assign("station_or_shop", matching: ["station", "provider", "shop", "merchant", "vendor"])
        assign("volume_liters", matching: ["volume", "liters", "litres", "gallons", "fuelvolume"])
        assign("total_cost", matching: ["totalcost", "amount", "cost", "price", "total"])
        assign("odometer", matching: ["odometer", "odo"])
        assign("maintenance_type", matching: ["maintenancetype", "servicetype", "repairtype"])
        assign("other_description", matching: ["otherdescription", "description", "service", "repair"])
        assign("notes", matching: ["notes", "memo", "comment"])
        assign("reminder_enabled", matching: ["reminderenabled", "reminder"])
        assign("next_service_odometer", matching: ["nextserviceodometer", "nextodo", "serviceodo"])
        assign("next_service_date", matching: ["nextservicedate", "servicedue", "duedate"])

        return mapping
    }

    private static func heuristicRecordType(from sourceHeader: [String]) -> String {
        let combinedHeader = sourceHeader.map(normalizedHeaderToken).joined(separator: " ")
        if combinedHeader.contains("liter") || combinedHeader.contains("litre") || combinedHeader.contains("gallon") || combinedHeader.contains("station") {
            return "fuel"
        }
        if combinedHeader.contains("service") || combinedHeader.contains("maintenance") || combinedHeader.contains("repair") || combinedHeader.contains("shop") {
            return "maintenance"
        }
        return "trip"
    }

    private static func heuristicDistanceUnit(from sourceHeader: [String]) -> AIAssistedDistanceUnit {
        let combinedHeader = sourceHeader.map(normalizedHeaderToken).joined(separator: " ")
        if combinedHeader.contains("mile") || combinedHeader.contains("mi") {
            return .miles
        }
        if combinedHeader.contains("kilometer") || combinedHeader.contains("kilometre") || combinedHeader.contains("km") {
            return .kilometers
        }
        return .unknown
    }

    nonisolated private static func normalizedHeaderToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "", options: .regularExpression)
    }

    nonisolated private static func escaped(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapedValue)\""
    }

    private static func compactAIAssistanceValue(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return ""
        }

        let collapsedWhitespace = trimmedValue.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if collapsedWhitespace.count > 80,
           collapsedWhitespace.range(of: #"^[A-Za-z0-9+/=]+$"#, options: .regularExpression) != nil {
            return "<binary data omitted>"
        }

        let limit = 40
        if collapsedWhitespace.count <= limit {
            return collapsedWhitespace
        }

        return String(collapsedWhitespace.prefix(limit)) + "…"
    }

    private static func tripRow(_ trip: Trip, payload: LogExportPayload, profile: CountryLogProfile) -> [String] {
        [
            "TRIP",
            exportTimestampString(trip.date),
            vehicleLogLabel(for: trip, payload: payload),
            trip.driverName,
            formattedOdometerValue(trip.odometerStart),
            formattedOdometerValue(trip.odometerEnd),
            formattedDistanceValue(trip.distanceMeters, unit: payload.distanceUnit),
            trip.details,
            trip.endAddress,
            profile.tripTypeLabel(trip.type)
        ]
    }

    private static func vehicleLogLabel(for trip: Trip, payload: LogExportPayload) -> String {
        let trimmedName = trip.vehicleProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            guard let vehicleID = trip.vehicleID else {
                return payload.vehicleDescription
            }
            return payload.vehicleDescriptions[vehicleID] ?? payload.vehicleDescription
        }
        return trimmedName
    }

    private static func exportTimestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func formattedOdometerValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }

    private static func formattedDistanceValue(_ meters: Double, unit: DistanceUnitSystem) -> String {
        unit.convertedDistance(for: meters).formatted(.number.precision(.fractionLength(2)))
    }

    private static func expenseRows(from payload: LogExportPayload) -> [ExpenseLogRow] {
        let fuelRows = payload.fuelEntries.map { entry in
            ExpenseLogRow(
                category: "FUEL",
                date: entry.date,
                vehicle: entry.vehicleProfileName,
                driver: "",
                odometer: entry.odometer,
                description: "\(payload.country.defaultFuelVolumeUnit.displayedVolume(for: entry.volume).formatted(.number.precision(.fractionLength(2))))\(payload.country.defaultFuelVolumeUnit == .gallons ? " gal" : "L") fuel up",
                amount: entry.totalCost,
                provider: entry.station
            )
        }

        let maintenanceRows = payload.maintenanceRecords.map { record in
            ExpenseLogRow(
                category: "MAINTENANCE",
                date: record.date,
                vehicle: record.vehicleProfileName,
                driver: "",
                odometer: record.odometer,
                description: record.title,
                amount: record.totalCost,
                provider: record.shopName
            )
        }

        return fuelRows + maintenanceRows
    }

    private static func expenseRow(_ row: ExpenseLogRow, profile: CountryLogProfile) -> [String] {
        [
            row.category,
            exportTimestampString(row.date),
            row.vehicle,
            row.driver,
            formattedOdometerValue(row.odometer),
            row.description,
            row.amount.formatted(.number.precision(.fractionLength(2))),
            row.provider
        ]
    }

    private static func countryProfile(for country: SupportedCountry, distanceUnit: DistanceUnitSystem) -> CountryLogProfile {
        let authorityPrefix: String = switch country {
        case .canada:
            "CRA"
        case .usa:
            "IRS"
        case .uk:
            "HMRC"
        case .australia:
            "ATO"
        case .newZealand:
            "IRD"
        case .southAfrica:
            "SARS"
        case .mexico:
            "SAT"
        case .other:
            "TAX"
        }

        let unitLabel = distanceUnit == .miles ? "MI" : "KM"
        let tripTypeLabel: (TripType) -> String = { tripType in
            switch (country, tripType) {
            case (.canada, .business):
                return "Work"
            case (_, .business):
                return "Business"
            case (_, .personal):
                return "Personal"
            }
        }

        return CountryLogProfile(
            logTitle: "\(authorityPrefix) COMPLIANT LOG",
            tripSummaryTitle: "TRIP SUMMARY",
            expenseLogTitle: "EXPENSE LOG (COMPLIANT)",
            tripHeader: [
                "TYPE",
                "DATE",
                "VEHICLE",
                "DRIVER",
                "OPENING \(unitLabel)",
                "CLOSING \(unitLabel)",
                "TOTAL \(unitLabel)",
                "REASON",
                "END ADDRESS",
                "TRIP TYPE"
            ],
            expenseHeader: [
                "CATEGORY",
                "DATE",
                "VEHICLE",
                "DRIVER",
                "ODO (\(distanceUnit == .miles ? "mi" : "km"))",
                "DESCRIPTION",
                "AMOUNT",
                "PROVIDER/STATION"
            ],
            totalBusinessDistanceLabel: "Total \(tripTypeLabel(.business)) \(unitLabel)",
            totalPersonalDistanceLabel: "Total Personal \(unitLabel)",
            totalCombinedDistanceLabel: "Total Combined \(unitLabel)",
            tripTypeLabel: tripTypeLabel
        )
    }

    private struct CountryLogProfile {
        let logTitle: String
        let tripSummaryTitle: String
        let expenseLogTitle: String
        let tripHeader: [String]
        let expenseHeader: [String]
        let totalBusinessDistanceLabel: String
        let totalPersonalDistanceLabel: String
        let totalCombinedDistanceLabel: String
        let tripTypeLabel: (TripType) -> String
    }

    private struct ExpenseLogRow {
        let category: String
        let date: Date
        let vehicle: String
        let driver: String
        let odometer: Double
        let description: String
        let amount: Double
        let provider: String
    }

    nonisolated private static func string(_ value: Double) -> String {
        var text = String(format: "%.6f", value)
        while text.contains(".") && text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    nonisolated private static func doubleValue(_ value: String?) -> Double? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let directValue = Double(trimmedValue) {
            return directValue
        }

        let posixFormatter = NumberFormatter()
        posixFormatter.locale = Locale(identifier: "en_US_POSIX")
        posixFormatter.numberStyle = .decimal
        if let formattedNumber = posixFormatter.number(from: trimmedValue) {
            return formattedNumber.doubleValue
        }

        let groupingStrippedValue = trimmedValue.replacingOccurrences(of: ",", with: "")
        if let normalizedGroupingValue = Double(groupingStrippedValue) {
            return normalizedGroupingValue
        }

        let decimalNormalizedValue = trimmedValue.replacingOccurrences(of: ",", with: ".")
        if let normalizedDecimalValue = Double(decimalNormalizedValue) {
            return normalizedDecimalValue
        }

        return nil
    }

    nonisolated private static func parseDate(_ value: String) throws -> Date {
        guard let date = isoFormatter.date(from: value) else {
            throw LogCSVError.invalidDate(value)
        }

        return date
    }

    private static let compliantDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    nonisolated private static func parseOptionalDate(_ value: String) throws -> Date? {
        guard !value.isEmpty else {
            return nil
        }

        return try parseDate(value)
    }
}

enum FinancialLogCSVCodec {
    private static let header = [
        "record_type",
        "country",
        "account_name",
        "account_email",
        "currency",
        "tax_authority",
        "tax_year_label",
        "tax_year_coverage",
        "export_range_start",
        "export_range_end",
        "exported_at",
        "record_id",
        "vehicle_id",
        "vehicle_name",
        "date",
        "category",
        "description",
        "amount",
        "business_use_percent",
        "business_portion_amount",
        "notes"
    ]

    nonisolated(unsafe) private static let isoFormatter = ISO8601DateFormatter()

    static func makeCSV(from payload: FinancialLogExportPayload) -> String {
        let previewTable = previewTable(from: payload)
        var metadataRows = [
            ["Account Name", valueOrDash(payload.userName)],
            ["Account Email", valueOrDash(payload.emailAddress)],
            ["Export Range", "\(shortDate(payload.exportDateRange.lowerBound)) to \(shortDate(payload.exportDateRange.upperBound))"],
            ["Tax Year Label", payload.taxYearLabel],
            ["Tax Year Coverage", payload.taxYearCoverage.joined(separator: " | ")],
            ["Tax Authority", payload.taxAuthorityName],
            ["Vehicle Description", payload.vehicleDescription],
            ["Country", payload.country.rawValue],
            ["Currency", payload.preferredCurrency.rawValue],
            ["Compliance Notes", payload.complianceNotes.joined(separator: " | ")]
        ]
        metadataRows.append([])
        let rows = metadataRows + [header] + previewTable.rows
        return rows.map { row in row.map(escaped).joined(separator: ",") }.joined(separator: "\n")
    }

    static func previewTable(from payload: FinancialLogExportPayload) -> CSVPreviewTable {
        let rows = payload.entries.map { entry in
            [
                entry.recordType,
                payload.country.rawValue,
                payload.userName,
                payload.emailAddress,
                payload.preferredCurrency.rawValue,
                payload.taxAuthorityName,
                payload.taxYearLabel,
                payload.taxYearCoverage.joined(separator: " | "),
                isoFormatter.string(from: payload.exportDateRange.lowerBound),
                isoFormatter.string(from: payload.exportDateRange.upperBound),
                isoFormatter.string(from: .now),
                entry.id.uuidString,
                entry.vehicleID?.uuidString ?? "",
                entry.vehicleName,
                isoFormatter.string(from: entry.date),
                entry.category,
                entry.description,
                string(entry.amount),
                entry.businessUsePercent.map { string($0) } ?? "",
                entry.businessPortionAmount.map { string($0) } ?? "",
                entry.notes
            ]
        }

        return CSVPreviewTable(headers: header, rows: rows)
    }

    nonisolated private static func valueOrDash(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    nonisolated private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    nonisolated private static func escaped(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapedValue)\""
    }

    nonisolated private static func string(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
    }
}

nonisolated struct LogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    let title: String
    let date: Date
}

nonisolated struct AllowanceAdjustment: Identifiable, Codable, Equatable {
    var id = UUID()
    let vehicleID: UUID
    let amount: Double
    let reason: String
    let date: Date
}

struct AllowanceBalanceSummary: Equatable {
    let receivedAllowance: Double
    let manualAdjustments: Double
    let scheduledExpenses: Double
    let fuelSpend: Double
    let maintenanceSpend: Double

    var spentAmount: Double {
        scheduledExpenses + fuelSpend + maintenanceSpend
    }

    var remainingBalance: Double {
        receivedAllowance + manualAdjustments - spentAmount
    }

    var utilizationProgress: Double {
        let availableFunds = receivedAllowance + manualAdjustments
        guard availableFunds > 0 else {
            return 0
        }

        return min(max(spentAmount / availableFunds, 0), 1)
    }
}

@MainActor
@Observable
final class MileageStore {
    static let demoTripLimit = 5
    static let demoFuelEntryLimit = 5
    static let demoMaintenanceRecordLimit = 5

    private enum Constants {
        static let unknownLocationLabel = "Unknown location"
    }

    nonisolated struct PersistenceSnapshot: Codable, Equatable {
        private enum CodingKeys: String, CodingKey {
            case selectedCountry
            case userName
            case emailAddress
            case preferredCurrency
            case unitSystem
            case fuelVolumeUnit
            case fuelEconomyFormat
            case preventAutoLock
            case vehicleDetectionEnabled
            case hasCompletedOnboarding
            case hasAcceptedPrivacyPolicy
            case hasAcceptedLegalNotice
            case accountSubscriptionType
            case businessProfile
            case organizations
            case activeOrganizationID
            case organizationMemberships
            case vehicles
            case archivedVehicles
            case activeVehicleID
            case drivers
            case archivedDrivers
            case activeDriverID
            case trips
            case fuelEntries
            case maintenanceRecords
            case logs
            case allowanceAdjustments
        }

        var selectedCountry: SupportedCountry
        var userName: String
        var emailAddress: String
        var preferredCurrency: PreferredCurrency
        var unitSystem: DistanceUnitSystem
        var fuelVolumeUnit: FuelVolumeUnit
        var fuelEconomyFormat: FuelEconomyFormat
        var preventAutoLock: Bool
        var vehicleDetectionEnabled: Bool
        var hasCompletedOnboarding: Bool
        var hasAcceptedPrivacyPolicy: Bool
        var hasAcceptedLegalNotice: Bool
        var accountSubscriptionType: AccountSubscriptionType
        var businessProfile: BusinessAccountProfile?
        var organizations: [OrganizationProfile]
        var activeOrganizationID: UUID?
        var organizationMemberships: [OrganizationMembership]
        var vehicles: [VehicleProfile]
        var archivedVehicles: [VehicleProfile]
        var activeVehicleID: UUID?
        var drivers: [DriverProfile]
        var archivedDrivers: [DriverProfile]
        var activeDriverID: UUID?
        var trips: [Trip]
        var fuelEntries: [FuelEntry]
        var maintenanceRecords: [MaintenanceRecord]
        var logs: [LogEntry]
        var allowanceAdjustments: [AllowanceAdjustment]

        init(
            selectedCountry: SupportedCountry,
            userName: String,
            emailAddress: String,
            preferredCurrency: PreferredCurrency,
            unitSystem: DistanceUnitSystem,
            fuelVolumeUnit: FuelVolumeUnit,
            fuelEconomyFormat: FuelEconomyFormat,
            preventAutoLock: Bool,
            vehicleDetectionEnabled: Bool,
            hasCompletedOnboarding: Bool,
            hasAcceptedPrivacyPolicy: Bool,
            hasAcceptedLegalNotice: Bool,
            accountSubscriptionType: AccountSubscriptionType = .personal,
            businessProfile: BusinessAccountProfile? = nil,
            organizations: [OrganizationProfile] = [],
            activeOrganizationID: UUID? = nil,
            organizationMemberships: [OrganizationMembership] = [],
            vehicles: [VehicleProfile],
            archivedVehicles: [VehicleProfile] = [],
            activeVehicleID: UUID?,
            drivers: [DriverProfile],
            archivedDrivers: [DriverProfile] = [],
            activeDriverID: UUID?,
            trips: [Trip],
            fuelEntries: [FuelEntry],
            maintenanceRecords: [MaintenanceRecord],
            logs: [LogEntry],
            allowanceAdjustments: [AllowanceAdjustment]
        ) {
            self.selectedCountry = selectedCountry
            self.userName = userName
            self.emailAddress = emailAddress
            self.preferredCurrency = preferredCurrency
            self.unitSystem = unitSystem
            self.fuelVolumeUnit = fuelVolumeUnit
            self.fuelEconomyFormat = fuelEconomyFormat.compatibleFormat(for: unitSystem)
            self.preventAutoLock = preventAutoLock
            self.vehicleDetectionEnabled = vehicleDetectionEnabled
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.hasAcceptedPrivacyPolicy = hasAcceptedPrivacyPolicy
            self.hasAcceptedLegalNotice = hasAcceptedLegalNotice
            self.accountSubscriptionType = accountSubscriptionType
            self.businessProfile = businessProfile
            self.organizations = organizations
            self.activeOrganizationID = activeOrganizationID
            self.organizationMemberships = organizationMemberships
            self.vehicles = vehicles
            self.archivedVehicles = archivedVehicles
            self.activeVehicleID = activeVehicleID
            self.drivers = drivers
            self.archivedDrivers = archivedDrivers
            self.activeDriverID = activeDriverID
            self.trips = trips
            self.fuelEntries = fuelEntries
            self.maintenanceRecords = maintenanceRecords
            self.logs = logs
            self.allowanceAdjustments = allowanceAdjustments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            selectedCountry = try container.decode(SupportedCountry.self, forKey: .selectedCountry)
            userName = try container.decodeIfPresent(String.self, forKey: .userName) ?? ""
            emailAddress = try container.decodeIfPresent(String.self, forKey: .emailAddress) ?? ""
            preferredCurrency = try container.decode(PreferredCurrency.self, forKey: .preferredCurrency)
            unitSystem = try container.decode(DistanceUnitSystem.self, forKey: .unitSystem)
            if let decodedFuelVolumeUnit = try container.decodeIfPresent(FuelVolumeUnit.self, forKey: .fuelVolumeUnit) {
                fuelVolumeUnit = decodedFuelVolumeUnit
            } else {
                fuelVolumeUnit = selectedCountry.defaultFuelVolumeUnit
            }
            let decodedFuelEconomyFormat = try container.decodeIfPresent(FuelEconomyFormat.self, forKey: .fuelEconomyFormat)
            fuelEconomyFormat = (decodedFuelEconomyFormat ?? .defaultFormat(for: unitSystem)).compatibleFormat(for: unitSystem)
            preventAutoLock = try container.decodeIfPresent(Bool.self, forKey: .preventAutoLock) ?? false
            vehicleDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .vehicleDetectionEnabled) ?? false
            hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
            hasAcceptedPrivacyPolicy = try container.decodeIfPresent(Bool.self, forKey: .hasAcceptedPrivacyPolicy) ?? false
            hasAcceptedLegalNotice = try container.decodeIfPresent(Bool.self, forKey: .hasAcceptedLegalNotice) ?? false
            accountSubscriptionType = try container.decodeIfPresent(AccountSubscriptionType.self, forKey: .accountSubscriptionType) ?? .personal
            businessProfile = try container.decodeIfPresent(BusinessAccountProfile.self, forKey: .businessProfile)
            organizations = try container.decodeIfPresent([OrganizationProfile].self, forKey: .organizations) ?? []
            activeOrganizationID = try container.decodeIfPresent(UUID.self, forKey: .activeOrganizationID)
            organizationMemberships = try container.decodeIfPresent([OrganizationMembership].self, forKey: .organizationMemberships) ?? []
            vehicles = try container.decodeIfPresent([VehicleProfile].self, forKey: .vehicles) ?? []
            archivedVehicles = try container.decodeIfPresent([VehicleProfile].self, forKey: .archivedVehicles) ?? []
            activeVehicleID = try container.decodeIfPresent(UUID.self, forKey: .activeVehicleID)
            drivers = try container.decodeIfPresent([DriverProfile].self, forKey: .drivers) ?? []
            archivedDrivers = try container.decodeIfPresent([DriverProfile].self, forKey: .archivedDrivers) ?? []
            activeDriverID = try container.decodeIfPresent(UUID.self, forKey: .activeDriverID)
            trips = try container.decodeIfPresent([Trip].self, forKey: .trips) ?? []
            fuelEntries = try container.decodeIfPresent([FuelEntry].self, forKey: .fuelEntries) ?? []
            maintenanceRecords = try container.decodeIfPresent([MaintenanceRecord].self, forKey: .maintenanceRecords) ?? []
            logs = try container.decodeIfPresent([LogEntry].self, forKey: .logs) ?? []
            allowanceAdjustments = try container.decodeIfPresent([AllowanceAdjustment].self, forKey: .allowanceAdjustments) ?? []
        }
    }

    var selectedCountry: SupportedCountry = .usa
    var userName = ""
    var emailAddress = ""
    var preferredCurrency: PreferredCurrency = .usd
    var unitSystem: DistanceUnitSystem = .miles
    var fuelVolumeUnit: FuelVolumeUnit = .gallons
    var fuelEconomyFormat: FuelEconomyFormat = .milesPerGallon
    var preventAutoLock = false
    var vehicleDetectionEnabled = false
    var hasCompletedOnboarding = false
    var hasAcceptedPrivacyPolicy = false
    var hasAcceptedLegalNotice = false
    var accountSubscriptionType: AccountSubscriptionType = .personal
    var businessProfile: BusinessAccountProfile?
    var organizations: [OrganizationProfile] = []
    var activeOrganizationID: UUID?
    var organizationMemberships: [OrganizationMembership] = []
    var vehicles: [VehicleProfile] = []
    var archivedVehicles: [VehicleProfile] = []
    var activeVehicleID: UUID?
    var drivers: [DriverProfile] = []
    var archivedDrivers: [DriverProfile] = []
    var activeDriverID: UUID?
    var trips: [Trip] = []
    var fuelEntries: [FuelEntry] = []
    var maintenanceRecords: [MaintenanceRecord] = []
    var logs: [LogEntry] = []
    var allowanceAdjustments: [AllowanceAdjustment] = []
    var isDemoModeEnabled = false

    var persistenceSnapshot: PersistenceSnapshot {
        PersistenceSnapshot(
            selectedCountry: selectedCountry,
            userName: userName,
            emailAddress: emailAddress,
            preferredCurrency: preferredCurrency,
            unitSystem: unitSystem,
            fuelVolumeUnit: fuelVolumeUnit,
            fuelEconomyFormat: fuelEconomyFormat,
            preventAutoLock: preventAutoLock,
            vehicleDetectionEnabled: vehicleDetectionEnabled,
            hasCompletedOnboarding: hasCompletedOnboarding,
            hasAcceptedPrivacyPolicy: hasAcceptedPrivacyPolicy,
            hasAcceptedLegalNotice: hasAcceptedLegalNotice,
            accountSubscriptionType: accountSubscriptionType,
            businessProfile: businessProfile,
            organizations: organizations,
            activeOrganizationID: activeOrganizationID,
            organizationMemberships: organizationMemberships,
            vehicles: vehicles,
            archivedVehicles: archivedVehicles,
            activeVehicleID: activeVehicleID,
            drivers: drivers,
            archivedDrivers: archivedDrivers,
            activeDriverID: activeDriverID,
            trips: trips,
            fuelEntries: fuelEntries,
            maintenanceRecords: maintenanceRecords,
            logs: logs,
            allowanceAdjustments: allowanceAdjustments
        )
    }

    var activeVehicle: VehicleProfile? {
        guard let activeVehicleID else {
            return nil
        }

        return availableVehicles.first { $0.id == activeVehicleID }
    }

    var activeDriver: DriverProfile? {
        guard let activeDriverID else {
            return nil
        }

        return availableDrivers.first { $0.id == activeDriverID }
    }

    var isReadyToDrive: Bool {
        activeVehicle != nil && activeDriver != nil
    }

    var currentOrganization: OrganizationProfile? {
        guard let activeOrganizationID else {
            return nil
        }

        return organizations.first { $0.id == activeOrganizationID }
    }

    var currentOrganizationMembers: [OrganizationMembership] {
        guard let activeOrganizationID else {
            return []
        }

        return organizationMemberships.filter { $0.organizationID == activeOrganizationID }
    }

    var currentUserOrganizationMembership: OrganizationMembership? {
        let normalizedEmail = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else {
            return nil
        }

        return currentOrganizationMembers.first {
            $0.normalizedEmailAddress == normalizedEmail && $0.status != .removed
        }
    }

    var isCurrentUserAccountManager: Bool {
        currentUserOrganizationMembership?.role == .accountManager
    }

    var isBusinessAccountActive: Bool {
        guard let organization = currentOrganization,
              let membership = currentUserOrganizationMembership,
              membership.isActive else {
            return false
        }

        return organization.hasActiveBilling
    }

    var availableVehicles: [VehicleProfile] {
        guard let membership = currentUserOrganizationMembership, membership.role == .employee else {
            return vehicles
        }

        let allowedVehicleIDs = Set(membership.assignedVehicleIDs)
        return vehicles.filter { allowedVehicleIDs.contains($0.id) }
    }

    var availableDrivers: [DriverProfile] {
        guard let membership = currentUserOrganizationMembership else {
            return drivers
        }

        if membership.role == .accountManager {
            return drivers
        }

        guard let assignedDriverID = membership.assignedDriverID else {
            return []
        }

        return drivers.filter { $0.id == assignedDriverID }
    }

    var canCurrentUserManageVehicles: Bool {
        currentUserOrganizationMembership?.hasPermission(.manageVehicles) ?? true
    }

    var canCurrentUserManageDrivers: Bool {
        currentUserOrganizationMembership?.hasPermission(.manageDrivers) ?? true
    }

    var canCurrentUserManageMembers: Bool {
        currentUserOrganizationMembership?.hasPermission(.manageMembers) ?? true
    }

    var canCurrentUserDeleteTrips: Bool {
        currentUserOrganizationMembership?.hasPermission(.deleteTrips) ?? true
    }

    var canCurrentUserDeleteFuelEntries: Bool {
        currentUserOrganizationMembership?.hasPermission(.deleteFuelEntries) ?? true
    }

    var canCurrentUserDeleteMaintenanceRecords: Bool {
        currentUserOrganizationMembership?.hasPermission(.deleteMaintenanceRecords) ?? true
    }

    var canCurrentUserExportLogs: Bool {
        currentUserOrganizationMembership?.hasPermission(.exportLogs) ?? true
    }

    var canCurrentUserViewLogs: Bool {
        currentUserOrganizationMembership?.hasPermission(.viewLogs) ?? true
    }

    var canModifyDemoData: Bool {
        !isDemoModeEnabled
    }

    var canAddMoreTrips: Bool {
        !isDemoModeEnabled || trips.count < Self.demoTripLimit
    }

    var canAddMoreFuelEntries: Bool {
        !isDemoModeEnabled || fuelEntries.count < Self.demoFuelEntryLimit
    }

    var canAddMoreMaintenanceRecords: Bool {
        !isDemoModeEnabled || maintenanceRecords.count < Self.demoMaintenanceRecordLimit
    }

    var demoTripsRemaining: Int {
        max(Self.demoTripLimit - trips.count, 0)
    }

    var demoFuelEntriesRemaining: Int {
        max(Self.demoFuelEntryLimit - fuelEntries.count, 0)
    }

    var demoMaintenanceRecordsRemaining: Int {
        max(Self.demoMaintenanceRecordLimit - maintenanceRecords.count, 0)
    }

    var demoModeSummary: String {
        "Demo Mode • Trips \(trips.count)/\(Self.demoTripLimit) • Fuel \(fuelEntries.count)/\(Self.demoFuelEntryLimit) • Maintenance \(maintenanceRecords.count)/\(Self.demoMaintenanceRecordLimit)"
    }

    func trip(for id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    func vehicle(for id: UUID?) -> VehicleProfile? {
        guard let id else { return nil }
        return vehicles.first { $0.id == id } ?? archivedVehicles.first { $0.id == id }
    }

    func driver(for id: UUID?) -> DriverProfile? {
        guard let id else { return nil }
        return drivers.first { $0.id == id } ?? archivedDrivers.first { $0.id == id }
    }

    func currentOdometerReading(for vehicleID: UUID?, activeTripDistanceMeters: Double = 0) -> Double {
        guard let vehicleID, let vehicle = vehicle(for: vehicleID) else {
            return 0
        }

        let latestRecordedOdometer = max(
            latestTrip(for: vehicle.id)?.odometerEnd ?? vehicle.startingOdometerReading,
            vehicle.startingOdometerReading
        )
        return latestRecordedOdometer + unitSystem.convertedDistance(for: activeTripDistanceMeters)
    }

    func currentOdometerReading(activeTripDistanceMeters: Double) -> Double {
        currentOdometerReading(for: activeVehicleID, activeTripDistanceMeters: activeTripDistanceMeters)
    }

    func currentBaseOdometerReading() -> Double {
        currentOdometerReading(activeTripDistanceMeters: 0)
    }

    func tripsForActiveVehicle() -> [Trip] {
        guard let activeVehicleID else {
            return []
        }

        return trips.filter { $0.vehicleID == activeVehicleID }
    }

    func fuelEntriesForActiveVehicle() -> [FuelEntry] {
        guard let activeVehicleID else {
            return []
        }

        return fuelEntries.filter { $0.vehicleID == activeVehicleID }
    }

    func maintenanceRecordsForActiveVehicle() -> [MaintenanceRecord] {
        guard let activeVehicleID else {
            return []
        }

        return maintenanceRecords.filter { $0.vehicleID == activeVehicleID }
    }

    func repairHistoricalTripAddressesIfNeeded() async -> Bool {
        var didChangeTrips = false

        for index in trips.indices {
            var trip = trips[index]
            var didUpdateTrip = false

            if shouldRepairAddress(trip.startAddress),
               let startPoint = trip.routePoints.first,
               let resolvedStartAddress = await reverseGeocodedAddress(for: startPoint.coordinate) {
                trip.startAddress = resolvedStartAddress
                didUpdateTrip = true
            }

            if shouldRepairAddress(trip.endAddress),
               let endPoint = trip.routePoints.last,
               let resolvedEndAddress = await reverseGeocodedAddress(for: endPoint.coordinate) {
                trip.endAddress = resolvedEndAddress
                didUpdateTrip = true
            }

            guard didUpdateTrip else {
                continue
            }

            trips[index] = trip
            didChangeTrips = true
        }

        if didChangeTrips {
            sortTripsDescending()
            addLog("Updated historical trip addresses from recorded route data")
        }

        return didChangeTrips
    }

    func repairRecentTripAddressesIfNeeded(limit: Int = 25) async -> Bool {
        guard !trips.isEmpty else {
            return false
        }

        var didChangeTrips = false
        let recentCount = min(max(limit, 0), trips.count)
        guard recentCount > 0 else {
            return false
        }

        for index in 0..<recentCount {
            var trip = trips[index]
            var didUpdateTrip = false

            if shouldRepairAddress(trip.startAddress),
               let startPoint = trip.routePoints.first,
               let resolvedStartAddress = await reverseGeocodedAddress(for: startPoint.coordinate) {
                trip.startAddress = resolvedStartAddress
                didUpdateTrip = true
            }

            if shouldRepairAddress(trip.endAddress),
               let endPoint = trip.routePoints.last,
               let resolvedEndAddress = await reverseGeocodedAddress(for: endPoint.coordinate) {
                trip.endAddress = resolvedEndAddress
                didUpdateTrip = true
            }

            guard didUpdateTrip else {
                continue
            }

            trips[index] = trip
            didChangeTrips = true
        }

        if didChangeTrips {
            sortTripsDescending()
            addLog("Updated recent trip addresses from recorded route data")
        }

        return didChangeTrips
    }

    var totalFuelSpend: Double {
        fuelEntries.reduce(0) { $0 + $1.totalCost }
    }

    var averageFuelVolumeText: String {
        guard !fuelEntries.isEmpty else {
            return fuelVolumeString(for: 0)
        }

        let average = fuelEntries.reduce(0) { $0 + $1.volume } / Double(fuelEntries.count)
        return fuelVolumeString(for: average)
    }

    var currentTaxYearFuelSpend: Double {
        fuelEntries(in: currentTaxYearInterval).reduce(0) { $0 + $1.totalCost }
    }

    var currentTaxYearFuelSpendForActiveVehicle: Double {
        guard let activeVehicleID else {
            return 0
        }

        return fuelEntries
            .filter { $0.vehicleID == activeVehicleID && currentTaxYearInterval.contains($0.date) }
            .reduce(0) { $0 + $1.totalCost }
    }

    var currentTaxYearMaintenanceSpend: Double {
        maintenanceRecords(in: currentTaxYearInterval).reduce(0) { $0 + $1.totalCost }
    }

    var currentTaxYearMaintenanceSpendForActiveVehicle: Double {
        guard let activeVehicleID else {
            return 0
        }

        return maintenanceRecords
            .filter { $0.vehicleID == activeVehicleID && currentTaxYearInterval.contains($0.date) }
            .reduce(0) { $0 + $1.totalCost }
    }

    var monthlyAverageFuelEconomyText: String {
        monthlyAverageFuelEconomyText(for: fuelEntries)
    }

    var monthlyAverageFuelEconomyTextForActiveVehicle: String {
        monthlyAverageFuelEconomyText(for: fuelEntriesForActiveVehicle())
    }

    private func monthlyAverageFuelEconomyText(for entries: [FuelEntry]) -> String {
        guard entries.count >= 2 else {
            return formattedFuelEconomy(distance: 0, liters: 0)
        }

        var monthlyTotals: [Date: (distance: Double, volume: Double)] = [:]
        let entriesByVehicle = Dictionary(grouping: entries, by: \.vehicleID)

        for vehicleEntries in entriesByVehicle.values {
            let sortedEntries = vehicleEntries.sorted {
                if $0.odometer == $1.odometer {
                    if $0.date == $1.date {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.date < $1.date
                }
                return $0.odometer < $1.odometer
            }

            for index in sortedEntries.indices.dropFirst() {
                let current = sortedEntries[index]
                guard currentTaxYearInterval.contains(current.date) else {
                    continue
                }

                let previous = sortedEntries[index - 1]
                let distance = max(current.odometer - previous.odometer, 0)
                guard distance > 0, current.volume > 0 else {
                    continue
                }

                let components = calendar.dateComponents([.year, .month], from: current.date)
                guard let monthStart = calendar.date(from: components) else {
                    continue
                }

                var monthTotals = monthlyTotals[monthStart, default: (0, 0)]
                monthTotals.distance += distance
                monthTotals.volume += current.volume
                monthlyTotals[monthStart] = monthTotals
            }
        }

        let monthlyEfficiencies = monthlyTotals.values.compactMap { totals -> Double? in
            let totalDistance = totals.distance
            let totalVolume = totals.volume
            guard totalDistance > 0, totalVolume > 0 else {
                return nil
            }

            return totalDistance / totalVolume
        }

        guard !monthlyEfficiencies.isEmpty else {
            return formattedFuelEconomy(distance: 0, liters: 0)
        }

        let averageEfficiency = monthlyEfficiencies.reduce(0, +) / Double(monthlyEfficiencies.count)
        let referenceLiters = unitSystem == .miles ? 3.785_411_784 : 1
        return formattedFuelEconomy(distance: averageEfficiency * referenceLiters, liters: referenceLiters)
    }

    func fuelEconomyText(for entry: FuelEntry) -> String? {
        let comparableEntries = fuelEntries
            .filter { $0.vehicleID == entry.vehicleID }
            .sorted {
                if $0.odometer == $1.odometer {
                    if $0.date == $1.date {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.date < $1.date
                }
                return $0.odometer < $1.odometer
            }

        guard let entryIndex = comparableEntries.firstIndex(where: { $0.id == entry.id }), entryIndex > 0 else {
            return nil
        }

        let previousEntry = comparableEntries[entryIndex - 1]
        let distance = max(entry.odometer - previousEntry.odometer, 0)
        guard distance > 0, entry.volume > 0 else {
            return nil
        }

        return formattedFuelEconomy(distance: distance, liters: entry.volume)
    }

    var currentTaxYearLabel: String {
        let startYear = calendar.component(.year, from: currentTaxYearInterval.start)
        let endYear = calendar.component(.year, from: currentTaxYearInterval.end.addingTimeInterval(-1))

        switch selectedCountry {
        case .southAfrica, .australia, .newZealand:
            return "Tax Year \(startYear)/\(String(endYear).suffix(2))"
        case .uk:
            return "Tax Year \(formattedDate(currentTaxYearInterval.start)) - \(formattedDate(currentTaxYearInterval.end.addingTimeInterval(-1)))"
        case .canada, .usa, .mexico, .other:
            return "Tax Year \(startYear)"
        }
    }

    func currencyString(for amount: Double) -> String {
        amount.formatted(.currency(code: preferredCurrency.rawValue))
    }

    func displayedFuelVolume(for liters: Double) -> Double {
        fuelVolumeUnit.displayedVolume(for: liters)
    }

    func liters(fromDisplayedFuelVolume displayedVolume: Double) -> Double {
        fuelVolumeUnit.liters(forDisplayedVolume: displayedVolume)
    }

    func fuelVolumeString(for liters: Double, fractionDigits: Int = 1) -> String {
        let displayedVolume = displayedFuelVolume(for: liters)
        return "\(displayedVolume.formatted(.number.precision(.fractionLength(fractionDigits)))) \(fuelVolumeUnit.symbol)"
    }

    func allowanceBalanceSummary(for vehicleID: UUID?) -> AllowanceBalanceSummary? {
        guard
            let vehicleID,
            let vehicle = vehicle(for: vehicleID),
            let allowancePlan = vehicle.allowancePlan
        else {
            return nil
        }

        let taxYearInterval = currentTaxYearInterval
        let interval = DateInterval(start: taxYearInterval.start, end: Date.now.addingTimeInterval(1))
        let receivedAllowance = recurringTotal(
            amount: allowancePlan.amount,
            schedule: allowancePlan.schedule,
            in: interval
        )
        let manualAdjustments = allowanceAdjustments
            .filter { $0.vehicleID == vehicleID && interval.contains($0.date) }
            .reduce(0) { $0 + $1.amount }
        let scheduledExpenses = recurringVehicleExpenseTotal(for: vehicle, in: interval)
        let fuelSpend = fuelEntries
            .filter { $0.vehicleID == vehicleID && interval.contains($0.date) }
            .reduce(0) { $0 + $1.totalCost }
        let maintenanceSpend = maintenanceRecords
            .filter { $0.vehicleID == vehicleID && interval.contains($0.date) }
            .reduce(0) { $0 + $1.totalCost }

        return AllowanceBalanceSummary(
            receivedAllowance: receivedAllowance,
            manualAdjustments: manualAdjustments,
            scheduledExpenses: scheduledExpenses,
            fuelSpend: fuelSpend,
            maintenanceSpend: maintenanceSpend
        )
    }

    func taxYearStatusSummary(vehicleID: UUID?) -> TaxYearStatusSummary {
        let tripsInTaxYear = trips.filter { trip in
            currentTaxYearInterval.contains(trip.date) && (vehicleID == nil || trip.vehicleID == vehicleID)
        }
        let fuelInTaxYear = fuelEntries.filter { entry in
            currentTaxYearInterval.contains(entry.date) && (vehicleID == nil || entry.vehicleID == vehicleID)
        }
        let maintenanceInTaxYear = maintenanceRecords.filter { record in
            currentTaxYearInterval.contains(record.date) && (vehicleID == nil || record.vehicleID == vehicleID)
        }

        let businessTrips = tripsInTaxYear.filter { $0.type == .business }
        let personalTrips = tripsInTaxYear.filter { $0.type == .personal }
        let businessDistance = businessTrips.reduce(0) { $0 + $1.distanceMeters }
        let personalDistance = personalTrips.reduce(0) { $0 + $1.distanceMeters }
        let fuelSpend = fuelInTaxYear.reduce(0) { $0 + $1.totalCost }
        let maintenanceSpend = maintenanceInTaxYear.reduce(0) { $0 + $1.totalCost }

        return TaxYearStatusSummary(
            totalTrips: tripsInTaxYear.count,
            totalBusinessTrips: businessTrips.count,
            totalPersonalTrips: personalTrips.count,
            totalBusinessDistanceMeters: businessDistance,
            totalPersonalDistanceMeters: personalDistance,
            totalCombinedDistanceMeters: businessDistance + personalDistance,
            totalFuelSpend: fuelSpend,
            totalMaintenanceSpend: maintenanceSpend,
            totalCombinedSpend: fuelSpend + maintenanceSpend
        )
    }

    func applyCountryPreferences(_ country: SupportedCountry) {
        selectedCountry = country
        unitSystem = country.defaultDistanceUnit
        preferredCurrency = country.defaultCurrency
        fuelVolumeUnit = country.defaultFuelVolumeUnit
        fuelEconomyFormat = .defaultFormat(for: unitSystem)
    }

    func formattedFuelEconomy(distance: Double, liters: Double) -> String {
        unitSystem.fuelEconomyString(
            distance: distance,
            liters: liters,
            format: fuelEconomyFormat.compatibleFormat(for: unitSystem)
        )
    }

    func addTrip(_ trip: Trip) {
        guard canAddMoreTrips else {
            addLog("Demo mode trip limit reached")
            return
        }
        let preparedTrip = prepareTripForInsertion(trip)
        trips.insert(preparedTrip, at: 0)
        sortTripsDescending()
        reconcileTripChain(for: preparedTrip.vehicleID, anchorTripID: preparedTrip.id, preferredStart: preparedTrip.odometerStart, preferredEnd: preparedTrip.odometerEnd)
        addLog(preparedTrip.manuallyEntered ? "Manual trip added: \(preparedTrip.name)" : "Completed trip: \(preparedTrip.name)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    private func shouldRepairAddress(_ address: String) -> Bool {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAddress.isEmpty
            || trimmedAddress.caseInsensitiveCompare(Constants.unknownLocationLabel) == .orderedSame
            || isCoordinatePlaceholderAddress(trimmedAddress)
    }

    private func isCoordinatePlaceholderAddress(_ address: String) -> Bool {
        let components = address
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard components.count == 2,
              let latitude = Double(components[0]),
              let longitude = Double(components[1]) else {
            return false
        }

        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    private func reverseGeocodedAddress(for coordinate: CLLocationCoordinate2D) async -> String? {
        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if #available(iOS 26, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    return nil
                }

                if let mapItem = try await request.mapItems.first {
                    if let fullAddress = mapItem.address?.fullAddress
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !fullAddress.isEmpty {
                        return formattedPOIAddress(name: mapItem.name, address: fullAddress)
                    }

                    if let shortAddress = mapItem.address?.shortAddress?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !shortAddress.isEmpty {
                        return formattedPOIAddress(name: mapItem.name, address: shortAddress)
                    }

                    if let fullAddress = mapItem.addressRepresentations?
                        .fullAddress(includingRegion: true, singleLine: true)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !fullAddress.isEmpty {
                        return formattedPOIAddress(name: mapItem.name, address: fullAddress)
                    }

                    let parts = [
                        mapItem.name,
                        mapItem.addressRepresentations?.cityWithContext(.full),
                        mapItem.addressRepresentations?.regionName
                    ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                    if !parts.isEmpty {
                        return parts.joined(separator: ", ")
                    }
                }
            } else {
                let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
                if let placemark {
                    let streetLine = [
                        placemark.subThoroughfare,
                        placemark.thoroughfare
                    ]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                    let parts = [
                        streetLine.isEmpty ? placemark.name : streetLine,
                        placemark.locality,
                        placemark.administrativeArea,
                        placemark.postalCode,
                        placemark.country
                    ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }

                    if !parts.isEmpty {
                        let address = parts.joined(separator: ", ")
                        return formattedPOIAddress(name: placemark.name, address: address)
                    }
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    private func formattedPOIAddress(name: String?, address: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            return address
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else {
            return trimmedAddress
        }

        let normalizedName = trimmedName.lowercased()
        let normalizedAddress = trimmedAddress.lowercased()
        if normalizedAddress == normalizedName || normalizedAddress.hasPrefix(normalizedName + ",") || normalizedAddress.hasPrefix(normalizedName + " -") {
            return trimmedAddress
        }

        return "\(trimmedName) - \(trimmedAddress)"
    }

    func updateTrip(_ updatedTrip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == updatedTrip.id }) else {
            return
        }

        let originalTrip = trips[index]
        let preparedTrip = prepareTripForUpdate(updatedTrip)
        trips[index] = preparedTrip
        sortTripsDescending()

        let affectedVehicleIDs = Set([originalTrip.vehicleID, preparedTrip.vehicleID].compactMap { $0 })
        for vehicleID in affectedVehicleIDs {
            if vehicleID == preparedTrip.vehicleID {
                reconcileTripChain(
                    for: vehicleID,
                    anchorTripID: preparedTrip.id,
                    preferredStart: preparedTrip.odometerStart,
                    preferredEnd: preparedTrip.odometerEnd
                )
            } else {
                reconcileTripChain(for: vehicleID, anchorTripID: nil, preferredStart: nil, preferredEnd: nil)
            }
        }

        addLog("Updated trip: \(preparedTrip.name)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func deleteTrip(id: UUID) {
        guard canModifyDemoData else {
            addLog("Demo mode does not allow deleting trips")
            return
        }
        guard canCurrentUserDeleteTrips else {
            addLog("Current user is not allowed to delete trips")
            return
        }
        guard let index = trips.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removedTrip = trips.remove(at: index)
        if let vehicleID = removedTrip.vehicleID {
            reconcileTripChain(for: vehicleID, anchorTripID: nil, preferredStart: nil, preferredEnd: nil)
        }
        addLog("Deleted trip: \(removedTrip.name)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func addFuelEntry(_ entry: FuelEntry) {
        guard canAddMoreFuelEntries else {
            addLog("Demo mode fuel-up limit reached")
            return
        }
        let preparedEntry = prepareFuelEntry(entry)
        fuelEntries.insert(preparedEntry, at: 0)
        addLog("Fuel entry added for \(preparedEntry.station)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func updateFuelEntry(_ updatedEntry: FuelEntry) {
        guard let index = fuelEntries.firstIndex(where: { $0.id == updatedEntry.id }) else {
            return
        }

        let preparedEntry = prepareFuelEntry(updatedEntry)
        fuelEntries[index] = preparedEntry
        fuelEntries.sort { $0.date > $1.date }
        addLog("Fuel entry updated for \(preparedEntry.station)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func deleteFuelEntry(id: UUID) {
        guard canModifyDemoData else {
            addLog("Demo mode does not allow deleting fuel entries")
            return
        }
        guard canCurrentUserDeleteFuelEntries else {
            addLog("Current user is not allowed to delete fuel entries")
            return
        }
        guard let index = fuelEntries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removedEntry = fuelEntries.remove(at: index)
        addLog("Fuel entry deleted for \(removedEntry.station)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func addMaintenanceRecord(_ record: MaintenanceRecord) {
        guard canAddMoreMaintenanceRecords else {
            addLog("Demo mode maintenance limit reached")
            return
        }
        let preparedRecord = prepareMaintenanceRecord(record)
        maintenanceRecords.insert(preparedRecord, at: 0)
        maintenanceRecords.sort { $0.date > $1.date }
        addLog("Maintenance record added: \(preparedRecord.title)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func updateMaintenanceRecord(_ updatedRecord: MaintenanceRecord) {
        guard let index = maintenanceRecords.firstIndex(where: { $0.id == updatedRecord.id }) else {
            return
        }

        let preparedRecord = prepareMaintenanceRecord(updatedRecord)
        maintenanceRecords[index] = preparedRecord
        maintenanceRecords.sort { $0.date > $1.date }
        addLog("Maintenance record updated: \(preparedRecord.title)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func deleteMaintenanceRecord(id: UUID) {
        guard canModifyDemoData else {
            addLog("Demo mode does not allow deleting maintenance records")
            return
        }
        guard canCurrentUserDeleteMaintenanceRecords else {
            addLog("Current user is not allowed to delete maintenance records")
            return
        }
        guard let index = maintenanceRecords.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removedRecord = maintenanceRecords.remove(at: index)
        addLog("Maintenance record deleted: \(removedRecord.title)")
        SharedAppModel.shared.persistAndSyncNowIfPossible()
    }

    func nextMaintenanceReminder(currentOdometer: Double) -> MaintenanceRecord? {
        activeMaintenanceReminders(currentOdometer: currentOdometer).first
    }

    func activeMaintenanceReminders(currentOdometer: Double) -> [MaintenanceRecord] {
        maintenanceRecords
            .filter { $0.reminderEnabled && $0.nextServiceOdometer != nil }
            .sorted {
                let lhsDistance = $0.distanceRemaining(from: currentOdometer) ?? .greatestFiniteMagnitude
                let rhsDistance = $1.distanceRemaining(from: currentOdometer) ?? .greatestFiniteMagnitude

                if lhsDistance == rhsDistance {
                    return ($0.nextServiceDate ?? .distantFuture) < ($1.nextServiceDate ?? .distantFuture)
                }

                return lhsDistance < rhsDistance
            }
    }

    func clearRecordedData() {
        organizations = []
        activeOrganizationID = nil
        organizationMemberships = []
        vehicles = []
        archivedVehicles = []
        activeVehicleID = nil
        drivers = []
        archivedDrivers = []
        activeDriverID = nil
        trips = []
        fuelEntries = []
        maintenanceRecords = []
        logs = []
        allowanceAdjustments = []
    }

    func markMaintenanceReminderSent(recordID: UUID, threshold: MaintenanceReminderThreshold) {
        guard let index = maintenanceRecords.firstIndex(where: { $0.id == recordID }) else {
            return
        }

        maintenanceRecords[index].markReminderSent(threshold)
    }

    func addVehicle(_ vehicle: VehicleProfile) {
        vehicles.append(vehicle)

        if activeVehicleID == nil || !availableVehicles.contains(where: { $0.id == activeVehicleID }) {
            activeVehicleID = vehicle.id
        }

        addLog("Vehicle added: \(vehicle.displayName)")
        NotificationCenter.default.post(name: .meerkatVehicleProfilesDidChange, object: nil)
    }

    func updateVehicle(_ updatedVehicle: VehicleProfile) {
        guard let index = vehicles.firstIndex(where: { $0.id == updatedVehicle.id }) else {
            return
        }

        let existingVehicle = vehicles[index]
        var preparedVehicle = updatedVehicle
        preparedVehicle.archivedAt = existingVehicle.archivedAt
        preparedVehicle.archiveReason = existingVehicle.archiveReason
        vehicles[index] = preparedVehicle
        reconcileTripChain(for: preparedVehicle.id, anchorTripID: nil, preferredStart: nil, preferredEnd: nil)
        syncAssociatedVehicleData(with: preparedVehicle)
        addLog("Vehicle updated: \(preparedVehicle.displayName)")
        NotificationCenter.default.post(name: .meerkatVehicleProfilesDidChange, object: nil)
    }

    func archiveVehicle(id: UUID, reason: String) {
        guard canModifyDemoData else {
            addLog("Demo mode does not allow deleting vehicles")
            return
        }
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else {
            return
        }

        var archivedVehicle = vehicles.remove(at: index)
        archivedVehicle.archivedAt = .now
        archivedVehicle.archiveReason = reason
        upsertArchivedVehicle(archivedVehicle)

        if activeVehicleID == id {
            activeVehicleID = vehicles.first?.id
        }

        syncAssociatedVehicleData(with: archivedVehicle)
        addLog("Vehicle archived: \(archivedVehicle.displayName) (\(reason))")
        NotificationCenter.default.post(name: .meerkatVehicleProfilesDidChange, object: nil)
    }

    func addDriver(_ driver: DriverProfile) {
        drivers.append(driver)

        if activeDriverID == nil || !availableDrivers.contains(where: { $0.id == activeDriverID }) {
            activeDriverID = driver.id
        }

        addLog("Driver added: \(driver.name)")
    }

    func updateDriver(_ updatedDriver: DriverProfile) {
        guard let index = drivers.firstIndex(where: { $0.id == updatedDriver.id }) else {
            return
        }

        let existingDriver = drivers[index]
        var preparedDriver = updatedDriver
        preparedDriver.archivedAt = existingDriver.archivedAt
        drivers[index] = preparedDriver
        syncTripDriverData(with: preparedDriver)
        addLog("Driver updated: \(preparedDriver.name)")
    }

    func archiveDriver(id: UUID) {
        guard canModifyDemoData else {
            addLog("Demo mode does not allow deleting drivers")
            return
        }
        guard let index = drivers.firstIndex(where: { $0.id == id }) else {
            return
        }

        var archivedDriver = drivers.remove(at: index)
        archivedDriver.archivedAt = .now
        upsertArchivedDriver(archivedDriver)
        syncTripDriverData(with: archivedDriver)

        if activeDriverID == id {
            activeDriverID = drivers.first?.id
        }

        addLog("Driver archived: \(archivedDriver.name)")
    }

    func deleteDriver(id: UUID) {
        guard canModifyDemoData else {
            addLog("Demo mode does not allow deleting drivers")
            return
        }
        if let index = drivers.firstIndex(where: { $0.id == id }) {
            let deletedDriver = drivers.remove(at: index)
            if activeDriverID == id {
                activeDriverID = drivers.first?.id
            }
            addLog("Driver deleted: \(deletedDriver.name)")
            return
        }

        if let index = archivedDrivers.firstIndex(where: { $0.id == id }) {
            let deletedDriver = archivedDrivers.remove(at: index)
            addLog("Archived driver deleted: \(deletedDriver.name)")
        }
    }

    func vehicleAssociationCount(for vehicleID: UUID) -> Int {
        trips.filter { $0.vehicleID == vehicleID }.count +
        fuelEntries.filter { $0.vehicleID == vehicleID }.count +
        maintenanceRecords.filter { $0.vehicleID == vehicleID }.count
    }

    func driverAssociationCount(for driverID: UUID) -> Int {
        trips.filter { $0.driverID == driverID }.count
    }

    func addLog(_ title: String) {
        logs.insert(LogEntry(title: title, date: .now), at: 0)
    }

    func addAllowanceAdjustment(vehicleID: UUID, amount: Double, reason: String) {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount != 0, !trimmedReason.isEmpty else {
            return
        }

        let adjustment = AllowanceAdjustment(
            vehicleID: vehicleID,
            amount: amount,
            reason: trimmedReason,
            date: .now
        )
        allowanceAdjustments.insert(adjustment, at: 0)

        let direction = amount >= 0 ? "added to" : "removed from"
        let absoluteAmount = currencyString(for: abs(amount))
        let vehicleName = vehicle(for: vehicleID)?.displayName ?? "Unknown vehicle"
        addLog("Allowance \(direction) \(vehicleName): \(absoluteAmount) (\(trimmedReason))")
    }

    func entriesForLogExport(vehicleID: UUID?, driverID: UUID?, dateRange: ClosedRange<Date>) -> LogExportPayload {
        let exportInterval = exportInterval(for: dateRange)
        let drivenVehicleIDsForSelectedDriver = Set(
            trips.filter { trip in
                dateRange.contains(trip.date) && (driverID == nil || trip.driverID == driverID)
            }.compactMap(\.vehicleID)
        )

        let filteredTrips = trips.filter { trip in
            dateRange.contains(trip.date) &&
                (vehicleID == nil || trip.vehicleID == vehicleID) &&
                (driverID == nil || trip.driverID == driverID)
        }

        let filteredFuelEntries = fuelEntries.filter { entry in
            guard dateRange.contains(entry.date) else {
                return false
            }
            if let vehicleID {
                return entry.vehicleID == vehicleID
            }
            if driverID != nil {
                return entry.vehicleID.map { drivenVehicleIDsForSelectedDriver.contains($0) } ?? false
            }
            return true
        }

        let filteredMaintenanceRecords = maintenanceRecords.filter { record in
            guard dateRange.contains(record.date) else {
                return false
            }
            if let vehicleID {
                return record.vehicleID == vehicleID
            }
            if driverID != nil {
                return record.vehicleID.map { drivenVehicleIDsForSelectedDriver.contains($0) } ?? false
            }
            return true
        }

        let vehicleDescriptions = Dictionary(uniqueKeysWithValues: allVehicles.map { vehicle in
            let description = [vehicle.make, vehicle.model]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return (vehicle.id, description.isEmpty ? vehicle.displayName : description)
        })

        let selectedVehicleDescription: String = {
            guard let vehicleID, let vehicle = vehicle(for: vehicleID) else {
                return "Multiple vehicles"
            }

            let description = [vehicle.make, vehicle.model]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return description.isEmpty ? vehicle.displayName : description
        }()

        let taxYearCoverage = taxYearCoverageLabels(for: exportInterval)

        return LogExportPayload(
            country: selectedCountry,
            userName: userName,
            emailAddress: emailAddress,
            vehicleDescription: selectedVehicleDescription,
            preferredCurrency: preferredCurrency,
            distanceUnit: unitSystem,
            exportDateRange: dateRange,
            taxYearInterval: taxYearInterval(for: dateRange.lowerBound),
            taxYearLabel: taxYearCoverage.joined(separator: " | "),
            taxAuthorityName: selectedCountry.taxAuthorityName,
            taxYearCoverage: taxYearCoverage,
            complianceNotes: selectedCountry.taxExportGuidance,
            vehicleDescriptions: vehicleDescriptions,
            trips: filteredTrips,
            fuelEntries: filteredFuelEntries,
            maintenanceRecords: filteredMaintenanceRecords
        )
    }

    func entriesForFinancialLogExport(vehicleID: UUID?, driverID: UUID?, dateRange: ClosedRange<Date>) -> FinancialLogExportPayload {
        let exportInterval = exportInterval(for: dateRange)
        let drivenVehicleIDsForSelectedDriver = Set(
            trips.filter { trip in
                dateRange.contains(trip.date) && (driverID == nil || trip.driverID == driverID)
            }.compactMap(\.vehicleID)
        )

        let vehiclesForExport: [VehicleProfile] = {
            if let vehicleID, let vehicle = vehicle(for: vehicleID) {
                return [vehicle]
            }
            if driverID != nil {
                return allVehicles.filter { drivenVehicleIDsForSelectedDriver.contains($0.id) }
            }

            return allVehicles
        }()
        let taxYearCoverage = taxYearCoverageLabels(for: exportInterval)
        let selectedVehicleDescription = vehicleID.flatMap { vehicle(for: $0)?.displayName } ?? "Multiple vehicles"
        let financialEntries = buildFinancialLogEntries(vehicles: vehiclesForExport, interval: exportInterval)
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.description < rhs.description
                }

                return lhs.date < rhs.date
            }

        return FinancialLogExportPayload(
            country: selectedCountry,
            userName: userName,
            emailAddress: emailAddress,
            vehicleDescription: selectedVehicleDescription,
            preferredCurrency: preferredCurrency,
            exportDateRange: dateRange,
            taxYearLabel: taxYearCoverage.joined(separator: " | "),
            taxAuthorityName: selectedCountry.taxAuthorityName,
            taxYearCoverage: taxYearCoverage,
            complianceNotes: selectedCountry.taxExportGuidance,
            entries: financialEntries
        )
    }

    func defaultLogDateRange() -> ClosedRange<Date> {
        let interval = currentTaxYearInterval
        return interval.start ... interval.end.addingTimeInterval(-1)
    }

    func importLogPayload(_ payload: LogImportPayload) {
        var vehicleIDMap: [UUID: UUID] = [:]
        for vehicle in payload.vehicles {
            if let existingVehicle = matchingVehicle(forImportedVehicle: vehicle) {
                vehicleIDMap[vehicle.id] = existingVehicle.id
                if vehicle.startingOdometerReading < existingVehicle.startingOdometerReading {
                    let updatedVehicle = VehicleProfile(
                        id: existingVehicle.id,
                        profileName: existingVehicle.profileName,
                        make: existingVehicle.make,
                        model: existingVehicle.model,
                        color: existingVehicle.color,
                        numberPlate: existingVehicle.numberPlate,
                        startingOdometerReading: vehicle.startingOdometerReading,
                        ownershipType: existingVehicle.ownershipType,
                        allowancePlan: existingVehicle.allowancePlan,
                        paymentPlan: existingVehicle.paymentPlan,
                        insurancePlan: existingVehicle.insurancePlan,
                        otherScheduledExpenses: existingVehicle.otherScheduledExpenses,
                        detectionProfile: existingVehicle.detectionProfile,
                        archivedAt: existingVehicle.archivedAt,
                        archiveReason: existingVehicle.archiveReason
                    )
                    upsertVehicle(updatedVehicle)
                }
            } else {
                upsertVehicle(vehicle)
                vehicleIDMap[vehicle.id] = vehicle.id
            }
        }

        var driverIDMap: [UUID: UUID] = [:]
        for driver in payload.drivers {
            if let existingDriver = matchingDriver(forImportedDriver: driver) {
                driverIDMap[driver.id] = existingDriver.id
            } else {
                upsertDriver(driver)
                driverIDMap[driver.id] = driver.id
            }
        }

        var affectedTripVehicleIDs: Set<UUID> = []
        var latestImportedTripVehicleID: UUID?
        var latestImportedTripDate: Date?
        for trip in payload.trips {
            var resolvedTrip = trip
            if let vehicleID = trip.vehicleID, let resolvedVehicleID = vehicleIDMap[vehicleID] {
                resolvedTrip.vehicleID = resolvedVehicleID
                resolvedTrip.vehicleProfileName = vehicle(for: resolvedVehicleID)?.displayName ?? resolvedTrip.vehicleProfileName
                affectedTripVehicleIDs.insert(resolvedVehicleID)
                if latestImportedTripDate == nil || trip.date > latestImportedTripDate ?? .distantPast {
                    latestImportedTripDate = trip.date
                    latestImportedTripVehicleID = resolvedVehicleID
                }
            }
            if let driverID = trip.driverID, let resolvedDriverID = driverIDMap[driverID] {
                resolvedTrip.driverID = resolvedDriverID
                resolvedTrip.driverName = drivers.first(where: { $0.id == resolvedDriverID })?.name ?? resolvedTrip.driverName
            }
            upsertTrip(resolvedTrip)
        }

        sortTripsDescending()
        for vehicleID in affectedTripVehicleIDs {
            reconcileTripChain(for: vehicleID, anchorTripID: nil, preferredStart: nil, preferredEnd: nil)
        }

        activeVehicleID = latestImportedTripVehicleID
            ?? payload.vehicles.compactMap { vehicleIDMap[$0.id] }.first
            ?? activeVehicleID

        for fuelEntry in payload.fuelEntries {
            var resolvedFuelEntry = fuelEntry
            if let vehicleID = fuelEntry.vehicleID, let resolvedVehicleID = vehicleIDMap[vehicleID] {
                resolvedFuelEntry.vehicleID = resolvedVehicleID
                resolvedFuelEntry.vehicleProfileName = vehicle(for: resolvedVehicleID)?.displayName ?? resolvedFuelEntry.vehicleProfileName
            }
            upsertFuelEntry(resolvedFuelEntry)
        }

        for maintenanceRecord in payload.maintenanceRecords {
            var resolvedMaintenanceRecord = maintenanceRecord
            if let vehicleID = maintenanceRecord.vehicleID, let resolvedVehicleID = vehicleIDMap[vehicleID] {
                resolvedMaintenanceRecord.vehicleID = resolvedVehicleID
                resolvedMaintenanceRecord.vehicleProfileName = vehicle(for: resolvedVehicleID)?.displayName ?? resolvedMaintenanceRecord.vehicleProfileName
            }
            upsertMaintenanceRecord(resolvedMaintenanceRecord)
        }

        sortTripsDescending()
        fuelEntries.sort { $0.date > $1.date }
        maintenanceRecords.sort { $0.date > $1.date }
        addLog("Imported log file with \(payload.trips.count) trips, \(payload.fuelEntries.count) fuel-ups, and \(payload.maintenanceRecords.count) maintenance items")
        NotificationCenter.default.post(name: .meerkatVehicleProfilesDidChange, object: nil)
    }

    func applyPersistenceSnapshot(_ snapshot: PersistenceSnapshot) {
        selectedCountry = snapshot.selectedCountry
        userName = snapshot.userName
        emailAddress = snapshot.emailAddress
        preferredCurrency = snapshot.preferredCurrency
        unitSystem = snapshot.unitSystem
        fuelVolumeUnit = snapshot.fuelVolumeUnit
        fuelEconomyFormat = snapshot.fuelEconomyFormat.compatibleFormat(for: snapshot.unitSystem)
        preventAutoLock = snapshot.preventAutoLock
        vehicleDetectionEnabled = snapshot.vehicleDetectionEnabled
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding
        hasAcceptedPrivacyPolicy = snapshot.hasAcceptedPrivacyPolicy
        hasAcceptedLegalNotice = snapshot.hasAcceptedLegalNotice
        accountSubscriptionType = snapshot.accountSubscriptionType
        businessProfile = snapshot.businessProfile
        organizations = snapshot.organizations
        activeOrganizationID = snapshot.activeOrganizationID
        organizationMemberships = snapshot.organizationMemberships
        vehicles = snapshot.vehicles
        archivedVehicles = snapshot.archivedVehicles
        activeVehicleID = snapshot.activeVehicleID
        drivers = snapshot.drivers
        archivedDrivers = snapshot.archivedDrivers
        activeDriverID = snapshot.activeDriverID
        trips = snapshot.trips
        fuelEntries = snapshot.fuelEntries
        maintenanceRecords = snapshot.maintenanceRecords
        logs = snapshot.logs
        allowanceAdjustments = snapshot.allowanceAdjustments
        refreshBusinessAccessState()
        sortTripsDescending()
        NotificationCenter.default.post(name: .meerkatVehicleProfilesDidChange, object: nil)
    }

    func upsertOrganization(_ organization: OrganizationProfile) {
        if let index = organizations.firstIndex(where: { $0.id == organization.id }) {
            organizations[index] = organization
        } else {
            organizations.append(organization)
        }

        if activeOrganizationID == nil {
            activeOrganizationID = organization.id
        }

        refreshBusinessAccessState()
    }

    func upsertOrganizationMembership(_ membership: OrganizationMembership) {
        if let index = organizationMemberships.firstIndex(where: { $0.id == membership.id }) {
            organizationMemberships[index] = membership
        } else {
            organizationMemberships.append(membership)
        }

        refreshBusinessAccessState()
    }

    func removeOrganizationMembership(id: UUID) {
        organizationMemberships.removeAll { $0.id == id }
        refreshBusinessAccessState()
    }

    func activateOrganization(_ organizationID: UUID?) {
        activeOrganizationID = organizationID
        refreshBusinessAccessState()
    }

    private func refreshBusinessAccessState() {
        if let activeOrganizationID,
           !organizations.contains(where: { $0.id == activeOrganizationID }) {
            self.activeOrganizationID = organizations.first?.id
        }

        let accessibleVehicleIDs = Set(availableVehicles.map(\.id))
        if let activeVehicleID, !accessibleVehicleIDs.contains(activeVehicleID) {
            self.activeVehicleID = availableVehicles.first?.id
        }

        let accessibleDriverIDs = Set(availableDrivers.map(\.id))
        if let activeDriverID, !accessibleDriverIDs.contains(activeDriverID) {
            self.activeDriverID = availableDrivers.first?.id
        }
    }

    private var calendar: Calendar {
        .current
    }

    private var allVehicles: [VehicleProfile] {
        vehicles + archivedVehicles
    }

    private var currentTaxYearInterval: DateInterval {
        taxYearInterval(for: Date.now)
    }

    private func exportInterval(for dateRange: ClosedRange<Date>) -> DateInterval {
        DateInterval(
            start: Calendar.current.startOfDay(for: dateRange.lowerBound),
            end: (Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: dateRange.upperBound) ?? dateRange.upperBound).addingTimeInterval(1)
        )
    }

    private func fuelEntries(in interval: DateInterval) -> [FuelEntry] {
        fuelEntries.filter { interval.contains($0.date) }
    }

    private func maintenanceRecords(in interval: DateInterval) -> [MaintenanceRecord] {
        maintenanceRecords.filter { interval.contains($0.date) }
    }

    private func taxYearInterval(for date: Date) -> DateInterval {
        let year = calendar.component(.year, from: date)

        switch selectedCountry {
        case .southAfrica:
            let marchFirst = makeDate(year: year, month: 3, day: 1)
            if date >= marchFirst {
                return DateInterval(start: marchFirst, end: makeDate(year: year + 1, month: 3, day: 1))
            } else {
                return DateInterval(start: makeDate(year: year - 1, month: 3, day: 1), end: marchFirst)
            }
        case .uk:
            let aprilSixth = makeDate(year: year, month: 4, day: 6)
            if date >= aprilSixth {
                return DateInterval(start: aprilSixth, end: makeDate(year: year + 1, month: 4, day: 6))
            } else {
                return DateInterval(start: makeDate(year: year - 1, month: 4, day: 6), end: aprilSixth)
            }
        case .australia:
            let julyFirst = makeDate(year: year, month: 7, day: 1)
            if date >= julyFirst {
                return DateInterval(start: julyFirst, end: makeDate(year: year + 1, month: 7, day: 1))
            } else {
                return DateInterval(start: makeDate(year: year - 1, month: 7, day: 1), end: julyFirst)
            }
        case .newZealand:
            let aprilFirst = makeDate(year: year, month: 4, day: 1)
            if date >= aprilFirst {
                return DateInterval(start: aprilFirst, end: makeDate(year: year + 1, month: 4, day: 1))
            } else {
                return DateInterval(start: makeDate(year: year - 1, month: 4, day: 1), end: aprilFirst)
            }
        case .canada, .usa, .mexico, .other:
            let januaryFirst = makeDate(year: year, month: 1, day: 1)
            return DateInterval(start: januaryFirst, end: makeDate(year: year + 1, month: 1, day: 1))
        }
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func taxYearLabel(for interval: DateInterval) -> String {
        let startYear = calendar.component(.year, from: interval.start)
        let endYear = calendar.component(.year, from: interval.end.addingTimeInterval(-1))

        switch selectedCountry {
        case .southAfrica, .australia, .newZealand:
            return "Tax Year \(startYear)/\(String(endYear).suffix(2))"
        case .uk:
            return "Tax Year \(formattedDate(interval.start)) - \(formattedDate(interval.end.addingTimeInterval(-1)))"
        case .canada, .usa, .mexico, .other:
            return "Tax Year \(startYear)"
        }
    }

    private func taxYearCoverageLabels(for interval: DateInterval) -> [String] {
        var labels: [String] = []
        var currentStart = interval.start

        while currentStart < interval.end {
            let taxInterval = taxYearInterval(for: currentStart)
            let label = taxYearLabel(for: taxInterval)
            if labels.last != label {
                labels.append(label)
            }

            if taxInterval.end >= interval.end {
                break
            }

            currentStart = taxInterval.end
        }

        return labels
    }

    private func recurringVehicleExpenseTotal(for vehicle: VehicleProfile, in interval: DateInterval) -> Double {
        var total = 0.0

        if let paymentPlan = vehicle.paymentPlan {
            total += recurringTotal(amount: paymentPlan.amount, schedule: paymentPlan.schedule, in: interval)
        }

        if let insurancePlan = vehicle.insurancePlan {
            total += recurringTotal(amount: insurancePlan.amount, schedule: insurancePlan.schedule, in: interval)
        }

        total += vehicle.otherScheduledExpenses.reduce(0) { partialResult, expense in
            partialResult + recurringTotal(amount: expense.amount, schedule: expense.schedule, in: interval)
        }

        return total
    }

    private func recurringTotal(amount: Double, schedule: VehicleRecurringSchedule, in interval: DateInterval) -> Double {
        Double(recurringOccurrences(for: schedule, in: interval)) * amount
    }

    private func recurringOccurrences(for schedule: VehicleRecurringSchedule, in interval: DateInterval) -> Int {
        recurringDates(for: schedule, in: interval).count
    }

    private func recurringDates(for schedule: VehicleRecurringSchedule, in interval: DateInterval) -> [Date] {
        switch schedule.frequency {
        case .weekly:
            return recurringDayBasedDates(stepInDays: 7, startDate: schedule.startDate, in: interval)
        case .biweekly:
            return recurringDayBasedDates(stepInDays: 14, startDate: schedule.startDate, in: interval)
        case .monthly:
            return recurringMonthlyDates(anchorDate: schedule.startDate, in: interval, includeLastDay: false)
        case .lastDayOfMonth:
            return recurringLastDayDates(anchorDate: schedule.startDate, in: interval)
        case .semimonthly:
            return recurringMonthlyDates(anchorDate: schedule.startDate, in: interval, includeLastDay: true)
        }
    }

    private func recurringDayBasedDates(stepInDays: Int, startDate: Date, in interval: DateInterval) -> [Date] {
        guard startDate < interval.end else {
            return []
        }

        var occurrence = startDate
        var dates: [Date] = []

        while occurrence < interval.end {
            if occurrence >= interval.start {
                dates.append(occurrence)
            }

            guard let nextOccurrence = calendar.date(byAdding: .day, value: stepInDays, to: occurrence) else {
                break
            }
            occurrence = nextOccurrence
        }

        return dates
    }

    private func recurringMonthlyDates(anchorDate: Date, in interval: DateInterval, includeLastDay: Bool) -> [Date] {
        guard anchorDate < interval.end else {
            return []
        }

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
        var currentMonth = monthStart
        var dates: [Date] = []

        while currentMonth < interval.end {
            let monthDate = monthlyOccurrenceDate(in: currentMonth, anchorDate: anchorDate)
            if monthDate >= anchorDate, interval.contains(monthDate) {
                dates.append(monthDate)
            }

            if includeLastDay, let lastDayDate = lastDayOfMonthDate(in: currentMonth, anchorDate: anchorDate) {
                if lastDayDate >= anchorDate, interval.contains(lastDayDate), !calendar.isDate(lastDayDate, inSameDayAs: monthDate) {
                    dates.append(lastDayDate)
                }
            }

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else {
                break
            }
            currentMonth = nextMonth
        }

        return dates.sorted()
    }

    private func recurringLastDayDates(anchorDate: Date, in interval: DateInterval) -> [Date] {
        guard anchorDate < interval.end else {
            return []
        }

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchorDate)) ?? anchorDate
        var currentMonth = monthStart
        var dates: [Date] = []

        while currentMonth < interval.end {
            if let lastDayDate = lastDayOfMonthDate(in: currentMonth, anchorDate: anchorDate),
               lastDayDate >= anchorDate,
               interval.contains(lastDayDate) {
                dates.append(lastDayDate)
            }

            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) else {
                break
            }
            currentMonth = nextMonth
        }

        return dates
    }

    private func businessUseFraction(for vehicleID: UUID?, in interval: DateInterval) -> Double? {
        guard let vehicleID else {
            return nil
        }

        let relevantTrips = trips.filter { $0.vehicleID == vehicleID && interval.contains($0.date) }
        let totalDistance = relevantTrips.reduce(0) { $0 + $1.distanceMeters }
        guard totalDistance > 0 else {
            return nil
        }

        let businessDistance = relevantTrips
            .filter { $0.type == .business }
            .reduce(0) { $0 + $1.distanceMeters }
        return businessDistance / totalDistance
    }

    private func buildFinancialLogEntries(vehicles: [VehicleProfile], interval: DateInterval) -> [FinancialLogEntry] {
        var entries: [FinancialLogEntry] = []
        let vehicleIDs = Set(vehicles.map(\.id))
        let occurredInterval = DateInterval(start: interval.start, end: min(interval.end, Date.now.addingTimeInterval(1)))

        for vehicle in vehicles {
            let vehicleName = vehicle.displayName
            let businessUseFraction = businessUseFraction(for: vehicle.id, in: interval)

            if let allowancePlan = vehicle.allowancePlan {
                let dates = recurringDates(for: allowancePlan.schedule, in: occurredInterval)
                entries.append(contentsOf: dates.map { date in
                    FinancialLogEntry(
                        recordType: "allowance",
                        vehicleID: vehicle.id,
                        vehicleName: vehicleName,
                        date: date,
                        category: "Allowance",
                        description: "Scheduled vehicle allowance",
                        amount: allowancePlan.amount,
                        businessUsePercent: nil,
                        businessPortionAmount: nil,
                        notes: allowancePlan.schedule.frequency.title
                    )
                })
            }

            if let paymentPlan = vehicle.paymentPlan {
                let dates = recurringDates(for: paymentPlan.schedule, in: occurredInterval)
                entries.append(contentsOf: dates.map { date in
                    let businessPortionAmount = businessUseFraction.map { paymentPlan.amount * $0 }
                    return FinancialLogEntry(
                        recordType: "payment",
                        vehicleID: vehicle.id,
                        vehicleName: vehicleName,
                        date: date,
                        category: paymentPlan.kind.title,
                        description: paymentPlan.kind.title,
                        amount: -paymentPlan.amount,
                        businessUsePercent: businessUseFraction.map { $0 * 100 },
                        businessPortionAmount: businessPortionAmount.map { -$0 },
                        notes: paymentPlan.schedule.frequency.title
                    )
                })
            }

            if let insurancePlan = vehicle.insurancePlan {
                let dates = recurringDates(for: insurancePlan.schedule, in: occurredInterval)
                entries.append(contentsOf: dates.map { date in
                    let businessPortionAmount = businessUseFraction.map { insurancePlan.amount * $0 }
                    return FinancialLogEntry(
                        recordType: "insurance",
                        vehicleID: vehicle.id,
                        vehicleName: vehicleName,
                        date: date,
                        category: "Insurance",
                        description: "Scheduled insurance",
                        amount: -insurancePlan.amount,
                        businessUsePercent: businessUseFraction.map { $0 * 100 },
                        businessPortionAmount: businessPortionAmount.map { -$0 },
                        notes: insurancePlan.schedule.frequency.title
                    )
                })
            }

            for expense in vehicle.otherScheduledExpenses {
                let dates = recurringDates(for: expense.schedule, in: occurredInterval)
                entries.append(contentsOf: dates.map { date in
                    let businessPortionAmount = businessUseFraction.map { expense.amount * $0 }
                    return FinancialLogEntry(
                        recordType: "scheduled_expense",
                        vehicleID: vehicle.id,
                        vehicleName: vehicleName,
                        date: date,
                        category: "Scheduled Expense",
                        description: expense.title,
                        amount: -expense.amount,
                        businessUsePercent: businessUseFraction.map { $0 * 100 },
                        businessPortionAmount: businessPortionAmount.map { -$0 },
                        notes: expense.schedule.frequency.title
                    )
                })
            }
        }

        let filteredAllowanceAdjustments = allowanceAdjustments.filter {
            vehicleIDs.contains($0.vehicleID) && interval.contains($0.date)
        }
        entries.append(contentsOf: filteredAllowanceAdjustments.map { adjustment in
            FinancialLogEntry(
                recordType: "allowance_adjustment",
                vehicleID: adjustment.vehicleID,
                vehicleName: vehicle(for: adjustment.vehicleID)?.displayName ?? "Unknown vehicle",
                date: adjustment.date,
                category: adjustment.amount >= 0 ? "Allowance Top Up" : "Allowance Reduction",
                description: adjustment.reason,
                amount: adjustment.amount,
                businessUsePercent: nil,
                businessPortionAmount: nil,
                notes: "Manual allowance adjustment"
            )
        })

        let filteredFuelEntries = fuelEntries.filter {
            (vehicleIDs.isEmpty || ($0.vehicleID.map(vehicleIDs.contains) ?? false)) && interval.contains($0.date)
        }
        entries.append(contentsOf: filteredFuelEntries.map { entry in
            let businessUseFraction = businessUseFraction(for: entry.vehicleID, in: interval)
            let businessPortionAmount = businessUseFraction.map { entry.totalCost * $0 }
            return FinancialLogEntry(
                recordType: "fuel",
                vehicleID: entry.vehicleID,
                vehicleName: entry.vehicleProfileName,
                date: entry.date,
                category: "Fuel",
                description: entry.station,
                amount: -entry.totalCost,
                businessUsePercent: businessUseFraction.map { $0 * 100 },
                businessPortionAmount: businessPortionAmount.map { -$0 },
                notes: "Volume \(entry.volume.formatted(.number.precision(.fractionLength(2)))) L"
            )
        })

        let filteredMaintenanceRecords = maintenanceRecords.filter {
            (vehicleIDs.isEmpty || ($0.vehicleID.map(vehicleIDs.contains) ?? false)) && interval.contains($0.date)
        }
        entries.append(contentsOf: filteredMaintenanceRecords.map { record in
            let businessUseFraction = businessUseFraction(for: record.vehicleID, in: interval)
            let businessPortionAmount = businessUseFraction.map { record.totalCost * $0 }
            let description = record.type == .other && !record.otherDescription.isEmpty
                ? record.otherDescription
                : record.type.title
            return FinancialLogEntry(
                recordType: "maintenance",
                vehicleID: record.vehicleID,
                vehicleName: record.vehicleProfileName,
                date: record.date,
                category: "Maintenance",
                description: description,
                amount: -record.totalCost,
                businessUsePercent: businessUseFraction.map { $0 * 100 },
                businessPortionAmount: businessPortionAmount.map { -$0 },
                notes: record.shopName
            )
        })

        return entries
    }

    private func monthlyOccurrenceDate(in monthStart: Date, anchorDate: Date) -> Date {
        let anchorComponents = calendar.dateComponents([.day, .hour, .minute, .second], from: anchorDate)
        let day = anchorComponents.day ?? 1
        let validRangeCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        var components = calendar.dateComponents([.year, .month], from: monthStart)
        components.day = min(day, validRangeCount)
        components.hour = anchorComponents.hour
        components.minute = anchorComponents.minute
        components.second = anchorComponents.second
        return calendar.date(from: components) ?? monthStart
    }

    private func lastDayOfMonthDate(in monthStart: Date, anchorDate: Date) -> Date? {
        let anchorComponents = calendar.dateComponents([.hour, .minute, .second], from: anchorDate)
        guard let validRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month], from: monthStart)
        components.day = validRange.count
        components.hour = anchorComponents.hour
        components.minute = anchorComponents.minute
        components.second = anchorComponents.second
        return calendar.date(from: components)
    }

    private func prepareFuelEntry(_ entry: FuelEntry) -> FuelEntry {
        var preparedEntry = entry
        if preparedEntry.vehicleID == nil, let activeVehicle {
            preparedEntry.vehicleID = activeVehicle.id
            preparedEntry.vehicleProfileName = activeVehicle.displayName
        } else if let vehicle = vehicle(for: preparedEntry.vehicleID) {
            preparedEntry.vehicleProfileName = vehicle.displayName
        }

        return preparedEntry
    }

    private func prepareMaintenanceRecord(_ record: MaintenanceRecord) -> MaintenanceRecord {
        var preparedRecord = record
        if preparedRecord.vehicleID == nil, let activeVehicle {
            preparedRecord.vehicleID = activeVehicle.id
            preparedRecord.vehicleProfileName = activeVehicle.displayName
        } else if let vehicle = vehicle(for: preparedRecord.vehicleID) {
            preparedRecord.vehicleProfileName = vehicle.displayName
        }

        return preparedRecord
    }

    private func upsertVehicle(_ vehicle: VehicleProfile) {
        if vehicle.archivedAt != nil {
            upsertArchivedVehicle(vehicle)
        } else if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
        } else {
            vehicles.append(vehicle)
        }
    }

    private func upsertDriver(_ driver: DriverProfile) {
        if driver.archivedAt != nil {
            upsertArchivedDriver(driver)
        } else if let index = drivers.firstIndex(where: { $0.id == driver.id }) {
            drivers[index] = driver
        } else {
            drivers.append(driver)
        }
    }

    private func matchingVehicle(forImportedVehicle vehicle: VehicleProfile) -> VehicleProfile? {
        let importedName = vehicle.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !importedName.isEmpty else {
            return nil
        }
        return vehicles.first(where: {
            $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(importedName) == .orderedSame
        })
    }

    private func matchingDriver(forImportedDriver driver: DriverProfile) -> DriverProfile? {
        let importedName = driver.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !importedName.isEmpty else {
            return nil
        }
        return drivers.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(importedName) == .orderedSame
        })
    }

    private func upsertTrip(_ trip: Trip) {
        let preparedTrip = prepareTripForUpdate(trip)
        if let index = trips.firstIndex(where: { $0.id == preparedTrip.id }) {
            trips[index] = preparedTrip
        } else {
            trips.append(preparedTrip)
        }
    }

    private func upsertFuelEntry(_ entry: FuelEntry) {
        let preparedEntry = prepareFuelEntry(entry)
        if let index = fuelEntries.firstIndex(where: { $0.id == preparedEntry.id }) {
            fuelEntries[index] = preparedEntry
        } else {
            fuelEntries.append(preparedEntry)
        }
    }

    private func upsertMaintenanceRecord(_ record: MaintenanceRecord) {
        let preparedRecord = prepareMaintenanceRecord(record)
        if let index = maintenanceRecords.firstIndex(where: { $0.id == preparedRecord.id }) {
            maintenanceRecords[index] = preparedRecord
        } else {
            maintenanceRecords.append(preparedRecord)
        }
    }

    private func prepareTripForInsertion(_ trip: Trip) -> Trip {
        var preparedTrip = trip
        if preparedTrip.vehicleID == nil, let vehicle = activeVehicle {
            preparedTrip.vehicleID = vehicle.id
            preparedTrip.vehicleProfileName = vehicle.displayName
        } else if let vehicle = vehicle(for: preparedTrip.vehicleID) {
            preparedTrip.vehicleProfileName = vehicle.displayName
        }
        if preparedTrip.driverID == nil, let driver = activeDriver {
            preparedTrip.driverID = driver.id
            preparedTrip.driverName = driver.name
            preparedTrip.driverDateOfBirth = driver.dateOfBirth
            preparedTrip.driverLicenceNumber = driver.licenceNumber
        } else if let driver = driver(for: preparedTrip.driverID) {
            preparedTrip.driverName = driver.name
            preparedTrip.driverDateOfBirth = driver.dateOfBirth
            preparedTrip.driverLicenceNumber = driver.licenceNumber
        }
        if preparedTrip.odometerStart <= 0 {
            preparedTrip.odometerStart = suggestedTripStartOdometer(for: preparedTrip, excludingTripID: nil) ?? preparedTrip.odometerStart
        }
        if preparedTrip.odometerEnd <= preparedTrip.odometerStart {
            preparedTrip.odometerEnd = preparedTrip.odometerStart + unitSystem.convertedDistance(for: preparedTrip.distanceMeters)
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
            preparedTrip.driverDateOfBirth = driver.dateOfBirth
            preparedTrip.driverLicenceNumber = driver.licenceNumber
        }
        if preparedTrip.odometerStart <= 0 {
            preparedTrip.odometerStart = suggestedTripStartOdometer(for: preparedTrip, excludingTripID: preparedTrip.id) ?? preparedTrip.odometerStart
        }
        if preparedTrip.odometerEnd <= preparedTrip.odometerStart {
            preparedTrip.odometerEnd = preparedTrip.odometerStart + unitSystem.convertedDistance(for: preparedTrip.distanceMeters)
        }
        preparedTrip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(preparedTrip.odometerEnd - preparedTrip.odometerStart, 0))
        return preparedTrip
    }

    private func sortTripsDescending() {
        trips.sort { $0.date > $1.date }
    }

    private func latestTrip(for vehicleID: UUID) -> Trip? {
        var latestTrip: Trip?

        for trip in trips where trip.vehicleID == vehicleID {
            guard let currentLatest = latestTrip else {
                latestTrip = trip
                continue
            }

            if trip.date > currentLatest.date {
                latestTrip = trip
            }
        }

        return latestTrip
    }

    private func suggestedTripStartOdometer(for trip: Trip, excludingTripID: UUID?) -> Double? {
        guard let vehicleID = trip.vehicleID, let vehicle = vehicle(for: vehicleID) else {
            return nil
        }

        let previousTrip = trips
            .filter { existingTrip in
                existingTrip.vehicleID == vehicleID &&
                existingTrip.id != excludingTripID &&
                existingTrip.date < trip.date
            }
            .max(by: { $0.date < $1.date })

        return previousTrip?.odometerEnd ?? vehicle.startingOdometerReading
    }

    private func upsertArchivedVehicle(_ vehicle: VehicleProfile) {
        if let index = archivedVehicles.firstIndex(where: { $0.id == vehicle.id }) {
            archivedVehicles[index] = vehicle
        } else {
            archivedVehicles.append(vehicle)
        }
    }

    private func upsertArchivedDriver(_ driver: DriverProfile) {
        if let index = archivedDrivers.firstIndex(where: { $0.id == driver.id }) {
            archivedDrivers[index] = driver
        } else {
            archivedDrivers.append(driver)
        }
    }

    private func syncAssociatedVehicleData(with vehicle: VehicleProfile) {
        for index in trips.indices where trips[index].vehicleID == vehicle.id {
            trips[index].vehicleProfileName = vehicle.displayName
        }

        for index in fuelEntries.indices where fuelEntries[index].vehicleID == vehicle.id {
            fuelEntries[index].vehicleProfileName = vehicle.displayName
        }

        for index in maintenanceRecords.indices where maintenanceRecords[index].vehicleID == vehicle.id {
            maintenanceRecords[index].vehicleProfileName = vehicle.displayName
        }
    }

    private func syncTripDriverData(with driver: DriverProfile) {
        for index in trips.indices where trips[index].driverID == driver.id {
            trips[index].driverName = driver.name
            trips[index].driverDateOfBirth = driver.dateOfBirth
            trips[index].driverLicenceNumber = driver.licenceNumber
        }
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
            let resolvedAnchorStart = preferredStart
                ?? (anchorTrip.odometerStart > 0 ? anchorTrip.odometerStart : suggestedTripStartOdometer(for: anchorTrip, excludingTripID: anchorTrip.id))
                ?? vehicle.startingOdometerReading
            anchorTrip.odometerStart = resolvedAnchorStart
            anchorTrip.odometerEnd = max(preferredEnd ?? anchorTrip.odometerEnd, anchorTrip.odometerStart)
            anchorTrip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(anchorTrip.odometerEnd - anchorTrip.odometerStart, 0))
            trips[anchorIndex] = anchorTrip

            if anchorPosition > 0 {
                let previousIndex = sortedIndices[anchorPosition - 1]
                var previousTrip = trips[previousIndex]
                previousTrip.odometerEnd = anchorTrip.odometerStart
                if previousTrip.odometerStart > previousTrip.odometerEnd {
                    previousTrip.odometerStart = previousTrip.odometerEnd
                }
                previousTrip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(previousTrip.odometerEnd - previousTrip.odometerStart, 0))
                trips[previousIndex] = previousTrip
            }

            if anchorPosition < sortedIndices.count - 1 {
                let nextIndex = sortedIndices[anchorPosition + 1]
                var nextTrip = trips[nextIndex]
                nextTrip.odometerStart = anchorTrip.odometerEnd
                if nextTrip.odometerEnd < nextTrip.odometerStart {
                    nextTrip.odometerEnd = nextTrip.odometerStart
                }
                nextTrip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(nextTrip.odometerEnd - nextTrip.odometerStart, 0))
                trips[nextIndex] = nextTrip
            }
        } else {
            var runningEnd = vehicle.startingOdometerReading
            for position in sortedIndices.indices {
                let index = sortedIndices[position]
                var trip = trips[index]
                if position == 0 {
                    if trip.odometerStart <= 0 {
                        trip.odometerStart = vehicle.startingOdometerReading
                    } else if trip.odometerStart < vehicle.startingOdometerReading {
                        trip.odometerStart = vehicle.startingOdometerReading
                    }
                } else if trip.odometerStart <= 0 {
                    trip.odometerStart = runningEnd
                }

                if trip.odometerEnd < trip.odometerStart {
                    let displayedDistance = unitSystem.convertedDistance(for: trip.distanceMeters)
                    trip.odometerEnd = trip.odometerStart + max(displayedDistance, 0)
                }

                trip.distanceMeters = unitSystem.meters(forDisplayedDistance: max(trip.odometerEnd - trip.odometerStart, 0))
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
    nonisolated struct PersistenceSnapshot: Codable, Equatable {
        var autoStartEnabled: Bool
        var backgroundTripTrackingEnabled: Bool
        var motionActivityEnabled: Bool
        var autoStartSpeedThresholdKilometersPerHour: Double
        var autoStopDelayMinutes: Double
        var selectedTripType: TripType

        private enum CodingKeys: String, CodingKey {
            case autoStartEnabled
            case backgroundTripTrackingEnabled
            case motionActivityEnabled
            case autoStartSpeedThresholdKilometersPerHour
            case autoStopDelayMinutes
            case selectedTripType
        }

        init(
            autoStartEnabled: Bool,
            backgroundTripTrackingEnabled: Bool,
            motionActivityEnabled: Bool,
            autoStartSpeedThresholdKilometersPerHour: Double,
            autoStopDelayMinutes: Double,
            selectedTripType: TripType
        ) {
            self.autoStartEnabled = autoStartEnabled
            self.backgroundTripTrackingEnabled = backgroundTripTrackingEnabled
            self.motionActivityEnabled = motionActivityEnabled
            self.autoStartSpeedThresholdKilometersPerHour = autoStartSpeedThresholdKilometersPerHour
            self.autoStopDelayMinutes = autoStopDelayMinutes
            self.selectedTripType = selectedTripType
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            autoStartEnabled = try container.decode(Bool.self, forKey: .autoStartEnabled)
            backgroundTripTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundTripTrackingEnabled) ?? true
            motionActivityEnabled = try container.decodeIfPresent(Bool.self, forKey: .motionActivityEnabled) ?? true
            autoStartSpeedThresholdKilometersPerHour = try container.decode(Double.self, forKey: .autoStartSpeedThresholdKilometersPerHour)
            autoStopDelayMinutes = try container.decodeIfPresent(Double.self, forKey: .autoStopDelayMinutes) ?? 10
            selectedTripType = try container.decode(TripType.self, forKey: .selectedTripType)
        }
    }

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let motionActivityManager = CMMotionActivityManager()
    @ObservationIgnored private let motionActivityQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MeerkatMotionActivityQueue"
        return queue
    }()
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var startLocation: CLLocation?
    @ObservationIgnored private var endLocation: CLLocation?
    @ObservationIgnored private var tripStartDate: Date?
    @ObservationIgnored private var tripStartOdometerReading: Double?
    @ObservationIgnored private var elapsedTimeTimer: Timer?
    @ObservationIgnored private var speedRefreshTimer: Timer?
    @ObservationIgnored private let tripTypeGracePeriod: TimeInterval = 15 * 60
    @ObservationIgnored private let speedStaleInterval: TimeInterval = 4
    @ObservationIgnored private let minimumDisplayedSpeedThresholdMetersPerSecond: Double = 1 / 3.6
    @ObservationIgnored private let stationarySpeedThresholdMetersPerSecond: Double = 0.75
    @ObservationIgnored private let speedDisagreementThresholdMetersPerSecond: Double = 3
    @ObservationIgnored private let stableLocationAccuracyThresholdMeters: CLLocationAccuracy = 25
    @ObservationIgnored private let stableLocationAgeThreshold: TimeInterval = 5
    @ObservationIgnored private let requiredStableLocationSampleCount = 2
    @ObservationIgnored private let maximumPlausibleSpeedMetersPerSecond: Double = 90
    @ObservationIgnored private var isMonitoringSignificantLocationChanges = false
    @ObservationIgnored private var isMonitoringMotionActivity = false
    @ObservationIgnored private var recordedRoutePoints: [Trip.RoutePoint] = []
    @ObservationIgnored private var belowAutoStopThresholdStartDate: Date?
    @ObservationIgnored private var isAutoStopping = false
    @ObservationIgnored private var latestMotionActivity: CMMotionActivity?
    @ObservationIgnored private var isAwaitingStableLocation = false
    @ObservationIgnored private var stableLocationSampleCount = 0
    @ObservationIgnored var shouldAllowVehicleTriggeredAutoStart: (() -> Bool)?

    var authorizationStatus: CLAuthorizationStatus
    var autoStartEnabled = true {
        didSet {
            refreshLocationMonitoring()
            refreshMotionActivityMonitoring()
        }
    }
    var backgroundTripTrackingEnabled = true {
        didSet {
            refreshLocationMonitoring()
        }
    }
    var motionActivityEnabled = true {
        didSet {
            refreshMotionActivityMonitoring()
        }
    }
    var autoStartSpeedThresholdKilometersPerHour = 10.0
    var autoStopDelayMinutes = 10.0
    var requiresDetectedVehicleForAutoStart = false
    var canRecordTrips = false {
        didSet {
            refreshLocationMonitoring()
            notifyStateChanged(forceWidgetReload: true)
        }
    }
    var isTracking = false {
        didSet {
            notifyStateChanged(forceWidgetReload: true)
        }
    }
    var selectedTripType: TripType = .business {
        didSet {
            notifyStateChanged(forceWidgetReload: true)
        }
    }
    var currentTripDistance: Double = 0 {
        didSet {
            notifyStateChanged()
        }
    }
    var currentSpeed: Double = 0 {
        didSet {
            notifyStateChanged()
        }
    }
    var elapsedTime: TimeInterval = 0 {
        didSet {
            notifyStateChanged()
        }
    }
    var onAutoStoppedTrip: (@MainActor (Trip) -> Void)?
    var onStateChanged: (@MainActor (_ forceWidgetReload: Bool) -> Void)?

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .automotiveNavigation
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
        startSpeedRefreshTimer()
        refreshLocationMonitoring()
        refreshMotionActivityMonitoring()
    }

    var persistenceSnapshot: PersistenceSnapshot {
        PersistenceSnapshot(
            autoStartEnabled: autoStartEnabled,
            backgroundTripTrackingEnabled: backgroundTripTrackingEnabled,
            motionActivityEnabled: motionActivityEnabled,
            autoStartSpeedThresholdKilometersPerHour: autoStartSpeedThresholdKilometersPerHour,
            autoStopDelayMinutes: autoStopDelayMinutes,
            selectedTripType: selectedTripType
        )
    }

    func applyPersistenceSnapshot(_ snapshot: PersistenceSnapshot) {
        autoStartEnabled = snapshot.autoStartEnabled
        backgroundTripTrackingEnabled = snapshot.backgroundTripTrackingEnabled
        motionActivityEnabled = snapshot.motionActivityEnabled
        autoStartSpeedThresholdKilometersPerHour = snapshot.autoStartSpeedThresholdKilometersPerHour
        autoStopDelayMinutes = snapshot.autoStopDelayMinutes
        selectedTripType = snapshot.selectedTripType
        refreshLocationMonitoring()
        refreshMotionActivityMonitoring()
        notifyStateChanged(forceWidgetReload: true)
    }

    func resetForFactoryReset() {
        isTracking = false
        currentTripDistance = 0
        currentSpeed = 0
        elapsedTime = 0
        lastLocation = nil
        startLocation = nil
        endLocation = nil
        tripStartDate = nil
        tripStartOdometerReading = nil
        recordedRoutePoints = []
        belowAutoStopThresholdStartDate = nil
        isAutoStopping = false
        latestMotionActivity = nil
        stopElapsedTimeTimer()
        refreshLocationMonitoring()
        refreshMotionActivityMonitoring()
        notifyStateChanged(forceWidgetReload: true)
    }

    var statusMessage: String {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard canRecordTrips else {
                return "Not ready to drive. Add and select a vehicle and driver before recording."
            }
            if isTracking {
                return "Using GPS updates to calculate your live mileage, even when the app is in the background."
            }
            if isAwaitingStableLocation {
                return "Waiting for GPS location accuracy before showing speed or starting a trip."
            }
            if hasLiveSpeedReading {
                let currentSpeedText = SharedAppModel.shared.store.unitSystem.speedString(for: currentSpeed)
                if autoStartEnabled {
                    let thresholdText = SharedAppModel.shared.store.unitSystem.speedString(
                        for: autoStartSpeedThresholdMetersPerSecond
                    )
                    return "Current speed is \(currentSpeedText). Recording starts automatically at \(thresholdText)."
                }
                return "Current speed is \(currentSpeedText). Start trip recording when you are ready."
            }
            if backgroundTripTrackingEnabled && authorizationStatus == .authorizedAlways && autoStartEnabled {
                return motionActivityStatusMessage(
                    defaultMessage: "Ready to wake up in the background and auto-start a trip when driving begins."
                )
            }
            if autoStartEnabled {
                return motionActivityStatusMessage(
                    defaultMessage: "Monitoring for speeds above \(autoStartSpeedThresholdKilometersPerHour.formatted(.number.precision(.fractionLength(0)))) km/h to auto-start a trip."
                )
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

    var hasLiveSpeedReading: Bool {
        currentSpeed >= minimumDisplayedSpeedThresholdMetersPerSecond
    }

    func recordingStatusText(unitSystem: DistanceUnitSystem) -> String {
        if isTracking {
            return "Recording in progress"
        }

        guard hasLiveSpeedReading else {
            return "Ready to drive"
        }

        let speedText = unitSystem.speedString(for: currentSpeed)
        if autoStartEnabled {
            let thresholdText = unitSystem.speedString(for: autoStartSpeedThresholdMetersPerSecond)
            return "Moving at \(speedText) • Auto-start at \(thresholdText)"
        }

        return "Moving at \(speedText)"
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

    var motionAuthorizationLabel: String {
        guard motionActivityEnabled else {
            return "Off"
        }

        guard CMMotionActivityManager.isActivityAvailable() else {
            return "Unavailable"
        }

        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            return "Allowed"
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
        elapsedTime.formattedDuration
    }

    var currentTripStartDate: Date? {
        tripStartDate
    }

    var currentLocation: CLLocation? {
        endLocation ?? lastLocation ?? locationManager.location
    }

    func currentAddress() async -> String? {
        guard let currentLocation else {
            return nil
        }

        return await resolveAddress(for: currentLocation)
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

    func requestAuthorizationIfNeeded() {
        guard authorizationStatus == .notDetermined else {
            return
        }

        requestAuthorization()
    }

    func requestAlwaysAuthorization() {
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }

        guard authorizationStatus == .authorizedWhenInUse else {
            return
        }

        locationManager.requestAlwaysAuthorization()
    }

    func requestPermissionsForCurrentTrackingMode() {
        guard backgroundTripTrackingEnabled else {
            if authorizationStatus == .notDetermined {
                requestAuthorization()
            }
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            requestAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysAuthorization()
        case .authorizedAlways, .denied, .restricted:
            break
        @unknown default:
            break
        }

        requestMotionActivityAuthorizationIfNeeded()
    }

    func resumeBackgroundMonitoringAfterSystemLaunch() {
        beginAwaitingStableLocation()
        refreshLocationMonitoring()
        refreshMotionActivityMonitoring()
    }

    func startTracking(startOdometerReading: Double? = nil) {
        guard !isTracking, canRecordTrips else {
            return
        }

        isTracking = true
        currentTripDistance = 0
        elapsedTime = 0
        lastLocation = nil
        endLocation = nil
        tripStartDate = .now
        tripStartOdometerReading = startOdometerReading ?? SharedAppModel.shared.store.currentBaseOdometerReading()
        startLocation = lastLocation
        recordedRoutePoints = []
        belowAutoStopThresholdStartDate = nil
        isAutoStopping = false
        stableLocationSampleCount = 0
        isAwaitingStableLocation = false
        refreshMotionActivityMonitoring()
        if let lastLocation {
            appendRecordedRoutePoint(for: lastLocation, minimumDistance: 0)
        }
        startElapsedTimeTimer()
        refreshLocationMonitoring()
        notifyStateChanged(forceWidgetReload: true)
    }

    func stopTracking(endOdometerReading: Double? = nil) async -> Trip? {
        guard isTracking else {
            return nil
        }

        isTracking = false
        stopElapsedTimeTimer()
        refreshLocationMonitoring()

        let trip = await completedTrip(endOdometerReading: endOdometerReading)

        currentTripDistance = 0
        elapsedTime = 0
        currentSpeed = 0
        lastLocation = nil
        startLocation = nil
        endLocation = nil
        tripStartDate = nil
        tripStartOdometerReading = nil
        recordedRoutePoints = []
        belowAutoStopThresholdStartDate = nil
        isAutoStopping = false
        beginAwaitingStableLocation()
        refreshMotionActivityMonitoring()
        notifyStateChanged(forceWidgetReload: true)

        return trip
    }

    func selectTripType(
        _ tripType: TripType,
        nextTripStartOdometerReading: Double? = nil,
        completedTripEndOdometerReading: Double? = nil
    ) async -> Trip? {
        guard tripType != selectedTripType else {
            return nil
        }

        guard isTracking else {
            selectedTripType = tripType
            notifyStateChanged(forceWidgetReload: true)
            return nil
        }

        if canChangeTripTypeWithoutSplitting {
            selectedTripType = tripType
            notifyStateChanged(forceWidgetReload: true)
            return nil
        }

        let completedTrip = await completedTrip(endOdometerReading: completedTripEndOdometerReading)
        selectedTripType = tripType
        currentTripDistance = 0
        elapsedTime = 0
        lastLocation = nil
        startLocation = endLocation
        tripStartDate = .now
        tripStartOdometerReading = nextTripStartOdometerReading
        recordedRoutePoints = []
        if let endLocation {
            appendRecordedRoutePoint(for: endLocation, minimumDistance: 0)
        }
        startElapsedTimeTimer()
        notifyStateChanged(forceWidgetReload: true)

        return completedTrip
    }

    func setTripStartOdometerReadingIfNeeded(_ reading: Double) {
        guard isTracking, tripStartOdometerReading == nil else {
            return
        }

        tripStartOdometerReading = reading
        notifyStateChanged(forceWidgetReload: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            beginAwaitingStableLocation()
        } else {
            resetStableLocationState()
        }
        refreshLocationMonitoring()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 40 {
            if shouldIgnoreForLocationStability(location) {
                currentSpeed = 0
                continue
            }

            let previousLocation = lastLocation
            currentSpeed = measuredSpeed(for: location, previousLocation: previousLocation)
            let shouldAutoStart = autoStartEnabled && !isTracking && shouldAutoStartTrip(for: currentSpeed)

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
            appendRecordedRoutePoint(for: location)

            guard let previousLocation else {
                continue
            }

            let delta = location.distance(from: previousLocation)
            if delta > 0 && delta < 500 {
                currentTripDistance += delta
            }

            updateAutoStopState(currentSpeed: currentSpeed)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        currentSpeed = 0
        beginAwaitingStableLocation()
        print("Location tracking failed: \(error.localizedDescription)")
    }

    private var autoStartSpeedThresholdMetersPerSecond: Double {
        autoStartSpeedThresholdKilometersPerHour / 3.6
    }

    private func shouldAutoStartTrip(for currentSpeed: Double) -> Bool {
        guard currentSpeed >= autoStartSpeedThresholdMetersPerSecond else {
            return false
        }

        guard requiresDetectedVehicleForAutoStart else {
            return true
        }

        return shouldAllowVehicleTriggeredAutoStart?() ?? false
    }

    private func startSpeedRefreshTimer() {
        speedRefreshTimer?.invalidate()
        speedRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            guard let tracker = self else {
                return
            }

            MainActor.assumeIsolated {
                tracker.refreshDisplayedSpeedIfNeeded()
            }
        }
    }

    private func refreshDisplayedSpeedIfNeeded() {
        guard let currentLocation else {
            currentSpeed = 0
            updateAutoStopState(currentSpeed: currentSpeed)
            return
        }

        if Date.now.timeIntervalSince(currentLocation.timestamp) > speedStaleInterval {
            currentSpeed = 0
            if !isTracking {
                beginAwaitingStableLocation()
            }
        }

        updateAutoStopState(currentSpeed: currentSpeed)
    }

    private func measuredSpeed(for location: CLLocation, previousLocation: CLLocation?) -> Double {
        let reportedSpeed = min(max(location.speed, 0), maximumPlausibleSpeedMetersPerSecond)
        if reportedSpeed >= minimumDisplayedSpeedThresholdMetersPerSecond {
            guard let previousLocation else {
                return reportedSpeed
            }

            let elapsedTime = location.timestamp.timeIntervalSince(previousLocation.timestamp)
            guard elapsedTime > 0 else {
                return reportedSpeed
            }

            let derivedSpeed = max(location.distance(from: previousLocation) / elapsedTime, 0)
            if derivedSpeed < minimumDisplayedSpeedThresholdMetersPerSecond {
                return reportedSpeed
            }

            if abs(reportedSpeed - derivedSpeed) >= speedDisagreementThresholdMetersPerSecond {
                return min(reportedSpeed, derivedSpeed)
            }

            return reportedSpeed
        }

        guard let previousLocation else {
            return reportedSpeed
        }

        let elapsedTime = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard elapsedTime > 0 else {
            return reportedSpeed
        }

        let derivedSpeed = max(location.distance(from: previousLocation) / elapsedTime, 0)
        guard derivedSpeed <= maximumPlausibleSpeedMetersPerSecond else {
            return reportedSpeed
        }

        if derivedSpeed < minimumDisplayedSpeedThresholdMetersPerSecond {
            return 0
        }

        guard reportedSpeed > 0 else {
            return derivedSpeed
        }

        if abs(reportedSpeed - derivedSpeed) >= speedDisagreementThresholdMetersPerSecond {
            return min(reportedSpeed, derivedSpeed)
        }

        return reportedSpeed
    }

    private func beginAwaitingStableLocation() {
        guard !isTracking else {
            return
        }

        isAwaitingStableLocation = canRecordTrips
        stableLocationSampleCount = 0
        currentSpeed = 0
        lastLocation = nil
        endLocation = nil
    }

    private func resetStableLocationState() {
        isAwaitingStableLocation = false
        stableLocationSampleCount = 0
    }

    private func shouldIgnoreForLocationStability(_ location: CLLocation) -> Bool {
        guard !isTracking, isAwaitingStableLocation else {
            return false
        }

        let isFreshEnough = Date.now.timeIntervalSince(location.timestamp) <= stableLocationAgeThreshold
        let isAccurateEnough = location.horizontalAccuracy <= stableLocationAccuracyThresholdMeters

        guard isFreshEnough, isAccurateEnough else {
            stableLocationSampleCount = 0
            lastLocation = nil
            return true
        }

        stableLocationSampleCount += 1
        if stableLocationSampleCount < requiredStableLocationSampleCount {
            lastLocation = location
            return true
        }

        isAwaitingStableLocation = false
        return false
    }

    private func startElapsedTimeTimer() {
        stopElapsedTimeTimer()
        updateElapsedTime()
        elapsedTimeTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(elapsedTimeTimerFired),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = nil
    }

    private func updateElapsedTime() {
        guard let tripStartDate, isTracking else {
            elapsedTime = 0
            return
        }

        elapsedTime = Date.now.timeIntervalSince(tripStartDate)
    }

    @objc private func elapsedTimeTimerFired() {
        updateElapsedTime()
    }

    private func notifyStateChanged(forceWidgetReload: Bool = false) {
        onStateChanged?(forceWidgetReload)
    }

    private func completedTrip(endOdometerReading: Double? = nil) async -> Trip {
        let tripDate = Date.now
        let duration = tripDate.timeIntervalSince(tripStartDate ?? tripDate)
        let odometerStart = tripStartOdometerReading ?? 0
        let odometerEnd = max(endOdometerReading ?? odometerStart, odometerStart)
        let finalDistanceMeters = endOdometerReading == nil
            ? currentTripDistance
            : SharedAppModel.shared.store.unitSystem.meters(forDisplayedDistance: max(odometerEnd - odometerStart, 0))
        let routePoints = finalizedRoutePoints()

        return Trip(
            name: "\(selectedTripType.title) trip on \(tripDate.formatted(date: .abbreviated, time: .omitted))",
            type: selectedTripType,
            vehicleID: nil,
            vehicleProfileName: "",
            driverID: nil,
            driverName: "",
            driverDateOfBirth: nil,
            driverLicenceNumber: "",
            startAddress: await resolveAddress(for: startLocation),
            endAddress: await resolveAddress(for: endLocation ?? lastLocation),
            details: "",
            odometerStart: odometerStart,
            odometerEnd: odometerEnd,
            distanceMeters: finalDistanceMeters,
            duration: duration,
            date: tripDate,
            routePoints: routePoints
        )
    }

    private var autoStopThresholdMetersPerSecond: Double {
        autoStartSpeedThresholdMetersPerSecond
    }

    private var autoStopDelayInterval: TimeInterval {
        autoStopDelayMinutes * 60
    }

    private func updateAutoStopState(currentSpeed: Double) {
        guard isTracking, !isAutoStopping else {
            return
        }

        guard currentSpeed < autoStopThresholdMetersPerSecond else {
            belowAutoStopThresholdStartDate = nil
            return
        }

        if belowAutoStopThresholdStartDate == nil {
            belowAutoStopThresholdStartDate = .now
            return
        }

        guard let belowAutoStopThresholdStartDate,
              Date.now.timeIntervalSince(belowAutoStopThresholdStartDate) >= autoStopDelayInterval else {
            return
        }

        autoStopCurrentTrip()
    }

    private func autoStopCurrentTrip() {
        guard !isAutoStopping else {
            return
        }

        isAutoStopping = true
        let endOdometerReading = (tripStartOdometerReading ?? 0) + SharedAppModel.shared.store.unitSystem.convertedDistance(for: currentTripDistance)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            if let trip = await self.stopTracking(endOdometerReading: endOdometerReading) {
                self.onAutoStoppedTrip?(trip)
            }
        }
    }

    private var isAutomotiveMotionLikely: Bool {
        guard let latestMotionActivity else {
            return false
        }

        return latestMotionActivity.automotive
    }

    private func requestMotionActivityAuthorizationIfNeeded() {
        guard motionActivityEnabled, CMMotionActivityManager.isActivityAvailable() else {
            return
        }

        guard CMMotionActivityManager.authorizationStatus() == .notDetermined else {
            refreshMotionActivityMonitoring()
            return
        }

        motionActivityManager.queryActivityStarting(from: .now.addingTimeInterval(-60), to: .now, to: motionActivityQueue) { _, _ in }
        refreshMotionActivityMonitoring()
    }

    private func refreshMotionActivityMonitoring() {
        guard motionActivityEnabled, CMMotionActivityManager.isActivityAvailable(), autoStartEnabled || isTracking else {
            stopMotionActivityMonitoringIfNeeded()
            return
        }

        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            startMotionActivityMonitoringIfNeeded()
        case .notDetermined:
            stopMotionActivityMonitoringIfNeeded()
        case .denied, .restricted:
            stopMotionActivityMonitoringIfNeeded()
        @unknown default:
            stopMotionActivityMonitoringIfNeeded()
        }
    }

    private func startMotionActivityMonitoringIfNeeded() {
        guard !isMonitoringMotionActivity else {
            return
        }

        motionActivityManager.startActivityUpdates(to: motionActivityQueue) { [weak self] activity in
            guard let self, let activity else {
                return
            }

            Task { @MainActor in
                self.latestMotionActivity = activity
            }
        }
        isMonitoringMotionActivity = true
    }

    private func stopMotionActivityMonitoringIfNeeded() {
        guard isMonitoringMotionActivity else {
            return
        }

        motionActivityManager.stopActivityUpdates()
        isMonitoringMotionActivity = false
    }

    private func motionActivityStatusMessage(defaultMessage: String) -> String {
        guard motionActivityEnabled else {
            return defaultMessage
        }

        guard CMMotionActivityManager.isActivityAvailable() else {
            return "\(defaultMessage) Motion & Fitness is unavailable on this device."
        }

        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            return "\(defaultMessage) Motion & Fitness helps confirm automotive activity while the app is running or backgrounded."
        case .notDetermined:
            return "\(defaultMessage) Enable Motion & Fitness access to improve automotive detection while the app is running or backgrounded."
        case .denied, .restricted:
            return "\(defaultMessage) Motion & Fitness access is unavailable, so auto-start relies on location and speed only."
        @unknown default:
            return defaultMessage
        }
    }

    private func appendRecordedRoutePoint(for location: CLLocation, minimumDistance: CLLocationDistance = 5) {
        let newPoint = Trip.RoutePoint(coordinate: location.coordinate)
        guard let lastPoint = recordedRoutePoints.last else {
            recordedRoutePoints.append(newPoint)
            return
        }

        let lastLocation = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
        guard location.distance(from: lastLocation) >= minimumDistance else {
            return
        }

        recordedRoutePoints.append(newPoint)
    }

    private func finalizedRoutePoints() -> [Trip.RoutePoint] {
        var routePoints = recordedRoutePoints

        if let endLocation {
            let endPoint = Trip.RoutePoint(coordinate: endLocation.coordinate)
            if routePoints.last != endPoint {
                routePoints.append(endPoint)
            }
        }

        return routePoints
    }

    private func resolveAddress(for location: CLLocation?) async -> String {
        guard let location else {
            return "Unknown location"
        }

        if #available(iOS 26, *) {
            do {
                let request = try requestForReverseGeocoding(location: location)
                if let mapItem = try await request.mapItems.first,
                   let address = formattedAddress(from: mapItem) {
                    return address
                }
            }
            catch {
                // Fall through to CLGeocoder fallback.
            }
        }

        if #unavailable(iOS 26) {
            do {
                let placemark = try await CLGeocoder().reverseGeocodeLocation(location).first
                if let placemark, let address = formattedAddress(from: placemark) {
                    return address
                }
            } catch {
                // Fall through to coordinate fallback.
            }
        }

        return coordinateString(for: location)
    }

    private func requestForReverseGeocoding(location: CLLocation) throws -> MKReverseGeocodingRequest {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            throw CocoaError(.coderInvalidValue)
        }

        return request
    }

    @available(iOS 26, *)
    private func formattedAddress(from mapItem: MKMapItem) -> String? {
        if let fullAddress = mapItem.address?.fullAddress
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return formattedPOIAddress(name: mapItem.name, address: fullAddress)
        }

        if let shortAddress = mapItem.address?.shortAddress?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !shortAddress.isEmpty {
            return formattedPOIAddress(name: mapItem.name, address: shortAddress)
        }

        if let fullAddress = mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return formattedPOIAddress(name: mapItem.name, address: fullAddress)
        }

        let parts = [
            mapItem.name,
            mapItem.addressRepresentations?.cityWithContext(.full),
            mapItem.addressRepresentations?.regionName
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: ", ")
    }

    private func formattedAddress(from placemark: CLPlacemark) -> String? {
        let streetLine = [
            placemark.subThoroughfare,
            placemark.thoroughfare
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = [
            streetLine.isEmpty ? placemark.name : streetLine,
            placemark.locality,
            placemark.administrativeArea,
            placemark.country
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return nil
        }

        let address = parts.joined(separator: ", ")
        return formattedPOIAddress(name: placemark.name, address: address)
    }

    private func formattedPOIAddress(name: String?, address: String) -> String {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            return address
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty else {
            return trimmedAddress
        }

        let normalizedName = trimmedName.lowercased()
        let normalizedAddress = trimmedAddress.lowercased()
        if normalizedAddress == normalizedName || normalizedAddress.hasPrefix(normalizedName + ",") || normalizedAddress.hasPrefix(normalizedName + " -") {
            return trimmedAddress
        }

        return "\(trimmedName) - \(trimmedAddress)"
    }

    private func coordinateString(for location: CLLocation) -> String {
        let latitude = location.coordinate.latitude.formatted(.number.precision(.fractionLength(5)))
        let longitude = location.coordinate.longitude.formatted(.number.precision(.fractionLength(5)))
        return "\(latitude), \(longitude)"
    }

    private func refreshLocationMonitoring() {
        let supportsBackgroundLocation = backgroundTripTrackingEnabled && Bundle.main.supportsBackgroundLocationUpdates
        let shouldMaintainLiveSpeedMonitoring = canRecordTrips
        locationManager.allowsBackgroundLocationUpdates = supportsBackgroundLocation
        locationManager.showsBackgroundLocationIndicator = supportsBackgroundLocation && isTracking

        switch authorizationStatus {
        case .authorizedAlways:
            if isTracking {
                resetStableLocationState()
                locationManager.desiredAccuracy = kCLLocationAccuracyBest
                locationManager.distanceFilter = 5
                locationManager.startUpdatingLocation()
            } else if shouldMaintainLiveSpeedMonitoring {
                beginAwaitingStableLocation()
                locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                locationManager.distanceFilter = 5
                locationManager.startUpdatingLocation()
            } else {
                resetStableLocationState()
                locationManager.stopUpdatingLocation()
            }
            startSignificantLocationMonitoringIfNeeded()
        case .authorizedWhenInUse:
            stopSignificantLocationMonitoringIfNeeded()
            if isTracking || shouldMaintainLiveSpeedMonitoring {
                if isTracking {
                    resetStableLocationState()
                } else {
                    beginAwaitingStableLocation()
                }
                locationManager.desiredAccuracy = isTracking ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
                locationManager.distanceFilter = 5
                locationManager.startUpdatingLocation()
            } else {
                resetStableLocationState()
                locationManager.stopUpdatingLocation()
            }
        case .notDetermined, .denied, .restricted:
            resetStableLocationState()
            stopSignificantLocationMonitoringIfNeeded()
            locationManager.stopUpdatingLocation()
        @unknown default:
            resetStableLocationState()
            stopSignificantLocationMonitoringIfNeeded()
            locationManager.stopUpdatingLocation()
        }
    }

    private func startSignificantLocationMonitoringIfNeeded() {
        guard backgroundTripTrackingEnabled, autoStartEnabled || isTracking else {
            stopSignificantLocationMonitoringIfNeeded()
            return
        }

        guard !isMonitoringSignificantLocationChanges else {
            return
        }

        locationManager.startMonitoringSignificantLocationChanges()
        isMonitoringSignificantLocationChanges = true
    }

    private func stopSignificantLocationMonitoringIfNeeded() {
        guard isMonitoringSignificantLocationChanges else {
            return
        }

        locationManager.stopMonitoringSignificantLocationChanges()
        isMonitoringSignificantLocationChanges = false
    }
}

private extension Bundle {
    var supportsBackgroundLocationUpdates: Bool {
        guard let modes = object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }

        return modes.contains("location")
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = max(Int(rounded()), 0)
        let totalMinutes = totalSeconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

@MainActor
final class MaintenanceReminderManager {
    private let notificationCenter = UNUserNotificationCenter.current()

    func processReminders(in store: MileageStore, currentOdometer: Double, unitSystem: DistanceUnitSystem) async -> MaintenanceReminderNotification? {
        let records = store.maintenanceRecords
            .filter { $0.reminderEnabled && $0.nextServiceOdometer != nil }
            .sorted {
                ($0.distanceRemaining(from: currentOdometer) ?? .greatestFiniteMagnitude) <
                    ($1.distanceRemaining(from: currentOdometer) ?? .greatestFiniteMagnitude)
            }

        var firstNotification: MaintenanceReminderNotification?

        for record in records {
            guard let distanceRemaining = record.distanceRemaining(from: currentOdometer) else {
                continue
            }

            for threshold in MaintenanceReminderThreshold.allCases {
                guard distanceRemaining <= threshold.rawValue, !record.hasSentReminder(for: threshold) else {
                    continue
                }

                let notification = makeNotification(for: record, threshold: threshold, distanceRemaining: distanceRemaining, unitSystem: unitSystem)
                store.markMaintenanceReminderSent(recordID: record.id, threshold: threshold)
                await requestAuthorizationIfPossible()
                await scheduleLocalNotification(notification)

                if firstNotification == nil {
                    firstNotification = notification
                }
            }
        }

        return firstNotification
    }

    func requestNotificationAuthorization() async {
        await requestAuthorizationIfPossible()
    }

    func clearScheduledNotifications() async {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
    }

    private func requestAuthorizationIfPossible() async {
        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return
        }
    }

    private func scheduleLocalNotification(_ notification: MaintenanceReminderNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "maintenance-\(notification.id.uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            return
        }
    }

    private func makeNotification(
        for record: MaintenanceRecord,
        threshold: MaintenanceReminderThreshold,
        distanceRemaining: Double,
        unitSystem: DistanceUnitSystem
    ) -> MaintenanceReminderNotification {
        let absoluteDistance = abs(distanceRemaining)
        let distanceText = unitSystem.distanceString(for: unitSystem.meters(forDisplayedDistance: absoluteDistance))
        let message: String

        if distanceRemaining >= 0 {
            message = "\(record.title) is due in \(distanceText) at \(record.shopName.isEmpty ? "your selected service location" : record.shopName)."
        } else {
            message = "\(record.title) is overdue by \(distanceText)."
        }

        return MaintenanceReminderNotification(
            title: threshold.title,
            message: message
        )
    }
}

nonisolated struct AppPersistenceSnapshot: Codable, Equatable {
    var store: MileageStore.PersistenceSnapshot
    var tripTracker: TripTracker.PersistenceSnapshot
}

private struct FirebaseReceiptManifest: Equatable {
    var fuelEntryPaths: [String: String]
    var maintenanceRecordPaths: [String: String]

    static let empty = FirebaseReceiptManifest(
        fuelEntryPaths: [:],
        maintenanceRecordPaths: [:]
    )

    var isEmpty: Bool {
        fuelEntryPaths.isEmpty && maintenanceRecordPaths.isEmpty
    }

    var allPaths: Set<String> {
        Set(fuelEntryPaths.values).union(maintenanceRecordPaths.values)
    }

    init(
        fuelEntryPaths: [String: String],
        maintenanceRecordPaths: [String: String]
    ) {
        self.fuelEntryPaths = fuelEntryPaths
        self.maintenanceRecordPaths = maintenanceRecordPaths
    }

    init(documentData: [String: Any]?) {
        fuelEntryPaths = documentData?[CloudSyncManager.Constants.firebaseFuelReceiptPathsKey] as? [String: String] ?? [:]
        maintenanceRecordPaths = documentData?[CloudSyncManager.Constants.firebaseMaintenanceReceiptPathsKey] as? [String: String] ?? [:]
    }
}

extension Notification.Name {
    static let meerkatTripTrackerStateDidChange = Notification.Name("MeerkatTripTrackerStateDidChange")
    static let meerkatVehicleProfilesDidChange = Notification.Name("MeerkatVehicleProfilesDidChange")
}

@MainActor
@Observable
final class VehicleConnectionManager: NSObject, CBCentralManagerDelegate {
    private enum BluetoothMatching {
        static let minimumRSSI = -85
        static let requiredVisibleDuration: TimeInterval = 3
        static let requiredAbsenceDuration: TimeInterval = 12
        static let unreliableRotationWindow: TimeInterval = 180
        static let unreliableRotationCount = 3
    }

    struct DiscoveredBluetoothDevice: Identifiable, Equatable {
        let id: UUID
        var firstSeen: Date
        var name: String
        var lastSeen: Date
        var rssi: Int
    }

    struct DetectorReliabilityIssue: Identifiable, Equatable {
        let id: UUID
        let vehicleID: UUID
        let detectorName: String
        let message: String
    }

    struct ConnectedAudioRoute: Identifiable, Equatable {
        let id: String
        let name: String
        let portType: AVAudioSession.Port

        var summary: String {
            switch portType {
            case .bluetoothHFP:
                return "\(name) (Calls)"
            case .bluetoothA2DP:
                return "\(name) (Media)"
            default:
                return name
            }
        }
    }

    private struct BluetoothNameObservation {
        let identifier: UUID
        let firstSeen: Date
        let lastSeen: Date
    }

    @ObservationIgnored private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)
    @ObservationIgnored private var staleDeviceTimer: Timer?
    @ObservationIgnored private let staleDeviceInterval: TimeInterval = 45
    @ObservationIgnored private var bluetoothNameObservations: [String: [BluetoothNameObservation]] = [:]
    @ObservationIgnored private var audioRouteObserverTokens: [NSObjectProtocol] = []

    private(set) var bluetoothAuthorization = CBManager.authorization
    private(set) var bluetoothState: CBManagerState = .unknown
    private(set) var discoveredBluetoothDevices: [DiscoveredBluetoothDevice] = []
    private(set) var connectedAudioRoutes: [ConnectedAudioRoute] = []
    private(set) var matchedVehicleID: UUID?
    private(set) var detectorReliabilityIssues: [DetectorReliabilityIssue] = []
    var isDetectionEnabled = false {
        didSet {
            if !isDetectionEnabled {
                discoveredBluetoothDevices = []
                detectorReliabilityIssues = []
            }
            refreshScanningState()
            reevaluateMatchedVehicle()
        }
    }
    private(set) var isManualBluetoothScanActive = false {
        didSet {
            refreshScanningState()
        }
    }
    var isCarPlayConnected = false {
        didSet {
            reevaluateMatchedVehicle()
        }
    }
    var onStateChanged: (() -> Void)?

    var configuredVehicles: [VehicleProfile] = [] {
        didSet {
            refreshScanningState()
            reevaluateMatchedVehicle()
        }
    }

    override init() {
        super.init()
        refreshAudioRouteSnapshot()
        registerAudioRouteObservers()
        staleDeviceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let manager = self else {
                return
            }

            Task { @MainActor in
                manager.purgeStaleDevices()
            }
        }
    }

    deinit {
        staleDeviceTimer?.invalidate()
        for token in audioRouteObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var statusSummary: String {
        let parts = [
            isDetectionEnabled ? "Vehicle detection enabled" : "Vehicle detection off",
            isCarPlayConnected ? "CarPlay connected" : nil,
            connectedAudioRoutes.isEmpty ? nil : "\(connectedAudioRoutes.count) car audio route(s) connected",
            discoveredBluetoothDevices.isEmpty ? nil : "\(discoveredBluetoothDevices.count) Bluetooth device(s) nearby",
            isManualBluetoothScanActive ? "Scanning for Bluetooth devices" : nil,
            isDetectionEnabled ? "BLE match after \(Int(BluetoothMatching.requiredVisibleDuration))s at RSSI \(BluetoothMatching.minimumRSSI) or stronger" : nil,
            detectorReliabilityIssues.isEmpty ? nil : "\(detectorReliabilityIssues.count) detector reliability warning(s)"
        ]
        .compactMap { $0 }

        return parts.isEmpty ? "No vehicle detector active" : parts.joined(separator: " • ")
    }

    var bluetoothStatusLabel: String {
        switch bluetoothState {
        case .poweredOn:
            return "On"
        case .poweredOff:
            return "Off"
        case .unsupported:
            return "Unsupported"
        case .unauthorized:
            return "Denied"
        case .resetting:
            return "Resetting"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }

    var isBluetoothScanningConfigured: Bool {
        isDetectionEnabled || configuredVehicles.contains {
            $0.detectionProfile.isEnabled && $0.detectionProfile.usesBluetoothPeripheral
        }
    }

    var visibleBluetoothDevices: [DiscoveredBluetoothDevice] {
        discoveredBluetoothDevices.filter { device in
            let isAssigned = configuredVehicles.contains {
                $0.detectionProfile.bluetoothPeripheralIdentifier == device.id.uuidString
            }
            return isAssigned || !isUnknownBluetoothDeviceName(device.name)
        }
    }

    var hiddenUnknownBluetoothDeviceCount: Int {
        max(0, discoveredBluetoothDevices.count - visibleBluetoothDevices.count)
    }

    func requestBluetoothAccessIfNeeded() {
        _ = centralManager.state
    }

    func refreshAudioRouteSnapshot() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        connectedAudioRoutes = outputs
            .filter { output in
                output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP
            }
            .map { output in
                let name = output.portName.trimmingCharacters(in: .whitespacesAndNewlines)
                return ConnectedAudioRoute(
                    id: output.uid,
                    name: name.isEmpty ? "Unknown audio device" : name,
                    portType: output.portType
                )
            }
        reevaluateMatchedVehicle()
    }

    func startManualBluetoothScan() {
        requestBluetoothAccessIfNeeded()
        isManualBluetoothScanActive = true
    }

    func stopManualBluetoothScan() {
        isManualBluetoothScanActive = false
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothAuthorization = CBManager.authorization
        bluetoothState = central.state
        refreshScanningState()
        reevaluateMatchedVehicle()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let fallbackName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let deviceName = (peripheral.name ?? fallbackName ?? "Unknown device").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = deviceName.isEmpty ? "Unknown device" : deviceName
        let discoveredDevice = DiscoveredBluetoothDevice(
            id: peripheral.identifier,
            firstSeen: .now,
            name: resolvedName,
            lastSeen: .now,
            rssi: RSSI.intValue
        )

        if let index = discoveredBluetoothDevices.firstIndex(where: { $0.id == discoveredDevice.id }) {
            let existingDevice = discoveredBluetoothDevices[index]
            discoveredBluetoothDevices[index] = DiscoveredBluetoothDevice(
                id: existingDevice.id,
                firstSeen: existingDevice.firstSeen,
                name: preferredBluetoothDeviceName(existing: existingDevice.name, latest: resolvedName),
                lastSeen: discoveredDevice.lastSeen,
                rssi: RSSI.intValue
            )
        } else {
            discoveredBluetoothDevices.append(discoveredDevice)
            sortDiscoveredBluetoothDevices()
        }
        recordBluetoothObservation(for: discoveredDevice)
        reevaluateMatchedVehicle()
    }

    func refreshConfiguredVehicles(_ vehicles: [VehicleProfile]) {
        configuredVehicles = vehicles
    }

    func canAutoStartTrip() -> Bool {
        !requiresVehicleSignalForAutoStart || matchedVehicleID != nil
    }

    var requiresVehicleSignalForAutoStart: Bool {
        isDetectionEnabled
    }

    private func refreshScanningState() {
        guard bluetoothState == .poweredOn else {
            centralManager.stopScan()
            return
        }

        guard isBluetoothScanningConfigured || isManualBluetoothScanActive else {
            centralManager.stopScan()
            return
        }

        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func registerAudioRouteObservers() {
        let center = NotificationCenter.default
        let routeToken = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshAudioRouteSnapshot()
            }
        }
        let inputToken = center.addObserver(
            forName: AVAudioSession.availableInputsChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refreshAudioRouteSnapshot()
            }
        }
        audioRouteObserverTokens = [routeToken, inputToken]
    }

    private func purgeStaleDevices() {
        let cutoff = Date.now.addingTimeInterval(-staleDeviceInterval)
        let oldCount = discoveredBluetoothDevices.count
        discoveredBluetoothDevices.removeAll { $0.lastSeen < cutoff }
        pruneBluetoothObservations()
        if discoveredBluetoothDevices.count != oldCount {
            sortDiscoveredBluetoothDevices()
        }

        reevaluateMatchedVehicle()
    }

    private func sortDiscoveredBluetoothDevices() {
        discoveredBluetoothDevices.sort { lhs, rhs in
            let lhsAssigned = configuredVehicles.contains { $0.detectionProfile.bluetoothPeripheralIdentifier == lhs.id.uuidString }
            let rhsAssigned = configuredVehicles.contains { $0.detectionProfile.bluetoothPeripheralIdentifier == rhs.id.uuidString }
            if lhsAssigned != rhsAssigned {
                return lhsAssigned && !rhsAssigned
            }

            if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

            return lhs.firstSeen < rhs.firstSeen
        }
    }

    private func preferredBluetoothDeviceName(existing: String, latest: String) -> String {
        let existingName = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let latestName = latest.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingIsUnknown = isUnknownBluetoothDeviceName(existingName)
        let latestIsUnknown = isUnknownBluetoothDeviceName(latestName)

        if existingIsUnknown && !latestIsUnknown {
            return latestName
        }

        if !existingIsUnknown && latestIsUnknown {
            return existingName
        }

        return latestIsUnknown ? "Unknown device" : latestName
    }

    private func isUnknownBluetoothDeviceName(_ name: String) -> Bool {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.isEmpty || normalized == "unknown device"
    }

    private func reevaluateMatchedVehicle() {
        guard isDetectionEnabled else {
            if matchedVehicleID != nil {
                matchedVehicleID = nil
                onStateChanged?()
            }
            return
        }

        refreshDetectorReliabilityIssues()

        let candidateVehicles = configuredVehicles.filter { vehicle in
            let profile = vehicle.detectionProfile
            guard profile.isEnabled else {
                return false
            }

            let matchesCarPlay = profile.usesCarPlay && isCarPlayConnected
            let matchesAudioRoute = profile.usesAudioRoute
                && profile.audioRouteIdentifier.map { identifier in
                    connectedAudioRoutes.contains { $0.id == identifier }
                } == true
            let matchesBluetooth = profile.usesBluetoothPeripheral && profile.bluetoothPeripheralUUID.map { uuid in
                bluetoothDeviceIsMatched(uuid: uuid)
            } == true

            return matchesCarPlay || matchesAudioRoute || matchesBluetooth
        }

        let nextVehicleID = candidateVehicles.first?.id
        if let matchedVehicleID,
           nextVehicleID == nil,
           let matchedVehicle = configuredVehicles.first(where: { $0.id == matchedVehicleID }),
           matchedVehicle.detectionProfile.usesBluetoothPeripheral,
           let matchedUUID = matchedVehicle.detectionProfile.bluetoothPeripheralUUID,
           shouldPreserveMatchedBluetoothVehicle(for: matchedUUID) {
            onStateChanged?()
            return
        }

        if nextVehicleID != matchedVehicleID {
            matchedVehicleID = nextVehicleID
            onStateChanged?()
            return
        }

        onStateChanged?()
    }

    private func bluetoothDeviceIsMatched(uuid: UUID) -> Bool {
        guard let device = discoveredBluetoothDevices.first(where: { $0.id == uuid }) else {
            return false
        }

        let visibleDuration = device.lastSeen.timeIntervalSince(device.firstSeen)
        return device.rssi >= BluetoothMatching.minimumRSSI && visibleDuration >= BluetoothMatching.requiredVisibleDuration
    }

    private func shouldPreserveMatchedBluetoothVehicle(for uuid: UUID) -> Bool {
        guard let device = discoveredBluetoothDevices.first(where: { $0.id == uuid }) else {
            return false
        }

        return Date.now.timeIntervalSince(device.lastSeen) < BluetoothMatching.requiredAbsenceDuration
    }

    private func recordBluetoothObservation(for device: DiscoveredBluetoothDevice) {
        let normalizedName = normalizedBluetoothName(device.name)
        guard !normalizedName.isEmpty, normalizedName != "unknown device" else {
            return
        }

        let observation = BluetoothNameObservation(
            identifier: device.id,
            firstSeen: device.firstSeen,
            lastSeen: device.lastSeen
        )

        var observations = bluetoothNameObservations[normalizedName] ?? []
        if let existingIndex = observations.firstIndex(where: { $0.identifier == device.id }) {
            let existing = observations[existingIndex]
            observations[existingIndex] = BluetoothNameObservation(
                identifier: existing.identifier,
                firstSeen: existing.firstSeen,
                lastSeen: observation.lastSeen
            )
        } else {
            observations.append(observation)
        }

        bluetoothNameObservations[normalizedName] = observations
    }

    private func pruneBluetoothObservations() {
        let cutoff = Date.now.addingTimeInterval(-BluetoothMatching.unreliableRotationWindow)
        bluetoothNameObservations = bluetoothNameObservations.reduce(into: [:]) { partialResult, entry in
            let filtered = entry.value.filter { $0.lastSeen >= cutoff }
            if !filtered.isEmpty {
                partialResult[entry.key] = filtered
            }
        }
    }

    private func refreshDetectorReliabilityIssues() {
        pruneBluetoothObservations()

        detectorReliabilityIssues = configuredVehicles.compactMap { vehicle in
            let profile = vehicle.detectionProfile
            let detectorName = normalizedBluetoothName(profile.bluetoothPeripheralName)
            guard profile.isEnabled,
                  profile.usesBluetoothPeripheral,
                  !detectorName.isEmpty else {
                return nil
            }

            let observations = bluetoothNameObservations[detectorName] ?? []
            let distinctIdentifiers = Set(observations.map(\.identifier))
            let assignedIdentifier = profile.bluetoothPeripheralUUID
            let hasAssignedIdentifier = assignedIdentifier.map { distinctIdentifiers.contains($0) } ?? false
            let alternateIdentifierCount = distinctIdentifiers.subtracting(Set(assignedIdentifier.map { [$0] } ?? [])).count

            guard !hasAssignedIdentifier && alternateIdentifierCount >= BluetoothMatching.unreliableRotationCount else {
                return nil
            }

            return DetectorReliabilityIssue(
                id: vehicle.id,
                vehicleID: vehicle.id,
                detectorName: profile.bluetoothPeripheralName,
                message: "The assigned Bluetooth detector may not be reliable. Devices named \(profile.bluetoothPeripheralName) have appeared with multiple changing identifiers, which usually means rotating addresses or privacy tokens."
            )
        }
    }

    private func normalizedBluetoothName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
@Observable
final class SharedAppModel {
    static let shared = SharedAppModel()

    let store = MileageStore()
    let tripTracker = TripTracker()
    let authSession = AuthSessionManager()
    let subscriptionManager = SubscriptionManager()
    let cloudSync = CloudSyncManager()
    let maintenanceReminderManager = MaintenanceReminderManager()
    let vehicleConnectionManager = VehicleConnectionManager()
    @ObservationIgnored private var vehicleProfilesObserver: NSObjectProtocol?
    @ObservationIgnored private var detectorLossWarningTask: Task<Void, Never>?
    @ObservationIgnored private let notificationCenter = UNUserNotificationCenter.current()
    @ObservationIgnored private var hasWarnedForCurrentDetectorLoss = false
    @ObservationIgnored private var shouldNotifyWhenDetectorRestored = false
    @ObservationIgnored private var notifiedUnreliableDetectorVehicleIDs: Set<UUID> = []

    private(set) var hasLoadedPersistence = false

    private init() {
        tripTracker.shouldAllowVehicleTriggeredAutoStart = { [weak self] in
            self?.vehicleConnectionManager.canAutoStartTrip() ?? true
        }
        tripTracker.onAutoStoppedTrip = { [weak self] trip in
            guard let self else {
                return
            }

            self.store.addTrip(trip)
            self.store.addLog("Trip auto-stopped after low-speed timeout")
            self.saveCurrentSnapshot()
        }
        tripTracker.onStateChanged = { [weak self] forceWidgetReload in
            self?.refreshWidgetSnapshot(forceReload: forceWidgetReload)
            NotificationCenter.default.post(name: .meerkatTripTrackerStateDidChange, object: nil)
            self?.syncDetectorLossWarningState()
        }
        vehicleConnectionManager.onStateChanged = { [weak self] in
            self?.applyDetectedVehicleSelectionIfNeeded()
            self?.syncDetectorLossWarningState()
        }
        vehicleProfilesObserver = NotificationCenter.default.addObserver(
            forName: .meerkatVehicleProfilesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshVehicleConnectionConfiguration()
                self?.syncDetectorLossWarningState()
            }
        }
        refreshWidgetSnapshot(forceReload: true)
    }

    var isDemoModeEnabled: Bool {
        authSession.isDemoModeEnabled
    }

    var persistenceSnapshot: AppPersistenceSnapshot {
        AppPersistenceSnapshot(
            store: store.persistenceSnapshot,
            tripTracker: tripTracker.persistenceSnapshot
        )
    }

    func loadPersistedDataIfNeeded() {
        guard !hasLoadedPersistence else {
            return
        }

        defer {
            hasLoadedPersistence = true
        }

        guard let snapshot = try? AppPersistenceController.load() else {
            return
        }

        store.applyPersistenceSnapshot(snapshot.store)
        tripTracker.applyPersistenceSnapshot(snapshot.tripTracker)
        refreshVehicleConnectionConfiguration()
        refreshWidgetSnapshot(forceReload: true)
    }

    func loadPersistedDataIfNeededAsync() async {
        guard !hasLoadedPersistence else {
            return
        }

        let snapshot = await Task.detached(priority: .userInitiated) {
            try? AppPersistenceController.load()
        }.value

        guard !hasLoadedPersistence else {
            return
        }

        hasLoadedPersistence = true

        guard let snapshot else {
            return
        }

        store.applyPersistenceSnapshot(snapshot.store)
        tripTracker.applyPersistenceSnapshot(snapshot.tripTracker)
        refreshVehicleConnectionConfiguration()
        if await store.repairHistoricalTripAddressesIfNeeded() {
            saveCurrentSnapshot()
        }
        refreshWidgetSnapshot(forceReload: true)
    }

    func prepareForLocationRelaunch() {
        loadPersistedDataIfNeeded()
        tripTracker.canRecordTrips = store.isReadyToDrive
        refreshVehicleConnectionConfiguration()
        tripTracker.resumeBackgroundMonitoringAfterSystemLaunch()
        refreshWidgetSnapshot(forceReload: true)
    }

    func saveCurrentSnapshot() {
        guard hasLoadedPersistence else {
            return
        }

        do {
            try AppPersistenceController.save(persistenceSnapshot)
        } catch {
            print("Failed to save app data: \(error.localizedDescription)")
        }
        refreshWidgetSnapshot()
    }

    func persistAndSyncNowIfPossible() {
        saveCurrentSnapshot()

        guard authSession.canUseCloudSyncFeatures else {
            return
        }

        let snapshot = persistenceSnapshot
        cloudSync.markLocalSnapshotDirty(snapshot)
        Task {
            await cloudSync.syncLocalChanges(snapshot: snapshot)
        }
    }

    func repairRecentTripAddressesAndSyncIfNeeded() async {
        guard hasLoadedPersistence else {
            return
        }

        guard await store.repairRecentTripAddressesIfNeeded() else {
            return
        }

        saveCurrentSnapshot()

        guard authSession.canUseCloudSyncFeatures else {
            return
        }

        let snapshot = persistenceSnapshot
        cloudSync.markLocalSnapshotDirty(snapshot)
        await cloudSync.syncLocalChanges(snapshot: snapshot)
    }

    func applyRestoredSnapshot(_ snapshot: AppPersistenceSnapshot) {
        store.applyPersistenceSnapshot(snapshot.store)
        tripTracker.applyPersistenceSnapshot(snapshot.tripTracker)
        tripTracker.canRecordTrips = store.isReadyToDrive
        refreshVehicleConnectionConfiguration()
        hasLoadedPersistence = true

        do {
            try AppPersistenceController.save(snapshot)
        } catch {
            print("Failed to save restored snapshot: \(error.localizedDescription)")
        }
        refreshWidgetSnapshot(forceReload: true)
    }

    func factoryResetAppData() {
        tripTracker.resetForFactoryReset()
        store.applyPersistenceSnapshot(AppPersistenceSnapshot.empty.store)
        store.isDemoModeEnabled = false
        tripTracker.applyPersistenceSnapshot(AppPersistenceSnapshot.empty.tripTracker)
        tripTracker.canRecordTrips = false
        refreshVehicleConnectionConfiguration()
        authSession.factoryReset()
        cloudSync.resetSession()

        do {
            try AppPersistenceController.deletePersistedSnapshot()
        } catch {
            print("Failed to delete persisted app data: \(error.localizedDescription)")
        }

        hasLoadedPersistence = true
        WidgetBridge.clear()
    }

    func clearRecordedAppData() {
        tripTracker.resetForFactoryReset()
        store.clearRecordedData()
        tripTracker.canRecordTrips = store.isReadyToDrive
        hasLoadedPersistence = true

        Task {
            await maintenanceReminderManager.clearScheduledNotifications()
        }

        persistAndSyncNowIfPossible()
        WidgetBridge.clear()
        refreshWidgetSnapshot(forceReload: true)
    }

    func deleteCurrentAccount() async throws {
        loadPersistedDataIfNeeded()

        if authSession.canUseCloudSyncFeatures {
            try await cloudSync.deleteAccountDataFromCloud()
        }

        tripTracker.resetForFactoryReset()
        store.applyPersistenceSnapshot(AppPersistenceSnapshot.empty.store)
        store.isDemoModeEnabled = false
        tripTracker.applyPersistenceSnapshot(AppPersistenceSnapshot.empty.tripTracker)
        tripTracker.canRecordTrips = false

        do {
            try AppPersistenceController.deletePersistedSnapshot()
        } catch {
            print("Failed to delete persisted app data: \(error.localizedDescription)")
        }

        if authSession.isEmailPasswordAuthenticated {
            authSession.deleteEmailPasswordAccount()
        } else {
            authSession.signOut()
        }

        cloudSync.resetSession()
        hasLoadedPersistence = true
        WidgetBridge.clear()
    }

    func enterDemoMode() {
        let snapshot = demoSnapshot()
        authSession.enableDemoMode()
        cloudSync.resetSession()
        tripTracker.resetForFactoryReset()
        store.applyPersistenceSnapshot(snapshot.store)
        store.isDemoModeEnabled = true
        tripTracker.applyPersistenceSnapshot(snapshot.tripTracker)
        tripTracker.canRecordTrips = store.isReadyToDrive
        hasLoadedPersistence = true
        saveCurrentSnapshot()
        refreshWidgetSnapshot(forceReload: true)
    }

    func exitDemoMode() {
        authSession.disableDemoMode()
        tripTracker.resetForFactoryReset()
        store.applyPersistenceSnapshot(AppPersistenceSnapshot.empty.store)
        store.isDemoModeEnabled = false
        tripTracker.applyPersistenceSnapshot(AppPersistenceSnapshot.empty.tripTracker)
        tripTracker.canRecordTrips = false
        hasLoadedPersistence = true

        do {
            try AppPersistenceController.deletePersistedSnapshot()
        } catch {
            print("Failed to delete demo app data: \(error.localizedDescription)")
        }

        WidgetBridge.clear()
        refreshWidgetSnapshot(forceReload: true)
    }

    private func demoSnapshot() -> AppPersistenceSnapshot {
        let vehicleID = UUID()
        let driverID = UUID()
        let calendar = Calendar.current
        let vehicle = VehicleProfile(
            id: vehicleID,
            profileName: "Demo Vehicle",
            make: "Toyota",
            model: "Corolla",
            color: "Silver",
            numberPlate: "DEMO-123",
            startingOdometerReading: 12_450,
            ownershipType: .personal
        )
        let driver = DriverProfile(
            id: driverID,
            name: "Demo Driver",
            dateOfBirth: calendar.date(byAdding: .year, value: -34, to: .now) ?? .now,
            licenceNumber: "D1234567"
        )

        let trips = [
            Trip(
                name: "Client Visit",
                type: .business,
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                driverID: driverID,
                driverName: driver.name,
                driverDateOfBirth: driver.dateOfBirth,
                driverLicenceNumber: driver.licenceNumber,
                startAddress: "101 Main Street",
                endAddress: "250 Market Avenue",
                details: "Met with a customer to review a service quote.",
                odometerStart: 12_450,
                odometerEnd: 12_468,
                distanceMeters: 28_968,
                duration: 1_920,
                date: calendar.date(byAdding: .day, value: -5, to: .now) ?? .now,
                manuallyEntered: true
            ),
            Trip(
                name: "Supply Run",
                type: .business,
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                driverID: driverID,
                driverName: driver.name,
                driverDateOfBirth: driver.dateOfBirth,
                driverLicenceNumber: driver.licenceNumber,
                startAddress: "250 Market Avenue",
                endAddress: "18 Industrial Road",
                details: "Collected shop supplies and printed materials.",
                odometerStart: 12_468,
                odometerEnd: 12_479,
                distanceMeters: 17_702,
                duration: 1_260,
                date: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now,
                manuallyEntered: true
            ),
            Trip(
                name: "Home Commute",
                type: .personal,
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                driverID: driverID,
                driverName: driver.name,
                driverDateOfBirth: driver.dateOfBirth,
                driverLicenceNumber: driver.licenceNumber,
                startAddress: "18 Industrial Road",
                endAddress: "44 Lake Drive",
                details: "",
                odometerStart: 12_479,
                odometerEnd: 12_491,
                distanceMeters: 19_312,
                duration: 1_500,
                date: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
                manuallyEntered: true
            )
        ]

        let fuelEntries = [
            FuelEntry(
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                station: "Shell Downtown",
                volume: 31.4,
                totalCost: 46.20,
                odometer: 12_460,
                date: calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
            ),
            FuelEntry(
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                station: "BP Highway",
                volume: 28.6,
                totalCost: 42.90,
                odometer: 12_476,
                date: calendar.date(byAdding: .day, value: -4, to: .now) ?? .now
            ),
            FuelEntry(
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                station: "Chevron West",
                volume: 30.1,
                totalCost: 45.35,
                odometer: 12_490,
                date: calendar.date(byAdding: .day, value: -1, to: .now) ?? .now
            )
        ]

        let maintenanceRecords = [
            MaintenanceRecord(
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                shopName: "Quick Lube",
                odometer: 12_430,
                date: calendar.date(byAdding: .day, value: -20, to: .now) ?? .now,
                type: .oilChange,
                notes: "Synthetic oil service completed.",
                totalCost: 79.99,
                reminderEnabled: true,
                nextServiceOdometer: 17_430,
                nextServiceDate: calendar.date(byAdding: .month, value: 6, to: .now)
            ),
            MaintenanceRecord(
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                shopName: "Brake & Tire",
                odometer: 12_200,
                date: calendar.date(byAdding: .day, value: -45, to: .now) ?? .now,
                type: .tyres,
                notes: "Rotation and pressure check.",
                totalCost: 54.50
            ),
            MaintenanceRecord(
                vehicleID: vehicleID,
                vehicleProfileName: vehicle.displayName,
                shopName: "City Garage",
                odometer: 12_350,
                date: calendar.date(byAdding: .day, value: -12, to: .now) ?? .now,
                type: .scheduledMaintenance,
                notes: "Annual inspection and fluid top-up.",
                totalCost: 139.00
            )
        ]

        return AppPersistenceSnapshot(
            store: MileageStore.PersistenceSnapshot(
                selectedCountry: .usa,
                userName: "Demo Driver",
                emailAddress: "",
                preferredCurrency: .usd,
                unitSystem: .miles,
                fuelVolumeUnit: .gallons,
                fuelEconomyFormat: .milesPerGallon,
            preventAutoLock: false,
            vehicleDetectionEnabled: false,
            hasCompletedOnboarding: true,
            hasAcceptedPrivacyPolicy: true,
            hasAcceptedLegalNotice: true,
            organizations: [],
            activeOrganizationID: nil,
            organizationMemberships: [],
            vehicles: [vehicle],
            activeVehicleID: vehicleID,
            drivers: [driver],
                activeDriverID: driverID,
                trips: trips,
                fuelEntries: fuelEntries,
                maintenanceRecords: maintenanceRecords,
                logs: [
                    LogEntry(title: "Demo mode started", date: .now),
                    LogEntry(title: "Sample trip, fuel, and maintenance records loaded", date: .now)
                ],
                allowanceAdjustments: []
            ),
            tripTracker: TripTracker.PersistenceSnapshot(
                autoStartEnabled: true,
                backgroundTripTrackingEnabled: true,
                motionActivityEnabled: true,
                autoStartSpeedThresholdKilometersPerHour: 10,
                autoStopDelayMinutes: 10,
                selectedTripType: .business
            )
        )
    }

    func handleIncomingURL(_ url: URL) {
        #if canImport(GoogleSignIn)
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }
        #endif

        guard url.scheme == WidgetBridge.urlScheme else {
            return
        }

        loadPersistedDataIfNeeded()

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {
        case "trip-type":
            guard let value = components?.queryItems?.first(where: { $0.name == "value" })?.value,
                  let tripType = TripType(rawValue: value) else {
                return
            }

            Task { @MainActor in
                let currentOdometer = store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
                if let completedTrip = await tripTracker.selectTripType(
                    tripType,
                    nextTripStartOdometerReading: currentOdometer,
                    completedTripEndOdometerReading: currentOdometer
                ) {
                    store.addTrip(completedTrip)
                }
                persistAndSyncNowIfPossible()
                refreshWidgetSnapshot(forceReload: true)
            }

        case "trip-recording":
            guard let action = components?.queryItems?.first(where: { $0.name == "action" })?.value else {
                return
            }

            Task { @MainActor in
                let currentOdometer = store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)

                switch action {
                case "start":
                    if !tripTracker.isTracking {
                        tripTracker.startTracking(startOdometerReading: store.currentBaseOdometerReading())
                    }

                case "stop":
                    if tripTracker.isTracking,
                       let trip = await tripTracker.stopTracking(endOdometerReading: currentOdometer) {
                        store.addTrip(trip)
                    }

                case "toggle":
                    if tripTracker.isTracking {
                        if let trip = await tripTracker.stopTracking(endOdometerReading: currentOdometer) {
                            store.addTrip(trip)
                        }
                    } else {
                        tripTracker.startTracking(startOdometerReading: store.currentBaseOdometerReading())
                    }

                default:
                    return
                }

                persistAndSyncNowIfPossible()
                refreshWidgetSnapshot(forceReload: true)
            }

        default:
            break
        }
    }

    func refreshWidgetSnapshot(forceReload: Bool = false) {
        let unitLabel = store.unitSystem == .miles ? "mi" : "km"
        let currentOdometer = store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
        let snapshot = AppWidgetSnapshot(
            lastUpdated: .now,
            isRecording: tripTracker.isTracking,
            tripTypeRawValue: tripTracker.selectedTripType.rawValue,
            tripTypeTitle: tripTracker.selectedTripType.title,
            speedText: store.unitSystem.speedString(for: tripTracker.currentSpeed),
            distanceText: store.unitSystem.distanceString(for: tripTracker.currentTripDistance),
            elapsedText: tripTracker.elapsedTimeString,
            elapsedTimeInterval: tripTracker.elapsedTime,
            tripStartDate: tripTracker.currentTripStartDate,
            odometerText: "\(currentOdometer.formatted(.number.precision(.fractionLength(1)))) \(unitLabel)",
            vehicleName: store.activeVehicle?.displayName ?? "No vehicle selected",
            driverName: store.activeDriver?.name ?? "No driver selected",
            statusText: tripTracker.recordingStatusText(unitSystem: store.unitSystem)
        )
        WidgetBridge.save(snapshot: snapshot, forceReload: forceReload)
    }

    func refreshVehicleConnectionConfiguration() {
        vehicleConnectionManager.isDetectionEnabled = store.vehicleDetectionEnabled
        vehicleConnectionManager.refreshConfiguredVehicles(store.vehicles)
        tripTracker.requiresDetectedVehicleForAutoStart = vehicleConnectionManager.requiresVehicleSignalForAutoStart
        applyDetectedVehicleSelectionIfNeeded()
        syncDetectorLossWarningState()
    }

    private func applyDetectedVehicleSelectionIfNeeded() {
        if let matchedVehicleID = vehicleConnectionManager.matchedVehicleID,
           store.activeVehicleID != matchedVehicleID {
            store.activeVehicleID = matchedVehicleID
        }

        tripTracker.requiresDetectedVehicleForAutoStart = vehicleConnectionManager.requiresVehicleSignalForAutoStart
        notifyAssignedDetectorReliabilityIssuesIfNeeded()
    }

    private func syncDetectorLossWarningState() {
        let shouldWatchForLoss =
            tripTracker.isTracking &&
            store.vehicleDetectionEnabled &&
            vehicleConnectionManager.requiresVehicleSignalForAutoStart

        if !shouldWatchForLoss {
            detectorLossWarningTask?.cancel()
            detectorLossWarningTask = nil
            hasWarnedForCurrentDetectorLoss = false
            shouldNotifyWhenDetectorRestored = false
            notifiedUnreliableDetectorVehicleIDs = []
            return
        }

        if vehicleConnectionManager.matchedVehicleID != nil {
            detectorLossWarningTask?.cancel()
            detectorLossWarningTask = nil
            if shouldNotifyWhenDetectorRestored {
                shouldNotifyWhenDetectorRestored = false
                hasWarnedForCurrentDetectorLoss = false
                Task { [weak self] in
                    await self?.notifyDetectorConnectionRestoredIfNeeded()
                }
                return
            }

            hasWarnedForCurrentDetectorLoss = false
            return
        }

        guard detectorLossWarningTask == nil, !hasWarnedForCurrentDetectorLoss else {
            return
        }

        detectorLossWarningTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            await self?.notifyDetectorConnectionLossIfNeeded()
        }
    }

    private func notifyDetectorConnectionLossIfNeeded() async {
        detectorLossWarningTask = nil

        guard tripTracker.isTracking,
              store.vehicleDetectionEnabled,
              vehicleConnectionManager.requiresVehicleSignalForAutoStart,
              vehicleConnectionManager.matchedVehicleID == nil,
              !hasWarnedForCurrentDetectorLoss else {
            return
        }

        hasWarnedForCurrentDetectorLoss = true
        shouldNotifyWhenDetectorRestored = true
        store.addLog("Vehicle detector connection lost for more than 1 minute during an active trip")
        await requestNotificationAuthorizationIfPossible()

        let content = UNMutableNotificationContent()
        content.title = "Check vehicle connection"
        content.body = "Meerkat lost the vehicle Bluetooth/CarPlay connection during this trip. Recording continues, but make sure the connection is restored before this trip ends or before the next trip starts."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "vehicle-detector-connection-warning",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            store.addLog("Failed to schedule detector loss notification: \(error.localizedDescription)")
        }
    }

    private func notifyDetectorConnectionRestoredIfNeeded() async {
        guard tripTracker.isTracking else {
            return
        }

        store.addLog("Vehicle detector connection restored during active trip")
        await requestNotificationAuthorizationIfPossible()

        let content = UNMutableNotificationContent()
        content.title = "Vehicle connection restored"
        content.body = "Meerkat detected that the vehicle Bluetooth/CarPlay connection is working again. Trip recording continues normally."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "vehicle-detector-connection-restored",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            store.addLog("Failed to schedule detector restored notification: \(error.localizedDescription)")
        }
    }

    private func requestNotificationAuthorizationIfPossible() async {
        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            store.addLog("Notification permission request failed: \(error.localizedDescription)")
        }
    }

    private func notifyAssignedDetectorReliabilityIssuesIfNeeded() {
        let newIssues = vehicleConnectionManager.detectorReliabilityIssues.filter {
            !notifiedUnreliableDetectorVehicleIDs.contains($0.vehicleID)
        }

        guard !newIssues.isEmpty else {
            return
        }

        for issue in newIssues {
            notifiedUnreliableDetectorVehicleIDs.insert(issue.vehicleID)
            store.addLog("Bluetooth detector may be unreliable for vehicle \(issue.vehicleID.uuidString)")
            Task { [weak self] in
                await self?.sendUnreliableDetectorNotification(for: issue)
            }
        }
    }

    private func sendUnreliableDetectorNotification(
        for issue: VehicleConnectionManager.DetectorReliabilityIssue
    ) async {
        await requestNotificationAuthorizationIfPossible()

        let content = UNMutableNotificationContent()
        content.title = "Bluetooth detector may be unreliable"
        content.body = "\(issue.message) Reliable alternatives: dedicated BLE beacon, iBeacon-compatible tag, USB-powered BLE beacon, or CarPlay plus a stable BLE beacon."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "vehicle-detector-unreliable-\(issue.vehicleID.uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await notificationCenter.add(request)
        } catch {
            store.addLog("Failed to schedule unreliable detector notification: \(error.localizedDescription)")
        }
    }
}

final class MeerkatAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            // Restore persisted trip tracking state at launch without depending on the
            // deprecated location launch option key.
            SharedAppModel.shared.prepareForLocationRelaunch()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )

        // Register the CarPlay scene in code so the app can attach the correct delegate
        // whenever the signed build includes the managed CarPlay entitlement.
        if connectingSceneSession.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
            configuration.sceneClass = CPTemplateApplicationScene.self
            configuration.delegateClass = MeerkatCarPlaySceneDelegate.self
        }
        else if connectingSceneSession.role.rawValue == "CPTemplateApplicationInstrumentClusterSceneSessionRoleApplication" {
            configuration.sceneClass = CPTemplateApplicationInstrumentClusterScene.self
            configuration.delegateClass = MeerkatCarPlayInstrumentClusterSceneDelegate.self
        }

        return configuration
    }
}

@MainActor
@Observable
final class MeerkatCarPlayClusterTelemetryModel {
    var isTracking = false
    var speedText = "0 mph"
    var speedValue = 0.0
    var speedMaximum = 120.0
    var tripTypeText = TripType.business.title
    var tripDistanceText = "0.0 mi"
    var odometerText = "0.0 mi"
    var elapsedText = "00:00:00"
    var statusText = "Ready"
    var vehicleText = "No vehicle selected"
    var driverText = "No driver selected"

    var speedProgress: Double {
        guard speedMaximum > 0 else {
            return 0
        }
        return min(max(speedValue / speedMaximum, 0), 1)
    }

    func refresh(from appModel: SharedAppModel) {
        let store = appModel.store
        let tripTracker = appModel.tripTracker
        let currentOdometer = store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
        let displayedSpeed = store.unitSystem.convertedDistance(for: max(tripTracker.currentSpeed, 0) * 3_600)

        isTracking = tripTracker.isTracking
        speedText = store.unitSystem.speedString(for: tripTracker.currentSpeed)
        speedValue = displayedSpeed
        speedMaximum = store.unitSystem == .miles ? 120 : 200
        tripTypeText = tripTracker.selectedTripType.title
        tripDistanceText = store.unitSystem.distanceString(for: tripTracker.currentTripDistance)
        odometerText = "\(currentOdometer.formatted(.number.precision(.fractionLength(1)))) \(store.unitSystem == .miles ? "mi" : "km")"
        elapsedText = tripTracker.elapsedTimeString
        statusText = tripTracker.recordingStatusText(unitSystem: store.unitSystem)
        vehicleText = store.activeVehicle?.displayName ?? "No vehicle selected"
        driverText = store.activeDriver?.name ?? "No driver selected"
    }
}

private struct MeerkatCarPlayClusterTelemetryView: View {
    @Bindable var model: MeerkatCarPlayClusterTelemetryModel

    var body: some View {
        ZStack {
            backgroundView
                .ignoresSafeArea()

            VStack(spacing: 12) {
                statusRow

                gaugeView

                HStack(spacing: 10) {
                    telemetryPill(title: "Trip", value: model.tripTypeText, emphasis: model.tripTypeText)
                    telemetryPill(title: "Distance", value: model.tripDistanceText, emphasis: nil)
                    telemetryPill(title: "Odometer", value: model.odometerText, emphasis: nil)
                    telemetryPill(title: "Elapsed", value: model.elapsedText, emphasis: nil)
                }

                Text("\(model.vehicleText) • \(model.driverText)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.07, green: 0.08, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.15, blue: 0.20).opacity(0.45),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 320
            )
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Label(model.isTracking ? "Recording" : "Ready", systemImage: model.isTracking ? "record.circle.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.isTracking ? Color.green : Color.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.09))
                )

            Text(model.statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var gaugeView: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let angle = -120.0 + (240.0 * model.speedProgress)
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.42))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Circle()
                    .trim(from: 0.17, to: 0.83)
                    .stroke(Color.white.opacity(0.14), lineWidth: 12)
                    .rotationEffect(.degrees(90))

                Circle()
                    .trim(from: 0.17, to: 0.17 + (0.66 * model.speedProgress))
                    .stroke(
                        AngularGradient(
                            colors: [Color.cyan, Color.green, Color.yellow, Color.orange, Color.red],
                            center: .center,
                            startAngle: .degrees(-120),
                            endAngle: .degrees(120)
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))

                ForEach(0 ..< 61, id: \.self) { tick in
                    let isMajorTick = tick.isMultiple(of: 5)
                    let normalized = Double(tick) / 60.0
                    let tickAngle = -120.0 + (normalized * 240.0)
                    Capsule(style: .continuous)
                        .fill(isMajorTick ? Color.white.opacity(0.85) : Color.white.opacity(0.35))
                        .frame(width: isMajorTick ? 2.6 : 1.5, height: isMajorTick ? 10 : 5)
                        .offset(y: -(size * 0.39))
                        .rotationEffect(.degrees(tickAngle))
                }

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4.5, height: size * 0.30)
                    .offset(y: -(size * 0.15))
                    .rotationEffect(.degrees(angle))
                    .shadow(color: Color.red.opacity(0.35), radius: 6, x: 0, y: 0)

                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)

                VStack(spacing: 3) {
                    Text(model.speedText)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(model.speedMaximum >= 190 ? "KM/H" : "MPH")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(height: 230)
    }

    private func telemetryPill(title: String, value: String, emphasis: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.58))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasisColor(for: emphasis))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func emphasisColor(for value: String?) -> Color {
        guard let value else {
            return .white
        }

        if value.caseInsensitiveCompare("Business") == .orderedSame {
            return Color.orange
        }
        if value.caseInsensitiveCompare("Personal") == .orderedSame {
            return Color.cyan
        }
        return .white
    }
}

@MainActor
final class MeerkatCarPlayInstrumentClusterSceneDelegate: UIResponder, CPTemplateApplicationInstrumentClusterSceneDelegate, CPInstrumentClusterControllerDelegate {
    private let appModel = SharedAppModel.shared
    private let telemetryModel = MeerkatCarPlayClusterTelemetryModel()
    private var instrumentClusterController: CPInstrumentClusterController?
    private var stateObserver: NSObjectProtocol?
    private var refreshTask: Task<Void, Never>?
    private weak var instrumentClusterWindow: UIWindow?
    private var hostingController: UIHostingController<MeerkatCarPlayClusterTelemetryView>?

    func templateApplicationInstrumentClusterScene(
        _ templateApplicationInstrumentClusterScene: CPTemplateApplicationInstrumentClusterScene,
        didConnect instrumentClusterController: CPInstrumentClusterController
    ) {
        self.instrumentClusterController = instrumentClusterController
        instrumentClusterController.delegate = self

        // Ensure cluster can render with locally persisted data immediately.
        appModel.loadPersistedDataIfNeeded()

        registerStateObserver()
        startRefreshLoop()
        refreshTelemetry()

        if let window = instrumentClusterController.instrumentClusterWindow {
            attachClusterWindow(window)
        }
    }

    func templateApplicationInstrumentClusterScene(
        _ templateApplicationInstrumentClusterScene: CPTemplateApplicationInstrumentClusterScene,
        didDisconnectInstrumentClusterController instrumentClusterController: CPInstrumentClusterController
    ) {
        cleanup()
    }

    func instrumentClusterControllerDidConnect(_ instrumentClusterWindow: UIWindow) {
        attachClusterWindow(instrumentClusterWindow)
    }

    func instrumentClusterControllerDidDisconnectWindow(_ instrumentClusterWindow: UIWindow) {
        if self.instrumentClusterWindow === instrumentClusterWindow {
            self.instrumentClusterWindow = nil
            self.hostingController = nil
        }
    }

    private func attachClusterWindow(_ window: UIWindow) {
        instrumentClusterWindow = window
        let rootView = MeerkatCarPlayClusterTelemetryView(model: telemetryModel)
        let controller = UIHostingController(rootView: rootView)
        controller.view.backgroundColor = .clear
        window.rootViewController = controller
        window.isHidden = false
        hostingController = controller
    }

    private func registerStateObserver() {
        stateObserver = NotificationCenter.default.addObserver(
            forName: .meerkatTripTrackerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTelemetry()
            }
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.refreshTelemetry()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refreshTelemetry() {
        telemetryModel.refresh(from: appModel)
    }

    private func cleanup() {
        refreshTask?.cancel()
        refreshTask = nil
        if let stateObserver {
            NotificationCenter.default.removeObserver(stateObserver)
            self.stateObserver = nil
        }
        instrumentClusterController?.delegate = nil
        instrumentClusterController = nil
        instrumentClusterWindow = nil
        hostingController = nil
    }
}

@MainActor
final class MeerkatCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private enum Constants {
        static let fuelLitersPresets: [Double] = [20, 30, 40, 50, 60, 70, 80, 90, 100]
        static let fuelGallonsPresets: [Double] = [5, 8, 10, 12, 15, 18, 20, 25, 30]
        static let fuelAmountPresets: [Double] = [20, 30, 40, 50, 60, 80, 100, 120, 150]
        static let dashboardRefreshInterval: TimeInterval = 8
    }

    private enum TripOdometerField {
        case start
        case end

        var title: String {
            switch self {
            case .start:
                return "Start Odometer"
            case .end:
                return "End Odometer"
            }
        }
    }

    private let appModel = SharedAppModel.shared
    private var interfaceController: CPInterfaceController?
    private var draftTripEndOdometer: Double?
    private var selectedFuelVolume: Double?
    private var selectedFuelPaidAmount: Double?
    private var draftFuelOdometer: Double?
    private var draftTripEditorOdometer: Double?
    private var tripStateObserver: NSObjectProtocol?
    private var rootTabBarTemplate: CPTabBarTemplate?
    private var needsRootTemplateRefresh = false
    private var odometerAdjustmentTemplate: CPListTemplate?
    private var odometerAdjustmentValueItem: CPListItem?
    private var pendingDashboardRefreshTask: Task<Void, Never>?
    private var lastDashboardRefreshDate: Date = .distantPast

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        appModel.vehicleConnectionManager.isCarPlayConnected = true
        tripStateObserver = NotificationCenter.default.addObserver(
            forName: .meerkatTripTrackerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTripTrackerStateDidChange()
            }
        }

        // Avoid leaving CarPlay blank while background hydration/repair tasks run.
        // Load local persisted state immediately and render the real dashboard first.
        interfaceController.setRootTemplate(makeLoadingTemplate(), animated: false, completion: nil)
        appModel.loadPersistedDataIfNeeded()
        refreshRootTemplate(animated: false)

        // Run the async load path in case this scene connected before local data was available.
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.appModel.loadPersistedDataIfNeededAsync()
            self.refreshRootTemplate(animated: false)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
        appModel.vehicleConnectionManager.isCarPlayConnected = false
        rootTabBarTemplate = nil
        needsRootTemplateRefresh = false
        odometerAdjustmentTemplate = nil
        odometerAdjustmentValueItem = nil
        pendingDashboardRefreshTask?.cancel()
        pendingDashboardRefreshTask = nil
        lastDashboardRefreshDate = .distantPast
        if let tripStateObserver {
            NotificationCenter.default.removeObserver(tripStateObserver)
            self.tripStateObserver = nil
        }
    }

    private var store: MileageStore { appModel.store }
    private var tripTracker: TripTracker { appModel.tripTracker }

    private var currentOdometer: Double {
        store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
    }

    private var isCarPlayStationary: Bool {
        abs(tripTracker.currentSpeed) < 0.75
    }

    private var allowanceSummary: AllowanceBalanceSummary? {
        store.allowanceBalanceSummary(for: store.activeVehicleID)
    }

    private var taxYearSummary: TaxYearStatusSummary {
        store.taxYearStatusSummary(vehicleID: store.activeVehicleID)
    }

    private var nextMaintenanceReminder: MaintenanceRecord? {
        store.nextMaintenanceReminder(currentOdometer: currentOdometer)
    }

    private var currentOdometerReadingText: String {
        "\(Int((draftTripEndOdometer ?? currentOdometer).rounded())) \(store.unitSystem == .miles ? "mi" : "km")"
    }

    private func refreshRootTemplate(animated: Bool = true) {
        guard let interfaceController else {
            return
        }

        pendingDashboardRefreshTask?.cancel()
        pendingDashboardRefreshTask = nil
        lastDashboardRefreshDate = .now

        if interfaceController.topTemplate !== interfaceController.rootTemplate {
            needsRootTemplateRefresh = true
            return
        }

        let rootTemplates = makeRootTemplates()

        if let rootTabBarTemplate,
           interfaceController.rootTemplate === rootTabBarTemplate {
            rootTabBarTemplate.updateTemplates(rootTemplates)
            needsRootTemplateRefresh = false
            return
        }

        let template = CPTabBarTemplate(templates: rootTemplates)
        rootTabBarTemplate = template
        needsRootTemplateRefresh = false
        interfaceController.setRootTemplate(template, animated: animated, completion: nil)
    }

    private var isDashboardTabSelected: Bool {
        rootTabBarTemplate?.selectedTemplate?.tabTitle == "Dashboard"
    }

    private func handleTripTrackerStateDidChange() {
        guard let interfaceController else {
            return
        }

        guard interfaceController.topTemplate === interfaceController.rootTemplate else {
            needsRootTemplateRefresh = true
            return
        }

        guard isDashboardTabSelected else {
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastDashboardRefreshDate)
        if elapsed >= Constants.dashboardRefreshInterval {
            refreshRootTemplate(animated: false)
            return
        }

        guard pendingDashboardRefreshTask == nil else {
            return
        }

        let remainingDelay = max(Constants.dashboardRefreshInterval - elapsed, 0.25)
        pendingDashboardRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
            guard let self else {
                return
            }

            self.pendingDashboardRefreshTask = nil

            guard let interfaceController = self.interfaceController,
                  interfaceController.topTemplate === interfaceController.rootTemplate,
                  self.isDashboardTabSelected
            else {
                return
            }

            self.refreshRootTemplate(animated: false)
        }
    }

    private func refreshRootTemplateIfNeeded(animated: Bool = true) {
        guard needsRootTemplateRefresh else {
            return
        }

        refreshRootTemplate(animated: animated)
    }

    private func makeRootTemplates() -> [CPTemplate] {
        let dashboardTemplate = makeDashboardTemplate()
        dashboardTemplate.tabTitle = "Dashboard"
        dashboardTemplate.tabImage = UIImage(systemName: "rectangle.grid.2x2")

        let tripTemplate = makeTripsHubTemplate()
        tripTemplate.tabTitle = "Trips"
        tripTemplate.tabImage = UIImage(systemName: "car.fill")

        let fuelTemplate = makeFuelHubTemplate()
        fuelTemplate.tabTitle = "Fuel"
        fuelTemplate.tabImage = UIImage(systemName: "fuelpump.fill")

        let rootTemplates: [CPTemplate] = [dashboardTemplate, tripTemplate, fuelTemplate]
        return Array(rootTemplates.prefix(CPTabBarTemplate.maximumTabCount))
    }

    private func makeDashboardTemplate() -> CPInformationTemplate {
        let items = [
            CPInformationItem(
                title: "Trip",
                detail: "\(tripTracker.recordingStatusText(unitSystem: store.unitSystem)) • \(tripTracker.selectedTripType.title)"
            ),
            CPInformationItem(
                title: "Odometer",
                detail: "\(Int(currentOdometer.rounded())) \(store.unitSystem == .miles ? "mi" : "km")"
            ),
            CPInformationItem(
                title: "Current Speed",
                detail: store.unitSystem.speedString(for: tripTracker.currentSpeed)
            ),
            CPInformationItem(
                title: "Distance Traveled",
                detail: store.unitSystem.distanceString(for: tripTracker.currentTripDistance)
            ),
            CPInformationItem(
                title: "Elapsed",
                detail: tripTracker.elapsedTimeString
            ),
            CPInformationItem(
                title: "Vehicle / Driver",
                detail: "\(store.activeVehicle?.displayName ?? "Not selected") • \(store.activeDriver?.name ?? "Not selected")"
            )
        ]

        let recordingButton = CPTextButton(
            title: tripTracker.isTracking ? "End Trip" : "Start Trip",
            textStyle: .confirm
        ) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                await self.toggleRecordingFromCarPlay()
            }
        }

        let adjustOdometerButton = CPTextButton(
            title: "Adjust Odo",
            textStyle: .normal
        ) { [weak self] _ in
            self?.showOdometerAdjustmentTemplate()
        }

        let businessButton = CPTextButton(
            title: "Business",
            textStyle: tripTracker.selectedTripType == .business ? .confirm : .normal
        ) { [weak self] _ in
            guard let self else {
                return
            }

            let nextTripType: TripType = self.tripTracker.selectedTripType == .business ? .personal : .business
            self.applyTripTypeSelection(nextTripType)
        }

        let personalButton = CPTextButton(
            title: "Personal",
            textStyle: tripTracker.selectedTripType == .personal ? .confirm : .normal
        ) { [weak self] _ in
            self?.applyTripTypeSelection(.personal)
        }

        let actions = tripTracker.isTracking
            ? [recordingButton, adjustOdometerButton, businessButton, personalButton]
            : [recordingButton, businessButton, personalButton]

        return CPInformationTemplate(
            title: "Dashboard",
            layout: .twoColumn,
            items: items,
            actions: actions
        )
    }

    private func makeTripsHubTemplate() -> CPListTemplate {
        let statusItem = CPListItem(
            text: isCarPlayStationary ? "Recent Trips" : "Trip Review Locked",
            detailText: isCarPlayStationary
                ? "Open a recent trip to review, edit, or delete it."
                : "Trip review and editing are available only when the vehicle is stopped."
        )
        statusItem.isEnabled = false

        let tripItems: [CPListItem]
        if store.trips.isEmpty {
            let emptyItem = CPListItem(text: "No recent trips", detailText: "Completed trips will appear here.")
            emptyItem.isEnabled = false
            tripItems = [emptyItem]
        } else {
            tripItems = Array(store.trips.prefix(12)).map { trip in
                let item = CPListItem(
                    text: trip.name,
                    detailText: "\(trip.date.formatted(date: .abbreviated, time: .shortened)) • \(trip.type.title) • \(store.unitSystem.distanceString(for: trip.distanceMeters))"
                )
                item.isEnabled = isCarPlayStationary
                item.accessoryType = isCarPlayStationary ? .disclosureIndicator : .none
                item.handler = { [weak self] _, completion in
                    self?.showTripDetailTemplate(for: trip.id)
                    completion()
                }
                return item
            }
        }

        return CPListTemplate(
            title: "Trips",
            sections: [
                CPListSection(items: [statusItem]),
                CPListSection(items: tripItems)
            ]
        )
    }

    private func makeFuelHubTemplate() -> CPInformationTemplate {
        let items = [
            CPInformationItem(
                title: "Fuel Economy",
                detail: store.monthlyAverageFuelEconomyText
            ),
            CPInformationItem(
                title: store.currentTaxYearLabel,
                detail: store.currencyString(for: store.currentTaxYearFuelSpend)
            ),
            CPInformationItem(
                title: "Average Fill",
                detail: store.averageFuelVolumeText
            ),
            CPInformationItem(
                title: "Receipts",
                detail: "Add receipt images later from your phone."
            )
        ]

        let addButton = CPTextButton(
            title: "Add Fuel-up",
            textStyle: .confirm
        ) { [weak self] _ in
            self?.draftFuelOdometer = self?.currentOdometer
            self?.interfaceController?.pushTemplate(
                self?.makeFuelTemplate() ?? CPListTemplate(title: "Fuel-up", sections: []),
                animated: true,
                completion: nil
            )
        }

        return CPInformationTemplate(
            title: "Fuel",
            layout: .twoColumn,
            items: items,
            actions: [addButton]
        )
    }

    private func maintenanceSummaryText() -> String {
        guard let reminder = nextMaintenanceReminder,
              let nextServiceOdometer = reminder.nextServiceOdometer else {
            return "No active reminders"
        }

        let delta = nextServiceOdometer - currentOdometer
        let distanceText = store.unitSystem.distanceString(for: abs(delta))
        let shopText = reminder.shopName.isEmpty ? "selected shop" : reminder.shopName

        if delta >= 0 {
            return "\(reminder.title) in \(distanceText) at \(shopText)"
        }

        return "\(reminder.title) overdue by \(distanceText) at \(shopText)"
    }

    private func showDashboardSummaryTemplate() {
        var items = [
            CPListItem(
                text: tripTracker.isTracking ? "Current Trip" : "Trip Snapshot",
                detailText: tripTracker.isTracking
                    ? "\(tripTracker.selectedTripType.title) • \(store.unitSystem.distanceString(for: tripTracker.currentTripDistance)) • \(tripTracker.elapsedTimeString)"
                    : "Odometer \(Int(currentOdometer.rounded())) \(store.unitSystem == .miles ? "mi" : "km") • \(tripTracker.selectedTripType.title)"
            ),
            CPListItem(
                text: store.currentTaxYearLabel,
                detailText: "\(taxYearSummary.totalTrips) trips • \(store.unitSystem.distanceString(for: taxYearSummary.totalCombinedDistanceMeters)) • \(store.currencyString(for: taxYearSummary.totalCombinedSpend)) spend"
            ),
            CPListItem(
                text: "Fuel Overview",
                detailText: "\(store.currencyString(for: store.currentTaxYearFuelSpend)) this year • Avg \(store.monthlyAverageFuelEconomyText)"
            ),
            CPListItem(
                text: "Maintenance",
                detailText: maintenanceSummaryText()
            )
        ]

        items.forEach { $0.isEnabled = false }

        if let allowanceSummary, let activeVehicle = store.activeVehicle {
            let allowanceItem = CPListItem(
                text: "Allowance Balance",
                detailText: "\(activeVehicle.displayName) • Remaining \(store.currencyString(for: allowanceSummary.remainingBalance))"
            )
            allowanceItem.isEnabled = false
            items.insert(allowanceItem, at: 3)
        }

        interfaceController?.pushTemplate(
            CPListTemplate(title: "Dashboard", sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func showMaintenanceSummaryTemplate() {
        let item = CPListItem(text: "Maintenance", detailText: maintenanceSummaryText())
        item.isEnabled = false
        interfaceController?.pushTemplate(
            CPListTemplate(title: "Maintenance", sections: [CPListSection(items: [item])]),
            animated: true,
            completion: nil
        )
    }

    private func showFuelSummaryTemplate() {
        let items = [
            CPListItem(
                text: store.currentTaxYearLabel,
                detailText: store.currencyString(for: store.currentTaxYearFuelSpend)
            ),
            CPListItem(
                text: "Monthly Average",
                detailText: store.monthlyAverageFuelEconomyText
            ),
            CPListItem(
                text: "Selection",
                detailText: selectedFuelVolume.map { volume in
                    let volumeText = store.fuelVolumeString(
                        for: store.liters(fromDisplayedFuelVolume: volume),
                        fractionDigits: 1
                    )
                    let amountText = selectedFuelPaidAmount.map(store.currencyString(for:)) ?? "No amount"
                    return "\(volumeText) • \(amountText)"
                } ?? "No fuel-up selected"
            )
        ]
        items.forEach { $0.isEnabled = false }
        interfaceController?.pushTemplate(
            CPListTemplate(title: "Fuel Summary", sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func applyTripTypeSelection(_ tripType: TripType) {
        Task { @MainActor in
            if let completedTrip = await tripTracker.selectTripType(
                tripType,
                nextTripStartOdometerReading: currentOdometer,
                completedTripEndOdometerReading: currentOdometer
            ) {
                store.addTrip(completedTrip)
            }
            appModel.saveCurrentSnapshot()
            refreshRootTemplate()
        }
    }

    private func applyStoredTripTypeSelection(_ tripType: TripType, tripID: UUID) {
        guard let trip = store.trip(for: tripID) else {
            return
        }

        var updatedTrip = trip
        updatedTrip.type = tripType
        store.updateTrip(updatedTrip)
        appModel.saveCurrentSnapshot()
        refreshRootTemplate()
        showTripDetailTemplate(for: tripID)
    }

    private func makeLoadingTemplate() -> CPTemplate {
        let item = CPListItem(
            text: "Preparing CarPlay",
            detailText: "Loading trips, vehicles, drivers, and settings"
        )
        item.isEnabled = false
        return CPListTemplate(title: "Meerkat", sections: [CPListSection(items: [item])])
    }

    private func makeTripTemplate() -> CPListTemplate {
        let statusItem = CPListItem(
            text: tripTracker.isTracking ? "Recording" : "Ready",
            detailText: "Type: \(tripTracker.selectedTripType.title) • Odometer: \(Int(currentOdometer.rounded())) \(store.unitSystem == .miles ? "mi" : "km")"
        )
        statusItem.isEnabled = false

        let elapsedItem = CPListItem(
            text: "Elapsed",
            detailText: tripTracker.elapsedTimeString
        )
        elapsedItem.isEnabled = false

        let toggleItem = CPListItem(
            text: tripTracker.isTracking ? "Stop Recording Trip" : "Start Recording Trip",
            detailText: tripTracker.isTracking ? "End the current trip" : "Begin GPS trip recording"
        )
        toggleItem.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }

            Task { @MainActor in
                await self.toggleRecordingFromCarPlay()
                completion()
            }
        }

        let tripTypeItem = CPListItem(
            text: "Trip Type",
            detailText: tripTracker.selectedTripType.title
        )
        tripTypeItem.accessoryType = .disclosureIndicator
        tripTypeItem.handler = { [weak self] _, completion in
            self?.showTripTypeTemplate()
            completion()
        }

        let odometerItem = CPListItem(
            text: "Edit Odometer",
            detailText: tripTracker.isTracking ? "Adjust and end the active trip" : "Available only while recording"
        )
        odometerItem.isEnabled = tripTracker.isTracking
        odometerItem.accessoryType = tripTracker.isTracking ? .disclosureIndicator : .none
        odometerItem.handler = { [weak self] _, completion in
            self?.showOdometerAdjustmentTemplate()
            completion()
        }

        let section = CPListSection(items: [statusItem, elapsedItem, toggleItem, tripTypeItem, odometerItem])
        return CPListTemplate(title: "Meerkat Trip", sections: [section])
    }

    private func makeSetupTemplate() -> CPListTemplate {
        let vehicleItem = CPListItem(
            text: "Vehicle",
            detailText: store.activeVehicle?.displayName ?? "Not selected"
        )
        vehicleItem.accessoryType = .disclosureIndicator
        vehicleItem.handler = { [weak self] _, completion in
            self?.showVehicleSelectionTemplate()
            completion()
        }

        let driverItem = CPListItem(
            text: "Driver",
            detailText: store.activeDriver?.name ?? "Not selected"
        )
        driverItem.accessoryType = .disclosureIndicator
        driverItem.handler = { [weak self] _, completion in
            self?.showDriverSelectionTemplate()
            completion()
        }

        let section = CPListSection(items: [vehicleItem, driverItem])
        return CPListTemplate(title: "Car Setup", sections: [section])
    }

    private func makeFuelTemplate() -> CPListTemplate {
        let statusItem = CPListItem(
            text: "Quick Fuel-up",
            detailText: "Enter the fuel-up details now and add the receipt later on your phone."
        )
        statusItem.isEnabled = false

        let odometerItem = CPListItem(
            text: "Odometer",
            detailText: "\(Int((draftFuelOdometer ?? currentOdometer).rounded())) \(store.unitSystem == .miles ? "mi" : "km")"
        )
        odometerItem.accessoryType = .disclosureIndicator
        odometerItem.handler = { [weak self] _, completion in
            self?.showFuelOdometerTemplate()
            completion()
        }

        let stationItem = CPListItem(
            text: "Station",
            detailText: "Auto-detected when you save"
        )
        stationItem.isEnabled = false

        let volumeItem = CPListItem(
            text: store.fuelVolumeUnit.title,
            detailText: selectedFuelVolume.map { store.fuelVolumeString(for: store.liters(fromDisplayedFuelVolume: $0), fractionDigits: 1) } ?? "Select"
        )
        volumeItem.accessoryType = .disclosureIndicator
        volumeItem.handler = { [weak self] _, completion in
            self?.showFuelVolumeTemplate()
            completion()
        }

        let amountItem = CPListItem(
            text: "Paid Amount",
            detailText: selectedFuelPaidAmount.map(store.currencyString(for:)) ?? "Select"
        )
        amountItem.accessoryType = .disclosureIndicator
        amountItem.handler = { [weak self] _, completion in
            self?.showFuelAmountTemplate()
            completion()
        }

        let saveItem = CPListItem(
            text: "Add Fuel-up",
            detailText: "Saves without a receipt so you can attach it later from the phone app"
        )
        saveItem.isEnabled = selectedFuelVolume != nil && selectedFuelPaidAmount != nil
        saveItem.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }

            Task { @MainActor in
                await self.saveFuelUpFromCarPlay()
                completion()
            }
        }

        let section = CPListSection(items: [statusItem, stationItem, odometerItem, volumeItem, amountItem, saveItem])
        return CPListTemplate(title: "Fuel-up", sections: [section])
    }

    private func showTripDetailTemplate(for tripID: UUID) {
        guard let trip = store.trip(for: tripID) else {
            return
        }

        let summaryItems = [
            CPListItem(text: "Trip Type", detailText: trip.type.title),
            CPListItem(text: "Date", detailText: trip.date.formatted(date: .abbreviated, time: .shortened)),
            CPListItem(text: "Distance", detailText: store.unitSystem.distanceString(for: trip.distanceMeters)),
            CPListItem(
                text: "Odometer",
                detailText: "\(Int(trip.odometerStart.rounded())) to \(Int(trip.odometerEnd.rounded())) \(store.unitSystem == .miles ? "mi" : "km")"
            ),
            CPListItem(text: "Start", detailText: trip.effectiveStartAddress),
            CPListItem(text: "End", detailText: trip.effectiveEndAddress)
        ]
        summaryItems.forEach { $0.isEnabled = false }

        let editTypeItem = CPListItem(text: "Edit Trip Type", detailText: trip.type.title)
        editTypeItem.isEnabled = isCarPlayStationary
        editTypeItem.accessoryType = isCarPlayStationary ? .disclosureIndicator : .none
        editTypeItem.handler = { [weak self] _, completion in
            self?.showStoredTripTypeTemplate(for: tripID)
            completion()
        }

        let editStartItem = CPListItem(
            text: "Edit Start Odometer",
            detailText: "\(Int(trip.odometerStart.rounded())) \(store.unitSystem == .miles ? "mi" : "km")"
        )
        editStartItem.isEnabled = isCarPlayStationary
        editStartItem.accessoryType = isCarPlayStationary ? .disclosureIndicator : .none
        editStartItem.handler = { [weak self] _, completion in
            self?.showTripOdometerEditor(for: tripID, field: .start)
            completion()
        }

        let editEndItem = CPListItem(
            text: "Edit End Odometer",
            detailText: "\(Int(trip.odometerEnd.rounded())) \(store.unitSystem == .miles ? "mi" : "km")"
        )
        editEndItem.isEnabled = isCarPlayStationary
        editEndItem.accessoryType = isCarPlayStationary ? .disclosureIndicator : .none
        editEndItem.handler = { [weak self] _, completion in
            self?.showTripOdometerEditor(for: tripID, field: .end)
            completion()
        }

        let deleteItem = CPListItem(text: "Delete Trip", detailText: "Remove this trip from your records")
        deleteItem.isEnabled = isCarPlayStationary
        deleteItem.handler = { [weak self] _, completion in
            self?.presentDeleteTripAlert(for: tripID)
            completion()
        }

        let actions = isCarPlayStationary
            ? [editTypeItem, editStartItem, editEndItem, deleteItem]
            : [CPListItem(text: "Editing Disabled", detailText: "Stop the vehicle to edit or delete this trip.")]
        if !isCarPlayStationary {
            actions.first?.isEnabled = false
        }

        interfaceController?.pushTemplate(
            CPListTemplate(
                title: "Trip Details",
                sections: [
                    CPListSection(items: summaryItems),
                    CPListSection(items: actions)
                ]
            ),
            animated: true,
            completion: nil
        )
    }

    private func showStoredTripTypeTemplate(for tripID: UUID) {
        guard let trip = store.trip(for: tripID) else {
            return
        }

        let items = TripType.allCases.map { tripType in
            let item = CPListItem(
                text: tripType.title,
                detailText: tripType == trip.type ? "Current" : nil
            )
            item.handler = { [weak self] _, completion in
                self?.applyStoredTripTypeSelection(tripType, tripID: tripID)
                completion()
            }
            return item
        }

        interfaceController?.pushTemplate(
            CPListTemplate(title: "Edit Trip Type", sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func showTripOdometerEditor(for tripID: UUID, field: TripOdometerField) {
        guard let trip = store.trip(for: tripID) else {
            return
        }

        let baseValue: Double
        switch field {
        case .start:
            baseValue = trip.odometerStart
        case .end:
            baseValue = trip.odometerEnd
        }

        let currentDraft = draftTripEditorOdometer ?? baseValue
        draftTripEditorOdometer = currentDraft

        let currentItem = CPListItem(
            text: field.title,
            detailText: "\(currentDraft.formatted(.number.precision(.fractionLength(1)))) \(store.unitSystem == .miles ? "mi" : "km")"
        )
        currentItem.isEnabled = false

        let adjustItems = [
            makeTripOdometerAdjustItem(title: "-10", delta: -10, tripID: tripID, field: field),
            makeTripOdometerAdjustItem(title: "-5", delta: -5, tripID: tripID, field: field),
            makeTripOdometerAdjustItem(title: "-1", delta: -1, tripID: tripID, field: field),
            makeTripOdometerAdjustItem(title: "+1", delta: 1, tripID: tripID, field: field),
            makeTripOdometerAdjustItem(title: "+5", delta: 5, tripID: tripID, field: field),
            makeTripOdometerAdjustItem(title: "+10", delta: 10, tripID: tripID, field: field)
        ]

        let applyItem = CPListItem(text: "Apply", detailText: "Save this odometer value")
        applyItem.handler = { [weak self] _, completion in
            self?.applyTripOdometerChange(for: tripID, field: field)
            completion()
        }

        interfaceController?.pushTemplate(
            CPListTemplate(
                title: field.title,
                sections: [
                    CPListSection(items: [currentItem]),
                    CPListSection(items: adjustItems),
                    CPListSection(items: [applyItem])
                ]
            ),
            animated: true,
            completion: nil
        )
    }

    private func makeTripOdometerAdjustItem(title: String, delta: Double, tripID: UUID, field: TripOdometerField) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil)
        item.handler = { [weak self] _, completion in
            guard let self, let trip = self.store.trip(for: tripID) else {
                completion()
                return
            }

            let currentValue = self.draftTripEditorOdometer ?? (field == .start ? trip.odometerStart : trip.odometerEnd)
            let adjustedValue = self.clampedTripOdometerValue(
                currentValue + delta,
                for: trip,
                field: field
            )
            self.draftTripEditorOdometer = adjustedValue
            self.showTripOdometerEditor(for: tripID, field: field)
            completion()
        }
        return item
    }

    private func applyTripOdometerChange(for tripID: UUID, field: TripOdometerField) {
        guard let trip = store.trip(for: tripID) else {
            return
        }

        let newValue = clampedTripOdometerValue(draftTripEditorOdometer ?? (field == .start ? trip.odometerStart : trip.odometerEnd), for: trip, field: field)
        var updatedTrip = trip
        switch field {
        case .start:
            updatedTrip.odometerStart = newValue
        case .end:
            updatedTrip.odometerEnd = newValue
        }
        store.updateTrip(updatedTrip)
        draftTripEditorOdometer = nil
        appModel.saveCurrentSnapshot()
        refreshRootTemplate()
        showTripDetailTemplate(for: tripID)
    }

    private func clampedTripOdometerValue(_ value: Double, for trip: Trip, field: TripOdometerField) -> Double {
        switch field {
        case .start:
            return max(min(value, trip.odometerEnd), 0)
        case .end:
            return max(value, trip.odometerStart)
        }
    }

    private func presentDeleteTripAlert(for tripID: UUID) {
        let cancelAction = CPAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }

        let deleteAction = CPAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else {
                return
            }
            self.store.deleteTrip(id: tripID)
            self.appModel.saveCurrentSnapshot()
            self.interfaceController?.dismissTemplate(animated: true, completion: nil)
            self.refreshRootTemplate()
        }

        interfaceController?.presentTemplate(
            CPAlertTemplate(
                titleVariants: ["Delete this trip?"],
                actions: [cancelAction, deleteAction]
            ),
            animated: true,
            completion: nil
        )
    }

    private func showTripTypeTemplate() {
        let items = TripType.allCases.map { tripType in
            let item = CPListItem(
                text: tripType.title,
                detailText: tripType == tripTracker.selectedTripType ? "Current" : nil
            )
            item.handler = { [weak self] _, completion in
                guard let self else {
                    completion()
                    return
                }

                Task { @MainActor in
                    if let completedTrip = await self.tripTracker.selectTripType(
                        tripType,
                        nextTripStartOdometerReading: self.currentOdometer,
                        completedTripEndOdometerReading: self.currentOdometer
                    ) {
                        self.store.addTrip(completedTrip)
                    }
                    self.appModel.saveCurrentSnapshot()
                    self.refreshRootTemplate()
                    completion()
                }
            }
            return item
        }

        interfaceController?.pushTemplate(
            CPListTemplate(title: "Trip Type", sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func showVehicleSelectionTemplate() {
        let items = store.vehicles.map { vehicle in
            let detailText = vehicle.id == store.activeVehicleID ? "Current • \(vehicle.subtitle)" : vehicle.subtitle
            let item = CPListItem(text: vehicle.displayName, detailText: detailText)
            item.handler = { [weak self] _, completion in
                self?.store.activeVehicleID = vehicle.id
                self?.appModel.saveCurrentSnapshot()
                self?.refreshRootTemplate()
                completion()
            }
            return item
        }

        interfaceController?.pushTemplate(
            CPListTemplate(title: "Select Vehicle", sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func showDriverSelectionTemplate() {
        let items = store.drivers.map { driver in
            let detailText = driver.id == store.activeDriverID ? "Current • \(driver.subtitle)" : driver.subtitle
            let item = CPListItem(text: driver.name, detailText: detailText)
            item.handler = { [weak self] _, completion in
                self?.store.activeDriverID = driver.id
                self?.appModel.saveCurrentSnapshot()
                self?.refreshRootTemplate()
                completion()
            }
            return item
        }

        interfaceController?.pushTemplate(
            CPListTemplate(title: "Select Driver", sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func showOdometerAdjustmentTemplate() {
        guard tripTracker.isTracking else {
            return
        }

        needsRootTemplateRefresh = true
        if draftTripEndOdometer == nil {
            draftTripEndOdometer = currentOdometer
        }

        let template = odometerAdjustmentTemplate ?? makeOdometerAdjustmentTemplate()
        updateOdometerAdjustmentTemplate()

        if interfaceController?.topTemplate !== template {
            interfaceController?.pushTemplate(template, animated: true, completion: nil)
        }
    }

    private func makeOdometerAdjustmentTemplate() -> CPListTemplate {
        let currentItem = CPListItem(
            text: "Trip End Odometer",
            detailText: currentOdometerReadingText
        )
        currentItem.isEnabled = false
        odometerAdjustmentValueItem = currentItem

        let applyItem = CPListItem(
            text: "End and Save",
            detailText: "Use this odometer reading to finish the trip"
        )
        applyItem.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }

            Task { @MainActor in
                await self.endTripUsingDraftOdometer()
                completion()
            }
        }

        let template = CPListTemplate(
            title: "Edit Odometer",
            sections: [
                CPListSection(items: [currentItem]),
                CPListSection(items: [
                    makeOdometerAdjustItem(title: "-10", delta: -10),
                    makeOdometerAdjustItem(title: "-1", delta: -1),
                    makeOdometerAdjustItem(title: "+1", delta: 1),
                    makeOdometerAdjustItem(title: "+10", delta: 10)
                ]),
                CPListSection(items: [applyItem])
            ]
        )
        template.tabTitle = "Dashboard"
        odometerAdjustmentTemplate = template
        return template
    }

    private func updateOdometerAdjustmentTemplate() {
        odometerAdjustmentValueItem?.setDetailText(currentOdometerReadingText)
    }

    private func makeOdometerAdjustItem(title: String, delta: Double) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil)
        item.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }

            let baseValue = self.draftTripEndOdometer ?? self.currentOdometer
            self.draftTripEndOdometer = max(baseValue + delta, self.store.currentBaseOdometerReading())
            self.updateOdometerAdjustmentTemplate()
            completion()
        }
        return item
    }

    private func showFuelVolumeTemplate() {
        let presetValues = store.fuelVolumeUnit == .gallons ? Constants.fuelGallonsPresets : Constants.fuelLitersPresets
        let items = presetValues.map { volume in
            let item = CPListItem(
                text: store.fuelVolumeString(for: store.liters(fromDisplayedFuelVolume: volume), fractionDigits: 1),
                detailText: selectedFuelVolume == volume ? "Selected" : nil
            )
            item.handler = { [weak self] _, completion in
                self?.selectedFuelVolume = volume
                self?.refreshRootTemplate()
                completion()
            }
            return item
        }

        interfaceController?.pushTemplate(
            CPListTemplate(title: store.fuelVolumeUnit.title, sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func showFuelAmountTemplate() {
        let items = Constants.fuelAmountPresets.map { amount in
            let item = CPListItem(
                text: store.currencyString(for: amount),
                detailText: selectedFuelPaidAmount == amount ? "Selected" : nil
            )
            item.handler = { [weak self] _, completion in
                self?.selectedFuelPaidAmount = amount
                self?.refreshRootTemplate()
                completion()
            }
            return item
        }

        interfaceController?.pushTemplate(
            CPListTemplate(title: "Paid Amount", sections: [CPListSection(items: items)]),
            animated: true,
            completion: nil
        )
    }

    private func showFuelOdometerTemplate() {
        let currentValue = draftFuelOdometer ?? currentOdometer
        draftFuelOdometer = currentValue

        let currentItem = CPListItem(
            text: "Selected Odometer",
            detailText: "\(currentValue.formatted(.number.precision(.fractionLength(1)))) \(store.unitSystem == .miles ? "mi" : "km")"
        )
        currentItem.isEnabled = false

        let adjustItems = [
            makeFuelOdometerAdjustItem(title: "-10", delta: -10),
            makeFuelOdometerAdjustItem(title: "-5", delta: -5),
            makeFuelOdometerAdjustItem(title: "-1", delta: -1),
            makeFuelOdometerAdjustItem(title: "+1", delta: 1),
            makeFuelOdometerAdjustItem(title: "+5", delta: 5),
            makeFuelOdometerAdjustItem(title: "+10", delta: 10)
        ]

        let useItem = CPListItem(text: "Use This Odometer", detailText: "Return to the fuel-up form")
        useItem.handler = { [weak self] _, completion in
            self?.interfaceController?.popTemplate(animated: true, completion: nil)
            completion()
        }

        interfaceController?.pushTemplate(
            CPListTemplate(
                title: "Fuel Odometer",
                sections: [
                    CPListSection(items: [currentItem]),
                    CPListSection(items: adjustItems),
                    CPListSection(items: [useItem])
                ]
            ),
            animated: true,
            completion: nil
        )
    }

    private func makeFuelOdometerAdjustItem(title: String, delta: Double) -> CPListItem {
        let item = CPListItem(text: title, detailText: nil)
        item.handler = { [weak self] _, completion in
            guard let self else {
                completion()
                return
            }

            let baseValue = self.draftFuelOdometer ?? self.currentOdometer
            self.draftFuelOdometer = max(baseValue + delta, self.store.currentBaseOdometerReading())
            self.showFuelOdometerTemplate()
            completion()
        }
        return item
    }

    private func toggleRecordingFromCarPlay() async {
        tripTracker.canRecordTrips = store.isReadyToDrive
        if tripTracker.isTracking {
            if let trip = await tripTracker.stopTracking(endOdometerReading: currentOdometer) {
                store.addTrip(trip)
            }
        } else {
            tripTracker.startTracking(startOdometerReading: store.currentBaseOdometerReading())
        }
        draftTripEndOdometer = nil
        appModel.saveCurrentSnapshot()
        refreshRootTemplate()
    }

    private func endTripUsingDraftOdometer() async {
        guard tripTracker.isTracking else {
            return
        }

        let endingOdometer = draftTripEndOdometer ?? currentOdometer
        if let trip = await tripTracker.stopTracking(endOdometerReading: endingOdometer) {
            store.addTrip(trip)
        }
        draftTripEndOdometer = nil
        odometerAdjustmentTemplate = nil
        odometerAdjustmentValueItem = nil
        appModel.saveCurrentSnapshot()
        interfaceController?.popTemplate(animated: true) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshRootTemplate(animated: true)
            }
        }
    }

    private func saveFuelUpFromCarPlay() async {
        guard
            let volume = selectedFuelVolume,
            let paidAmount = selectedFuelPaidAmount
        else {
            return
        }

        let stationName = await resolveFuelStopName()
        let entry = FuelEntry(
            vehicleID: store.activeVehicleID,
            vehicleProfileName: store.activeVehicle?.displayName ?? "",
            station: stationName,
            volume: store.liters(fromDisplayedFuelVolume: volume),
            totalCost: paidAmount,
            odometer: draftFuelOdometer ?? currentOdometer,
            date: .now,
            receiptImageData: nil
        )
        store.addFuelEntry(entry)
        selectedFuelVolume = nil
        selectedFuelPaidAmount = nil
        draftFuelOdometer = nil
        appModel.saveCurrentSnapshot()
        refreshRootTemplate()
    }

    private func resolveFuelStopName() async -> String {
        guard let location = tripTracker.currentLocation else {
            return "Fuel stop"
        }

        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 100)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let closestStation = response.mapItems
                .compactMap({ item -> (String, CLLocationDistance)? in
                    guard let name = item.name else {
                        return nil
                    }
                    let distance = location.distance(from: item.location)
                    guard distance <= 100 else {
                        return nil
                    }
                    return (name, distance)
                })
                .min(by: { $0.1 < $1.1 }) {
                return closestStation.0
            }
        } catch {
            return await tripTracker.currentAddress() ?? "Fuel stop"
        }

        return await tripTracker.currentAddress() ?? "Fuel stop"
    }
}

enum AppPersistenceController {
    private nonisolated static let fileName = "MeerkatMileageTracker.json"

    nonisolated static func load() throws -> AppPersistenceSnapshot? {
        let url = try persistenceURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppPersistenceSnapshot.self, from: data)
    }

    nonisolated static func save(_ snapshot: AppPersistenceSnapshot) throws {
        let url = try persistenceURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func deletePersistedSnapshot() throws {
        let url = try persistenceURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private nonisolated static func persistenceURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL.appendingPathComponent("MeerkatMileageTracker", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent(fileName)
    }
}

extension AppPersistenceSnapshot {
    static let empty = AppPersistenceSnapshot(
        store: MileageStore.PersistenceSnapshot(
            selectedCountry: .usa,
            userName: "",
            emailAddress: "",
            preferredCurrency: .usd,
            unitSystem: .miles,
            fuelVolumeUnit: .gallons,
            fuelEconomyFormat: .milesPerGallon,
            preventAutoLock: false,
            vehicleDetectionEnabled: false,
            hasCompletedOnboarding: false,
            hasAcceptedPrivacyPolicy: false,
            hasAcceptedLegalNotice: false,
            organizations: [],
            activeOrganizationID: nil,
            organizationMemberships: [],
            vehicles: [],
            activeVehicleID: nil,
            drivers: [],
            activeDriverID: nil,
            trips: [],
            fuelEntries: [],
            maintenanceRecords: [],
            logs: [],
            allowanceAdjustments: []
        ),
        tripTracker: TripTracker.PersistenceSnapshot(
            autoStartEnabled: true,
            backgroundTripTrackingEnabled: true,
            motionActivityEnabled: true,
            autoStartSpeedThresholdKilometersPerHour: 10,
            autoStopDelayMinutes: 10,
            selectedTripType: .business
        )
    )
    var isEmpty: Bool {
        self == AppPersistenceSnapshot.empty
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> AppPersistenceSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppPersistenceSnapshot.self, from: data)
    }
}

@MainActor
@Observable
final class AuthSessionManager {
    enum AccessState: Equatable {
        case signedOut
        case locked
        case unlocked
    }

    private enum Constants {
        static let sessionService = "MeerkatMileageTracker.Auth"
        static let sessionAccount = "sessionIdentifier"
        static let emailAuthService = "MeerkatMileageTracker.EmailAuth"
        static let emailAccountKey = "emailAddress"
        static let passwordHashKey = "passwordHash"
        static let appleProfileService = "MeerkatMileageTracker.AppleProfile"
        static let appleNameAccountKey = "fullName"
        static let appleEmailAccountKey = "emailAddress"
        static let emailSessionPrefix = "email:"
        static let demoModeDefaultsKey = "MeerkatMileageTracker.DemoModeEnabled"
        static let ownerEmailAddress = "rheedergreeff@icloud.com"
        static let approvedBetaEmailAddresses: [String] = []
    }

    private(set) var accessState: AccessState = .signedOut
    private(set) var appleUserID: String?
    private(set) var signedInEmailAddress: String?
    private(set) var isDemoModeEnabled = false
    private(set) var appleFullName = ""
    private(set) var appleEmailAddress = ""
    var shouldStartOnboardingForCurrentSession = false
    private(set) var isBiometricAvailable = false
    private(set) var biometricLabel = "Face ID"
    private(set) var isSandboxReceiptEnvironment = false
    var isPresentingLoginSheet = false
    var errorMessage: String?
    private var currentAppleSignInNonce: String?
    #if canImport(FirebaseAuth)
    private var pendingSecondFactorResolver: MultiFactorResolver?
    private var pendingSecondFactorVerificationID: String?
    private(set) var secondFactorHintDisplayNames: [String] = []
    var selectedSecondFactorHintIndex = 0
    #endif

    init() {
        refreshBiometricAvailability()
        restoreStoredSession()
        refreshSandboxReceiptEnvironment()
    }

    var isSignedIn: Bool {
        appleUserID != nil
    }

    var isEmailPasswordAuthenticated: Bool {
        signedInEmailAddress != nil
    }

    var canDeleteCurrentAccount: Bool {
        !isDemoModeEnabled && (isSignedIn || isEmailPasswordAuthenticated)
    }

    var hasOwnerAccess: Bool {
        let ownerEmail = normalized(email: Constants.ownerEmailAddress)
        return signedInEmailAddress == ownerEmail || normalized(email: appleEmailAddress) == ownerEmail
    }

    var hasApprovedBetaAccess: Bool {
        guard isSandboxReceiptEnvironment else {
            return false
        }

        let approvedEmails = Set(Constants.approvedBetaEmailAddresses.map { normalized(email: $0) })
        return approvedEmails.contains(signedInEmailAddress ?? "")
            || approvedEmails.contains(normalized(email: appleEmailAddress))
    }

    var canUseCloudSyncFeatures: Bool {
        isSignedIn || isEmailPasswordAuthenticated || isConnectedToFirebase || hasApprovedBetaAccess
    }

    var hasStoredEmailPasswordAccount: Bool {
        storedEmailAddress != nil && storedPasswordHash != nil
    }

    var isUnlocked: Bool {
        accessState == .unlocked
    }

    var isAwaitingSecondFactor: Bool {
        #if canImport(FirebaseAuth)
        pendingSecondFactorResolver != nil
        #else
        false
        #endif
    }

    var usesFirebaseEmailPasswordAuth: Bool {
        #if canImport(FirebaseAuth)
        true
        #else
        false
        #endif
    }

    var isConnectedToFirebase: Bool {
        #if canImport(FirebaseAuth)
        Auth.auth().currentUser != nil
        #else
        false
        #endif
    }

    var firebaseConnectionLabel: String {
        #if canImport(FirebaseAuth)
        if let email = Auth.auth().currentUser?.email, !email.isEmpty {
            return "Connected as \(normalized(email: email))"
        }
        if Auth.auth().currentUser != nil {
            return "Connected"
        }
        return "Not connected"
        #else
        return "Not connected"
        #endif
    }

    var firebaseDebugLabel: String {
        #if canImport(FirebaseAuth)
        guard let user = Auth.auth().currentUser else {
            return "No Firebase user"
        }
        let providerIDs = user.providerData.map(\.providerID)
        let providersText = providerIDs.isEmpty ? "none" : providerIDs.joined(separator: ", ")
        return "uid: \(user.uid) | providers: \(providersText)"
        #else
        return "Firebase SDK unavailable"
        #endif
    }

    func restoreStoredSession() {
        isDemoModeEnabled = UserDefaults.standard.bool(forKey: Constants.demoModeDefaultsKey)
        appleUserID = nil
        signedInEmailAddress = nil
        appleFullName = ""
        appleEmailAddress = ""
        shouldStartOnboardingForCurrentSession = false

        let storedSession = KeychainController.readString(service: Constants.sessionService, account: Constants.sessionAccount)
        #if canImport(FirebaseAuth)
        if Auth.auth().currentUser != nil {
            if firebaseCurrentUserProviderIDs().contains("apple.com") {
                appleUserID = Auth.auth().currentUser?.uid
                appleFullName = Auth.auth().currentUser?.displayName ?? KeychainController.readString(
                    service: Constants.appleProfileService,
                    account: Constants.appleNameAccountKey
                ) ?? ""
                appleEmailAddress = Auth.auth().currentUser?.email ?? KeychainController.readString(
                    service: Constants.appleProfileService,
                    account: Constants.appleEmailAccountKey
                ) ?? ""
            } else if let firebaseEmail = currentFirebaseEmailAddress() {
                signedInEmailAddress = firebaseEmail
            }
        } else if let storedSession, !storedSession.hasPrefix(Constants.emailSessionPrefix) {
            appleUserID = storedSession
        }
        #else
        if let storedSession, storedSession.hasPrefix(Constants.emailSessionPrefix) {
            let storedEmail = String(storedSession.dropFirst(Constants.emailSessionPrefix.count))
            if storedEmail == storedEmailAddress {
                signedInEmailAddress = storedEmail
            }
        } else {
            appleUserID = storedSession
        }
        #endif

        if appleUserID != nil {
            appleFullName = KeychainController.readString(
                service: Constants.appleProfileService,
                account: Constants.appleNameAccountKey
            ) ?? ""
            appleEmailAddress = KeychainController.readString(
                service: Constants.appleProfileService,
                account: Constants.appleEmailAccountKey
            ) ?? ""
        }

        if isDemoModeEnabled {
            accessState = .unlocked
        } else {
            accessState = hasAuthenticatedSession ? (isBiometricAvailable ? .locked : .unlocked) : .signedOut
        }
    }

    func handleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "The Apple sign-in response was invalid."
                return
            }

            #if canImport(FirebaseAuth)
            Task {
                do {
                    try await signInWithAppleThroughFirebase(credential)
                } catch {
                    if await handlePotentialSecondFactorRequirement(error) {
                        return
                    }
                    errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "The app couldn't complete Apple sign-in.")
                }
            }
            #else
            do {
                try completeSuccessfulAppleSession(userID: credential.user, fullName: credential.fullName, email: credential.email)
            } catch {
                errorMessage = "The app couldn't securely store your sign-in."
            }
            #endif
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }

            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.unknown.rawValue {
                errorMessage = "Sign in with Apple is currently unavailable. Please try again later."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]

        #if canImport(FirebaseAuth)
        let nonce = randomNonceString()
        currentAppleSignInNonce = nonce
        request.nonce = sha256(nonce)
        #endif
    }

    func signInWithGoogle() {
        #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
        guard let presentingViewController = activeRootViewController() else {
            errorMessage = "Google sign-in is unavailable because the login screen could not be presented."
            return
        }

        guard let clientID = firebaseClientID(), !clientID.isEmpty else {
            errorMessage = "Google sign-in is unavailable. Missing Firebase client ID configuration."
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        Task {
            do {
                let signInResult = try await signInWithGoogleSDK(presentingViewController: presentingViewController)
                guard let idToken = signInResult.user.idToken?.tokenString else {
                    throw NSError(
                        domain: "GoogleSignIn",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Google sign-in did not return a valid ID token."]
                    )
                }

                let accessToken = signInResult.user.accessToken.tokenString
                let firebaseCredential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
                let user = try await signInFirebase(with: firebaseCredential)

                signedInEmailAddress = normalized(email: user.email ?? signInResult.user.profile?.email ?? "")
                if signedInEmailAddress?.isEmpty == true {
                    signedInEmailAddress = nil
                }
                appleUserID = nil
                appleFullName = ""
                appleEmailAddress = ""
                disableDemoMode()
                errorMessage = nil
                isPresentingLoginSheet = false
                refreshBiometricAvailability()
                accessState = isBiometricAvailable ? .locked : .unlocked
            } catch {
                if isGoogleSignInCancellation(error) {
                    return
                }
                if await handlePotentialSecondFactorRequirement(error) {
                    return
                }
                errorMessage = firebaseAuthErrorMessage(
                    for: error,
                    defaultMessage: "The app couldn't complete Google sign-in."
                )
            }
        }
        #else
        errorMessage = "Google sign-in is not available in this build."
        #endif
    }

    func sendSecondFactorCode() {
        #if canImport(FirebaseAuth)
        Task {
            do {
                try await sendSecondFactorCodeIfNeeded()
            } catch {
                errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "The app couldn't send a verification code.")
            }
        }
        #endif
    }

    func completeSecondFactorSignIn(code: String) {
        #if canImport(FirebaseAuth)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = "Enter the SMS verification code."
            return
        }

        Task {
            do {
                let user = try await resolveSecondFactorSignIn(with: trimmedCode)
                signedInEmailAddress = normalized(email: user.email ?? "")
                if signedInEmailAddress?.isEmpty == true {
                    signedInEmailAddress = nil
                }
                appleUserID = nil
                appleFullName = ""
                appleEmailAddress = ""
                disableDemoMode()
                shouldStartOnboardingForCurrentSession = false
                clearSecondFactorState()
                errorMessage = nil
                isPresentingLoginSheet = false
                refreshBiometricAvailability()
                accessState = isBiometricAvailable ? .locked : .unlocked
            } catch {
                errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "The verification code was invalid.")
            }
        }
        #endif
    }

    func createEmailPasswordAccount(email: String, password: String, passwordConfirmation: String) {
        let normalizedEmail = normalized(email: email)
        guard isValidEmail(normalizedEmail) else {
            errorMessage = "Enter a valid email address."
            return
        }

        guard password.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }

        guard password == passwordConfirmation else {
            errorMessage = "Passwords do not match."
            return
        }

        #if canImport(FirebaseAuth)
        Task {
            do {
                let user = try await createFirebaseUser(email: normalizedEmail, password: password)
                signedInEmailAddress = normalized(email: user.email ?? normalizedEmail)
                appleUserID = nil
                appleFullName = ""
                appleEmailAddress = ""
                disableDemoMode()
                shouldStartOnboardingForCurrentSession = true
                errorMessage = nil
                isPresentingLoginSheet = false
                refreshBiometricAvailability()
                accessState = isBiometricAvailable ? .locked : .unlocked
            } catch {
                errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "The app couldn't create your account.")
            }
        }
        #else
        do {
            try KeychainController.saveString(normalizedEmail, service: Constants.emailAuthService, account: Constants.emailAccountKey)
            try KeychainController.saveString(passwordHash(for: password), service: Constants.emailAuthService, account: Constants.passwordHashKey)
            try KeychainController.saveString(Constants.emailSessionPrefix + normalizedEmail, service: Constants.sessionService, account: Constants.sessionAccount)
            appleUserID = nil
            appleFullName = ""
            appleEmailAddress = ""
            signedInEmailAddress = normalizedEmail
            disableDemoMode()
            shouldStartOnboardingForCurrentSession = true
            errorMessage = nil
            isPresentingLoginSheet = false
            refreshBiometricAvailability()
            accessState = isBiometricAvailable ? .locked : .unlocked
        } catch {
            errorMessage = "The app couldn't securely store your sign-in."
        }
        #endif
    }

    func signInWithEmail(email: String, password: String) {
        let normalizedEmail = normalized(email: email)
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }

        #if canImport(FirebaseAuth)
        Task {
            do {
                clearSecondFactorState()
                let user = try await signInFirebaseUser(email: normalizedEmail, password: password)
                signedInEmailAddress = normalized(email: user.email ?? normalizedEmail)
                appleUserID = nil
                appleFullName = ""
                appleEmailAddress = ""
                disableDemoMode()
                shouldStartOnboardingForCurrentSession = false
                errorMessage = nil
                isPresentingLoginSheet = false
                refreshBiometricAvailability()
                accessState = isBiometricAvailable ? .locked : .unlocked
            } catch {
                if await handlePotentialSecondFactorRequirement(error) {
                    return
                }
                errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "Incorrect email or password.")
            }
        }
        #else
        guard let storedEmailAddress, let storedPasswordHash else {
            errorMessage = "No email account exists yet. Create one first."
            return
        }

        guard normalizedEmail == storedEmailAddress, passwordHash(for: password) == storedPasswordHash else {
            errorMessage = "Incorrect email or password."
            return
        }

        do {
            try KeychainController.saveString(Constants.emailSessionPrefix + normalizedEmail, service: Constants.sessionService, account: Constants.sessionAccount)
            appleUserID = nil
            appleFullName = ""
            appleEmailAddress = ""
            signedInEmailAddress = normalizedEmail
            disableDemoMode()
            shouldStartOnboardingForCurrentSession = false
            errorMessage = nil
            isPresentingLoginSheet = false
            refreshBiometricAvailability()
            accessState = isBiometricAvailable ? .locked : .unlocked
        } catch {
            errorMessage = "The app couldn't securely store your sign-in."
        }
        #endif
    }

    func resetEmailPassword(email: String, newPassword: String, passwordConfirmation: String) {
        let normalizedEmail = normalized(email: email)
        guard isValidEmail(normalizedEmail) else {
            errorMessage = "Enter the email address for your account."
            return
        }

        #if canImport(FirebaseAuth)
        Task {
            do {
                try await sendFirebasePasswordReset(email: normalizedEmail)
                errorMessage = "Password reset email sent."
            } catch {
                errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "The app couldn't send a password reset email.")
            }
        }
        #else
        guard let storedEmailAddress, storedEmailAddress == normalizedEmail else {
            errorMessage = "No account was found for that email address."
            return
        }

        guard newPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }

        guard newPassword == passwordConfirmation else {
            errorMessage = "Passwords do not match."
            return
        }

        do {
            try KeychainController.saveString(passwordHash(for: newPassword), service: Constants.emailAuthService, account: Constants.passwordHashKey)
            errorMessage = "Password updated. You can sign in now."
        } catch {
            errorMessage = "The app couldn't update your password."
        }
        #endif
    }

    func deleteEmailPasswordAccount() {
        #if canImport(FirebaseAuth)
        Task {
            do {
                try await deleteCurrentFirebaseUser()
                KeychainController.deleteValue(service: Constants.sessionService, account: Constants.sessionAccount)
                signedInEmailAddress = nil
                errorMessage = nil
                accessState = .signedOut
            } catch {
                errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "The app couldn't delete your account.")
            }
        }
        #else
        KeychainController.deleteValue(service: Constants.emailAuthService, account: Constants.emailAccountKey)
        KeychainController.deleteValue(service: Constants.emailAuthService, account: Constants.passwordHashKey)

        if isEmailPasswordAuthenticated {
            signOut()
        } else {
            errorMessage = nil
        }
        #endif
    }

    func unlock() async {
        refreshBiometricAvailability()

        if isDemoModeEnabled {
            accessState = .unlocked
            return
        }

        guard hasAuthenticatedSession else {
            accessState = .signedOut
            return
        }

        if !isBiometricAvailable {
            accessState = .unlocked
            return
        }

        do {
            try await BiometricAuthenticator.authenticate(reason: "Unlock your mileage data.")
            errorMessage = nil
            accessState = .unlocked
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func lockIfNeeded() {
        guard hasAuthenticatedSession, isBiometricAvailable else {
            return
        }

        accessState = .locked
    }

    func signOut() {
        #if canImport(FirebaseAuth)
        if Auth.auth().currentUser != nil {
            try? Auth.auth().signOut()
        }
        #endif
        KeychainController.deleteValue(service: Constants.sessionService, account: Constants.sessionAccount)
        disableDemoMode()
        appleUserID = nil
        appleFullName = ""
        appleEmailAddress = ""
        signedInEmailAddress = nil
        shouldStartOnboardingForCurrentSession = false
        #if canImport(FirebaseAuth)
        clearSecondFactorState()
        #endif
        errorMessage = nil
        isPresentingLoginSheet = false
        accessState = .signedOut
    }

    func returnToLoginScreen() {
        errorMessage = nil
        isPresentingLoginSheet = false
        accessState = .signedOut
    }

    func factoryReset() {
        KeychainController.deleteValue(service: Constants.emailAuthService, account: Constants.emailAccountKey)
        KeychainController.deleteValue(service: Constants.emailAuthService, account: Constants.passwordHashKey)
        KeychainController.deleteValue(service: Constants.appleProfileService, account: Constants.appleNameAccountKey)
        KeychainController.deleteValue(service: Constants.appleProfileService, account: Constants.appleEmailAccountKey)
        signOut()
    }

    func enableDemoMode() {
        KeychainController.deleteValue(service: Constants.sessionService, account: Constants.sessionAccount)
        appleUserID = nil
        signedInEmailAddress = nil
        appleFullName = ""
        appleEmailAddress = ""
        shouldStartOnboardingForCurrentSession = false
        isDemoModeEnabled = true
        UserDefaults.standard.set(true, forKey: Constants.demoModeDefaultsKey)
        errorMessage = nil
        isPresentingLoginSheet = false
        accessState = .unlocked
    }

    func disableDemoMode() {
        isDemoModeEnabled = false
        UserDefaults.standard.removeObject(forKey: Constants.demoModeDefaultsKey)
    }

    func clearError() {
        errorMessage = nil
    }

    private func refreshBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        isBiometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        biometricLabel = switch context.biometryType {
        case .faceID:
            "Face ID"
        case .touchID:
            "Touch ID"
        default:
            "Biometrics"
        }
    }

    func consumeOnboardingRequest() -> Bool {
        let shouldStart = shouldStartOnboardingForCurrentSession
        shouldStartOnboardingForCurrentSession = false
        return shouldStart
    }

    private var storedEmailAddress: String? {
        KeychainController.readString(service: Constants.emailAuthService, account: Constants.emailAccountKey)
            .map(normalized(email:))
    }

    private var storedPasswordHash: String? {
        KeychainController.readString(service: Constants.emailAuthService, account: Constants.passwordHashKey)
    }

    private var hasAuthenticatedSession: Bool {
        appleUserID != nil || signedInEmailAddress != nil
    }

    private func normalized(email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailPattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return email.range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func passwordHash(for password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func completeSuccessfulAppleSession(
        userID: String,
        fullName: PersonNameComponents?,
        email: String?
    ) throws {
        try KeychainController.saveString(userID, service: Constants.sessionService, account: Constants.sessionAccount)

        if let fullName = formattedAppleFullName(from: fullName) {
            try KeychainController.saveString(
                fullName,
                service: Constants.appleProfileService,
                account: Constants.appleNameAccountKey
            )
            appleFullName = fullName
        } else {
            appleFullName = KeychainController.readString(
                service: Constants.appleProfileService,
                account: Constants.appleNameAccountKey
            ) ?? ""
        }

        if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            try KeychainController.saveString(
                email,
                service: Constants.appleProfileService,
                account: Constants.appleEmailAccountKey
            )
            appleEmailAddress = email
        } else {
            appleEmailAddress = KeychainController.readString(
                service: Constants.appleProfileService,
                account: Constants.appleEmailAccountKey
            ) ?? ""
        }

        appleUserID = userID
        signedInEmailAddress = nil
        disableDemoMode()
        errorMessage = nil
        isPresentingLoginSheet = false
        refreshBiometricAvailability()
        accessState = isBiometricAvailable ? .locked : .unlocked
    }

    #if canImport(FirebaseAuth)
    private func clearSecondFactorState() {
        pendingSecondFactorResolver = nil
        pendingSecondFactorVerificationID = nil
        secondFactorHintDisplayNames = []
        selectedSecondFactorHintIndex = 0
    }

    private func handlePotentialSecondFactorRequirement(_ error: Error) async -> Bool {
        let nsError = error as NSError
        guard AuthErrorCode(rawValue: nsError.code) == .secondFactorRequired,
              let resolver = nsError.userInfo[AuthErrorUserInfoMultiFactorResolverKey] as? MultiFactorResolver else {
            return false
        }

        pendingSecondFactorResolver = resolver
        secondFactorHintDisplayNames = resolver.hints.map { hint in
            if let phoneHint = hint as? PhoneMultiFactorInfo {
                return "SMS \(phoneHint.phoneNumber)"
            }
            return "Second factor"
        }
        selectedSecondFactorHintIndex = 0

        do {
            try await sendSecondFactorCodeIfNeeded()
            errorMessage = "Enter the verification code sent to your phone."
        } catch {
            errorMessage = firebaseAuthErrorMessage(for: error, defaultMessage: "The app couldn't send a verification code.")
        }

        return true
    }

    private func sendSecondFactorCodeIfNeeded() async throws {
        guard let resolver = pendingSecondFactorResolver else {
            return
        }

        guard !resolver.hints.isEmpty else {
            throw NSError(domain: "FirebaseAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No enrolled second factors were found for this account."])
        }

        let boundedIndex = min(max(selectedSecondFactorHintIndex, 0), resolver.hints.count - 1)
        guard let phoneHint = resolver.hints[boundedIndex] as? PhoneMultiFactorInfo else {
            throw NSError(domain: "FirebaseAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported second-factor type."])
        }

        let verificationID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            PhoneAuthProvider.provider().verifyPhoneNumber(
                with: phoneHint,
                uiDelegate: nil,
                multiFactorSession: resolver.session
            ) { verificationID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let verificationID {
                    continuation.resume(returning: verificationID)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseAuth", code: -1))
                }
            }
        }

        pendingSecondFactorVerificationID = verificationID
    }

    private func resolveSecondFactorSignIn(with code: String) async throws -> User {
        guard let resolver = pendingSecondFactorResolver,
              let verificationID = pendingSecondFactorVerificationID else {
            throw NSError(domain: "FirebaseAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "A verification code must be requested first."])
        }

        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
        let assertion = PhoneMultiFactorGenerator.assertion(with: credential)

        let authResult = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AuthDataResult, Error>) in
            resolver.resolveSignIn(with: assertion) { authResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let authResult {
                    continuation.resume(returning: authResult)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseAuth", code: -1))
                }
            }
        }

        return authResult.user
    }

    private func currentFirebaseEmailAddress() -> String? {
        Auth.auth().currentUser?.email.map(normalized(email:))
    }

    private func firebaseCurrentUserProviderIDs() -> [String] {
        Auth.auth().currentUser?.providerData.map(\.providerID) ?? []
    }

    private func createFirebaseUser(email: String, password: String) async throws -> User {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().createUser(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseAuth", code: -1))
                }
            }
        }
    }

    private func signInFirebaseUser(email: String, password: String) async throws -> User {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(withEmail: email, password: password) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseAuth", code: -1))
                }
            }
        }
    }

    private func signInFirebase(with credential: AuthCredential) async throws -> User {
        try await withCheckedThrowingContinuation { continuation in
            Auth.auth().signIn(with: credential) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let user = result?.user {
                    continuation.resume(returning: user)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseAuth", code: -1))
                }
            }
        }
    }

    private func sendFirebasePasswordReset(email: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Auth.auth().sendPasswordReset(withEmail: email) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func deleteCurrentFirebaseUser() async throws {
        guard let user = Auth.auth().currentUser else {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func signInWithAppleThroughFirebase(_ credential: ASAuthorizationAppleIDCredential) async throws {
        guard let nonce = currentAppleSignInNonce else {
            throw NSError(domain: "FirebaseAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing Apple sign-in nonce."])
        }

        guard let idTokenData = credential.identityToken,
              let idTokenString = String(data: idTokenData, encoding: .utf8) else {
            throw NSError(domain: "FirebaseAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "The Apple identity token was invalid."])
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )

        _ = try await signInFirebase(with: firebaseCredential)

        currentAppleSignInNonce = nil
        let resolvedUserID = Auth.auth().currentUser?.uid ?? credential.user
        try completeSuccessfulAppleSession(userID: resolvedUserID, fullName: credential.fullName, email: credential.email ?? Auth.auth().currentUser?.email)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }

            randomBytes.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    private func firebaseAuthErrorMessage(for error: Error, defaultMessage: String) -> String {
        let nsError = error as NSError
        guard let authCode = AuthErrorCode(rawValue: nsError.code) else {
            return defaultMessage
        }

        switch authCode {
        case .invalidEmail:
            return "Enter a valid email address."
        case .emailAlreadyInUse:
            return "An account already exists for that email address."
        case .wrongPassword, .invalidCredential, .userNotFound:
            return "Incorrect email or password."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .missingOrInvalidNonce:
            return "Apple sign-in security validation failed. Try again."
        case .secondFactorRequired:
            return "A verification code is required to complete sign-in."
        case .requiresRecentLogin:
            return "For security, sign in again before deleting this account."
        case .networkError:
            return "Network error. Check your connection and try again."
        default:
            return defaultMessage
        }
    }
    #endif

    #if canImport(FirebaseAuth) && canImport(GoogleSignIn)
    private func firebaseClientID() -> String? {
        if let configuredClientID = Auth.auth().app?.options.clientID {
            return configuredClientID
        }

        if let firebaseClientID = FirebaseApp.app()?.options.clientID {
            return firebaseClientID
        }

        return Bundle.main.object(forInfoDictionaryKey: "CLIENT_ID") as? String
    }

    private func activeRootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) else {
            return nil
        }

        guard let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene.windows.first?.rootViewController else {
            return nil
        }

        return topMostViewController(from: root)
    }

    private func topMostViewController(from root: UIViewController) -> UIViewController {
        var current = root
        while let presented = current.presentedViewController {
            current = presented
        }
        return current
    }

    private func signInWithGoogleSDK(presentingViewController: UIViewController) async throws -> GIDSignInResult {
        if #available(iOS 15.0, *) {
            return try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        }

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(domain: "GoogleSignIn", code: -1))
                }
            }
        }
    }

    private func isGoogleSignInCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == GIDSignInErrorDomain, nsError.code == GIDSignInError.canceled.rawValue {
            return true
        }
        return false
    }
    #endif

    private func formattedAppleFullName(from components: PersonNameComponents?) -> String? {
        guard let components else {
            return nil
        }

        let formatter = PersonNameComponentsFormatter()
        let formattedName = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return formattedName.isEmpty ? nil : formattedName
    }

    private func refreshSandboxReceiptEnvironment() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            isSandboxReceiptEnvironment = await resolveSandboxReceiptEnvironment()
        }
    }

    private func resolveSandboxReceiptEnvironment() async -> Bool {
        if #available(iOS 18.0, *) {
            do {
                let verificationResult = try await AppTransaction.shared
                switch verificationResult {
                case .verified(let appTransaction), .unverified(let appTransaction, _):
                    return appTransaction.environment == .sandbox
                }
            } catch {
                return false
            }
        } else {
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        }
    }
}

@MainActor
@Observable
final class SubscriptionManager {
    enum SubscriptionTier: CaseIterable, Identifiable {
        case personalMonthly
        case personalYearly
        case businessMonthly
        case businessYearly

        var id: String { productID }

        var productID: String {
            switch self {
            case .personalMonthly:
                return "MeerkatMilage"
            case .personalYearly:
                return "MeerkatMilageYearly"
            case .businessMonthly:
                return "BusinessMonthly"
            case .businessYearly:
                return "BusinessYearly"
            }
        }

        var isBusiness: Bool {
            switch self {
            case .businessMonthly, .businessYearly:
                return true
            case .personalMonthly, .personalYearly:
                return false
            }
        }

        var statusTitle: String {
            switch self {
            case .personalMonthly:
                return "Personal Monthly"
            case .personalYearly:
                return "Personal Yearly"
            case .businessMonthly:
                return "Business Monthly"
            case .businessYearly:
                return "Business Yearly"
            }
        }

        init?(productID: String) {
            switch productID {
            case Self.personalMonthly.productID:
                self = .personalMonthly
            case Self.personalYearly.productID:
                self = .personalYearly
            case Self.businessMonthly.productID:
                self = .businessMonthly
            case Self.businessYearly.productID:
                self = .businessYearly
            default:
                return nil
            }
        }
    }

    private enum Constants {
        static let fallbackDisplayName = "Meerkat Subscription"
        static let fallbackPeriodDescription = "Auto-renewing subscription"
        static let fallbackPriceDescription = "Price shown in the App Store before purchase"
    }

    private var updatesTask: Task<Void, Never>?
    private var hasLoadedEntitlements = false

    private(set) var hasActiveSubscription = false
    private(set) var activeTier: SubscriptionTier?
    private(set) var activeProductID: String?
    private(set) var activeRenewalDate: Date?
    var selectedAccountType: AccountSubscriptionType = .personal
    private(set) var statusMessage = "Checking subscription status..."
    private(set) var isRefreshing = false
    private(set) var availableProductIDs: [String] = []
    private(set) var productLoadErrorMessage: String?
    private(set) var subscriptionDisplayName = "Meerkat Subscription"
    private(set) var subscriptionPeriodDescription = "1 month auto-renewing subscription"
    private(set) var subscriptionPriceDescription = "Price shown in the App Store before purchase"

    var hasBusinessSubscription: Bool {
        activeTier?.isBusiness == true
    }

    var canInviteEmployees: Bool {
        hasBusinessSubscription
    }

    var subscriptionServiceDescription: String {
        if hasBusinessSubscription {
            return "Business access unlocks full app usage and enables employee invitations and member management for your organization."
        }

        return "Personal access unlocks full app usage for a single user during each subscription period."
    }

    var activeRenewalDateLabel: String {
        guard let activeRenewalDate else {
            return "Not available"
        }
        return activeRenewalDate.formatted(date: .abbreviated, time: .omitted)
    }

    init() {
        updatesTask = Task(priority: .background) { [weak self] in
            guard let self else {
                return
            }

            await self.refreshSubscriptionStatus()
            await self.observeTransactionUpdates()
        }
    }

    var productIDs: [String] {
        switch selectedAccountType {
        case .personal:
            return [SubscriptionTier.personalMonthly.productID, SubscriptionTier.personalYearly.productID]
        case .business:
            return [SubscriptionTier.businessMonthly.productID, SubscriptionTier.businessYearly.productID]
        }
    }

    var hasLoadedStatus: Bool {
        hasLoadedEntitlements
    }

    var missingProductIDs: [String] {
        productIDs.filter { !availableProductIDs.contains($0) }
    }

    func prepare() async {
        guard !hasLoadedEntitlements else {
            return
        }

        await refreshSubscriptionStatus()
    }

    func setSelectedAccountType(_ type: AccountSubscriptionType) async {
        guard selectedAccountType != type else {
            return
        }
        selectedAccountType = type
        await refreshSubscriptionProducts()
    }

    func refreshSubscriptionStatus() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            hasLoadedEntitlements = true
        }

        await refreshSubscriptionProducts()

        var activeCandidateTier: SubscriptionTier?
        var activeCandidateProductID: String?
        var activeCandidateDate: Date = .distantPast
        var activeCandidateRenewalDate: Date?

        for await verificationResult in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verificationResult else {
                continue
            }

            guard transaction.productType == .autoRenewable else {
                continue
            }

            guard transaction.revocationDate == nil else {
                continue
            }

            if let expirationDate = transaction.expirationDate, expirationDate < .now {
                continue
            }

            guard let tier = SubscriptionTier(productID: transaction.productID) else {
                continue
            }

            let candidateDate = transaction.expirationDate ?? transaction.purchaseDate
            guard candidateDate >= activeCandidateDate else {
                continue
            }

            activeCandidateDate = candidateDate
            activeCandidateTier = tier
            activeCandidateProductID = transaction.productID
            activeCandidateRenewalDate = transaction.expirationDate
        }

        activeTier = activeCandidateTier
        activeProductID = activeCandidateProductID
        activeRenewalDate = activeCandidateRenewalDate
        hasActiveSubscription = activeCandidateTier != nil

        if let activeTier {
            selectedAccountType = activeTier.isBusiness ? .business : .personal
        }

        if let activeTier {
            statusMessage = "\(activeTier.statusTitle) subscription active."
        } else {
            statusMessage = "No active subscription."
        }
    }

    func restorePurchases() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await AppStore.sync()
            await refreshSubscriptionStatus()
            if !hasActiveSubscription {
                statusMessage = "No active subscription was found to restore."
            }
        } catch {
            statusMessage = "Could not restore purchases: \(error.localizedDescription)"
        }
    }

    func noteOfferCodeRedemptionSheetResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            statusMessage = "Offer code sheet closed. If redemption succeeds, access updates automatically."
        case .failure(let error):
            statusMessage = "Could not present offer code redemption: \(error.localizedDescription)"
        }
    }

    private func refreshSubscriptionProducts() async {
        do {
            let products = try await Product.products(for: productIDs)
            availableProductIDs = products.map(\.id).sorted()
            updateSubscriptionDisplayDetails(using: products)
            productLoadErrorMessage = nil
        } catch {
            availableProductIDs = []
            subscriptionDisplayName = Constants.fallbackDisplayName
            subscriptionPeriodDescription = Constants.fallbackPeriodDescription
            subscriptionPriceDescription = Constants.fallbackPriceDescription
            productLoadErrorMessage = error.localizedDescription
        }
    }

    private func updateSubscriptionDisplayDetails(using products: [Product]) {
        guard !products.isEmpty else {
            subscriptionDisplayName = Constants.fallbackDisplayName
            subscriptionPeriodDescription = Constants.fallbackPeriodDescription
            subscriptionPriceDescription = Constants.fallbackPriceDescription
            return
        }

        let primaryProduct: Product
        if let activeProductID,
           let matchingActiveProduct = products.first(where: { $0.id == activeProductID }) {
            primaryProduct = matchingActiveProduct
        } else if let preferredAvailableProduct = SubscriptionTier
            .allCases
            .compactMap({ tier in products.first(where: { $0.id == tier.productID }) })
            .first {
            primaryProduct = preferredAvailableProduct
        } else if let firstProduct = products.first {
            primaryProduct = firstProduct
        } else {
            subscriptionDisplayName = Constants.fallbackDisplayName
            subscriptionPeriodDescription = Constants.fallbackPeriodDescription
            subscriptionPriceDescription = Constants.fallbackPriceDescription
            return
        }

        subscriptionDisplayName = primaryProduct.displayName
        subscriptionPeriodDescription = subscriptionPeriodDescription(for: primaryProduct.subscription?.subscriptionPeriod)
        subscriptionPriceDescription = subscriptionPriceDescription(for: primaryProduct)
    }

    private func subscriptionPriceDescription(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }

        return "\(product.displayPrice) \(periodUnitPriceLabel(for: period))"
    }

    private func subscriptionPeriodDescription(for period: Product.SubscriptionPeriod?) -> String {
        guard let period else {
            return Constants.fallbackPeriodDescription
        }

        let unitLabel: String
        switch period.unit {
        case .day:
            unitLabel = period.value == 1 ? "day" : "days"
        case .week:
            unitLabel = period.value == 1 ? "week" : "weeks"
        case .month:
            unitLabel = period.value == 1 ? "month" : "months"
        case .year:
            unitLabel = period.value == 1 ? "year" : "years"
        @unknown default:
            unitLabel = "period"
        }

        return "\(period.value) \(unitLabel) auto-renewing subscription"
    }

    private func periodUnitPriceLabel(for period: Product.SubscriptionPeriod) -> String {
        let unitLabel: String
        switch period.unit {
        case .day:
            unitLabel = "day"
        case .week:
            unitLabel = "week"
        case .month:
            unitLabel = "month"
        case .year:
            unitLabel = "year"
        @unknown default:
            unitLabel = "period"
        }

        return "per \(unitLabel)"
    }

    private func observeTransactionUpdates() async {
        for await verificationResult in Transaction.updates {
            guard case .verified(let transaction) = verificationResult else {
                continue
            }

            if transaction.productType == .autoRenewable {
                await refreshSubscriptionStatus()
            }

            await transaction.finish()
        }
    }

}

@MainActor
@Observable
final class CloudSyncManager {
    struct SyncAuditEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let provider: String
        let action: String
        let outcome: String
        let summary: String
    }

    fileprivate enum Constants {
        static let cloudContainerIdentifier = "iCloud.com.miletracker.app.Meerkat---Milage-Tracker"
        static let customZoneName = "MeerkatData"
        static let settingsRecordType = "AppSettings"
        static let trackerSettingsRecordType = "TrackerSettings"
        static let vehicleRecordType = "Vehicle"
        static let driverRecordType = "Driver"
        static let tripRecordType = "Trip"
        static let fuelEntryRecordType = "FuelEntry"
        static let maintenanceRecordType = "MaintenanceRecord"
        static let logRecordType = "LogEntry"
        static let allowanceAdjustmentRecordType = "AllowanceAdjustment"
        static let settingsRecordName = "app-settings"
        static let trackerSettingsRecordName = "tracker-settings"
        static let payloadKey = "payload"
        static let updatedAtKey = "updatedAt"
        static let maximumModifyItemsPerRequest = 200
        static let firebaseUsersCollection = "users"
        static let firebaseSnapshotCollection = "appData"
        static let firebaseSnapshotDocument = "current"
        static let firebaseSnapshotChunksCollection = "snapshotChunks"
        static let firebaseVehiclesCollection = "vehicles"
        static let firebaseDriversCollection = "drivers"
        static let firebaseTripsCollection = "trips"
        static let firebaseFuelEntriesCollection = "fuelEntries"
        static let firebaseMaintenanceRecordsCollection = "maintenanceRecords"
        static let firebaseLogsCollection = "logs"
        static let firebaseAllowanceAdjustmentsCollection = "allowanceAdjustments"
        static let firebaseOrganizationsCollection = "organizations"
        static let firebaseOrganizationMembershipsCollection = "organizationMemberships"
        static let firebaseFuelReceiptPathsKey = "fuelReceiptPaths"
        static let firebaseMaintenanceReceiptPathsKey = "maintenanceReceiptPaths"
        static let firebaseReceiptsFolder = "receipts"
        static let firebaseFuelReceiptsFolder = "fuel"
        static let firebaseMaintenanceReceiptsFolder = "maintenance"
        static let firebaseReceiptMaximumDownloadBytes = 12 * 1_024 * 1_024
        static let firebaseUpdatedAtKey = "updatedAt"
        static let firebaseLastSyncedAtKey = "lastSyncedAt"
        static let firebasePayloadChunkCountKey = "payloadChunkCount"
        static let firebasePayloadChunkDataKey = "payloadChunk"
        static let firebasePayloadChunkSize = 900_000
        // Keep batches well below Firestore hard limits to avoid "Transaction too big"
        // failures when records carry large payloads (e.g., long routes/notes).
        static let firebaseMaxBatchOperations = 75
    }

    private var container: CKContainer?
    private var database: CKDatabase?
    private var lastUploadedSnapshot: AppPersistenceSnapshot?
    private var pendingUploadSnapshot: AppPersistenceSnapshot?
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "Meerkat.CloudSyncMonitor")
    private let maxAuditEntries = 60
    private var lastSuccessfulSyncDate: Date?

    var statusMessage = "Cloud sync not started."
    var isSyncing = false
    var hasCompletedInitialSync = false
    var recentSyncAuditEntries: [SyncAuditEntry] = []
    var latestUploadedTripID: UUID?
    var latestUploadedFuelEntryID: UUID?
    var latestUploadedMaintenanceRecordID: UUID?
    var uploadedTripIDs: Set<UUID> = []
    var uploadedFuelEntryIDs: Set<UUID> = []
    var uploadedMaintenanceRecordIDs: Set<UUID> = []
    var pendingTripIDs: Set<UUID> = []
    var pendingFuelEntryIDs: Set<UUID> = []
    var pendingMaintenanceRecordIDs: Set<UUID> = []

    init() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else {
                return
            }

            Task { @MainActor [weak self] in
                await self?.retryPendingUploadIfPossible()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private var customZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Constants.customZoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var defaultZoneID: CKRecordZone.ID {
        CKRecordZone.default().zoneID
    }

    func resetSession() {
        statusMessage = "Cloud sync not started."
        isSyncing = false
        hasCompletedInitialSync = false
        lastUploadedSnapshot = nil
        pendingUploadSnapshot = nil
        recentSyncAuditEntries = []
        latestUploadedTripID = nil
        latestUploadedFuelEntryID = nil
        latestUploadedMaintenanceRecordID = nil
        uploadedTripIDs = []
        uploadedFuelEntryIDs = []
        uploadedMaintenanceRecordIDs = []
        pendingTripIDs = []
        pendingFuelEntryIDs = []
        pendingMaintenanceRecordIDs = []
        lastSuccessfulSyncDate = nil
    }

    private func providerLabel() -> String {
        usesFirebaseSync ? "Firebase" : "iCloud"
    }

    private func snapshotSummary(_ snapshot: AppPersistenceSnapshot) -> String {
        "vehicles:\(snapshot.store.vehicles.count) archivedVehicles:\(snapshot.store.archivedVehicles.count) drivers:\(snapshot.store.drivers.count) archivedDrivers:\(snapshot.store.archivedDrivers.count) trips:\(snapshot.store.trips.count) fuel:\(snapshot.store.fuelEntries.count) maintenance:\(snapshot.store.maintenanceRecords.count) logs:\(snapshot.store.logs.count)"
    }

    private func appendAudit(
        action: String,
        outcome: String,
        snapshot: AppPersistenceSnapshot?
    ) {
        let summary = snapshot.map(snapshotSummary) ?? "no-snapshot"
        let entry = SyncAuditEntry(
            timestamp: .now,
            provider: providerLabel(),
            action: action,
            outcome: outcome,
            summary: summary
        )
        recentSyncAuditEntries.append(entry)
        if recentSyncAuditEntries.count > maxAuditEntries {
            recentSyncAuditEntries.removeFirst(recentSyncAuditEntries.count - maxAuditEntries)
        }
        print("[CloudSyncAudit] \(entry.timestamp.formatted(date: .abbreviated, time: .standard)) \(entry.provider) \(entry.action) \(entry.outcome) \(entry.summary)")
    }

    private func markSnapshotAsUploaded(_ snapshot: AppPersistenceSnapshot) {
        lastUploadedSnapshot = snapshot
        lastSuccessfulSyncDate = .now
        latestUploadedTripID = snapshot.store.trips.first?.id
        latestUploadedFuelEntryID = snapshot.store.fuelEntries.first?.id
        latestUploadedMaintenanceRecordID = snapshot.store.maintenanceRecords.first?.id
        uploadedTripIDs = Set(snapshot.store.trips.map(\.id))
        uploadedFuelEntryIDs = Set(snapshot.store.fuelEntries.map(\.id))
        uploadedMaintenanceRecordIDs = Set(snapshot.store.maintenanceRecords.map(\.id))
        pendingTripIDs = []
        pendingFuelEntryIDs = []
        pendingMaintenanceRecordIDs = []
    }

    func shouldRefreshOnForeground(snapshot: AppPersistenceSnapshot, minimumInterval: TimeInterval) -> Bool {
        guard hasCompletedInitialSync else {
            return true
        }

        if isSyncing {
            return false
        }

        if pendingUploadSnapshot != nil || !pendingTripIDs.isEmpty || !pendingFuelEntryIDs.isEmpty || !pendingMaintenanceRecordIDs.isEmpty {
            return true
        }

        guard let lastUploadedSnapshot else {
            return true
        }

        if snapshot != lastUploadedSnapshot {
            return true
        }

        guard let lastSuccessfulSyncDate else {
            return true
        }

        return Date().timeIntervalSince(lastSuccessfulSyncDate) >= minimumInterval
    }

    func markLocalSnapshotDirty(_ snapshot: AppPersistenceSnapshot) {
        guard let lastUploadedSnapshot else {
            uploadedTripIDs = []
            uploadedFuelEntryIDs = []
            uploadedMaintenanceRecordIDs = []
            latestUploadedTripID = nil
            latestUploadedFuelEntryID = nil
            latestUploadedMaintenanceRecordID = nil
            pendingTripIDs = Set(snapshot.store.trips.map(\.id))
            pendingFuelEntryIDs = Set(snapshot.store.fuelEntries.map(\.id))
            pendingMaintenanceRecordIDs = Set(snapshot.store.maintenanceRecords.map(\.id))
            return
        }

        let uploadedTripsByID = Dictionary(uniqueKeysWithValues: lastUploadedSnapshot.store.trips.map { ($0.id, $0) })
        uploadedTripIDs = Set(
            snapshot.store.trips.compactMap { trip in
                uploadedTripsByID[trip.id] == trip ? trip.id : nil
            }
        )
        if let latestUploadedTripID, !uploadedTripIDs.contains(latestUploadedTripID) {
            self.latestUploadedTripID = nil
        }
        pendingTripIDs = Set(snapshot.store.trips.map(\.id)).subtracting(uploadedTripIDs)

        let uploadedFuelEntriesByID = Dictionary(uniqueKeysWithValues: lastUploadedSnapshot.store.fuelEntries.map { ($0.id, $0) })
        uploadedFuelEntryIDs = Set(
            snapshot.store.fuelEntries.compactMap { entry in
                uploadedFuelEntriesByID[entry.id] == entry ? entry.id : nil
            }
        )
        if let latestUploadedFuelEntryID, !uploadedFuelEntryIDs.contains(latestUploadedFuelEntryID) {
            self.latestUploadedFuelEntryID = nil
        }
        pendingFuelEntryIDs = Set(snapshot.store.fuelEntries.map(\.id)).subtracting(uploadedFuelEntryIDs)

        let uploadedMaintenanceRecordsByID = Dictionary(uniqueKeysWithValues: lastUploadedSnapshot.store.maintenanceRecords.map { ($0.id, $0) })
        uploadedMaintenanceRecordIDs = Set(
            snapshot.store.maintenanceRecords.compactMap { record in
                uploadedMaintenanceRecordsByID[record.id] == record ? record.id : nil
            }
        )
        if let latestUploadedMaintenanceRecordID, !uploadedMaintenanceRecordIDs.contains(latestUploadedMaintenanceRecordID) {
            self.latestUploadedMaintenanceRecordID = nil
        }
        pendingMaintenanceRecordIDs = Set(snapshot.store.maintenanceRecords.map(\.id)).subtracting(uploadedMaintenanceRecordIDs)
    }

    func syncLocalChanges(snapshot: AppPersistenceSnapshot) async {
        guard !snapshot.isEmpty else {
            return
        }

        if usesFirebaseSync {
            if isSyncing {
                pendingUploadSnapshot = snapshot
                statusMessage = "Cloud sync queued."
                return
            }
            await uploadSnapshot(snapshot, markInitialSyncComplete: hasCompletedInitialSync)
            return
        }

        if isSyncing {
            pendingUploadSnapshot = snapshot
            statusMessage = "Cloud sync queued."
            return
        }

        await uploadSnapshot(snapshot, markInitialSyncComplete: hasCompletedInitialSync)
    }

    func performInitialSync(localSnapshot: AppPersistenceSnapshot) async -> AppPersistenceSnapshot? {
        guard !hasCompletedInitialSync else {
            return nil
        }

        if usesFirebaseSync {
            isSyncing = true
            defer {
                isSyncing = false
                hasCompletedInitialSync = true
            }

            do {
                if let remoteSnapshot = try await fetchFirebaseSnapshot() {
                    let mergedSnapshot = mergeSnapshots(local: localSnapshot, remote: remoteSnapshot, baseline: .empty)
                    if mergedSnapshot != remoteSnapshot {
                        try await uploadFirebaseSnapshot(mergedSnapshot)
                    }
                    markSnapshotAsUploaded(mergedSnapshot)
                    statusMessage = mergedSnapshot == remoteSnapshot ? "Cloud data restored." : "Cloud data merged."
                    appendAudit(
                        action: "initial-sync",
                        outcome: mergedSnapshot == remoteSnapshot ? "restored" : "merged",
                        snapshot: mergedSnapshot
                    )
                    return mergedSnapshot == localSnapshot ? nil : mergedSnapshot
                }

                if !localSnapshot.isEmpty {
                    try await uploadFirebaseSnapshot(localSnapshot)
                    markSnapshotAsUploaded(localSnapshot)
                    statusMessage = "Cloud backup created."
                    appendAudit(action: "initial-sync", outcome: "uploaded-local-backup", snapshot: localSnapshot)
                } else {
                    statusMessage = "Cloud sync is ready."
                    appendAudit(action: "initial-sync", outcome: "ready-no-data", snapshot: localSnapshot)
                }
            } catch {
                statusMessage = "Cloud sync failed: \(error.localizedDescription)"
                appendAudit(action: "initial-sync", outcome: "failed: \(error.localizedDescription)", snapshot: localSnapshot)
            }

            return nil
        }

        guard configureCloudKitIfPossible() else {
            statusMessage = "Cloud sync is not configured yet."
            hasCompletedInitialSync = true
            return nil
        }

        isSyncing = true
        defer {
            isSyncing = false
            hasCompletedInitialSync = true
        }

        do {
            let accountStatus = try await accountStatus()
            switch accountStatus {
            case .available:
                break
            case .noAccount:
                statusMessage = "Sign in to iCloud in Settings to sync data."
                return nil
            case .restricted:
                statusMessage = "iCloud sync is restricted on this device."
                return nil
            case .couldNotDetermine:
                statusMessage = "The app couldn't determine iCloud status."
                return nil
            case .temporarilyUnavailable:
                statusMessage = "iCloud is temporarily unavailable."
                return nil
            @unknown default:
                statusMessage = "The current iCloud status isn't supported."
                return nil
            }

            try await ensureCustomZoneExists()

            if let remoteSnapshot = try await fetchRemoteSnapshot() {
                let mergedSnapshot = mergeSnapshots(
                    local: localSnapshot,
                    remote: remoteSnapshot,
                    baseline: .empty
                )
                if mergedSnapshot != remoteSnapshot {
                    try await upload(snapshot: mergedSnapshot)
                }

                markSnapshotAsUploaded(mergedSnapshot)
                statusMessage = mergedSnapshot == remoteSnapshot ? "Cloud data restored." : "Cloud data merged."
                appendAudit(
                    action: "initial-sync",
                    outcome: mergedSnapshot == remoteSnapshot ? "restored" : "merged",
                    snapshot: mergedSnapshot
                )
                return mergedSnapshot == localSnapshot ? nil : mergedSnapshot
            }

            if !localSnapshot.isEmpty {
                try await upload(snapshot: localSnapshot)
                markSnapshotAsUploaded(localSnapshot)
                statusMessage = "Cloud backup created."
                appendAudit(action: "initial-sync", outcome: "uploaded-local-backup", snapshot: localSnapshot)
            } else {
                statusMessage = "Cloud sync is ready."
                appendAudit(action: "initial-sync", outcome: "ready-no-data", snapshot: localSnapshot)
            }
        } catch {
            statusMessage = "Cloud sync failed: \(error.localizedDescription)"
            appendAudit(action: "initial-sync", outcome: "failed: \(error.localizedDescription)", snapshot: localSnapshot)
        }

        return nil
    }

    func backupToCloud(snapshot: AppPersistenceSnapshot) async {
        guard !snapshot.isEmpty else {
            statusMessage = "There is no local data to upload."
            return
        }

        if usesFirebaseSync {
            isSyncing = true
            defer {
                isSyncing = false
                hasCompletedInitialSync = true
            }

            do {
                try await uploadFirebaseSnapshot(snapshot)
                markSnapshotAsUploaded(snapshot)
                statusMessage = "Cloud backup complete."
            } catch {
                statusMessage = "Cloud backup failed: \(error.localizedDescription)"
            }
            return
        }

        guard configureCloudKitIfPossible() else {
            statusMessage = "Cloud sync is not configured yet."
            return
        }

        do {
            try await validateAccountAvailability()
        } catch {
            statusMessage = "Cloud backup unavailable: \(error.localizedDescription)"
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            hasCompletedInitialSync = true
        }

        do {
            try await ensureCustomZoneExists()
            try await upload(snapshot: snapshot)
            markSnapshotAsUploaded(snapshot)
            statusMessage = "Cloud backup complete."
        } catch {
            statusMessage = "Cloud backup failed: \(error.localizedDescription)"
        }
    }

    func deleteAccountDataFromCloud() async throws {
        if usesFirebaseSync {
            isSyncing = true
            defer {
                isSyncing = false
            }

            do {
                try await deleteFirebaseSnapshot()
                lastUploadedSnapshot = nil
                latestUploadedTripID = nil
                latestUploadedFuelEntryID = nil
                latestUploadedMaintenanceRecordID = nil
                uploadedTripIDs = []
                uploadedFuelEntryIDs = []
                uploadedMaintenanceRecordIDs = []
                pendingTripIDs = []
                pendingFuelEntryIDs = []
                pendingMaintenanceRecordIDs = []
                pendingUploadSnapshot = nil
                hasCompletedInitialSync = false
                statusMessage = "Cloud account data deleted."
                return
            } catch {
                statusMessage = "Cloud account deletion failed: \(error.localizedDescription)"
                throw error
            }
        }

        guard configureCloudKitIfPossible() else {
            throw CKError(.serviceUnavailable)
        }

        try await validateAccountAvailability()

        isSyncing = true
        defer {
            isSyncing = false
        }

        do {
            try await deleteCustomZoneIfPresent()
            lastUploadedSnapshot = nil
            latestUploadedTripID = nil
            latestUploadedFuelEntryID = nil
            latestUploadedMaintenanceRecordID = nil
            uploadedTripIDs = []
            uploadedFuelEntryIDs = []
            uploadedMaintenanceRecordIDs = []
            pendingTripIDs = []
            pendingFuelEntryIDs = []
            pendingMaintenanceRecordIDs = []
            pendingUploadSnapshot = nil
            hasCompletedInitialSync = false
            statusMessage = "Cloud account data deleted."
        } catch {
            statusMessage = "Cloud account deletion failed: \(error.localizedDescription)"
            throw error
        }
    }

    func uploadIfNeeded(snapshot: AppPersistenceSnapshot) async {
        guard hasCompletedInitialSync, !snapshot.isEmpty, snapshot != lastUploadedSnapshot else {
            return
        }
        await uploadSnapshot(snapshot, markInitialSyncComplete: true)
    }

    func restoreFromCloud() async -> AppPersistenceSnapshot? {
        if usesFirebaseSync {
            isSyncing = true
            defer {
                isSyncing = false
                hasCompletedInitialSync = true
            }

            do {
                guard let remoteSnapshot = try await fetchFirebaseSnapshot() else {
                    statusMessage = "No cloud backup was found."
                    appendAudit(action: "restore", outcome: "no-backup", snapshot: nil)
                    return nil
                }
                markSnapshotAsUploaded(remoteSnapshot)
                statusMessage = "Cloud data restored."
                appendAudit(action: "restore", outcome: "restored", snapshot: remoteSnapshot)
                return remoteSnapshot
            } catch {
                statusMessage = "Cloud restore failed: \(error.localizedDescription)"
                appendAudit(action: "restore", outcome: "failed: \(error.localizedDescription)", snapshot: nil)
                return nil
            }
        }

        guard configureCloudKitIfPossible() else {
            statusMessage = "Cloud sync is not configured yet."
            return nil
        }

        do {
            try await ensureCustomZoneExists()
            try await validateAccountAvailability()
        } catch {
            statusMessage = "Cloud restore unavailable: \(error.localizedDescription)"
            appendAudit(action: "restore", outcome: "unavailable: \(error.localizedDescription)", snapshot: nil)
            return nil
        }

        isSyncing = true
        defer {
            isSyncing = false
            hasCompletedInitialSync = true
        }

        do {
            guard let remoteSnapshot = try await fetchRemoteSnapshot() else {
                statusMessage = "No cloud backup was found."
                appendAudit(action: "restore", outcome: "no-backup", snapshot: nil)
                return nil
            }

            markSnapshotAsUploaded(remoteSnapshot)
            statusMessage = "Cloud data restored."
            appendAudit(action: "restore", outcome: "restored", snapshot: remoteSnapshot)
            return remoteSnapshot
        } catch {
            statusMessage = "Cloud restore failed: \(error.localizedDescription)"
            appendAudit(action: "restore", outcome: "failed: \(error.localizedDescription)", snapshot: nil)
            return nil
        }
    }

    func refreshFromCloud() async -> AppPersistenceSnapshot? {
        guard hasCompletedInitialSync else {
            return nil
        }

        return await restoreFromCloud()
    }

    func sync(snapshot: AppPersistenceSnapshot, preferRemoteOnFirstSync: Bool = false) async -> AppPersistenceSnapshot? {
        if usesFirebaseSync {
            isSyncing = true
            defer {
                isSyncing = false
                hasCompletedInitialSync = true
            }

            do {
                let previousSnapshot = lastUploadedSnapshot ?? .empty
                if let remoteSnapshot = try await fetchFirebaseSnapshot() {
                    if lastUploadedSnapshot == nil, preferRemoteOnFirstSync, snapshot.isEmpty {
                        markSnapshotAsUploaded(remoteSnapshot)
                        statusMessage = "Cloud data restored."
                        appendAudit(action: "sync", outcome: "restored-prefer-remote", snapshot: remoteSnapshot)
                        return remoteSnapshot
                    }

                    let mergedSnapshot = mergeSnapshots(local: snapshot, remote: remoteSnapshot, baseline: previousSnapshot)
                    if mergedSnapshot != remoteSnapshot {
                        try await uploadFirebaseSnapshot(mergedSnapshot)
                    }
                    markSnapshotAsUploaded(mergedSnapshot)

                    if mergedSnapshot != snapshot {
                        statusMessage = mergedSnapshot == remoteSnapshot ? "Cloud data updated." : "Cloud data merged."
                        appendAudit(
                            action: "sync",
                            outcome: mergedSnapshot == remoteSnapshot ? "updated-from-remote" : "merged-local-remote",
                            snapshot: mergedSnapshot
                        )
                        return mergedSnapshot
                    }

                    statusMessage = mergedSnapshot == previousSnapshot ? "Cloud sync up to date." : "Cloud sync complete."
                    appendAudit(
                        action: "sync",
                        outcome: mergedSnapshot == previousSnapshot ? "up-to-date" : "complete-no-local-change",
                        snapshot: mergedSnapshot
                    )
                    return nil
                }

                guard !snapshot.isEmpty, snapshot != previousSnapshot else {
                    statusMessage = lastUploadedSnapshot == nil ? "Cloud sync is ready." : "Cloud sync up to date."
                    appendAudit(
                        action: "sync",
                        outcome: lastUploadedSnapshot == nil ? "ready-no-data" : "up-to-date",
                        snapshot: snapshot
                    )
                    return nil
                }

                try await uploadFirebaseSnapshot(snapshot)
                markSnapshotAsUploaded(snapshot)
                statusMessage = lastUploadedSnapshot == nil ? "Cloud backup created." : "Cloud sync complete."
                appendAudit(action: "sync", outcome: "uploaded-local-snapshot", snapshot: snapshot)
            } catch {
                statusMessage = "Cloud sync failed: \(error.localizedDescription)"
                appendAudit(action: "sync", outcome: "failed: \(error.localizedDescription)", snapshot: snapshot)
            }

            return nil
        }

        guard configureCloudKitIfPossible() else {
            statusMessage = "Cloud sync is not configured yet."
            hasCompletedInitialSync = true
            return nil
        }

        isSyncing = true
        defer {
            isSyncing = false
            hasCompletedInitialSync = true
        }

        do {
            try await validateAccountAvailability()
            try await ensureCustomZoneExists()

            let previousSnapshot = lastUploadedSnapshot ?? AppPersistenceSnapshot.empty
            if let remoteSnapshot = try await fetchRemoteSnapshot() {
                if lastUploadedSnapshot == nil, preferRemoteOnFirstSync, snapshot.isEmpty {
                    markSnapshotAsUploaded(remoteSnapshot)
                    statusMessage = "Cloud data restored."
                    appendAudit(action: "sync", outcome: "restored-prefer-remote", snapshot: remoteSnapshot)
                    return remoteSnapshot
                }

                let mergedSnapshot = mergeSnapshots(
                    local: snapshot,
                    remote: remoteSnapshot,
                    baseline: previousSnapshot
                )

                if mergedSnapshot != remoteSnapshot {
                    try await upload(snapshot: mergedSnapshot)
                }

                markSnapshotAsUploaded(mergedSnapshot)

                if mergedSnapshot != snapshot {
                    statusMessage = mergedSnapshot == remoteSnapshot ? "Cloud data updated from iCloud." : "Cloud data merged."
                    appendAudit(
                        action: "sync",
                        outcome: mergedSnapshot == remoteSnapshot ? "updated-from-remote" : "merged-local-remote",
                        snapshot: mergedSnapshot
                    )
                    return mergedSnapshot
                }

                statusMessage = mergedSnapshot == previousSnapshot ? "Cloud sync up to date." : "Cloud sync complete."
                appendAudit(
                    action: "sync",
                    outcome: mergedSnapshot == previousSnapshot ? "up-to-date" : "complete-no-local-change",
                    snapshot: mergedSnapshot
                )
                return nil
            }

            guard !snapshot.isEmpty, snapshot != previousSnapshot else {
                statusMessage = lastUploadedSnapshot == nil ? "Cloud sync is ready." : "Cloud sync up to date."
                appendAudit(
                    action: "sync",
                    outcome: lastUploadedSnapshot == nil ? "ready-no-data" : "up-to-date",
                    snapshot: snapshot
                )
                return nil
            }

            let isFirstUpload = lastUploadedSnapshot == nil
            try await upload(snapshot: snapshot)
            markSnapshotAsUploaded(snapshot)
            statusMessage = isFirstUpload ? "Cloud backup created." : "Cloud sync complete."
            appendAudit(action: "sync", outcome: isFirstUpload ? "uploaded-first-backup" : "uploaded-local-snapshot", snapshot: snapshot)
        } catch {
            statusMessage = "Cloud sync failed: \(error.localizedDescription)"
            appendAudit(action: "sync", outcome: "failed: \(error.localizedDescription)", snapshot: snapshot)
        }

        return nil
    }

    private func uploadSnapshot(_ snapshot: AppPersistenceSnapshot, markInitialSyncComplete: Bool) async {
        if usesFirebaseSync {
            isSyncing = true
            defer {
                isSyncing = false
                if markInitialSyncComplete {
                    hasCompletedInitialSync = true
                }
                if let pendingUploadSnapshot,
                   pendingUploadSnapshot != lastUploadedSnapshot,
                   pendingUploadSnapshot != snapshot {
                    Task { @MainActor [weak self] in
                        await self?.retryPendingUploadIfPossible()
                    }
                }
            }

            do {
                try await uploadFirebaseSnapshot(snapshot)
                markSnapshotAsUploaded(snapshot)
                if pendingUploadSnapshot == snapshot {
                    pendingUploadSnapshot = nil
                }
                statusMessage = "Cloud sync complete."
                appendAudit(action: "upload", outcome: "success", snapshot: snapshot)
            } catch {
                if pendingUploadSnapshot == nil {
                    pendingUploadSnapshot = snapshot
                }
                statusMessage = "Cloud sync pending: \(error.localizedDescription)"
                appendAudit(action: "upload", outcome: "pending: \(error.localizedDescription)", snapshot: snapshot)
            }
            return
        }

        guard configureCloudKitIfPossible() else {
            pendingUploadSnapshot = snapshot
            statusMessage = "Cloud sync is not configured yet."
            appendAudit(action: "upload", outcome: "not-configured", snapshot: snapshot)
            return
        }

        isSyncing = true
        defer {
            isSyncing = false
            if markInitialSyncComplete {
                hasCompletedInitialSync = true
            }
            if let pendingUploadSnapshot,
               pendingUploadSnapshot != lastUploadedSnapshot,
               pendingUploadSnapshot != snapshot {
                Task { @MainActor [weak self] in
                    await self?.retryPendingUploadIfPossible()
                }
            }
        }

        do {
            try await validateAccountAvailability()
            try await ensureCustomZoneExists()
            try await upload(snapshot: snapshot)
            markSnapshotAsUploaded(snapshot)
            if pendingUploadSnapshot == snapshot {
                pendingUploadSnapshot = nil
            }
            statusMessage = "Cloud sync complete."
            appendAudit(action: "upload", outcome: "success", snapshot: snapshot)
        } catch {
            if pendingUploadSnapshot == nil {
                pendingUploadSnapshot = snapshot
            }
            statusMessage = "Cloud sync pending: \(error.localizedDescription)"
            appendAudit(action: "upload", outcome: "pending: \(error.localizedDescription)", snapshot: snapshot)
        }
    }

    private func retryPendingUploadIfPossible() async {
        guard let pendingUploadSnapshot, !isSyncing else {
            return
        }

        await uploadSnapshot(pendingUploadSnapshot, markInitialSyncComplete: hasCompletedInitialSync)
    }

    private var usesFirebaseSync: Bool {
        #if canImport(FirebaseAuth)
        Auth.auth().currentUser != nil
        #else
        false
        #endif
    }

    #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
    private var firebaseUserID: String? {
        Auth.auth().currentUser?.uid
    }

    private var firebaseUserDocument: DocumentReference? {
        guard let userID = firebaseUserID else {
            return nil
        }
        return Firestore.firestore()
            .collection(Constants.firebaseUsersCollection)
            .document(userID)
    }

    private var firebaseSnapshotDocument: DocumentReference? {
        guard let userDocument = firebaseUserDocument else {
            return nil
        }
        return userDocument
            .collection(Constants.firebaseSnapshotCollection)
            .document(Constants.firebaseSnapshotDocument)
    }

    private func firebaseOrganizationDocument(for snapshot: AppPersistenceSnapshot) -> DocumentReference? {
        guard let organizationID = snapshot.store.activeOrganizationID?.uuidString else {
            return nil
        }

        return Firestore.firestore()
            .collection(Constants.firebaseOrganizationsCollection)
            .document(organizationID)
    }

    private func fetchFirebaseSnapshot() async throws -> AppPersistenceSnapshot? {
        guard let document = firebaseSnapshotDocument else {
            return nil
        }

        let snapshotDocument = try await fetchFirebaseDocumentSnapshot(document)
        var resolvedSnapshot: AppPersistenceSnapshot?
        var receiptManifest = FirebaseReceiptManifest(documentData: snapshotDocument.data())

        if snapshotDocument.exists {
            do {
                let payload = try await fetchFirebasePayloadString(from: snapshotDocument, document: document)
                if let data = Data(base64Encoded: payload) {
                    resolvedSnapshot = try AppPersistenceSnapshot.decoded(from: data)
                }
            } catch {
                // Legacy payload/chunks may be missing or malformed; continue with structured collections.
                resolvedSnapshot = nil
            }
        }

        let structuredSnapshot = try await fetchFirebaseStructuredSnapshot(
            overlaying: resolvedSnapshot ?? .empty
        )

        if let structuredSnapshot {
            resolvedSnapshot = structuredSnapshot.snapshot
            receiptManifest = structuredSnapshot.receiptManifest
        }

        guard let resolvedSnapshot else {
            return nil
        }

        return try await hydrateFirebaseSnapshot(resolvedSnapshot, receiptManifest: receiptManifest)
    }

    private func uploadFirebaseSnapshot(_ snapshot: AppPersistenceSnapshot) async throws {
        guard let document = firebaseSnapshotDocument else {
            throw NSError(domain: "Firestore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated Firebase user."])
        }

        let existingSnapshot = try await fetchFirebaseDocumentSnapshot(document)
        let existingManifest = FirebaseReceiptManifest(documentData: existingSnapshot.data())
        let preparedUpload = try await prepareFirebaseSnapshotForUpload(snapshot)
        let payload = try preparedUpload.snapshot.encodedData().base64EncodedString()
        let payloadChunks = chunkedFirebasePayload(payload)
        let values: [String: Any] = [
            Constants.updatedAtKey: Timestamp(date: .now),
            Constants.firebaseFuelReceiptPathsKey: preparedUpload.receiptManifest.fuelEntryPaths,
            Constants.firebaseMaintenanceReceiptPathsKey: preparedUpload.receiptManifest.maintenanceRecordPaths,
            Constants.firebasePayloadChunkCountKey: payloadChunks.count,
        ]

        try await deleteFirebaseReceiptAssets(
            at: Array(existingManifest.allPaths.subtracting(preparedUpload.receiptManifest.allPaths))
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(values) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        try await syncFirebasePayloadChunks(payloadChunks, for: document)

        try await syncFirebaseStructuredCollections(
            snapshot,
            receiptManifest: preparedUpload.receiptManifest
        )
    }

    private func deleteFirebaseSnapshot() async throws {
        guard let document = firebaseSnapshotDocument,
              let userDocument = firebaseUserDocument
        else {
            return
        }

        let snapshot = try await fetchFirebaseDocumentSnapshot(document)
        let manifest = FirebaseReceiptManifest(documentData: snapshot.data())
        try await deleteFirebaseReceiptAssets(at: Array(manifest.allPaths))
        try await deleteFirebasePayloadChunks(for: document)
        try await deleteFirebaseStructuredCollections(for: userDocument)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            userDocument.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func fetchFirebaseDocumentSnapshot(_ document: DocumentReference) async throws -> DocumentSnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<DocumentSnapshot, Error>) in
            document.getDocument { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(domain: "Firestore", code: -1))
                }
            }
        }
    }

    private func fetchFirebasePayloadString(
        from snapshot: DocumentSnapshot,
        document: DocumentReference
    ) async throws -> String {
        if let payload = snapshot.data()?[Constants.payloadKey] as? String {
            return payload
        }

        guard let chunkCount = snapshot.data()?[Constants.firebasePayloadChunkCountKey] as? Int,
              chunkCount > 0
        else {
            throw NSError(
                domain: "Firestore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cloud payload metadata is missing."]
            )
        }

        let chunksCollection = document.collection(Constants.firebaseSnapshotChunksCollection)
        var payload = ""
        payload.reserveCapacity(chunkCount * Constants.firebasePayloadChunkSize)

        for index in 0..<chunkCount {
            let chunkDocument = try await fetchFirebaseDocumentSnapshot(
                chunksCollection.document(firebasePayloadChunkDocumentID(for: index))
            )
            guard let chunk = chunkDocument.data()?[Constants.firebasePayloadChunkDataKey] as? String else {
                throw NSError(
                    domain: "Firestore",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cloud payload chunk \(index) is missing."]
                )
            }
            payload.append(chunk)
        }

        return payload
    }

    private func chunkedFirebasePayload(_ payload: String) -> [String] {
        guard !payload.isEmpty else {
            return [""]
        }

        var chunks: [String] = []
        var startIndex = payload.startIndex

        while startIndex < payload.endIndex {
            let endIndex = payload.index(
                startIndex,
                offsetBy: Constants.firebasePayloadChunkSize,
                limitedBy: payload.endIndex
            ) ?? payload.endIndex
            chunks.append(String(payload[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return chunks
    }

    private func firebasePayloadChunkDocumentID(for index: Int) -> String {
        String(format: "chunk-%04d", index)
    }

    private func syncFirebasePayloadChunks(
        _ chunks: [String],
        for document: DocumentReference
    ) async throws {
        let chunksCollection = document.collection(Constants.firebaseSnapshotChunksCollection)
        let existingChunkIDs = try await fetchFirebaseCollectionDocumentIDs(chunksCollection)
        let desiredChunkIDs = Set(chunks.indices.map(firebasePayloadChunkDocumentID(for:)))
        let staleChunkIDs = existingChunkIDs.subtracting(desiredChunkIDs)

        for (index, chunk) in chunks.enumerated() {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                chunksCollection.document(firebasePayloadChunkDocumentID(for: index)).setData([
                    Constants.firebasePayloadChunkDataKey: chunk,
                    Constants.updatedAtKey: Timestamp(date: .now),
                ]) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }

        for staleChunkID in staleChunkIDs {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                chunksCollection.document(staleChunkID).delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func deleteFirebasePayloadChunks(for document: DocumentReference) async throws {
        let chunksCollection = document.collection(Constants.firebaseSnapshotChunksCollection)
        let chunkIDs = try await fetchFirebaseCollectionDocumentIDs(chunksCollection)
        for chunkID in chunkIDs {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                chunksCollection.document(chunkID).delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func prepareFirebaseSnapshotForUpload(_ snapshot: AppPersistenceSnapshot) async throws -> (snapshot: AppPersistenceSnapshot, receiptManifest: FirebaseReceiptManifest) {
        #if canImport(FirebaseStorage)
        guard let userID = firebaseUserID else {
            return (snapshot, .empty)
        }

        var sanitizedFuelEntries = snapshot.store.fuelEntries
        var fuelEntryPaths: [String: String] = [:]
        for index in sanitizedFuelEntries.indices {
            guard let receiptData = sanitizedFuelEntries[index].receiptImageData, !receiptData.isEmpty else {
                continue
            }

            let path = firebaseReceiptPath(
                for: .fuel,
                userID: userID,
                itemID: sanitizedFuelEntries[index].id
            )
            try await uploadFirebaseReceiptData(receiptData, to: path)
            sanitizedFuelEntries[index].receiptImageData = nil
            fuelEntryPaths[sanitizedFuelEntries[index].id.uuidString] = path
        }

        var sanitizedMaintenanceRecords = snapshot.store.maintenanceRecords
        var maintenanceRecordPaths: [String: String] = [:]
        for index in sanitizedMaintenanceRecords.indices {
            guard let receiptData = sanitizedMaintenanceRecords[index].receiptImageData, !receiptData.isEmpty else {
                continue
            }

            let path = firebaseReceiptPath(
                for: .maintenance,
                userID: userID,
                itemID: sanitizedMaintenanceRecords[index].id
            )
            try await uploadFirebaseReceiptData(receiptData, to: path)
            sanitizedMaintenanceRecords[index].receiptImageData = nil
            maintenanceRecordPaths[sanitizedMaintenanceRecords[index].id.uuidString] = path
        }

        let sanitizedStore = MileageStore.PersistenceSnapshot(
            selectedCountry: snapshot.store.selectedCountry,
            userName: snapshot.store.userName,
            emailAddress: snapshot.store.emailAddress,
            preferredCurrency: snapshot.store.preferredCurrency,
            unitSystem: snapshot.store.unitSystem,
            fuelVolumeUnit: snapshot.store.fuelVolumeUnit,
            fuelEconomyFormat: snapshot.store.fuelEconomyFormat,
            preventAutoLock: snapshot.store.preventAutoLock,
            vehicleDetectionEnabled: snapshot.store.vehicleDetectionEnabled,
            hasCompletedOnboarding: snapshot.store.hasCompletedOnboarding,
            hasAcceptedPrivacyPolicy: snapshot.store.hasAcceptedPrivacyPolicy,
            hasAcceptedLegalNotice: snapshot.store.hasAcceptedLegalNotice,
            accountSubscriptionType: snapshot.store.accountSubscriptionType,
            businessProfile: snapshot.store.businessProfile,
            organizations: snapshot.store.organizations,
            activeOrganizationID: snapshot.store.activeOrganizationID,
            organizationMemberships: snapshot.store.organizationMemberships,
            vehicles: snapshot.store.vehicles,
            archivedVehicles: snapshot.store.archivedVehicles,
            activeVehicleID: snapshot.store.activeVehicleID,
            drivers: snapshot.store.drivers,
            archivedDrivers: snapshot.store.archivedDrivers,
            activeDriverID: snapshot.store.activeDriverID,
            trips: snapshot.store.trips,
            fuelEntries: sanitizedFuelEntries,
            maintenanceRecords: sanitizedMaintenanceRecords,
            logs: snapshot.store.logs,
            allowanceAdjustments: snapshot.store.allowanceAdjustments
        )
        return (
            AppPersistenceSnapshot(
                store: sanitizedStore,
                tripTracker: snapshot.tripTracker
            ),
            FirebaseReceiptManifest(
                fuelEntryPaths: fuelEntryPaths,
                maintenanceRecordPaths: maintenanceRecordPaths
            )
        )
        #else
        return (snapshot, .empty)
        #endif
    }

    private func hydrateFirebaseSnapshot(_ snapshot: AppPersistenceSnapshot, receiptManifest: FirebaseReceiptManifest) async throws -> AppPersistenceSnapshot {
        #if canImport(FirebaseStorage)
        guard !receiptManifest.isEmpty else {
            return snapshot
        }

        var hydratedFuelEntries = snapshot.store.fuelEntries
        for index in hydratedFuelEntries.indices {
            guard let path = receiptManifest.fuelEntryPaths[hydratedFuelEntries[index].id.uuidString] else {
                continue
            }
            hydratedFuelEntries[index].receiptImageData = try? await downloadFirebaseReceiptData(from: path)
        }

        var hydratedMaintenanceRecords = snapshot.store.maintenanceRecords
        for index in hydratedMaintenanceRecords.indices {
            guard let path = receiptManifest.maintenanceRecordPaths[hydratedMaintenanceRecords[index].id.uuidString] else {
                continue
            }
            hydratedMaintenanceRecords[index].receiptImageData = try? await downloadFirebaseReceiptData(from: path)
        }

        let hydratedStore = MileageStore.PersistenceSnapshot(
            selectedCountry: snapshot.store.selectedCountry,
            userName: snapshot.store.userName,
            emailAddress: snapshot.store.emailAddress,
            preferredCurrency: snapshot.store.preferredCurrency,
            unitSystem: snapshot.store.unitSystem,
            fuelVolumeUnit: snapshot.store.fuelVolumeUnit,
            fuelEconomyFormat: snapshot.store.fuelEconomyFormat,
            preventAutoLock: snapshot.store.preventAutoLock,
            vehicleDetectionEnabled: snapshot.store.vehicleDetectionEnabled,
            hasCompletedOnboarding: snapshot.store.hasCompletedOnboarding,
            hasAcceptedPrivacyPolicy: snapshot.store.hasAcceptedPrivacyPolicy,
            hasAcceptedLegalNotice: snapshot.store.hasAcceptedLegalNotice,
            accountSubscriptionType: snapshot.store.accountSubscriptionType,
            businessProfile: snapshot.store.businessProfile,
            organizations: snapshot.store.organizations,
            activeOrganizationID: snapshot.store.activeOrganizationID,
            organizationMemberships: snapshot.store.organizationMemberships,
            vehicles: snapshot.store.vehicles,
            archivedVehicles: snapshot.store.archivedVehicles,
            activeVehicleID: snapshot.store.activeVehicleID,
            drivers: snapshot.store.drivers,
            archivedDrivers: snapshot.store.archivedDrivers,
            activeDriverID: snapshot.store.activeDriverID,
            trips: snapshot.store.trips,
            fuelEntries: hydratedFuelEntries,
            maintenanceRecords: hydratedMaintenanceRecords,
            logs: snapshot.store.logs,
            allowanceAdjustments: snapshot.store.allowanceAdjustments
        )
        return AppPersistenceSnapshot(
            store: hydratedStore,
            tripTracker: snapshot.tripTracker
        )
        #else
        return snapshot
        #endif
    }

    private func syncFirebaseStructuredCollections(
        _ snapshot: AppPersistenceSnapshot,
        receiptManifest: FirebaseReceiptManifest
    ) async throws {
        guard let userDocument = firebaseUserDocument else {
            throw NSError(domain: "Firestore", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated Firebase user."])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            userDocument.setData(firebaseProfileDocumentData(from: snapshot), merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        let vehicles = snapshot.store.vehicles + snapshot.store.archivedVehicles
        try await syncFirebaseCollection(
            named: Constants.firebaseVehiclesCollection,
            documents: vehicles.map { vehicle in
                FirebaseStructuredDocument(
                    id: vehicle.id.uuidString,
                    data: firebaseVehicleDocumentData(from: vehicle)
                )
            },
            userDocument: userDocument
        )

        let drivers = snapshot.store.drivers + snapshot.store.archivedDrivers
        try await syncFirebaseCollection(
            named: Constants.firebaseDriversCollection,
            documents: drivers.map { driver in
                FirebaseStructuredDocument(
                    id: driver.id.uuidString,
                    data: firebaseDriverDocumentData(from: driver)
                )
            },
            userDocument: userDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseTripsCollection,
            documents: snapshot.store.trips.map { trip in
                FirebaseStructuredDocument(
                    id: trip.id.uuidString,
                    data: firebaseTripDocumentData(from: trip)
                )
            },
            userDocument: userDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseFuelEntriesCollection,
            documents: snapshot.store.fuelEntries.map { entry in
                FirebaseStructuredDocument(
                    id: entry.id.uuidString,
                    data: firebaseFuelEntryDocumentData(
                        from: entry,
                        receiptManifest: receiptManifest
                    )
                )
            },
            userDocument: userDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseMaintenanceRecordsCollection,
            documents: snapshot.store.maintenanceRecords.map { record in
                FirebaseStructuredDocument(
                    id: record.id.uuidString,
                    data: firebaseMaintenanceRecordDocumentData(
                        from: record,
                        receiptManifest: receiptManifest
                    )
                )
            },
            userDocument: userDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseLogsCollection,
            documents: snapshot.store.logs.map { entry in
                FirebaseStructuredDocument(
                    id: entry.id.uuidString,
                    data: firebaseLogDocumentData(from: entry)
                )
            },
            userDocument: userDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseAllowanceAdjustmentsCollection,
            documents: snapshot.store.allowanceAdjustments.map { adjustment in
                FirebaseStructuredDocument(
                    id: adjustment.id.uuidString,
                    data: firebaseAllowanceAdjustmentDocumentData(from: adjustment)
                )
            },
            userDocument: userDocument
        )

        try await syncFirebaseOrganizationCollections(
            snapshot,
            receiptManifest: receiptManifest
        )
    }

    private func syncFirebaseOrganizationCollections(
        _ snapshot: AppPersistenceSnapshot,
        receiptManifest: FirebaseReceiptManifest
    ) async throws {
        let organization = snapshot.store.activeOrganizationID.flatMap { organizationID in
            snapshot.store.organizations.first { $0.id == organizationID }
        }

        guard let organizationDocument = firebaseOrganizationDocument(for: snapshot),
              let organization,
              let currentUser = Auth.auth().currentUser else {
            return
        }

        let ownerUID = currentUser.uid
        let ownerEmail = snapshot.store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (currentUser.email ?? "")
            : snapshot.store.emailAddress

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            organizationDocument.setData([
                "id": organization.id.uuidString,
                "name": organization.name,
                "plan": organization.plan.rawValue,
                "ownerUID": ownerUID,
                "ownerEmail": ownerEmail,
                Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
                Constants.firebaseLastSyncedAtKey: Timestamp(date: .now)
            ], merge: true) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        let vehicles = snapshot.store.vehicles + snapshot.store.archivedVehicles
        try await syncFirebaseCollection(
            named: Constants.firebaseVehiclesCollection,
            documents: vehicles.map { vehicle in
                var data = firebaseVehicleDocumentData(from: vehicle)
                data["ownerUID"] = ownerUID
                data["ownerEmail"] = ownerEmail
                return FirebaseStructuredDocument(
                    id: vehicle.id.uuidString,
                    data: data
                )
            },
            parentDocument: organizationDocument
        )

        let drivers = snapshot.store.drivers + snapshot.store.archivedDrivers
        try await syncFirebaseCollection(
            named: Constants.firebaseDriversCollection,
            documents: drivers.map { driver in
                var data = firebaseDriverDocumentData(from: driver)
                data["ownerUID"] = ownerUID
                data["ownerEmail"] = ownerEmail
                return FirebaseStructuredDocument(
                    id: driver.id.uuidString,
                    data: data
                )
            },
            parentDocument: organizationDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseTripsCollection,
            documents: snapshot.store.trips.map { trip in
                var data = firebaseTripDocumentData(from: trip)
                data["ownerUID"] = ownerUID
                data["ownerEmail"] = ownerEmail
                data["organizationID"] = organization.id.uuidString
                return FirebaseStructuredDocument(
                    id: trip.id.uuidString,
                    data: data
                )
            },
            parentDocument: organizationDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseFuelEntriesCollection,
            documents: snapshot.store.fuelEntries.map { entry in
                var data = firebaseFuelEntryDocumentData(from: entry, receiptManifest: receiptManifest)
                data["ownerUID"] = ownerUID
                data["ownerEmail"] = ownerEmail
                data["organizationID"] = organization.id.uuidString
                return FirebaseStructuredDocument(
                    id: entry.id.uuidString,
                    data: data
                )
            },
            parentDocument: organizationDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseMaintenanceRecordsCollection,
            documents: snapshot.store.maintenanceRecords.map { record in
                var data = firebaseMaintenanceRecordDocumentData(from: record, receiptManifest: receiptManifest)
                data["ownerUID"] = ownerUID
                data["ownerEmail"] = ownerEmail
                data["organizationID"] = organization.id.uuidString
                return FirebaseStructuredDocument(
                    id: record.id.uuidString,
                    data: data
                )
            },
            parentDocument: organizationDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseLogsCollection,
            documents: snapshot.store.logs.map { entry in
                var data = firebaseLogDocumentData(from: entry)
                data["ownerUID"] = ownerUID
                data["ownerEmail"] = ownerEmail
                data["organizationID"] = organization.id.uuidString
                return FirebaseStructuredDocument(
                    id: entry.id.uuidString,
                    data: data
                )
            },
            parentDocument: organizationDocument
        )

        try await syncFirebaseCollection(
            named: Constants.firebaseAllowanceAdjustmentsCollection,
            documents: snapshot.store.allowanceAdjustments.map { adjustment in
                var data = firebaseAllowanceAdjustmentDocumentData(from: adjustment)
                data["ownerUID"] = ownerUID
                data["ownerEmail"] = ownerEmail
                data["organizationID"] = organization.id.uuidString
                return FirebaseStructuredDocument(
                    id: adjustment.id.uuidString,
                    data: data
                )
            },
            parentDocument: organizationDocument
        )
    }

    private func syncFirebaseCollection(
        named collectionName: String,
        documents: [FirebaseStructuredDocument],
        userDocument: DocumentReference
    ) async throws {
        try await syncFirebaseCollection(
            named: collectionName,
            documents: documents,
            parentDocument: userDocument
        )
    }

    private func syncFirebaseCollection(
        named collectionName: String,
        documents: [FirebaseStructuredDocument],
        parentDocument: DocumentReference
    ) async throws {
        let collection = parentDocument.collection(collectionName)
        let existingIDs = try await fetchFirebaseCollectionDocumentIDs(collection)
        let desiredIDs = Set(documents.map(\.id))
        let staleIDs = Array(existingIDs.subtracting(desiredIDs))

        let firestore = Firestore.firestore()
        var batch = firestore.batch()
        var operationCount = 0

        func commitBatchIfNeeded(force: Bool = false) async throws {
            guard operationCount > 0, force || operationCount >= Constants.firebaseMaxBatchOperations else {
                return
            }
            let currentBatch = batch
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                currentBatch.commit { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            batch = firestore.batch()
            operationCount = 0
        }

        for document in documents {
            batch.setData(document.data, forDocument: collection.document(document.id))
            operationCount += 1
            try await commitBatchIfNeeded()
        }

        for staleID in staleIDs {
            batch.deleteDocument(collection.document(staleID))
            operationCount += 1
            try await commitBatchIfNeeded()
        }

        try await commitBatchIfNeeded(force: true)
    }

    private func fetchFirebaseCollectionDocumentIDs(_ collection: CollectionReference) async throws -> Set<String> {
        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            collection.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(domain: "Firestore", code: -1))
                }
            }
        }
        return Set(snapshot.documents.map(\.documentID))
    }

    private func fetchFirebaseCollectionSnapshots(_ collection: CollectionReference) async throws -> [QueryDocumentSnapshot] {
        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            collection.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: NSError(domain: "Firestore", code: -1))
                }
            }
        }
        return snapshot.documents
    }

    private func deleteFirebaseStructuredCollections(for userDocument: DocumentReference) async throws {
        let collectionNames = [
            Constants.firebaseVehiclesCollection,
            Constants.firebaseDriversCollection,
            Constants.firebaseTripsCollection,
            Constants.firebaseFuelEntriesCollection,
            Constants.firebaseMaintenanceRecordsCollection,
            Constants.firebaseLogsCollection,
            Constants.firebaseAllowanceAdjustmentsCollection,
        ]

        for collectionName in collectionNames {
            let collection = userDocument.collection(collectionName)
            let ids = try await fetchFirebaseCollectionDocumentIDs(collection)
            guard !ids.isEmpty else {
                continue
            }

            let firestore = Firestore.firestore()
            var batch = firestore.batch()
            var operationCount = 0

            for id in ids {
                batch.deleteDocument(collection.document(id))
                operationCount += 1
                if operationCount >= Constants.firebaseMaxBatchOperations {
                    let currentBatch = batch
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        currentBatch.commit { error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                    batch = firestore.batch()
                    operationCount = 0
                }
            }

            if operationCount > 0 {
                let currentBatch = batch
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    currentBatch.commit { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
        }
    }
    #else
    private func fetchFirebaseSnapshot() async throws -> AppPersistenceSnapshot? {
        throw NSError(domain: "Firebase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cloud sync is unavailable in this build."])
    }

    private func uploadFirebaseSnapshot(_ snapshot: AppPersistenceSnapshot) async throws {
        _ = snapshot
        throw NSError(domain: "Firebase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cloud sync is unavailable in this build."])
    }

    private func deleteFirebaseSnapshot() async throws {
        throw NSError(domain: "Firebase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cloud sync is unavailable in this build."])
    }
    #endif

    #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
    private struct FirebaseStructuredDocument {
        let id: String
        let data: [String: Any]
    }

    private struct FirebaseStructuredSnapshot {
        let snapshot: AppPersistenceSnapshot
        let receiptManifest: FirebaseReceiptManifest
    }

    private func firebaseProfileDocumentData(from snapshot: AppPersistenceSnapshot) -> [String: Any] {
        let currentUser = Auth.auth().currentUser
        var data: [String: Any] = [
            "selectedCountry": snapshot.store.selectedCountry.rawValue,
            "preferredCurrency": snapshot.store.preferredCurrency.rawValue,
            "unitSystem": snapshot.store.unitSystem.rawValue,
            "fuelVolumeUnit": snapshot.store.fuelVolumeUnit.rawValue,
            "fuelEconomyFormat": snapshot.store.fuelEconomyFormat.rawValue,
            "preventAutoLock": snapshot.store.preventAutoLock,
            "vehicleDetectionEnabled": snapshot.store.vehicleDetectionEnabled,
            "hasCompletedOnboarding": snapshot.store.hasCompletedOnboarding,
            "hasAcceptedPrivacyPolicy": snapshot.store.hasAcceptedPrivacyPolicy,
            "hasAcceptedLegalNotice": snapshot.store.hasAcceptedLegalNotice,
            "accountSubscriptionType": snapshot.store.accountSubscriptionType.rawValue,
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
            Constants.firebaseLastSyncedAtKey: Timestamp(date: .now),
        ]

        let displayName = snapshot.store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            data["displayName"] = displayName
        } else if let fallbackName = currentUser?.displayName, !fallbackName.isEmpty {
            data["displayName"] = fallbackName
        }

        let email = snapshot.store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty {
            data["email"] = email
        } else if let fallbackEmail = currentUser?.email, !fallbackEmail.isEmpty {
            data["email"] = fallbackEmail
        }

        let authProviders = currentUser?.providerData.map(\.providerID) ?? []
        if !authProviders.isEmpty {
            data["authProviders"] = authProviders
        }

        if let activeVehicleID = snapshot.store.activeVehicleID {
            data["activeVehicleID"] = activeVehicleID.uuidString
        } else {
            data["activeVehicleID"] = FieldValue.delete()
        }
        if let activeDriverID = snapshot.store.activeDriverID {
            data["activeDriverID"] = activeDriverID.uuidString
        } else {
            data["activeDriverID"] = FieldValue.delete()
        }
        if let businessProfile = snapshot.store.businessProfile,
           let businessProfileData = try? firestoreJSONObject(from: businessProfile) {
            data["businessProfile"] = businessProfileData
        } else {
            data["businessProfile"] = FieldValue.delete()
        }

        return data
    }

    private func firebaseVehicleDocumentData(from vehicle: VehicleProfile) -> [String: Any] {
        var data: [String: Any] = [
            "id": vehicle.id.uuidString,
            "profileName": vehicle.profileName,
            "displayName": vehicle.displayName,
            "make": vehicle.make,
            "model": vehicle.model,
            "color": vehicle.color,
            "numberPlate": vehicle.numberPlate,
            "fleetNumber": vehicle.fleetNumber,
            "startingOdometerReading": vehicle.startingOdometerReading,
            "ownershipType": vehicle.ownershipType.rawValue,
            "archived": vehicle.archivedAt != nil,
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
        ]
        data["detectionProfile"] = [
            "isEnabled": vehicle.detectionProfile.isEnabled,
            "allowedSources": vehicle.detectionProfile.allowedSources.map(\.rawValue),
            "bluetoothPeripheralIdentifier": vehicle.detectionProfile.bluetoothPeripheralIdentifier as Any,
            "bluetoothPeripheralName": vehicle.detectionProfile.bluetoothPeripheralName,
            "audioRouteIdentifier": vehicle.detectionProfile.audioRouteIdentifier as Any,
            "audioRouteName": vehicle.detectionProfile.audioRouteName
        ]
        if let archivedAt = vehicle.archivedAt {
            data["archivedAt"] = Timestamp(date: archivedAt)
        }
        if let archiveReason = vehicle.archiveReason, !archiveReason.isEmpty {
            data["archiveReason"] = archiveReason
        }
        if let allowancePlan = try? firestoreJSONObject(from: vehicle.allowancePlan) {
            data["allowancePlan"] = allowancePlan
        }
        if let paymentPlan = try? firestoreJSONObject(from: vehicle.paymentPlan) {
            data["paymentPlan"] = paymentPlan
        }
        if let insurancePlan = try? firestoreJSONObject(from: vehicle.insurancePlan) {
            data["insurancePlan"] = insurancePlan
        }
        if let scheduledExpenses = try? firestoreJSONObject(from: vehicle.otherScheduledExpenses) {
            data["otherScheduledExpenses"] = scheduledExpenses
        }
        return data
    }

    private func firebaseDriverDocumentData(from driver: DriverProfile) -> [String: Any] {
        var data: [String: Any] = [
            "id": driver.id.uuidString,
            "name": driver.name,
            "dateOfBirth": Timestamp(date: driver.dateOfBirth),
            "licenceNumber": driver.licenceNumber,
            "licenceClass": driver.licenceClass,
            "emailAddress": driver.emailAddress,
            "phoneNumber": driver.phoneNumber,
            "permissions": driver.permissions.map(\.rawValue),
            "archived": driver.archivedAt != nil,
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
        ]
        if let archivedAt = driver.archivedAt {
            data["archivedAt"] = Timestamp(date: archivedAt)
        }
        return data
    }

    private func firebaseTripDocumentData(from trip: Trip) -> [String: Any] {
        var data: [String: Any] = [
            "id": trip.id.uuidString,
            "name": trip.name,
            "tripType": trip.type.rawValue,
            "vehicleProfileName": trip.vehicleProfileName,
            "driverName": trip.driverName,
            "startAddress": trip.effectiveStartAddress,
            "endAddress": trip.effectiveEndAddress,
            "details": trip.details,
            "odometerStart": trip.odometerStart,
            "odometerEnd": trip.odometerEnd,
            "distanceMeters": trip.distanceMeters,
            "duration": trip.duration,
            "date": Timestamp(date: trip.date),
            "manuallyEntered": trip.manuallyEntered,
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
        ]
        if let vehicleID = trip.vehicleID {
            data["vehicleID"] = vehicleID.uuidString
        }
        if let driverID = trip.driverID {
            data["driverID"] = driverID.uuidString
        }
        if let driverDateOfBirth = trip.driverDateOfBirth {
            data["driverDateOfBirth"] = Timestamp(date: driverDateOfBirth)
        }
        if !trip.driverLicenceNumber.isEmpty {
            data["driverLicenceNumber"] = trip.driverLicenceNumber
        }
        if let firstRoutePoint = trip.routePoints.first {
            data["startLatitude"] = firstRoutePoint.latitude
            data["startLongitude"] = firstRoutePoint.longitude
        }
        if let lastRoutePoint = trip.routePoints.last {
            data["endLatitude"] = lastRoutePoint.latitude
            data["endLongitude"] = lastRoutePoint.longitude
        }
        if let routePoints = try? firestoreJSONObject(from: trip.routePoints) {
            data["routePoints"] = routePoints
        }
        return data
    }

    private func firebaseFuelEntryDocumentData(
        from entry: FuelEntry,
        receiptManifest: FirebaseReceiptManifest
    ) -> [String: Any] {
        var data: [String: Any] = [
            "id": entry.id.uuidString,
            "vehicleProfileName": entry.vehicleProfileName,
            "station": entry.station,
            "volume": entry.volume,
            "totalCost": entry.totalCost,
            "odometer": entry.odometer,
            "date": Timestamp(date: entry.date),
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
        ]
        if let vehicleID = entry.vehicleID {
            data["vehicleID"] = vehicleID.uuidString
        }
        if let receiptPath = receiptManifest.fuelEntryPaths[entry.id.uuidString] {
            data["receiptPath"] = receiptPath
        }
        return data
    }

    private func firebaseMaintenanceRecordDocumentData(
        from record: MaintenanceRecord,
        receiptManifest: FirebaseReceiptManifest
    ) -> [String: Any] {
        var data: [String: Any] = [
            "id": record.id.uuidString,
            "vehicleProfileName": record.vehicleProfileName,
            "shopName": record.shopName,
            "odometer": record.odometer,
            "date": Timestamp(date: record.date),
            "type": record.type.rawValue,
            "otherDescription": record.otherDescription,
            "notes": record.notes,
            "totalCost": record.totalCost,
            "reminderEnabled": record.reminderEnabled,
            "hasSentThousandReminder": record.hasSentThousandReminder,
            "hasSentTwoHundredReminder": record.hasSentTwoHundredReminder,
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
        ]
        if let vehicleID = record.vehicleID {
            data["vehicleID"] = vehicleID.uuidString
        }
        if let nextServiceOdometer = record.nextServiceOdometer {
            data["nextServiceOdometer"] = nextServiceOdometer
        }
        if let nextServiceDate = record.nextServiceDate {
            data["nextServiceDate"] = Timestamp(date: nextServiceDate)
        }
        if let receiptPath = receiptManifest.maintenanceRecordPaths[record.id.uuidString] {
            data["receiptPath"] = receiptPath
        }
        return data
    }

    private func firebaseLogDocumentData(from entry: LogEntry) -> [String: Any] {
        [
            "id": entry.id.uuidString,
            "title": entry.title,
            "message": entry.title,
            "date": Timestamp(date: entry.date),
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
        ]
    }

    private func firebaseAllowanceAdjustmentDocumentData(from adjustment: AllowanceAdjustment) -> [String: Any] {
        [
            "id": adjustment.id.uuidString,
            "vehicleID": adjustment.vehicleID.uuidString,
            "amount": adjustment.amount,
            "reason": adjustment.reason,
            "date": Timestamp(date: adjustment.date),
            Constants.firebaseUpdatedAtKey: Timestamp(date: .now),
        ]
    }

    private func firestoreJSONObject<T: Encodable>(from value: T?) throws -> Any? {
        guard let value else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func firebaseDecodable<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func fetchFirebaseStructuredSnapshot(
        overlaying baseSnapshot: AppPersistenceSnapshot
    ) async throws -> FirebaseStructuredSnapshot? {
        guard let userDocument = firebaseUserDocument else {
            return nil
        }

        let userSnapshot = try await fetchFirebaseDocumentSnapshot(userDocument)
        let membershipDocuments = try await fetchFirebaseCollectionSnapshots(
            userDocument.collection(Constants.firebaseOrganizationMembershipsCollection)
        )

        let restoredMemberships = membershipDocuments.compactMap(firebaseOrganizationMembership(from:))
        let activeMembership =
            restoredMemberships.first(where: { $0.status == .active }) ??
            restoredMemberships.first(where: { $0.status == .invited })

        let organizationDocument: DocumentReference? = activeMembership.map { membership in
            Firestore.firestore()
                .collection(Constants.firebaseOrganizationsCollection)
                .document(membership.organizationID.uuidString)
        }
        let organizationSnapshot: DocumentSnapshot?
        if let organizationDocument {
            organizationSnapshot = try await fetchFirebaseDocumentSnapshot(organizationDocument)
        } else {
            organizationSnapshot = nil
        }
        let restoredOrganizations: [OrganizationProfile] = organizationSnapshot.flatMap { snapshot in
            firebaseOrganizationProfile(from: snapshot)
        }.map { [$0] } ?? []

        let structuredSourceDocument = organizationDocument ?? userDocument

        let vehicleDocuments = try await fetchFirebaseCollectionSnapshots(
            structuredSourceDocument.collection(Constants.firebaseVehiclesCollection)
        )
        let driverDocuments = try await fetchFirebaseCollectionSnapshots(
            structuredSourceDocument.collection(Constants.firebaseDriversCollection)
        )
        let tripDocuments = try await fetchFirebaseCollectionSnapshots(
            structuredSourceDocument.collection(Constants.firebaseTripsCollection)
        )
        let fuelEntryDocuments = try await fetchFirebaseCollectionSnapshots(
            structuredSourceDocument.collection(Constants.firebaseFuelEntriesCollection)
        )
        let maintenanceDocuments = try await fetchFirebaseCollectionSnapshots(
            structuredSourceDocument.collection(Constants.firebaseMaintenanceRecordsCollection)
        )
        let logDocuments = try await fetchFirebaseCollectionSnapshots(
            structuredSourceDocument.collection(Constants.firebaseLogsCollection)
        )
        let allowanceAdjustmentDocuments = try await fetchFirebaseCollectionSnapshots(
            structuredSourceDocument.collection(Constants.firebaseAllowanceAdjustmentsCollection)
        )

        let hasStructuredData =
            userSnapshot.exists ||
            organizationSnapshot?.exists == true ||
            !vehicleDocuments.isEmpty ||
            !driverDocuments.isEmpty ||
            !tripDocuments.isEmpty ||
            !fuelEntryDocuments.isEmpty ||
            !maintenanceDocuments.isEmpty ||
            !logDocuments.isEmpty ||
            !allowanceAdjustmentDocuments.isEmpty

        guard hasStructuredData else {
            return nil
        }

        let baseStore = baseSnapshot.store
        let userData = userSnapshot.data() ?? [:]

        let decodedVehicles = vehicleDocuments.compactMap(firebaseVehicleProfile(from:))
        let activeVehicles = decodedVehicles.filter { $0.archivedAt == nil }
        let archivedVehicles = decodedVehicles.filter { $0.archivedAt != nil }
        let decodedDrivers = driverDocuments.compactMap(firebaseDriverProfile(from:))
        let activeDrivers = decodedDrivers.filter { $0.archivedAt == nil }
        let archivedDrivers = decodedDrivers.filter { $0.archivedAt != nil }
        let decodedTrips = tripDocuments.compactMap(firebaseTrip(from:))
        let baseFuelEntryReceipts = Dictionary(
            uniqueKeysWithValues: baseStore.fuelEntries.map { ($0.id, $0.receiptImageData) }
        )
        let baseMaintenanceReceipts = Dictionary(
            uniqueKeysWithValues: baseStore.maintenanceRecords.map { ($0.id, $0.receiptImageData) }
        )
        let decodedFuelEntries = fuelEntryDocuments.compactMap {
            firebaseFuelEntry(from: $0, existingReceiptData: baseFuelEntryReceipts)
        }
        let decodedMaintenanceRecords = maintenanceDocuments.compactMap {
            firebaseMaintenanceRecord(from: $0, existingReceiptData: baseMaintenanceReceipts)
        }
        let decodedLogs = logDocuments.compactMap(firebaseLogEntry(from:))
        let decodedAllowanceAdjustments = allowanceAdjustmentDocuments.compactMap(firebaseAllowanceAdjustment(from:))

        var selectedCountry = baseStore.selectedCountry
        if let rawCountry = userData["selectedCountry"] as? String,
           let parsedCountry = SupportedCountry(rawValue: rawCountry) {
            selectedCountry = parsedCountry
        }

        var unitSystem = baseStore.unitSystem
        if let rawUnitSystem = userData["unitSystem"] as? String,
           let parsedUnitSystem = DistanceUnitSystem(rawValue: rawUnitSystem) {
            unitSystem = parsedUnitSystem
        }

        var preferredCurrency = baseStore.preferredCurrency
        if let rawCurrency = userData["preferredCurrency"] as? String,
           let parsedCurrency = PreferredCurrency(rawValue: rawCurrency) {
            preferredCurrency = parsedCurrency
        }

        var fuelVolumeUnit = baseStore.fuelVolumeUnit
        if let rawFuelVolumeUnit = userData["fuelVolumeUnit"] as? String,
           let parsedFuelVolumeUnit = FuelVolumeUnit(rawValue: rawFuelVolumeUnit) {
            fuelVolumeUnit = parsedFuelVolumeUnit
        }

        var fuelEconomyFormat = baseStore.fuelEconomyFormat
        if let rawFuelEconomyFormat = userData["fuelEconomyFormat"] as? String,
           let parsedFuelEconomyFormat = FuelEconomyFormat(rawValue: rawFuelEconomyFormat) {
            fuelEconomyFormat = parsedFuelEconomyFormat.compatibleFormat(for: unitSystem)
        } else {
            fuelEconomyFormat = fuelEconomyFormat.compatibleFormat(for: unitSystem)
        }

        let preventAutoLock = userData["preventAutoLock"] as? Bool ?? baseStore.preventAutoLock

        var accountSubscriptionType = baseStore.accountSubscriptionType
        if let rawAccountSubscriptionType = userData["accountSubscriptionType"] as? String,
           let parsedAccountSubscriptionType = AccountSubscriptionType(rawValue: rawAccountSubscriptionType) {
            accountSubscriptionType = parsedAccountSubscriptionType
        }

        let businessProfile =
            firebaseDecodable(BusinessAccountProfile.self, from: userData["businessProfile"]) ??
            baseStore.businessProfile

        let resolvedUserName =
            (userData["displayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let resolvedEmail =
            (userData["email"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        let activeVehicleID = firebaseUUID(
            from: userData["activeVehicleID"]
        ) ?? baseStore.activeVehicleID

        let vehicleDetectionEnabled = userData["vehicleDetectionEnabled"] as? Bool ?? baseStore.vehicleDetectionEnabled

        let mergedStore = MileageStore.PersistenceSnapshot(
            selectedCountry: selectedCountry,
            userName: resolvedUserName.isEmpty ? baseStore.userName : resolvedUserName,
            emailAddress: resolvedEmail.isEmpty ? baseStore.emailAddress : resolvedEmail,
            preferredCurrency: preferredCurrency,
            unitSystem: unitSystem,
            fuelVolumeUnit: fuelVolumeUnit,
            fuelEconomyFormat: fuelEconomyFormat,
            preventAutoLock: preventAutoLock,
            vehicleDetectionEnabled: vehicleDetectionEnabled,
            hasCompletedOnboarding: userData["hasCompletedOnboarding"] as? Bool ?? baseStore.hasCompletedOnboarding,
            hasAcceptedPrivacyPolicy: userData["hasAcceptedPrivacyPolicy"] as? Bool ?? baseStore.hasAcceptedPrivacyPolicy,
            hasAcceptedLegalNotice: userData["hasAcceptedLegalNotice"] as? Bool ?? baseStore.hasAcceptedLegalNotice,
            accountSubscriptionType: accountSubscriptionType,
            businessProfile: businessProfile,
            organizations: restoredOrganizations.isEmpty ? baseStore.organizations : restoredOrganizations,
            activeOrganizationID: activeMembership?.organizationID ?? baseStore.activeOrganizationID,
            organizationMemberships: restoredMemberships.isEmpty ? baseStore.organizationMemberships : restoredMemberships,
            vehicles: activeVehicles.isEmpty ? baseStore.vehicles : activeVehicles,
            archivedVehicles: archivedVehicles.isEmpty ? baseStore.archivedVehicles : archivedVehicles,
            activeVehicleID: activeVehicleID,
            drivers: activeDrivers.isEmpty ? baseStore.drivers : activeDrivers,
            archivedDrivers: archivedDrivers.isEmpty ? baseStore.archivedDrivers : archivedDrivers,
            activeDriverID: firebaseUUID(from: userData["activeDriverID"]) ?? activeMembership?.assignedDriverID ?? baseStore.activeDriverID,
            trips: decodedTrips.isEmpty ? baseStore.trips : decodedTrips.sorted { $0.date > $1.date },
            fuelEntries: decodedFuelEntries.isEmpty ? baseStore.fuelEntries : decodedFuelEntries.sorted { $0.date > $1.date },
            maintenanceRecords: decodedMaintenanceRecords.isEmpty ? baseStore.maintenanceRecords : decodedMaintenanceRecords.sorted { $0.date > $1.date },
            logs: decodedLogs.isEmpty ? baseStore.logs : decodedLogs.sorted { $0.date > $1.date },
            allowanceAdjustments: decodedAllowanceAdjustments.isEmpty ? baseStore.allowanceAdjustments : decodedAllowanceAdjustments.sorted { $0.date > $1.date }
        )

        let receiptManifest = FirebaseReceiptManifest(
            fuelEntryPaths: Dictionary(
                uniqueKeysWithValues: fuelEntryDocuments.compactMap { document in
                    guard let id = firebaseUUID(from: document.data()["id"] ?? document.documentID)?.uuidString,
                          let receiptPath = document.data()["receiptPath"] as? String
                    else {
                        return nil
                    }
                    return (id, receiptPath)
                }
            ),
            maintenanceRecordPaths: Dictionary(
                uniqueKeysWithValues: maintenanceDocuments.compactMap { document in
                    guard let id = firebaseUUID(from: document.data()["id"] ?? document.documentID)?.uuidString,
                          let receiptPath = document.data()["receiptPath"] as? String
                    else {
                        return nil
                    }
                    return (id, receiptPath)
                }
            )
        )

        return FirebaseStructuredSnapshot(
            snapshot: AppPersistenceSnapshot(store: mergedStore, tripTracker: baseSnapshot.tripTracker),
            receiptManifest: receiptManifest
        )
    }

    private func firebaseTrip(from document: QueryDocumentSnapshot) -> Trip? {
        let data = document.data()
        guard let id = firebaseUUID(from: data["id"] ?? document.documentID),
              let date = firebaseDate(from: data["date"])
        else {
            return nil
        }

        return Trip(
            id: id,
            name: data["name"] as? String ?? "",
            type: TripType(rawValue: data["tripType"] as? String ?? "") ?? .business,
            vehicleID: firebaseUUID(from: data["vehicleID"]),
            vehicleProfileName: data["vehicleProfileName"] as? String ?? "",
            driverID: firebaseUUID(from: data["driverID"]),
            driverName: data["driverName"] as? String ?? "",
            driverDateOfBirth: firebaseDate(from: data["driverDateOfBirth"]),
            driverLicenceNumber: data["driverLicenceNumber"] as? String ?? "",
            startAddress: data["startAddress"] as? String ?? "",
            endAddress: data["endAddress"] as? String ?? "",
            details: data["details"] as? String ?? "",
            odometerStart: firebaseDouble(from: data["odometerStart"]),
            odometerEnd: firebaseDouble(from: data["odometerEnd"]),
            distanceMeters: firebaseDouble(from: data["distanceMeters"]),
            duration: firebaseDouble(from: data["duration"]),
            date: date,
            routePoints: firebaseRoutePoints(from: data["routePoints"]),
            manuallyEntered: data["manuallyEntered"] as? Bool ?? false
        )
    }

    private func firebaseVehicleProfile(from document: QueryDocumentSnapshot) -> VehicleProfile? {
        let data = document.data()
        guard let id = firebaseUUID(from: data["id"] ?? document.documentID) else {
            return nil
        }

        let archivedAt = firebaseDate(from: data["archivedAt"]) ?? ((data["archived"] as? Bool == true) ? (firebaseDate(from: data[Constants.firebaseUpdatedAtKey]) ?? .now) : nil)
        let detectionData = data["detectionProfile"] as? [String: Any]
        let detectionProfile = VehicleDetectionProfile(
            isEnabled: detectionData?["isEnabled"] as? Bool ?? false,
            allowedSources: Set(
                (detectionData?["allowedSources"] as? [String] ?? [])
                    .compactMap(VehicleConnectionSource.init(rawValue:))
            ),
            bluetoothPeripheralIdentifier: detectionData?["bluetoothPeripheralIdentifier"] as? String,
            bluetoothPeripheralName: detectionData?["bluetoothPeripheralName"] as? String ?? "",
            audioRouteIdentifier: detectionData?["audioRouteIdentifier"] as? String,
            audioRouteName: detectionData?["audioRouteName"] as? String ?? ""
        )

        return VehicleProfile(
            id: id,
            profileName: data["profileName"] as? String ?? "",
            make: data["make"] as? String ?? "",
            model: data["model"] as? String ?? "",
            color: data["color"] as? String ?? "",
            numberPlate: data["numberPlate"] as? String ?? "",
            fleetNumber: data["fleetNumber"] as? String ?? "",
            startingOdometerReading: firebaseDouble(from: data["startingOdometerReading"]),
            ownershipType: VehicleOwnershipType(rawValue: data["ownershipType"] as? String ?? "") ?? .personal,
            detectionProfile: detectionProfile,
            archivedAt: archivedAt,
            archiveReason: data["archiveReason"] as? String
        )
    }

    private func firebaseDriverProfile(from document: QueryDocumentSnapshot) -> DriverProfile? {
        let data = document.data()
        guard let id = firebaseUUID(from: data["id"] ?? document.documentID),
              let dateOfBirth = firebaseDate(from: data["dateOfBirth"])
        else {
            return nil
        }

        return DriverProfile(
            id: id,
            name: data["name"] as? String ?? "",
            dateOfBirth: dateOfBirth,
            licenceNumber: data["licenceNumber"] as? String ?? "",
            licenceClass: data["licenceClass"] as? String ?? "",
            emailAddress: data["emailAddress"] as? String ?? "",
            phoneNumber: data["phoneNumber"] as? String ?? "",
            permissions: (data["permissions"] as? [String] ?? []).compactMap(OrganizationPermission.init(rawValue:)),
            archivedAt: firebaseDate(from: data["archivedAt"])
        )
    }

    private func firebaseLogEntry(from document: QueryDocumentSnapshot) -> LogEntry? {
        let data = document.data()
        guard let id = firebaseUUID(from: data["id"] ?? document.documentID),
              let date = firebaseDate(from: data["date"]) else {
            return nil
        }

        return LogEntry(
            id: id,
            title: (data["title"] as? String) ?? (data["message"] as? String) ?? "",
            date: date
        )
    }

    private func firebaseAllowanceAdjustment(from document: QueryDocumentSnapshot) -> AllowanceAdjustment? {
        let data = document.data()
        guard let id = firebaseUUID(from: data["id"] ?? document.documentID),
              let vehicleID = firebaseUUID(from: data["vehicleID"]),
              let date = firebaseDate(from: data["date"]) else {
            return nil
        }

        return AllowanceAdjustment(
            id: id,
            vehicleID: vehicleID,
            amount: firebaseDouble(from: data["amount"]),
            reason: data["reason"] as? String ?? "",
            date: date
        )
    }

    private func firebaseOrganizationProfile(from snapshot: DocumentSnapshot) -> OrganizationProfile? {
        guard let data = snapshot.data(),
              let planRawValue = data["plan"] as? String,
              let plan = OrganizationSubscriptionPlan(rawValue: planRawValue),
              let id = UUID(uuidString: snapshot.documentID) else {
            return nil
        }

        let billingStatus = (data["billingStatus"] as? String)
            .flatMap(OrganizationBillingStatus.init(rawValue:))
            ?? .pendingPayment

        return OrganizationProfile(
            id: id,
            name: data["name"] as? String ?? "",
            plan: plan,
            createdAt: firebaseDate(from: data["createdAt"]) ?? .now,
            billingStatus: billingStatus,
            expiresAt: firebaseDate(from: data["expiresAt"])
        )
    }

    private func firebaseOrganizationMembership(from document: QueryDocumentSnapshot) -> OrganizationMembership? {
        let data = document.data()
        guard let organizationID = firebaseUUID(from: data["organizationID"]),
              let emailAddress = data["emailAddress"] as? String,
              let roleRawValue = data["role"] as? String,
              let role = OrganizationMemberRole(rawValue: roleRawValue),
              let statusRawValue = data["status"] as? String,
              let status = OrganizationMemberStatus(rawValue: statusRawValue) else {
            return nil
        }

        let permissions = (data["permissions"] as? [String] ?? [])
            .compactMap(OrganizationPermission.init(rawValue:))
        let assignedVehicleIDs = (data["assignedVehicleIDs"] as? [String] ?? [])
            .compactMap(UUID.init(uuidString:))

        return OrganizationMembership(
            id: firebaseUUID(from: data["id"] ?? document.documentID) ?? UUID(),
            organizationID: organizationID,
            emailAddress: emailAddress,
            displayName: data["displayName"] as? String ?? "",
            role: role,
            status: status,
            assignedVehicleIDs: assignedVehicleIDs,
            assignedDriverID: firebaseUUID(from: data["assignedDriverID"]),
            permissions: permissions,
            invitedAt: firebaseDate(from: data["invitedAt"]) ?? .now,
            activatedAt: firebaseDate(from: data["activatedAt"]),
            removedAt: firebaseDate(from: data["removedAt"])
        )
    }

    private func firebaseFuelEntry(
        from document: QueryDocumentSnapshot,
        existingReceiptData: [UUID: Data?]
    ) -> FuelEntry? {
        let data = document.data()
        guard let id = firebaseUUID(from: data["id"] ?? document.documentID),
              let date = firebaseDate(from: data["date"])
        else {
            return nil
        }

        return FuelEntry(
            id: id,
            vehicleID: firebaseUUID(from: data["vehicleID"]),
            vehicleProfileName: data["vehicleProfileName"] as? String ?? "",
            station: data["station"] as? String ?? "",
            volume: firebaseDouble(from: data["volume"]),
            totalCost: firebaseDouble(from: data["totalCost"]),
            odometer: firebaseDouble(from: data["odometer"]),
            date: date,
            receiptImageData: existingReceiptData[id] ?? nil
        )
    }

    private func firebaseMaintenanceRecord(
        from document: QueryDocumentSnapshot,
        existingReceiptData: [UUID: Data?]
    ) -> MaintenanceRecord? {
        let data = document.data()
        guard let id = firebaseUUID(from: data["id"] ?? document.documentID),
              let date = firebaseDate(from: data["date"])
        else {
            return nil
        }

        return MaintenanceRecord(
            id: id,
            vehicleID: firebaseUUID(from: data["vehicleID"]),
            vehicleProfileName: data["vehicleProfileName"] as? String ?? "",
            shopName: data["shopName"] as? String ?? "",
            odometer: firebaseDouble(from: data["odometer"]),
            date: date,
            type: MaintenanceType(rawValue: data["type"] as? String ?? "") ?? .other,
            otherDescription: data["otherDescription"] as? String ?? "",
            notes: data["notes"] as? String ?? "",
            totalCost: firebaseDouble(from: data["totalCost"]),
            receiptImageData: existingReceiptData[id] ?? nil,
            reminderEnabled: data["reminderEnabled"] as? Bool ?? false,
            nextServiceOdometer: firebaseOptionalDouble(from: data["nextServiceOdometer"]),
            nextServiceDate: firebaseDate(from: data["nextServiceDate"]),
            hasSentThousandReminder: data["hasSentThousandReminder"] as? Bool ?? false,
            hasSentTwoHundredReminder: data["hasSentTwoHundredReminder"] as? Bool ?? false
        )
    }

    private func firebaseUUID(from value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }

        if let rawString = value as? String {
            return UUID(uuidString: rawString)
        }

        return nil
    }

    private func firebaseDate(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }

        if let date = value as? Date {
            return date
        }

        return nil
    }

    private func firebaseDouble(from value: Any?) -> Double {
        firebaseOptionalDouble(from: value) ?? 0
    }

    private func firebaseOptionalDouble(from value: Any?) -> Double? {
        if value is NSNull {
            return nil
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    private func firebaseRoutePoints(from value: Any?) -> [Trip.RoutePoint] {
        guard let points = value as? [[String: Any]] else {
            return []
        }

        return points.compactMap { point in
            guard let latitude = firebaseOptionalDouble(from: point["latitude"]),
                  let longitude = firebaseOptionalDouble(from: point["longitude"])
            else {
                return nil
            }
            return Trip.RoutePoint(latitude: latitude, longitude: longitude)
        }
    }
    #endif

    #if canImport(FirebaseAuth) && canImport(FirebaseFirestore) && canImport(FirebaseStorage)
    private enum FirebaseReceiptKind {
        case fuel
        case maintenance

        var folderName: String {
            switch self {
            case .fuel:
                return Constants.firebaseFuelReceiptsFolder
            case .maintenance:
                return Constants.firebaseMaintenanceReceiptsFolder
            }
        }
    }

    private func firebaseReceiptPath(
        for kind: FirebaseReceiptKind,
        userID: String,
        itemID: UUID
    ) -> String {
        [
            Constants.firebaseUsersCollection,
            userID,
            Constants.firebaseReceiptsFolder,
            kind.folderName,
            itemID.uuidString
        ].joined(separator: "/")
    }

    private func uploadFirebaseReceiptData(_ data: Data, to path: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Storage.storage().reference(withPath: path).putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func downloadFirebaseReceiptData(from path: String) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            Storage.storage().reference(withPath: path).getData(maxSize: Int64(Constants.firebaseReceiptMaximumDownloadBytes)) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseStorage", code: -1))
                }
            }
        }
    }

    private func deleteFirebaseReceiptAssets(at paths: [String]) async throws {
        for path in Set(paths) {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Storage.storage().reference(withPath: path).delete { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == StorageErrorDomain,
                   nsError.code == StorageErrorCode.objectNotFound.rawValue {
                    continue
                }
                throw error
            }
        }
    }
    #else
    private func deleteFirebaseReceiptAssets(at paths: [String]) async throws {
        _ = paths
    }
    #endif

    private func mergeSnapshots(
        local: AppPersistenceSnapshot,
        remote: AppPersistenceSnapshot,
        baseline: AppPersistenceSnapshot
    ) -> AppPersistenceSnapshot {
        AppPersistenceSnapshot(
            store: mergeStoreSnapshot(local: local.store, remote: remote.store, baseline: baseline.store),
            tripTracker: mergeTrackerSnapshot(local: local.tripTracker, remote: remote.tripTracker, baseline: baseline.tripTracker)
        )
    }

    private func mergeStoreSnapshot(
        local: MileageStore.PersistenceSnapshot,
        remote: MileageStore.PersistenceSnapshot,
        baseline: MileageStore.PersistenceSnapshot
    ) -> MileageStore.PersistenceSnapshot {
        MileageStore.PersistenceSnapshot(
            selectedCountry: mergedValue(local.selectedCountry, remote.selectedCountry, baseline.selectedCountry),
            userName: mergedValue(local.userName, remote.userName, baseline.userName),
            emailAddress: mergedValue(local.emailAddress, remote.emailAddress, baseline.emailAddress),
            preferredCurrency: mergedValue(local.preferredCurrency, remote.preferredCurrency, baseline.preferredCurrency),
            unitSystem: mergedValue(local.unitSystem, remote.unitSystem, baseline.unitSystem),
            fuelVolumeUnit: mergedValue(local.fuelVolumeUnit, remote.fuelVolumeUnit, baseline.fuelVolumeUnit),
            fuelEconomyFormat: mergedValue(local.fuelEconomyFormat, remote.fuelEconomyFormat, baseline.fuelEconomyFormat),
            preventAutoLock: mergedValue(local.preventAutoLock, remote.preventAutoLock, baseline.preventAutoLock),
            vehicleDetectionEnabled: mergedValue(local.vehicleDetectionEnabled, remote.vehicleDetectionEnabled, baseline.vehicleDetectionEnabled),
            hasCompletedOnboarding: mergedValue(local.hasCompletedOnboarding, remote.hasCompletedOnboarding, baseline.hasCompletedOnboarding),
            hasAcceptedPrivacyPolicy: mergedValue(local.hasAcceptedPrivacyPolicy, remote.hasAcceptedPrivacyPolicy, baseline.hasAcceptedPrivacyPolicy),
            hasAcceptedLegalNotice: mergedValue(local.hasAcceptedLegalNotice, remote.hasAcceptedLegalNotice, baseline.hasAcceptedLegalNotice),
            accountSubscriptionType: mergedValue(local.accountSubscriptionType, remote.accountSubscriptionType, baseline.accountSubscriptionType),
            businessProfile: mergedValue(local.businessProfile, remote.businessProfile, baseline.businessProfile),
            organizations: mergeCollection(local.organizations, remote.organizations, baseline.organizations),
            activeOrganizationID: mergedValue(local.activeOrganizationID, remote.activeOrganizationID, baseline.activeOrganizationID),
            organizationMemberships: mergeCollection(local.organizationMemberships, remote.organizationMemberships, baseline.organizationMemberships),
            vehicles: mergeCollection(local.vehicles, remote.vehicles, baseline.vehicles),
            archivedVehicles: mergeCollection(local.archivedVehicles, remote.archivedVehicles, baseline.archivedVehicles),
            activeVehicleID: mergedValue(local.activeVehicleID, remote.activeVehicleID, baseline.activeVehicleID),
            drivers: mergeCollection(local.drivers, remote.drivers, baseline.drivers),
            archivedDrivers: mergeCollection(local.archivedDrivers, remote.archivedDrivers, baseline.archivedDrivers),
            activeDriverID: mergedValue(local.activeDriverID, remote.activeDriverID, baseline.activeDriverID),
            trips: mergeCollection(local.trips, remote.trips, baseline.trips).sorted { $0.date > $1.date },
            fuelEntries: mergeCollection(local.fuelEntries, remote.fuelEntries, baseline.fuelEntries).sorted { $0.date > $1.date },
            maintenanceRecords: mergeCollection(local.maintenanceRecords, remote.maintenanceRecords, baseline.maintenanceRecords).sorted { $0.date > $1.date },
            logs: mergeCollection(local.logs, remote.logs, baseline.logs).sorted { $0.date > $1.date },
            allowanceAdjustments: mergeCollection(local.allowanceAdjustments, remote.allowanceAdjustments, baseline.allowanceAdjustments).sorted { $0.date > $1.date }
        )
    }

    private func mergeTrackerSnapshot(
        local: TripTracker.PersistenceSnapshot,
        remote: TripTracker.PersistenceSnapshot,
        baseline: TripTracker.PersistenceSnapshot
    ) -> TripTracker.PersistenceSnapshot {
        TripTracker.PersistenceSnapshot(
            autoStartEnabled: mergedValue(local.autoStartEnabled, remote.autoStartEnabled, baseline.autoStartEnabled),
            backgroundTripTrackingEnabled: mergedValue(local.backgroundTripTrackingEnabled, remote.backgroundTripTrackingEnabled, baseline.backgroundTripTrackingEnabled),
            motionActivityEnabled: mergedValue(local.motionActivityEnabled, remote.motionActivityEnabled, baseline.motionActivityEnabled),
            autoStartSpeedThresholdKilometersPerHour: mergedValue(local.autoStartSpeedThresholdKilometersPerHour, remote.autoStartSpeedThresholdKilometersPerHour, baseline.autoStartSpeedThresholdKilometersPerHour),
            autoStopDelayMinutes: mergedValue(local.autoStopDelayMinutes, remote.autoStopDelayMinutes, baseline.autoStopDelayMinutes),
            selectedTripType: mergedValue(local.selectedTripType, remote.selectedTripType, baseline.selectedTripType)
        )
    }

    private func mergedValue<T: Equatable>(_ local: T, _ remote: T, _ baseline: T) -> T {
        if local == remote {
            return local
        }

        let localChanged = local != baseline
        let remoteChanged = remote != baseline

        switch (localChanged, remoteChanged) {
        case (true, false):
            return local
        case (false, true):
            return remote
        case (true, true):
            return local
        case (false, false):
            return local
        }
    }

    private func mergeCollection<T: Identifiable & Equatable>(
        _ local: [T],
        _ remote: [T],
        _ baseline: [T]
    ) -> [T] where T.ID: Hashable {
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })

        let orderedIDs = local.map(\.id) + remote.map(\.id).filter { !localByID.keys.contains($0) }

        return orderedIDs.compactMap { id in
            let localValue = localByID[id]
            let remoteValue = remoteByID[id]
            let baselineValue = baselineByID[id]

            if localValue == remoteValue {
                return localValue
            }

            let localChanged = localValue != baselineValue
            let remoteChanged = remoteValue != baselineValue

            switch (localChanged, remoteChanged) {
            case (true, false):
                return localValue
            case (false, true):
                return remoteValue
            case (true, true):
                return localValue ?? remoteValue
            case (false, false):
                return localValue ?? remoteValue
            }
        }
    }

    private func fetchRemoteSnapshot() async throws -> AppPersistenceSnapshot? {
        let settingsSnapshot = try await fetchSingletonSnapshot(
            recordType: Constants.settingsRecordType,
            recordName: Constants.settingsRecordName,
            as: MileageStore.PersistenceSnapshot.self
        )
        let trackerSnapshot = try await fetchSingletonSnapshot(
            recordType: Constants.trackerSettingsRecordType,
            recordName: Constants.trackerSettingsRecordName,
            as: TripTracker.PersistenceSnapshot.self
        )
        let zoneRecords = try await fetchAllRecordsFromCustomZone()
        let vehicles = try decodeCollectionRecords(recordType: Constants.vehicleRecordType, from: zoneRecords, as: VehicleProfile.self)
        let drivers = try decodeCollectionRecords(recordType: Constants.driverRecordType, from: zoneRecords, as: DriverProfile.self)
        let trips = try decodeCollectionRecords(recordType: Constants.tripRecordType, from: zoneRecords, as: Trip.self)
        let fuelEntries = try decodeCollectionRecords(recordType: Constants.fuelEntryRecordType, from: zoneRecords, as: FuelEntry.self)
        let maintenanceRecords = try decodeCollectionRecords(recordType: Constants.maintenanceRecordType, from: zoneRecords, as: MaintenanceRecord.self)
        let logs = try decodeCollectionRecords(recordType: Constants.logRecordType, from: zoneRecords, as: LogEntry.self)
        let allowanceAdjustments = try decodeCollectionRecords(recordType: Constants.allowanceAdjustmentRecordType, from: zoneRecords, as: AllowanceAdjustment.self)

        let remoteStoreSnapshot = MileageStore.PersistenceSnapshot(
            selectedCountry: settingsSnapshot?.selectedCountry ?? .usa,
            userName: settingsSnapshot?.userName ?? "",
            emailAddress: settingsSnapshot?.emailAddress ?? "",
            preferredCurrency: settingsSnapshot?.preferredCurrency ?? .usd,
            unitSystem: settingsSnapshot?.unitSystem ?? .miles,
            fuelVolumeUnit: settingsSnapshot?.fuelVolumeUnit ?? (settingsSnapshot?.selectedCountry.defaultFuelVolumeUnit ?? .gallons),
            fuelEconomyFormat: (settingsSnapshot?.fuelEconomyFormat ?? .defaultFormat(for: settingsSnapshot?.unitSystem ?? .miles))
                .compatibleFormat(for: settingsSnapshot?.unitSystem ?? .miles),
            preventAutoLock: settingsSnapshot?.preventAutoLock ?? false,
            vehicleDetectionEnabled: settingsSnapshot?.vehicleDetectionEnabled ?? false,
            hasCompletedOnboarding: settingsSnapshot?.hasCompletedOnboarding ?? false,
            hasAcceptedPrivacyPolicy: settingsSnapshot?.hasAcceptedPrivacyPolicy ?? false,
            hasAcceptedLegalNotice: settingsSnapshot?.hasAcceptedLegalNotice ?? false,
            vehicles: vehicles,
            activeVehicleID: settingsSnapshot?.activeVehicleID,
            drivers: drivers,
            activeDriverID: settingsSnapshot?.activeDriverID,
            trips: trips,
            fuelEntries: fuelEntries,
            maintenanceRecords: maintenanceRecords,
            logs: logs,
            allowanceAdjustments: allowanceAdjustments
        )

        let remoteTrackerSnapshot = trackerSnapshot ?? TripTracker.PersistenceSnapshot(
            autoStartEnabled: true,
            backgroundTripTrackingEnabled: true,
            motionActivityEnabled: true,
            autoStartSpeedThresholdKilometersPerHour: 10,
            autoStopDelayMinutes: 10,
            selectedTripType: .business
        )

        let snapshot = AppPersistenceSnapshot(
            store: remoteStoreSnapshot,
            tripTracker: remoteTrackerSnapshot
        )

        return snapshot.isEmpty ? nil : snapshot
    }

    private func upload(snapshot: AppPersistenceSnapshot) async throws {
        let previousSnapshot = lastUploadedSnapshot ?? AppPersistenceSnapshot.empty
        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        if snapshot.store.unitSystem != previousSnapshot.store.unitSystem ||
            snapshot.store.selectedCountry != previousSnapshot.store.selectedCountry ||
            snapshot.store.userName != previousSnapshot.store.userName ||
            snapshot.store.emailAddress != previousSnapshot.store.emailAddress ||
            snapshot.store.preferredCurrency != previousSnapshot.store.preferredCurrency ||
            snapshot.store.fuelVolumeUnit != previousSnapshot.store.fuelVolumeUnit ||
            snapshot.store.fuelEconomyFormat != previousSnapshot.store.fuelEconomyFormat ||
            snapshot.store.preventAutoLock != previousSnapshot.store.preventAutoLock ||
            snapshot.store.hasCompletedOnboarding != previousSnapshot.store.hasCompletedOnboarding ||
            snapshot.store.hasAcceptedPrivacyPolicy != previousSnapshot.store.hasAcceptedPrivacyPolicy ||
            snapshot.store.hasAcceptedLegalNotice != previousSnapshot.store.hasAcceptedLegalNotice ||
            snapshot.store.activeVehicleID != previousSnapshot.store.activeVehicleID ||
            snapshot.store.activeDriverID != previousSnapshot.store.activeDriverID {
            recordsToSave.append(
                try makeSingletonRecord(
                    recordType: Constants.settingsRecordType,
                    recordName: Constants.settingsRecordName,
                    payload: MileageStore.PersistenceSnapshot(
                        selectedCountry: snapshot.store.selectedCountry,
                        userName: snapshot.store.userName,
                        emailAddress: snapshot.store.emailAddress,
                        preferredCurrency: snapshot.store.preferredCurrency,
                        unitSystem: snapshot.store.unitSystem,
                        fuelVolumeUnit: snapshot.store.fuelVolumeUnit,
                        fuelEconomyFormat: snapshot.store.fuelEconomyFormat,
                        preventAutoLock: snapshot.store.preventAutoLock,
                        vehicleDetectionEnabled: snapshot.store.vehicleDetectionEnabled,
                        hasCompletedOnboarding: snapshot.store.hasCompletedOnboarding,
                        hasAcceptedPrivacyPolicy: snapshot.store.hasAcceptedPrivacyPolicy,
                        hasAcceptedLegalNotice: snapshot.store.hasAcceptedLegalNotice,
                        vehicles: [],
                        activeVehicleID: snapshot.store.activeVehicleID,
                        drivers: [],
                        activeDriverID: snapshot.store.activeDriverID,
                        trips: [],
                        fuelEntries: [],
                        maintenanceRecords: [],
                        logs: [],
                        allowanceAdjustments: []
                    )
                )
            )
        }

        if snapshot.tripTracker != previousSnapshot.tripTracker {
            recordsToSave.append(
                try makeSingletonRecord(
                    recordType: Constants.trackerSettingsRecordType,
                    recordName: Constants.trackerSettingsRecordName,
                    payload: snapshot.tripTracker
                )
            )
        }

        let vehicleChanges = try recordChanges(
            previous: previousSnapshot.store.vehicles,
            current: snapshot.store.vehicles,
            recordType: Constants.vehicleRecordType
        )
        recordsToSave.append(contentsOf: vehicleChanges.recordsToSave)
        recordIDsToDelete.append(contentsOf: vehicleChanges.recordIDsToDelete)

        let driverChanges = try recordChanges(
            previous: previousSnapshot.store.drivers,
            current: snapshot.store.drivers,
            recordType: Constants.driverRecordType
        )
        recordsToSave.append(contentsOf: driverChanges.recordsToSave)
        recordIDsToDelete.append(contentsOf: driverChanges.recordIDsToDelete)

        let tripChanges = try recordChanges(
            previous: previousSnapshot.store.trips,
            current: snapshot.store.trips,
            recordType: Constants.tripRecordType
        )
        recordsToSave.append(contentsOf: tripChanges.recordsToSave)
        recordIDsToDelete.append(contentsOf: tripChanges.recordIDsToDelete)

        let fuelChanges = try recordChanges(
            previous: previousSnapshot.store.fuelEntries,
            current: snapshot.store.fuelEntries,
            recordType: Constants.fuelEntryRecordType
        )
        recordsToSave.append(contentsOf: fuelChanges.recordsToSave)
        recordIDsToDelete.append(contentsOf: fuelChanges.recordIDsToDelete)

        let maintenanceChanges = try recordChanges(
            previous: previousSnapshot.store.maintenanceRecords,
            current: snapshot.store.maintenanceRecords,
            recordType: Constants.maintenanceRecordType
        )
        recordsToSave.append(contentsOf: maintenanceChanges.recordsToSave)
        recordIDsToDelete.append(contentsOf: maintenanceChanges.recordIDsToDelete)

        let logChanges = try recordChanges(
            previous: previousSnapshot.store.logs,
            current: snapshot.store.logs,
            recordType: Constants.logRecordType
        )
        recordsToSave.append(contentsOf: logChanges.recordsToSave)
        recordIDsToDelete.append(contentsOf: logChanges.recordIDsToDelete)

        let allowanceAdjustmentChanges = try recordChanges(
            previous: previousSnapshot.store.allowanceAdjustments,
            current: snapshot.store.allowanceAdjustments,
            recordType: Constants.allowanceAdjustmentRecordType
        )
        recordsToSave.append(contentsOf: allowanceAdjustmentChanges.recordsToSave)
        recordIDsToDelete.append(contentsOf: allowanceAdjustmentChanges.recordIDsToDelete)

        guard !recordsToSave.isEmpty || !recordIDsToDelete.isEmpty else {
            return
        }

        try await modifyRecords(saving: recordsToSave, deleting: recordIDsToDelete)
    }

    private func accountStatus() async throws -> CKAccountStatus {
        guard let container else {
            throw CKError(.notAuthenticated)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func validateAccountAvailability() async throws {
        let status = try await accountStatus()

        switch status {
        case .available:
            return
        case .noAccount:
            throw CKError(.notAuthenticated)
        case .restricted:
            throw CKError(.permissionFailure)
        case .couldNotDetermine:
            throw CKError(.networkUnavailable)
        case .temporarilyUnavailable:
            throw CKError(.serviceUnavailable)
        @unknown default:
            throw CKError(.serviceUnavailable)
        }
    }

    private func fetchSingletonSnapshot<T: Decodable>(
        recordType: String,
        recordName: String,
        as type: T.Type
    ) async throws -> T? {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: customZoneID)

        do {
            let record = try await fetchRecord(withID: recordID)
            guard let payload = record[Constants.payloadKey] as? Data else {
                return nil
            }

            return try decodePayload(type, from: payload)
        } catch let error as CKError where error.code == .unknownItem {
            let legacyRecordID = CKRecord.ID(recordName: recordName, zoneID: defaultZoneID)
            do {
                let record = try await fetchRecord(withID: legacyRecordID)
                guard let payload = record[Constants.payloadKey] as? Data else {
                    return nil
                }

                return try decodePayload(type, from: payload)
            } catch let legacyError as CKError where legacyError.code == .unknownItem {
                return nil
            }
        }
    }

    private func decodeCollectionRecords<T: Decodable>(
        recordType: String,
        from records: [CKRecord],
        as type: T.Type
    ) throws -> [T] {
        try records.compactMap { record in
            guard record.recordType == recordType else {
                return nil
            }

            guard let payload = record[Constants.payloadKey] as? Data else {
                return nil
            }

            return try decodePayload(type, from: payload)
        }
    }

    private func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord {
        guard let database else {
            throw CKError(.notAuthenticated)
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func makeSingletonRecord<T: Encodable>(
        recordType: String,
        recordName: String,
        payload: T
    ) throws -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: customZoneID))
        record[Constants.payloadKey] = try encodePayload(payload) as CKRecordValue
        record[Constants.updatedAtKey] = Date() as CKRecordValue
        return record
    }

    private func recordChanges<T: Codable & Equatable & Identifiable>(
        previous: [T],
        current: [T],
        recordType: String
    ) throws -> (recordsToSave: [CKRecord], recordIDsToDelete: [CKRecord.ID]) where T.ID == UUID {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })

        var recordsToSave: [CKRecord] = []
        var recordIDsToDelete: [CKRecord.ID] = []

        for (id, item) in currentByID where previousByID[id] != item {
            recordsToSave.append(try makeRecord(for: item, recordType: recordType))
        }

        for id in previousByID.keys where currentByID[id] == nil {
            recordIDsToDelete.append(recordID(for: id, recordType: recordType))
        }

        return (recordsToSave, recordIDsToDelete)
    }

    private func makeRecord<T: Encodable & Identifiable>(
        for item: T,
        recordType: String
    ) throws -> CKRecord where T.ID == UUID {
        let record = CKRecord(recordType: recordType, recordID: recordID(for: item.id, recordType: recordType))
        record[Constants.payloadKey] = try encodePayload(item) as CKRecordValue
        record[Constants.updatedAtKey] = Date() as CKRecordValue
        return record
    }

    private func recordID(for id: UUID, recordType: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(recordType)-\(id.uuidString)", zoneID: customZoneID)
    }

    private func encodePayload<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decodePayload<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func modifyRecords(saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID]) async throws {
        guard let database else {
            throw CKError(.notAuthenticated)
        }

        var saveStartIndex = 0
        var deleteStartIndex = 0

        while saveStartIndex < recordsToSave.count || deleteStartIndex < recordIDsToDelete.count {
            let remainingSaveCount = recordsToSave.count - saveStartIndex
            let saveBatchCount = min(Constants.maximumModifyItemsPerRequest, remainingSaveCount)
            let currentSaveBatch = saveBatchCount > 0
                ? Array(recordsToSave[saveStartIndex ..< saveStartIndex + saveBatchCount])
                : []

            let remainingCapacity = Constants.maximumModifyItemsPerRequest - currentSaveBatch.count
            let remainingDeleteCount = recordIDsToDelete.count - deleteStartIndex
            let deleteBatchCount = min(remainingCapacity, remainingDeleteCount)
            let currentDeleteBatch = deleteBatchCount > 0
                ? Array(recordIDsToDelete[deleteStartIndex ..< deleteStartIndex + deleteBatchCount])
                : []

            _ = try await database.modifyRecords(
                saving: currentSaveBatch,
                deleting: currentDeleteBatch,
                savePolicy: .changedKeys,
                atomically: false
            )

            saveStartIndex += currentSaveBatch.count
            deleteStartIndex += currentDeleteBatch.count
        }
    }

    private func fetchAllRecordsFromCustomZone() async throws -> [CKRecord] {
        guard let database else {
            throw CKError(.notAuthenticated)
        }

        var fetchedRecordsByID: [CKRecord.ID: CKRecord] = [:]
        var changeToken: CKServerChangeToken?
        var moreComing = true

        while moreComing {
            let batch = try await fetchRecordZoneChanges(
                in: database,
                zoneID: customZoneID,
                changeToken: changeToken
            )

            for (recordID, result) in batch.modificationResultsByID {
                switch result {
                case .success(let modification):
                    fetchedRecordsByID[recordID] = modification.record
                case .failure(let error):
                    throw error
                }
            }

            for deletion in batch.deletions {
                fetchedRecordsByID.removeValue(forKey: deletion.recordID)
            }

            changeToken = batch.changeToken
            moreComing = batch.moreComing
        }

        return Array(fetchedRecordsByID.values)
    }

    private func ensureCustomZoneExists() async throws {
        guard let database else {
            throw CKError(.notAuthenticated)
        }

        _ = try await database.modifyRecordZones(
            saving: [CKRecordZone(zoneName: Constants.customZoneName)],
            deleting: []
        )
    }

    private func deleteCustomZoneIfPresent() async throws {
        guard let database else {
            throw CKError(.notAuthenticated)
        }

        do {
            _ = try await database.modifyRecordZones(
                saving: [],
                deleting: [customZoneID]
            )
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            return
        }
    }

    private func fetchRecordZoneChanges(
        in database: CKDatabase,
        zoneID: CKRecordZone.ID,
        changeToken: CKServerChangeToken?
    ) async throws -> (
        modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
        deletions: [CKDatabase.RecordZoneChange.Deletion],
        changeToken: CKServerChangeToken,
        moreComing: Bool
    ) {
        try await withCheckedThrowingContinuation { continuation in
            database.fetchRecordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken,
                desiredKeys: nil,
                resultsLimit: nil
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func configureCloudKitIfPossible() -> Bool {
        if container != nil, database != nil {
            return true
        }

        let resolvedContainer = CKContainer(identifier: Constants.cloudContainerIdentifier)
        container = resolvedContainer
        database = resolvedContainer.privateCloudDatabase
        return true
    }
}

enum BiometricAuthenticator {
    static func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var error: NSError?
            let policy: LAPolicy
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                policy = .deviceOwnerAuthenticationWithBiometrics
            } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                policy = .deviceOwnerAuthentication
            } else {
                continuation.resume(throwing: error ?? LAError(.biometryNotAvailable))
                return
            }

            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? LAError(.authenticationFailed))
                }
            }
        }
    }
}

enum KeychainController {
    static func saveString(_ value: String, service: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func readString(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    static func deleteValue(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: LocalizedError {
        case unhandled(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandled(let status):
                "Keychain error: \(status)"
            }
        }
    }
}
