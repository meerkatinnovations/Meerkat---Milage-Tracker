//  ContentView.swift
//  Meerkat - Milage Tracker
//
//  Created by Rheeder Greeff on 2026-03-15.
//

import CoreLocation
import CoreBluetooth
import AVFoundation
import AuthenticationServices
import MapKit
import MessageUI
import Observation
import PhotosUI
import StoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import VisionKit
#if canImport(FirebaseFunctions) && canImport(FirebaseMessagingInterop)
import FirebaseFunctions
#endif

private extension UTType {
    static let excelWorkbook = UTType(filenameExtension: "xlsx") ?? .spreadsheet
}

struct ContentView: View {
    private enum Constants {
        static let minimumForegroundRefreshInterval: TimeInterval = 180
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = SharedAppModel.shared
    @State private var store = SharedAppModel.shared.store
    @State private var tripTracker = SharedAppModel.shared.tripTracker
    @State private var authSession = SharedAppModel.shared.authSession
    @State private var subscriptionManager = SharedAppModel.shared.subscriptionManager
    @State private var cloudSync = SharedAppModel.shared.cloudSync
    @State private var maintenanceReminderManager = SharedAppModel.shared.maintenanceReminderManager
    @State private var maintenanceReminderAlert: MaintenanceReminderNotification?
    @State private var isBootstrappingCloudData = false

    var body: some View {
        Group {
            switch authSession.accessState {
            case .signedOut:
                LoginView(authSession: authSession, cloudSync: cloudSync, subscriptionManager: subscriptionManager)
            case .locked:
                UnlockView(authSession: authSession)
            case .unlocked:
                if subscriptionManager.hasActiveSubscription || authSession.isDemoModeEnabled || authSession.hasOwnerAccess || authSession.hasApprovedBetaAccess {
                    if shouldShowBlockingInitialCloudRestore {
                        initialCloudRestoreView
                    } else if shouldShowOnboarding {
                        OnboardingView(
                            store: store,
                            tripTracker: tripTracker,
                            authSession: authSession,
                            maintenanceReminderManager: maintenanceReminderManager
                        )
                    } else {
                        mainTabView
                            .sheet(isPresented: loginSheetBinding) {
                                NavigationStack {
                                    LoginView(authSession: authSession, cloudSync: cloudSync, subscriptionManager: subscriptionManager)
                                }
                            }
                    }
                } else {
                    SubscriptionGateView(subscriptionManager: subscriptionManager, authSession: authSession, cloudSync: cloudSync)
                        .sheet(isPresented: loginSheetBinding) {
                            NavigationStack {
                                LoginView(authSession: authSession, cloudSync: cloudSync, subscriptionManager: subscriptionManager)
                            }
                        }
                }
            }
        }
        .tint(.orange)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topTrailing) {
            if authSession.canUseCloudSyncFeatures && isBootstrappingCloudData {
                cloudSyncStatusIndicator
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
        .overlay(alignment: .topLeading) {
            if authSession.isDemoModeEnabled {
                DemoModeBadge(summary: store.demoModeSummary)
                    .padding(.top, 12)
                    .padding(.leading, 16)
            }
        }
        .task {
            loadPersistedDataIfNeeded()
            syncTripTrackerReadiness()
            await subscriptionManager.setSelectedAccountType(store.accountSubscriptionType)
            await subscriptionManager.prepare()
            await bootstrapCloudSyncIfNeeded(preferRemoteOnFirstSync: true)
            await appModel.repairRecentTripAddressesAndSyncIfNeeded()
            requestLocationAuthorizationIfNeeded()
            await checkMaintenanceReminders()
            applyPendingOnboardingResetIfNeeded()
        }
        .onChange(of: persistenceSnapshot, initial: false) { _, snapshot in
            guard appModel.hasLoadedPersistence else {
                return
            }

            save(snapshot)
            Task {
                await uploadSnapshotToCloudIfNeeded(snapshot)
                await checkMaintenanceReminders()
            }
        }
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            if newPhase == .active {
                appModel.refreshVehicleConnectionConfiguration()
                Task {
                    await subscriptionManager.refreshSubscriptionStatus()
                    await bootstrapCloudSyncIfNeeded(refreshRemote: true)
                    await appModel.repairRecentTripAddressesAndSyncIfNeeded()
                }
                requestLocationAuthorizationIfNeeded()
                Task {
                    await checkMaintenanceReminders()
                }
                applyPendingOnboardingResetIfNeeded()
            }
        }
        .onChange(of: authSession.accessState, initial: false) { _, _ in
            Task {
                if authSession.canUseCloudSyncFeatures {
                    await bootstrapCloudSyncIfNeeded(preferRemoteOnFirstSync: true)
                } else {
                    cloudSync.resetSession()
                    isBootstrappingCloudData = false
                }
            }
            applyPendingOnboardingResetIfNeeded()
        }
        .onChange(of: store.isReadyToDrive, initial: true) { _, _ in
            syncTripTrackerReadiness()
        }
        .onChange(of: store.accountSubscriptionType, initial: true) { _, newType in
            Task {
                await subscriptionManager.setSelectedAccountType(newType)
            }
        }
        .alert(item: $maintenanceReminderAlert) { reminder in
            Alert(
                title: Text(reminder.title),
                message: Text(reminder.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var persistenceSnapshot: AppPersistenceSnapshot {
        AppPersistenceSnapshot(
            store: store.persistenceSnapshot,
            tripTracker: tripTracker.persistenceSnapshot
        )
    }

    private var loginSheetBinding: Binding<Bool> {
        Binding(
            get: { authSession.isPresentingLoginSheet },
            set: { authSession.isPresentingLoginSheet = $0 }
        )
    }

    private var shouldShowOnboarding: Bool {
        !store.hasCompletedOnboarding || !store.hasAcceptedPrivacyPolicy || !store.hasAcceptedLegalNotice
    }

    private var shouldShowBlockingInitialCloudRestore: Bool {
        guard authSession.canUseCloudSyncFeatures,
              !cloudSync.hasCompletedInitialSync,
              isBootstrappingCloudData else {
            return false
        }

        // Keep the app fully usable offline/on reopen when local data already exists.
        // Only block when there is no local snapshot yet and we are truly restoring.
        return persistenceSnapshot.isEmpty
    }

    private var initialCloudRestoreView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Restoring your data...")
                .font(.headline)
            Text("Please wait while Meerkat syncs your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var cloudSyncStatusIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Syncing")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        .allowsHitTesting(false)
        .accessibilityLabel(cloudSync.statusMessage)
    }

    private var mainTabView: some View {
        TabView {
            NavigationStack {
                TripsView(store: store, tripTracker: tripTracker, cloudSync: cloudSync)
            }
            .tabItem {
                Label("Trips", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }

            NavigationStack {
                FuelView(
                    store: store,
                    tripTracker: tripTracker,
                    cloudSync: cloudSync
                )
            }
            .tabItem {
                Label("Fuel", systemImage: "fuelpump")
            }

            NavigationStack {
                MaintenanceView(store: store, tripTracker: tripTracker, cloudSync: cloudSync)
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
                SettingsView(
                    store: store,
                    tripTracker: tripTracker,
                    vehicleConnectionManager: appModel.vehicleConnectionManager,
                    authSession: authSession,
                    subscriptionManager: subscriptionManager,
                    cloudSync: cloudSync,
                    onExitDemoMode: {
                        appModel.exitDemoMode()
                    },
                    onClearRecordedAppData: {
                        appModel.clearRecordedAppData()
                    },
                    onFactoryReset: {
                        appModel.factoryResetAppData()
                    }
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .overlay {
            GlobalTripRecorderButton(store: store, tripTracker: tripTracker)
        }
    }

    private func loadPersistedDataIfNeeded() {
        guard !appModel.hasLoadedPersistence else {
            return
        }
        appModel.loadPersistedDataIfNeeded()
        syncTripTrackerReadiness()
    }

    private func save(_ snapshot: AppPersistenceSnapshot) {
        appModel.saveCurrentSnapshot()
    }

    private func uploadSnapshotToCloudIfNeeded(_ snapshot: AppPersistenceSnapshot) async {
        guard authSession.canUseCloudSyncFeatures else {
            return
        }

        await cloudSync.uploadIfNeeded(snapshot: snapshot)
    }

    private func syncTripTrackerReadiness() {
        tripTracker.canRecordTrips = store.isReadyToDrive
    }

    private func requestLocationAuthorizationIfNeeded() {
        guard authSession.accessState != .locked else {
            return
        }

        tripTracker.requestAuthorizationIfNeeded()
    }

    private func checkMaintenanceReminders() async {
        guard appModel.hasLoadedPersistence else {
            return
        }

        let currentOdometer = store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
        maintenanceReminderAlert = await maintenanceReminderManager.processReminders(
            in: store,
            currentOdometer: currentOdometer,
            unitSystem: store.unitSystem
        )
    }

    private func applyPendingOnboardingResetIfNeeded() {
        guard authSession.consumeOnboardingRequest() else {
            return
        }

        store.hasCompletedOnboarding = false
        store.hasAcceptedPrivacyPolicy = false
        store.hasAcceptedLegalNotice = false
    }

    private func bootstrapCloudSyncIfNeeded(
        preferRemoteOnFirstSync: Bool = false,
        refreshRemote: Bool = false
    ) async {
        guard authSession.canUseCloudSyncFeatures, appModel.hasLoadedPersistence, !isBootstrappingCloudData else {
            return
        }

        if refreshRemote,
           !cloudSync.shouldRefreshOnForeground(
                snapshot: persistenceSnapshot,
                minimumInterval: Constants.minimumForegroundRefreshInterval
           ) {
            return
        }

        isBootstrappingCloudData = true
        defer {
            isBootstrappingCloudData = false
        }

        let resolvedSnapshot: AppPersistenceSnapshot?
        if refreshRemote, cloudSync.hasCompletedInitialSync {
            resolvedSnapshot = await cloudSync.sync(
                snapshot: persistenceSnapshot,
                preferRemoteOnFirstSync: false
            )
        } else if !cloudSync.hasCompletedInitialSync {
            resolvedSnapshot = await cloudSync.performInitialSync(
                localSnapshot: persistenceSnapshot
            )
        } else {
            resolvedSnapshot = await cloudSync.sync(
                snapshot: persistenceSnapshot,
                preferRemoteOnFirstSync: preferRemoteOnFirstSync
            )
        }

        guard let resolvedSnapshot else {
            return
        }

        appModel.applyRestoredSnapshot(resolvedSnapshot)
        await checkMaintenanceReminders()
    }
}

private struct DemoModeBadge: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Demo Mode")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
            Text(summary)
                .font(.caption2)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(.orange.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}

private struct LoginView: View {
    private enum EmailAuthMode: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case createAccount = "Create Account"

        var id: String { rawValue }
    }

    @Bindable var authSession: AuthSessionManager
    @Bindable var cloudSync: CloudSyncManager
    @Bindable var subscriptionManager: SubscriptionManager
    @State private var appModel = SharedAppModel.shared
    @State private var emailAuthMode: EmailAuthMode = .signIn
    @State private var emailAddress = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var resetEmailAddress = ""
    @State private var resetPassword = ""
    @State private var resetPasswordConfirmation = ""
    @State private var isPresentingPasswordReset = false
    @State private var isPresentingOfferCodeRedemption = false
    @State private var secondFactorCode = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.18), Color.yellow.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 188, height: 188)

                        Image("LoginMeerkat")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 152, height: 152)
                    }
                    .contentShape(Rectangle())

                    VStack(spacing: 10) {
                        Text("Meerkat Mileage Tracker")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Track trips, fuel, maintenance, and tax-ready records in one place.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email & Password")
                            .font(.headline)
                        Text(authSession.usesFirebaseEmailPasswordAuth
                             ? "Create an account or sign in with your existing email and password. Your data can sync securely across your devices."
                             : "Create a local account or sign in with your existing email and password. Incorrect credentials are shown immediately.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Picker("Email Access", selection: $emailAuthMode) {
                        ForEach(EmailAuthMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)

                    if emailAuthMode == .createAccount {
                        SecureField("Confirm password", text: $passwordConfirmation)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(emailAuthMode == .signIn ? "Sign In With Email" : "Create Account") {
                        if emailAuthMode == .signIn {
                            secondFactorCode = ""
                            authSession.signInWithEmail(
                                email: emailAddress,
                                password: password
                            )
                        } else {
                            authSession.createEmailPasswordAccount(
                                email: emailAddress,
                                password: password,
                                passwordConfirmation: passwordConfirmation
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)

                    if authSession.isAwaitingSecondFactor {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Two-Factor Verification")
                                .font(.headline)

                            if authSession.secondFactorHintDisplayNames.count > 1 {
                                Picker("Verification Method", selection: $authSession.selectedSecondFactorHintIndex) {
                                    ForEach(Array(authSession.secondFactorHintDisplayNames.enumerated()), id: \.offset) { index, label in
                                        Text(label).tag(index)
                                    }
                                }
                            } else if let hint = authSession.secondFactorHintDisplayNames.first {
                                Text("Code destination: \(hint)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            TextField("Verification code", text: $secondFactorCode)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 12) {
                                Button("Resend Code") {
                                    authSession.sendSecondFactorCode()
                                }
                                .buttonStyle(.bordered)

                                Button("Verify Code") {
                                    authSession.completeSecondFactorSignIn(code: secondFactorCode)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .disabled(secondFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    if emailAuthMode == .signIn {
                        Button("Forgot Password?") {
                            resetEmailAddress = emailAddress
                            resetPassword = ""
                            resetPasswordConfirmation = ""
                            isPresentingPasswordReset = true
                        }
                        .font(.footnote.weight(.semibold))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account Type")
                            .font(.headline)
                        Picker("Account Type", selection: accountTypeBinding) {
                            ForEach(availableAccountTypes) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Your selection controls which subscription plans are shown.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sign in with Apple")
                            .font(.headline)
                        Text("Connect your Apple Account for iCloud backup and optional biometric unlock. You can also continue directly to subscription options.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    SignInWithAppleButton(.signIn) { request in
                        authSession.prepareAppleSignInRequest(request)
                    } onCompletion: { result in
                        authSession.handleSignInCompletion(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)

                    Button {
                        authSession.signInWithGoogle()
                    } label: {
                        Label("Sign In With Google", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    VStack(spacing: 12) {
                        Button("View Demo Mode") {
                            appModel.enterDemoMode()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Redeem App Store Offer Code") {
                            isPresentingOfferCodeRedemption = true
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Text("Use an offer code from Apple to unlock eligible plans.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Demo Mode includes sample data and limited record creation so you can explore the app before subscribing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
                .frame(maxWidth: 520)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.orange.opacity(0.12), lineWidth: 1)
                )

                VStack(spacing: 10) {
                    Text("Cloud status: \(cloudSync.statusMessage)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let errorMessage = authSession.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color.orange.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .offerCodeRedemption(isPresented: $isPresentingOfferCodeRedemption) { result in
            subscriptionManager.noteOfferCodeRedemptionSheetResult(result)
        }
        .sheet(isPresented: $isPresentingPasswordReset) {
            NavigationStack {
                Form {
                    Section("Reset Password") {
                        TextField("Email", text: $resetEmailAddress)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                        if !authSession.usesFirebaseEmailPasswordAuth {
                            SecureField("New password", text: $resetPassword)
                            SecureField("Confirm new password", text: $resetPasswordConfirmation)
                        }

                        Text(authSession.usesFirebaseEmailPasswordAuth
                             ? "Enter your account email and the app will send a password reset email."
                             : "Enter the email for your local account and choose a new password with at least 8 characters.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Recover Password")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresentingPasswordReset = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(authSession.usesFirebaseEmailPasswordAuth ? "Send Email" : "Reset") {
                            authSession.resetEmailPassword(
                                email: resetEmailAddress,
                                newPassword: resetPassword,
                                passwordConfirmation: resetPasswordConfirmation
                            )
                            isPresentingPasswordReset = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var accountTypeBinding: Binding<AccountSubscriptionType> {
        Binding(
            get: { appModel.store.accountSubscriptionType },
            set: { appModel.store.accountSubscriptionType = normalizedAccountType($0) }
        )
    }

    private var availableAccountTypes: [AccountSubscriptionType] {
        if AppFeatureFlags.businessSubscriptionsEnabled {
            return AccountSubscriptionType.allCases
        }

        return AccountSubscriptionType.allCases.filter { $0 != .business }
    }

    private func normalizedAccountType(_ type: AccountSubscriptionType) -> AccountSubscriptionType {
        guard !AppFeatureFlags.businessSubscriptionsEnabled, type == .business else {
            return type
        }

        return .personal
    }
}

private struct OnboardingView: View {
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker
    @Bindable var authSession: AuthSessionManager
    let maintenanceReminderManager: MaintenanceReminderManager

    @State private var step: OnboardingStep = .account
    @State private var notificationAuthorizationLabel = "Checking..."
    @State private var vehicleProfileName = ""
    @State private var vehicleMake = ""
    @State private var vehicleModel = ""
    @State private var vehicleColor = ""
    @State private var vehicleNumberPlate = ""
    @State private var vehicleFleetNumber = ""
    @State private var vehicleStartingOdometer = ""
    @State private var vehicleOwnershipType: VehicleOwnershipType = .personal
    @State private var driverName = ""
    @State private var driverDateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var driverLicenceNumber = ""
    @State private var driverLicenceClass = ""
    @State private var driverEmailAddress = ""
    @State private var driverPhoneNumber = ""
    @State private var businessAccountManagerPhone = ""
    @State private var businessName = ""
    @State private var businessLegalEntityName = ""
    @State private var businessTaxRegistrationNumber = ""
    @State private var businessVatRegistrationNumber = ""
    @State private var businessBillingAddressLine1 = ""
    @State private var businessBillingAddressLine2 = ""
    @State private var businessBillingCity = ""
    @State private var businessBillingStateOrProvince = ""
    @State private var businessBillingPostalCode = ""
    @State private var businessBillingCountry = ""
    @State private var acceptsPrivacyPolicy = false
    @State private var acceptsLegalNotice = false
    @State private var isRequestingPermissions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    progressCard
                    currentStepCard
                    footerActions
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.12), Color(.systemGroupedBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarBackButtonHidden(true)
        }
        .task {
            await refreshNotificationAuthorizationLabel()
        }
        .onAppear {
            normalizeBusinessAccountSelectionIfNeeded()
            prefillAccountDetailsFromAppleSignInIfNeeded()
            prefillBusinessProfileIfNeeded()
            acceptsPrivacyPolicy = store.hasAcceptedPrivacyPolicy
            acceptsLegalNotice = store.hasAcceptedLegalNotice
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 104, height: 104)

                Image("LoginMeerkat")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
            }

            VStack(spacing: 8) {
                Text("Welcome to Meerkat")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Set up your country, preferences, tracking defaults, permissions, and optional first vehicle and driver before you start recording trips.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 680)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(step.title)
                    .font(.headline)
                Spacer()
                Text("Step \(currentStepNumber) of \(OnboardingStep.allCases.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(currentStepNumber), total: Double(OnboardingStep.allCases.count))
                .tint(.orange)

            Text(step.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 680)
        .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var currentStepCard: some View {
        switch step {
        case .account:
            onboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Country", selection: selectedCountryBinding) {
                        ForEach(SupportedCountry.allCases) { country in
                            Text(country.rawValue).tag(country)
                        }
                    }

                    TextField("Your name", text: $store.userName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    TextField("Email address", text: $store.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    if !store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !isValidEmail(store.emailAddress) {
                        Text("Enter a valid email address to continue.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    if isBusinessAccount {
                        Divider()
                        Text("Business Account Details")
                            .font(.headline)

                        TextField("Business name", text: $businessName)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)

                        TextField("Legal entity name", text: $businessLegalEntityName)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)

                        TextField("Account manager phone", text: $businessAccountManagerPhone)
                            .keyboardType(.phonePad)
                            .textFieldStyle(.roundedBorder)

                        TextField("Tax registration number", text: $businessTaxRegistrationNumber)
                            .textInputAutocapitalization(.characters)
                            .textFieldStyle(.roundedBorder)

                        TextField("VAT registration number (optional)", text: $businessVatRegistrationNumber)
                            .textInputAutocapitalization(.characters)
                            .textFieldStyle(.roundedBorder)

                        TextField("Billing address line 1", text: $businessBillingAddressLine1)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)

                        TextField("Billing address line 2 (optional)", text: $businessBillingAddressLine2)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)

                        TextField("City", text: $businessBillingCity)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)

                        TextField("State / Province", text: $businessBillingStateOrProvince)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)

                        TextField("Postal code", text: $businessBillingPostalCode)
                            .textInputAutocapitalization(.characters)
                            .textFieldStyle(.roundedBorder)

                        TextField("Country", text: $businessBillingCountry)
                            .textInputAutocapitalization(.words)
                            .textFieldStyle(.roundedBorder)
                    }

                    Text("Country defaults will automatically update distance, fuel volume, and currency. You can still adjust them on the next step.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    webPortalNotice(
                        title: "Manage Data on the Web",
                        message: "You can also access your account at app.meerkatinnovations.ca to manage synced data and export logs from a computer."
                    )
                }
            }
        case .preferences:
            onboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Currency", selection: $store.preferredCurrency) {
                        ForEach(PreferredCurrency.allCases) { currency in
                            Text("\(currency.rawValue) • \(currency.title)").tag(currency)
                        }
                    }

                    Picker("Distance", selection: $store.unitSystem) {
                        ForEach(DistanceUnitSystem.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }

                    Picker("Fuel Volume", selection: $store.fuelVolumeUnit) {
                        ForEach(FuelVolumeUnit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }

                    Picker("Fuel Economy", selection: fuelEconomyFormatBinding) {
                        ForEach(availableFuelEconomyFormats) { format in
                            Text(format.title).tag(format)
                        }
                    }

                    Toggle("Keep screen awake on trip", isOn: $store.preventAutoLock)

                    Text("These preferences control measurement formatting across trips, fuel-ups, logs, and exports.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .tracking:
            onboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Auto-start trips", isOn: $tripTracker.autoStartEnabled)
                    Toggle("Background trip tracking", isOn: $tripTracker.backgroundTripTrackingEnabled)
                    Toggle("Use Motion & Fitness", isOn: $tripTracker.motionActivityEnabled)

                    Stepper(
                        value: $tripTracker.autoStartSpeedThresholdKilometersPerHour,
                        in: 5 ... 130,
                        step: 5
                    ) {
                        LabeledContent(
                            "Auto-start speed",
                            value: "\(tripTracker.autoStartSpeedThresholdKilometersPerHour.formatted(.number.precision(.fractionLength(0)))) km/h"
                        )
                    }

                    Stepper(
                        value: $tripTracker.autoStopDelayMinutes,
                        in: 1 ... 60,
                        step: 1
                    ) {
                        LabeledContent(
                            "Auto-stop delay",
                            value: "\(tripTracker.autoStopDelayMinutes.formatted(.number.precision(.fractionLength(0)))) min"
                        )
                    }

                    Text("Default auto-stop is 10 minutes below the auto-start speed threshold. When the delay is reached, the active trip is finished and saved automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .permissions:
            onboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    permissionRow(title: "Location access", value: tripTracker.authorizationLabel)
                    permissionRow(title: "Motion & Fitness", value: tripTracker.motionAuthorizationLabel)
                    permissionRow(title: "Notifications", value: notificationAuthorizationLabel)

                    Button(isRequestingPermissions ? "Requesting Permissions..." : "Allow All Permissions") {
                        requestAllPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isRequestingPermissions)

                    Text("The app will request location, background location when needed, motion and fitness, and notifications for maintenance reminders. Camera and photo access are still requested only when you scan or attach receipts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .vehicle:
            onboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Profile name (optional)", text: $vehicleProfileName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    TextField("Make", text: $vehicleMake)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    TextField("Model", text: $vehicleModel)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    TextField("Color", text: $vehicleColor)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    TextField("Number plate", text: $vehicleNumberPlate)
                        .textInputAutocapitalization(.characters)
                        .textFieldStyle(.roundedBorder)

                    if isBusinessAccount {
                        TextField("Fleet number (optional)", text: $vehicleFleetNumber)
                            .textInputAutocapitalization(.characters)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("Starting odometer", text: $vehicleStartingOdometer)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    Picker("Ownership", selection: $vehicleOwnershipType) {
                        ForEach(VehicleOwnershipType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }

                    if let activeVehicle = store.activeVehicle {
                        Text("Current active vehicle: \(activeVehicle.displayName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Vehicle") {
                        saveOnboardingVehicle()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!canSaveOnboardingVehicle)
                }
            }
        case .driver:
            onboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Driver name", text: $driverName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    DatePicker("Date of birth", selection: $driverDateOfBirth, displayedComponents: .date)

                    TextField("Licence number", text: $driverLicenceNumber)
                        .textInputAutocapitalization(.characters)
                        .textFieldStyle(.roundedBorder)

                    if isBusinessAccount {
                        TextField("Licence class", text: $driverLicenceClass)
                            .textInputAutocapitalization(.characters)
                            .textFieldStyle(.roundedBorder)

                        TextField("Driver email address", text: $driverEmailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        TextField("Driver phone number", text: $driverPhoneNumber)
                            .keyboardType(.phonePad)
                            .textFieldStyle(.roundedBorder)

                    }

                    if let activeDriver = store.activeDriver {
                        Text("Current active driver: \(activeDriver.name)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Driver") {
                        saveOnboardingDriver()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!canSaveOnboardingDriver)
                }
            }
        case .legal:
            onboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Please review and accept the privacy policy and legal notice before using the app.")
                        .font(.body)

                    NavigationLink("Read full privacy policy and legal notice") {
                        SettingsPrivacyLegalView()
                    }
                    .font(.headline)

                    legalSummaryBlock(
                        title: "Privacy",
                        text: "Trip locations, mileage records, fuel and maintenance logs, vehicle and driver profiles, receipts, and app preferences are used to operate the app and any iCloud backup features you enable."
                    )

                    legalSummaryBlock(
                        title: "Legal",
                        text: "The app is a recordkeeping tool. You remain responsible for reviewing mileage, odometer, reimbursement, tax, employment, and regulatory information before relying on it."
                    )

                    Toggle("I accept the Privacy Policy", isOn: $acceptsPrivacyPolicy)
                    Toggle("I accept the Legal Notice", isOn: $acceptsLegalNotice)

                    Text("If you decline these notices, you will be returned to the login screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            if step != .account {
                Button("Back") {
                    step = OnboardingStep(rawValue: step.rawValue - 1) ?? .account
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if step == .vehicle || step == .driver {
                Button("Skip") {
                    advance()
                }
                .buttonStyle(.bordered)
            }

            if step == .legal {
                Button("Decline") {
                    declineLegalNotices()
                }
                .buttonStyle(.bordered)

                Button("Accept & Finish") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canFinishOnboarding)
            } else {
                Button("Continue") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canContinueFromCurrentStep)
            }
        }
        .frame(maxWidth: 680)
    }

    private func webPortalNotice(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "desktopcomputer")
                .font(.headline)
                .foregroundStyle(Color.orange)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link("Open app.meerkatinnovations.ca", destination: URL(string: "https://app.meerkatinnovations.ca")!)
                .font(.footnote.weight(.semibold))
        }
        .padding(16)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var selectedCountryBinding: Binding<SupportedCountry> {
        Binding(
            get: { store.selectedCountry },
            set: { store.applyCountryPreferences($0) }
        )
    }

    private var availableFuelEconomyFormats: [FuelEconomyFormat] {
        switch store.unitSystem {
        case .miles:
            return [.milesPerGallon]
        case .kilometers:
            return [.kilometersPerLiter, .litersPer100Kilometers]
        }
    }

    private var fuelEconomyFormatBinding: Binding<FuelEconomyFormat> {
        Binding(
            get: { store.fuelEconomyFormat.compatibleFormat(for: store.unitSystem) },
            set: { store.fuelEconomyFormat = $0.compatibleFormat(for: store.unitSystem) }
        )
    }

    private var currentStepNumber: Int {
        step.rawValue + 1
    }

    private var isBusinessAccount: Bool {
        AppFeatureFlags.businessSubscriptionsEnabled
            && (
                store.accountSubscriptionType == .business
                    || SharedAppModel.shared.subscriptionManager.selectedAccountType == .business
                    || SharedAppModel.shared.subscriptionManager.hasBusinessSubscription
            )
    }

    private var canSaveOnboardingVehicle: Bool {
        !vehicleMake.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !vehicleColor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !vehicleNumberPlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        parseDecimalInput(vehicleStartingOdometer) != nil
    }

    private var canSaveOnboardingDriver: Bool {
        let basicFieldsAreValid = !driverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !driverLicenceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard isBusinessAccount else {
            return basicFieldsAreValid
        }

        return basicFieldsAreValid &&
            !driverLicenceClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            isValidEmail(driverEmailAddress)
    }

    private var canFinishOnboarding: Bool {
        acceptsPrivacyPolicy && acceptsLegalNotice
    }

    private var canContinueFromCurrentStep: Bool {
        switch step {
        case .account:
            return canContinueFromAccountStep
        default:
            return true
        }
    }

    private var canContinueFromAccountStep: Bool {
        let trimmedName = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && isValidEmail(trimmedEmail)
    }

    private func advance() {
        guard canContinueFromCurrentStep else {
            return
        }

        if step == .account {
            persistBusinessProfileIfNeeded()
        }

        guard let nextStep = OnboardingStep(rawValue: step.rawValue + 1) else {
            return
        }

        step = nextStep
    }

    private func normalizeBusinessAccountSelectionIfNeeded() {
        guard isBusinessAccount else {
            return
        }

        if store.accountSubscriptionType != .business {
            store.accountSubscriptionType = .business
        }
    }

    private func prefillAccountDetailsFromAppleSignInIfNeeded() {
        if store.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !authSession.appleFullName.isEmpty {
            store.userName = authSession.appleFullName
        }

        if store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !authSession.appleEmailAddress.isEmpty {
            store.emailAddress = authSession.appleEmailAddress
        }
    }

    private func prefillBusinessProfileIfNeeded() {
        guard let profile = store.businessProfile else {
            return
        }

        businessAccountManagerPhone = profile.accountManagerPhone
        businessName = profile.businessName
        businessLegalEntityName = profile.legalEntityName
        businessTaxRegistrationNumber = profile.taxRegistrationNumber
        businessVatRegistrationNumber = profile.vatRegistrationNumber
        businessBillingAddressLine1 = profile.billingAddressLine1
        businessBillingAddressLine2 = profile.billingAddressLine2
        businessBillingCity = profile.city
        businessBillingStateOrProvince = profile.stateOrProvince
        businessBillingPostalCode = profile.postalCode
        businessBillingCountry = profile.country
    }

    private func requestAllPermissions() {
        isRequestingPermissions = true
        tripTracker.requestPermissionsForCurrentTrackingMode()

        Task {
            await maintenanceReminderManager.requestNotificationAuthorization()
            await refreshNotificationAuthorizationLabel()
            isRequestingPermissions = false
        }
    }

    private func saveOnboardingVehicle() {
        guard
            let odometerReading = parseDecimalInput(vehicleStartingOdometer)
        else {
            return
        }

        let vehicle = VehicleProfile(
            profileName: vehicleProfileName.trimmingCharacters(in: .whitespacesAndNewlines),
            make: vehicleMake.trimmingCharacters(in: .whitespacesAndNewlines),
            model: vehicleModel.trimmingCharacters(in: .whitespacesAndNewlines),
            color: vehicleColor.trimmingCharacters(in: .whitespacesAndNewlines),
            numberPlate: vehicleNumberPlate.trimmingCharacters(in: .whitespacesAndNewlines),
            fleetNumber: vehicleFleetNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            startingOdometerReading: odometerReading,
            ownershipType: vehicleOwnershipType
        )

        store.addVehicle(vehicle)
        store.activeVehicleID = vehicle.id
        clearVehicleDraft()
    }

    private func saveOnboardingDriver() {
        let normalizedDriverEmail = driverEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let driver = DriverProfile(
            name: driverName.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: driverDateOfBirth,
            licenceNumber: driverLicenceNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            licenceClass: driverLicenceClass.trimmingCharacters(in: .whitespacesAndNewlines),
            emailAddress: normalizedDriverEmail,
            phoneNumber: driverPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            permissions: []
        )

        store.addDriver(driver)
        store.activeDriverID = driver.id

        let resolvedOrganizationID = isBusinessAccount ? ensureBusinessOrganizationSetupIfNeeded() : nil
        if isBusinessAccount, isValidEmail(normalizedDriverEmail), let organizationID = resolvedOrganizationID {
            let membership = OrganizationMembership(
                organizationID: organizationID,
                emailAddress: normalizedDriverEmail,
                displayName: driver.name,
                role: .employee,
                status: .invited,
                assignedVehicleIDs: [],
                assignedDriverID: driver.id,
                permissions: driver.permissions,
                invitedAt: .now,
                activatedAt: nil,
                removedAt: nil
            )
            store.upsertOrganizationMembership(membership)
        }

        clearDriverDraft()
    }

    private func completeOnboarding() {
        store.hasAcceptedPrivacyPolicy = acceptsPrivacyPolicy
        store.hasAcceptedLegalNotice = acceptsLegalNotice
        store.hasCompletedOnboarding = true
        store.addLog("Onboarding completed")
    }

    private func declineLegalNotices() {
        store.hasAcceptedPrivacyPolicy = false
        store.hasAcceptedLegalNotice = false
        store.hasCompletedOnboarding = false
        authSession.signOut()
    }

    private func clearVehicleDraft() {
        vehicleProfileName = ""
        vehicleMake = ""
        vehicleModel = ""
        vehicleColor = ""
        vehicleNumberPlate = ""
        vehicleFleetNumber = ""
        vehicleStartingOdometer = ""
        vehicleOwnershipType = .personal
    }

    private func clearDriverDraft() {
        driverName = ""
        driverDateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
        driverLicenceNumber = ""
        driverLicenceClass = ""
        driverEmailAddress = ""
        driverPhoneNumber = ""
    }

    private func persistBusinessProfileIfNeeded() {
        guard isBusinessAccount else {
            store.businessProfile = nil
            return
        }

        store.businessProfile = BusinessAccountProfile(
            accountManagerName: store.userName.trimmingCharacters(in: .whitespacesAndNewlines),
            accountManagerEmail: store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            accountManagerPhone: businessAccountManagerPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            businessName: businessName.trimmingCharacters(in: .whitespacesAndNewlines),
            legalEntityName: businessLegalEntityName.trimmingCharacters(in: .whitespacesAndNewlines),
            taxRegistrationNumber: businessTaxRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            vatRegistrationNumber: businessVatRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            billingAddressLine1: businessBillingAddressLine1.trimmingCharacters(in: .whitespacesAndNewlines),
            billingAddressLine2: businessBillingAddressLine2.trimmingCharacters(in: .whitespacesAndNewlines),
            city: businessBillingCity.trimmingCharacters(in: .whitespacesAndNewlines),
            stateOrProvince: businessBillingStateOrProvince.trimmingCharacters(in: .whitespacesAndNewlines),
            postalCode: businessBillingPostalCode.trimmingCharacters(in: .whitespacesAndNewlines),
            country: businessBillingCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        _ = ensureBusinessOrganizationSetupIfNeeded()
    }

    @discardableResult
    private func ensureBusinessOrganizationSetupIfNeeded() -> UUID? {
        let hasBusinessAccess = SharedAppModel.shared.subscriptionManager.hasBusinessSubscription
            || store.isBusinessAccountActive
            || store.currentUserOrganizationMembership != nil
        guard isBusinessAccount, hasBusinessAccess else {
            return nil
        }

        let organizationName = businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(store.userName.trimmingCharacters(in: .whitespacesAndNewlines)) Organization"
            : businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedManagerEmail = resolvedOnboardingManagerEmailAddress()
        guard isValidEmail(normalizedManagerEmail) else {
            return nil
        }

        let organizationPlan = resolvedOrganizationPlan()
        let organizationBillingStatus: OrganizationBillingStatus = SharedAppModel.shared.subscriptionManager.hasBusinessSubscription ? .active : .pendingPayment
        var organization = store.currentOrganization
            ?? OrganizationProfile(name: organizationName, plan: organizationPlan, billingStatus: organizationBillingStatus, expiresAt: nil)
        organization.name = organizationName
        organization.plan = organizationPlan
        organization.billingStatus = organizationBillingStatus
        store.upsertOrganization(organization)
        store.activateOrganization(organization.id)

        if let existingManagerMembership = store.organizationMemberships.first(where: {
            $0.organizationID == organization.id && $0.normalizedEmailAddress == normalizedManagerEmail
        }) {
            var updatedMembership = existingManagerMembership
            updatedMembership.displayName = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedMembership.role = .accountManager
            updatedMembership.status = .active
            updatedMembership.permissions = []
            updatedMembership.activatedAt = .now
            updatedMembership.removedAt = nil
            store.upsertOrganizationMembership(updatedMembership)
        } else {
            let managerMembership = OrganizationMembership(
                organizationID: organization.id,
                emailAddress: normalizedManagerEmail,
                displayName: store.userName.trimmingCharacters(in: .whitespacesAndNewlines),
                role: .accountManager,
                status: .active,
                assignedVehicleIDs: [],
                assignedDriverID: nil,
                permissions: [],
                invitedAt: .now,
                activatedAt: .now,
                removedAt: nil
            )
            store.upsertOrganizationMembership(managerMembership)
        }

        return organization.id
    }

    private func resolvedOnboardingManagerEmailAddress() -> String {
        let storeEmail = store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isValidEmail(storeEmail) {
            return storeEmail
        }

        let signedInEmail = authSession.signedInEmailAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if isValidEmail(signedInEmail) {
            if store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.emailAddress = signedInEmail
            }
            return signedInEmail
        }

        let appleEmail = authSession.appleEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isValidEmail(appleEmail) {
            if store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.emailAddress = appleEmail
            }
            return appleEmail
        }

        return storeEmail
    }

    private func resolvedOrganizationPlan() -> OrganizationSubscriptionPlan {
        switch SharedAppModel.shared.subscriptionManager.activeTier {
        case .businessYearly:
            return .businessYearly
        case .businessMonthly, .personalMonthly, .personalYearly, nil:
            return .businessMonthly
        }
    }

    private func isValidEmail(_ emailAddress: String) -> Bool {
        let emailPattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func refreshNotificationAuthorizationLabel() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationLabel = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Allowed"
        case .notDetermined:
            "Not Set"
        case .denied:
            "Denied"
        @unknown default:
            "Unknown"
        }
    }

    private func permissionRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func legalSummaryBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func onboardingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18, content: content)
            .padding(22)
            .frame(maxWidth: 680, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func parseDecimalInput(_ value: String) -> Double? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let normalizedValue = trimmedValue.replacingOccurrences(of: ",", with: ".")
        return Double(normalizedValue)
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case account
    case preferences
    case tracking
    case permissions
    case vehicle
    case driver
    case legal

    var title: String {
        switch self {
        case .account:
            return "Account Setup"
        case .preferences:
            return "Preferences"
        case .tracking:
            return "Tracking Settings"
        case .permissions:
            return "Permissions"
        case .vehicle:
            return "Add Your First Vehicle"
        case .driver:
            return "Add Your First Driver"
        case .legal:
            return "Privacy & Legal"
        }
    }

    var subtitle: String {
        switch self {
        case .account:
            return "Choose your country and basic account details."
        case .preferences:
            return "Confirm how currency and measurements should appear throughout the app."
        case .tracking:
            return "Set the defaults the app will use when detecting and stopping trips."
        case .permissions:
            return "Grant the permissions needed for background trip recording and reminders."
        case .vehicle:
            return "Add a vehicle now or skip and do it later from Settings."
        case .driver:
            return "Add a driver now or skip and do it later from Settings."
        case .legal:
            return "Review and accept the required notices to continue into the app."
        }
    }
}

private struct SubscriptionGateView: View {
    @Bindable var subscriptionManager: SubscriptionManager
    @Bindable var authSession: AuthSessionManager
    @Bindable var cloudSync: CloudSyncManager
    @State private var appModel = SharedAppModel.shared
    @State private var isPresentingManageSubscriptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "car.circle.fill")
                            .font(.system(size: 68))
                            .foregroundStyle(.orange)
                        Text("Unlock Meerkat")
                            .font(.largeTitle.weight(.bold))
                        Text("Choose a subscription to unlock trip tracking, fuel logging, maintenance records, and exports.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account Type")
                            .font(.headline)
                        Picker("Account Type", selection: accountTypeBinding) {
                            ForEach(availableAccountTypes) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .frame(maxWidth: 420)

                    if subscriptionManager.hasLoadedStatus {
                        SubscriptionStoreView(productIDs: subscriptionManager.productIDs) {
                            VStack(spacing: 8) {
                                Text("Subscription Required")
                                    .font(.title2.weight(.semibold))
                                Text("Your subscription unlocks the full app and stays active across renewals.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal)
                        }
                        .subscriptionStoreButtonLabel(.multiline)
                        .frame(minHeight: 420)
                    } else {
                        ProgressView("Loading subscriptions...")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }

                    Text(subscriptionManager.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    SubscriptionReviewDisclosureView(subscriptionManager: subscriptionManager)

                    Button(subscriptionManager.isRefreshing ? "Restoring..." : "Restore Purchases") {
                        Task {
                            await subscriptionManager.restorePurchases()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(subscriptionManager.isRefreshing)

                    Button("View Demo Mode") {
                        appModel.enterDemoMode()
                    }
                    .buttonStyle(.bordered)

                    Button("Back to Login") {
                        authSession.returnToLoginScreen()
                    }
                    .buttonStyle(.bordered)

                    if subscriptionManager.hasActiveSubscription {
                        Button("Manage Subscription") {
                            isPresentingManageSubscriptions = true
                        }
                        .buttonStyle(.bordered)
                    }

                    if authSession.canUseCloudSyncFeatures {
                        Text("Cloud backup: \(cloudSync.statusMessage)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Button("Connect Apple Account for iCloud Backup") {
                            authSession.isPresentingLoginSheet = true
                        }
                        .buttonStyle(.bordered)

                        Text("Demo Mode is available with sample data and limited record creation for exploring the app before subscribing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let selectedAccountType = normalizedAccountType(SharedAppModel.shared.store.accountSubscriptionType)
                SharedAppModel.shared.store.accountSubscriptionType = selectedAccountType
                await subscriptionManager.setSelectedAccountType(selectedAccountType)
                await subscriptionManager.refreshSubscriptionStatus()
            }
        }
        .manageSubscriptionsSheet(isPresented: $isPresentingManageSubscriptions)
    }

    private var accountTypeBinding: Binding<AccountSubscriptionType> {
        Binding(
            get: { SharedAppModel.shared.store.accountSubscriptionType },
            set: { newType in
                let normalizedType = normalizedAccountType(newType)
                SharedAppModel.shared.store.accountSubscriptionType = normalizedType
                Task {
                    await subscriptionManager.setSelectedAccountType(normalizedType)
                    await subscriptionManager.refreshSubscriptionStatus()
                }
            }
        )
    }

    private var availableAccountTypes: [AccountSubscriptionType] {
        if AppFeatureFlags.businessSubscriptionsEnabled {
            return AccountSubscriptionType.allCases
        }

        return AccountSubscriptionType.allCases.filter { $0 != .business }
    }

    private func normalizedAccountType(_ type: AccountSubscriptionType) -> AccountSubscriptionType {
        guard !AppFeatureFlags.businessSubscriptionsEnabled, type == .business else {
            return type
        }

        return .personal
    }
}

private struct SubscriptionReviewDisclosureView: View {
    @Bindable var subscriptionManager: SubscriptionManager

    private let standardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subscription Details")
                .font(.headline)

            LabeledContent("Service", value: subscriptionManager.subscriptionDisplayName)
            LabeledContent("Length", value: subscriptionManager.subscriptionPeriodDescription)
            LabeledContent("Price", value: subscriptionManager.subscriptionPriceDescription)

            Text(subscriptionManager.subscriptionServiceDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            NavigationLink("Open Privacy Policy") {
                SettingsPrivacyLegalView()
            }
            .font(.footnote.weight(.semibold))

            Link("Open Terms of Use (Apple Standard EULA)", destination: standardEULAURL)
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct UnlockView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var authSession: AuthSessionManager
    @State private var hasAttemptedAutomaticUnlock = false
    @State private var isAutoUnlockInProgress = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Unlock Meerkat")
                .font(.largeTitle.weight(.bold))

            Text("Use \(authSession.biometricLabel) to access your stored mileage data.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Unlock with \(authSession.biometricLabel)") {
                Task {
                    await performAutomaticUnlockIfNeeded(force: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isAutoUnlockInProgress)

            Button("Sign Out") {
                authSession.signOut()
            }
            .buttonStyle(.bordered)

            Button("Back to Login") {
                authSession.returnToLoginScreen()
            }
            .buttonStyle(.bordered)

            if let errorMessage = authSession.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            resetAutomaticUnlockState()
            triggerAutomaticUnlockIfNeeded()
        }
        .onChange(of: scenePhase, initial: false) { _, newPhase in
            guard newPhase == .active else {
                resetAutomaticUnlockState()
                return
            }

            triggerAutomaticUnlockIfNeeded(force: true)
        }
        .onDisappear {
            resetAutomaticUnlockState()
        }
    }

    private func triggerAutomaticUnlockIfNeeded(force: Bool = false) {
        guard scenePhase == .active else {
            return
        }

        Task {
            await performAutomaticUnlockIfNeeded(force: force)
        }
    }

    private func resetAutomaticUnlockState() {
        hasAttemptedAutomaticUnlock = false
        isAutoUnlockInProgress = false
    }

    private func performAutomaticUnlockIfNeeded(force: Bool = false) async {
        guard authSession.accessState == .locked else {
            return
        }

        guard !isAutoUnlockInProgress else {
            return
        }

        guard force || !hasAttemptedAutomaticUnlock else {
            return
        }

        hasAttemptedAutomaticUnlock = true
        isAutoUnlockInProgress = true
        defer {
            isAutoUnlockInProgress = false
        }

        await authSession.unlock()
    }
}

private struct TripsView: View {
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker
    @Bindable var cloudSync: CloudSyncManager
    @State private var isPresentingOdometerEditor = false
    @State private var isPresentingManualTripEntry = false
    @State private var editedOdometerReading = ""
    @State private var odometerAdjustment = 0.0
    @State private var isApplyingEditedOdometerReading = false

    var body: some View {
        GeometryReader { geometry in
            if usesSplitLayout(for: geometry.size) {
                splitLayout(in: geometry.size)
            } else {
                stackedLayout
            }
        }
        .onChange(of: tripTracker.isTracking, initial: false) { _, isTracking in
            if isTracking {
                odometerAdjustment = 0
                tripTracker.setTripStartOdometerReadingIfNeeded(store.currentBaseOdometerReading())
            } else {
                odometerAdjustment = 0
            }
        }
        .sheet(isPresented: $isPresentingOdometerEditor) {
            NavigationStack {
                Form {
                    Section("Current Odometer") {
                        TextField("Odometer", text: $editedOdometerReading)
                            .keyboardType(.numberPad)
                        Text("Use this to align the trip with the vehicle's actual odometer when GPS distance drifts. Applying this value ends the current trip with the entered odometer reading.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Edit Odometer")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresentingOdometerEditor = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            Task {
                                await applyEditedOdometerReading()
                            }
                        }
                        .disabled(!canApplyEditedOdometerReading || isApplyingEditedOdometerReading)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isPresentingManualTripEntry) {
            NavigationStack {
                ManualTripEntryView(store: store, defaultTripType: tripTracker.selectedTripType)
            }
        }
    }

    private var stackedLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                activeTripCard
                recentTripsSection
            }
            .padding()
            .padding(.bottom, 110)
        }
    }

    private func splitLayout(in size: CGSize) -> some View {
        let padding = horizontalPadding(for: size)
        let spacing = splitSpacing(for: size)
        let availableWidth = max(size.width - (padding * 2) - spacing, 0)
        let dashboardWidth = min(max(availableWidth * 0.42, 340), 520)
        let tripsWidth = max(availableWidth - dashboardWidth, 360)

        return HStack(alignment: .top, spacing: spacing) {
            ScrollView {
                activeTripCard
                    .frame(width: dashboardWidth)
                    .padding(.vertical, 20)
                    .padding(.leading, padding)
                    .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            ScrollView {
                recentTripsSection
                    .frame(width: tripsWidth, alignment: .leading)
                    .padding(.vertical, 20)
                    .padding(.trailing, padding)
                    .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var activeTripCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(dashboardTitle, systemImage: "location.fill")
                    .font(.headline)
                Spacer()
            }

            tripTypePicker
            dashboardView

            Text(dashboardStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var tripTypePicker: some View {
        HStack(spacing: 10) {
            ForEach(TripType.allCases) { tripType in
                Button {
                    Task {
                        if let completedTrip = await tripTracker.selectTripType(
                            tripType,
                            nextTripStartOdometerReading: dashboardOdometerReading,
                            completedTripEndOdometerReading: dashboardOdometerReading
                        ) {
                            store.addTrip(completedTrip)
                            store.addLog("Trip type changed to \(tripType.title); started a new trip")
                            odometerAdjustment = 0
                        }
                    }
                } label: {
                    Label(tripType.title, systemImage: tripType.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(store.isDemoModeEnabled && !store.canAddMoreTrips && !tripTracker.isTracking)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tripTracker.selectedTripType == tripType ? .white.opacity(0.22) : .white.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(tripTracker.selectedTripType == tripType ? 0.35 : 0.12), lineWidth: 1)
                }
            }
        }
        .opacity(store.isReadyToDrive ? 1 : 0.65)
    }

    private var dashboardView: some View {
        VStack(alignment: .leading, spacing: 14) {
            dashboardMeta

            Text("Odometer")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 10) {
                Button {
                    presentOdometerEditor()
                } label: {
                    VStack(spacing: 10) {
                        FlipOdometerView(value: dashboardOdometerReading)
                        Text(store.unitSystem == .miles ? "MI" : "KM")
                            .font(.title3.weight(.black))
                        if tripTracker.isTracking {
                            Text("Tap to adjust")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(!tripTracker.isTracking)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                statPill(title: "Distance", value: store.unitSystem.distanceString(for: tripTracker.currentTripDistance))
                statPill(title: "Elapsed", value: tripTracker.elapsedTimeString)
            }

            if store.isDemoModeEnabled {
                Text("Demo limit: up to \(MileageStore.demoTripLimit) trips. Existing demo trips can't be deleted.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
    }

    private var gpsOdometerReading: Double {
        store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
    }

    private var dashboardOdometerReading: Double {
        gpsOdometerReading + odometerAdjustment
    }

    private var canApplyEditedOdometerReading: Bool {
        guard let reading = parseEditedOdometerReading() else {
            return false
        }

        return reading >= store.currentBaseOdometerReading()
    }

    private var dashboardMeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            metaRow(title: "Vehicle", value: store.activeVehicle?.displayName ?? "Not selected")
            metaRow(title: "Driver", value: store.activeDriver?.name ?? "Not selected")
        }
    }

    private var recentTripsSection: some View {
        let filteredTrips = store.tripsForActiveVehicle()
        let tripGroups = filteredTrips.groupedByMonth(using: \.date)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Trips")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    isPresentingManualTripEntry = true
                } label: {
                    Label("Add Manually", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!store.isReadyToDrive)
            }

            if tripGroups.isEmpty {
                Text(store.activeVehicle == nil ? "Select a vehicle to view trips." : "No trips added yet for this vehicle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(tripGroups) { group in
                    MonthlyDisclosureSection(group: group) { trip in
                        NavigationLink {
                            TripDetailView(store: store, tripID: trip.id)
                        } label: {
                            tripRow(trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !store.isReadyToDrive {
                Text("Select a vehicle and driver before adding a manual trip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func tripRow(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trip.name)
                    .font(.headline)
                if trip.manuallyEntered {
                    Text("Manual")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if trip.requiresBusinessDetailsAttention {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                if shouldShowPendingBadge(for: trip) {
                    pendingCloudSyncBadge
                } else if shouldShowUploadedBadge(for: trip) {
                    uploadedToCloudBadge
                }
                Spacer()
                Text(distanceText(for: trip))
                    .font(.subheadline.weight(.semibold))
            }

            HStack {
                Label(trip.type.title, systemImage: trip.type.systemImage)
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            HStack {
                Label(trip.driverName, systemImage: "person.fill")
                Spacer()
                Text(trip.vehicleProfileName)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

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

    private func distanceText(for trip: Trip) -> String {
        let fallbackMeters = store.unitSystem.meters(forDisplayedDistance: max(trip.odometerEnd - trip.odometerStart, 0))
        let displayDistance = trip.distanceMeters > 0 ? trip.distanceMeters : fallbackMeters
        return store.unitSystem.distanceString(for: displayDistance)
    }

    private func shouldShowUploadedBadge(for trip: Trip) -> Bool {
        cloudSync.uploadedTripIDs.contains(trip.id)
    }

    private func shouldShowPendingBadge(for trip: Trip) -> Bool {
        cloudSync.pendingTripIDs.contains(trip.id)
    }

    private var uploadedToCloudBadge: some View {
        Image(systemName: "checkmark.icloud.fill")
            .font(.caption2)
            .foregroundStyle(.green)
            .accessibilityLabel("Uploaded to Firebase")
    }

    private var pendingCloudSyncBadge: some View {
        Image(systemName: "icloud.and.arrow.up.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
            .accessibilityLabel("Pending Firebase upload")
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

    private func metaRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private var dashboardTitle: String {
        if !store.isReadyToDrive {
            return "Not ready to drive"
        }

        if tripTracker.isTracking {
            return "Trip in progress"
        }

        return tripTracker.hasLiveSpeedReading ? "Vehicle moving" : "Ready to drive"
    }

    private var dashboardStatusMessage: String {
        if !store.isReadyToDrive {
            return "Add a vehicle and driver, or select a vehicle and driver, before starting a trip."
        }

        return tripTracker.statusMessage
    }

    private func presentOdometerEditor() {
        guard tripTracker.isTracking else {
            return
        }

        editedOdometerReading = String(Int(dashboardOdometerReading.rounded()))
        isPresentingOdometerEditor = true
    }

    private func applyEditedOdometerReading() async {
        guard let reading = parseEditedOdometerReading(), tripTracker.isTracking else {
            return
        }

        isApplyingEditedOdometerReading = true
        defer {
            isApplyingEditedOdometerReading = false
        }

        if let trip = await tripTracker.stopTracking(endOdometerReading: reading) {
            store.addTrip(trip)
        }

        odometerAdjustment = 0
        isPresentingOdometerEditor = false
    }

    private func parseEditedOdometerReading() -> Double? {
        let trimmedValue = editedOdometerReading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let digitsOnly = trimmedValue.filter(\.isNumber)
        guard !digitsOnly.isEmpty else {
            return nil
        }

        return Double(digitsOnly)
    }

    private func usesSplitLayout(for size: CGSize) -> Bool {
        size.width > size.height && size.width >= 700
    }

    private func horizontalPadding(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.03, 20), 32)
    }

    private func splitSpacing(for size: CGSize) -> CGFloat {
        min(max(size.width * 0.02, 16), 28)
    }
}

private struct GlobalTripRecorderButton: View {
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker
    @State private var buttonCenter: CGPoint?
    @State private var dragOffset: CGSize = .zero
    @State private var countdownValue: Int?
    @State private var countdownTask: Task<Void, Never>?

    private let buttonSize = CGSize(width: 154, height: 64)

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .allowsHitTesting(false)
                .overlay {
                    recorderButton(in: geometry)
                }
                .onAppear {
                    guard buttonCenter == nil else {
                        return
                    }
                    buttonCenter = defaultButtonCenter(in: geometry.size, safeAreaInsets: geometry.safeAreaInsets)
                }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func recorderButton(in geometry: GeometryProxy) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 38, height: 38)

                Image(systemName: countdownValue == nil ? (tripTracker.isTracking ? "stop.fill" : "play.fill") : "hourglass")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let countdownValue {
                    Text(tripTracker.isTracking ? "ENDING TRIP IN" : "STARTING TRIP IN")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)

                    Text("\(countdownValue)")
                        .font(.title3.weight(.black))
                        .monospacedDigit()
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tripTracker.isTracking ? .red : (tripTracker.hasLiveSpeedReading ? .orange : .green))
                            .frame(width: 8, height: 8)

                        Text(tripTracker.isTracking ? "REC" : (tripTracker.hasLiveSpeedReading ? "MOVING" : "READY"))
                            .font(.caption2.weight(.bold))
                            .textCase(.uppercase)
                    }

                    Text(store.unitSystem.speedString(for: tripTracker.currentSpeed))
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: countdownValue == nil
                            ? (tripTracker.isTracking
                                ? [Color.red.opacity(0.95), Color.orange.opacity(0.85)]
                                : [Color.green.opacity(0.95), Color.teal.opacity(0.85)])
                            : [Color.orange.opacity(0.98), Color.red.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.2), radius: 16, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onLongPressGesture(
            minimumDuration: 0.45,
            maximumDistance: 12,
            pressing: { isPressing in
                if !isPressing {
                    cancelCountdown()
                }
            }
        ) {
            beginCountdown()
        }
        .disabled((!store.isReadyToDrive && !tripTracker.isTracking) || (store.isDemoModeEnabled && !store.canAddMoreTrips && !tripTracker.isTracking))
        .opacity(((!store.isReadyToDrive && !tripTracker.isTracking) || (store.isDemoModeEnabled && !store.canAddMoreTrips && !tripTracker.isTracking)) ? 0.72 : 1)
        .position(resolvedButtonCenter(in: geometry.size, safeAreaInsets: geometry.safeAreaInsets))
        .offset(dragOffset)
        .onChange(of: tripTracker.isTracking) { _, _ in
            cancelCountdown()
        }
        .onDisappear {
            cancelCountdown()
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    cancelCountdown()
                    dragOffset = value.translation
                }
                .onEnded { value in
                    let currentCenter = resolvedButtonCenter(in: geometry.size, safeAreaInsets: geometry.safeAreaInsets)
                    buttonCenter = clampedButtonCenter(
                        CGPoint(
                            x: currentCenter.x + value.translation.width,
                            y: currentCenter.y + value.translation.height
                        ),
                        in: geometry.size,
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    dragOffset = .zero
                }
        )
    }

    private func beginCountdown() {
        guard countdownTask == nil else {
            return
        }

        countdownTask = Task { @MainActor in
            for value in stride(from: 3, through: 1, by: -1) {
                countdownValue = value

                if value > 1 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }

                if Task.isCancelled {
                    countdownValue = nil
                    countdownTask = nil
                    return
                }
            }

            countdownValue = nil
            countdownTask = nil
            await toggleTracking()
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = nil
    }

    private func startTracking() {
        guard store.isReadyToDrive else {
            store.addLog("Trip start blocked: vehicle or driver not selected")
            return
        }

        guard store.canAddMoreTrips else {
            store.addLog("Demo mode trip limit reached")
            return
        }

        switch tripTracker.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            tripTracker.startTracking(startOdometerReading: store.currentBaseOdometerReading())
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

    private func toggleTracking() async {
        if tripTracker.isTracking {
            let endOdometerReading = store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
            if let trip = await tripTracker.stopTracking(endOdometerReading: endOdometerReading) {
                store.addTrip(trip)
            }
        } else {
            startTracking()
        }
    }

    private func resolvedButtonCenter(in size: CGSize, safeAreaInsets: EdgeInsets) -> CGPoint {
        clampedButtonCenter(
            buttonCenter ?? defaultButtonCenter(in: size, safeAreaInsets: safeAreaInsets),
            in: size,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func defaultButtonCenter(in size: CGSize, safeAreaInsets: EdgeInsets) -> CGPoint {
        clampedButtonCenter(
            CGPoint(
                x: size.width - 96,
                y: size.height - safeAreaInsets.bottom - 98
            ),
            in: size,
            safeAreaInsets: safeAreaInsets
        )
    }

    private func clampedButtonCenter(_ center: CGPoint, in size: CGSize, safeAreaInsets: EdgeInsets) -> CGPoint {
        let horizontalInset = (buttonSize.width / 2) + 16
        let topInset = safeAreaInsets.top + (buttonSize.height / 2) + 16
        let bottomInset = safeAreaInsets.bottom + (buttonSize.height / 2) + 84

        return CGPoint(
            x: min(max(center.x, horizontalInset), size.width - horizontalInset),
            y: min(max(center.y, topInset), size.height - bottomInset)
        )
    }
}

@MainActor
@Observable
private final class PlaceAutocompleteModel: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Hashable {
        let completion: MKLocalSearchCompletion

        var id: String {
            "\(completion.title)|\(completion.subtitle)"
        }

        var displayText: String {
            completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle)"
        }
    }

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    var suggestions: [Suggestion] = []

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 3 else {
            suggestions = []
            completer.queryFragment = ""
            return
        }

        completer.queryFragment = trimmedQuery
    }

    func clear() {
        suggestions = []
        completer.queryFragment = ""
    }

    func resolve(_ suggestion: Suggestion) async -> String {
        let request = MKLocalSearch.Request(completion: suggestion.completion)

        do {
            let response = try await MKLocalSearch(request: request).start()
            if let mapItem = response.mapItems.first,
               let formattedAddress = mapItem.autocompleteDisplayAddress {
                clear()
                return formattedAddress
            }
        } catch {
            clear()
            return suggestion.displayText
        }

        clear()
        return suggestion.displayText
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let newSuggestions = completer.results.prefix(5).map(Suggestion.init)
        Task { @MainActor in
            suggestions = Array(newSuggestions)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            suggestions = []
        }
    }
}

private struct PlaceAutocompleteField: View {
    let prompt: String
    @Binding var text: String
    var axis: Axis = .vertical

    @State private var autocomplete = PlaceAutocompleteModel()
    @State private var suppressNextQueryUpdate = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(prompt, text: $text, axis: axis)
                .focused($isFocused)
                .onChange(of: text) { _, newValue in
                    if suppressNextQueryUpdate {
                        suppressNextQueryUpdate = false
                        return
                    }

                    guard isFocused else {
                        autocomplete.clear()
                        return
                    }

                    autocomplete.updateQuery(newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        autocomplete.clear()
                    }
                }

            if isFocused && !autocomplete.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(autocomplete.suggestions) { suggestion in
                        Button {
                            Task {
                                let resolvedAddress = await autocomplete.resolve(suggestion)
                                suppressNextQueryUpdate = true
                                text = resolvedAddress
                                isFocused = false
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.completion.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !suggestion.completion.subtitle.isEmpty {
                                    Text(suggestion.completion.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if suggestion.id != autocomplete.suggestions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator).opacity(0.25), lineWidth: 1)
                )
            }
        }
    }
}

private extension MKMapItem {
    var autocompleteDisplayAddress: String? {
        if let fullAddress = addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return fullAddress
        }

        if let fullAddress = address?.fullAddress.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullAddress.isEmpty {
            return fullAddress
        }

        let parts = [
            name,
            address?.shortAddress,
            addressRepresentations?.cityWithContext(.full),
            addressRepresentations?.regionName
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            return nil
        }

        return parts.joined(separator: ", ")
    }
}

private struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MileageStore
    let tripID: UUID

    @State private var tripName = ""
    @State private var tripType: TripType = .personal
    @State private var selectedVehicleID: UUID?
    @State private var selectedDriverID: UUID?
    @State private var startAddress = ""
    @State private var endAddress = ""
    @State private var tripDetails = ""
    @State private var odometerStart = ""
    @State private var odometerEnd = ""
    @State private var hasLoaded = false
    @State private var showOdometerWarning = false
    @State private var odometerNumberFormatter = NumberFormatter.tripEditorOdometer
    @State private var tripMapCameraPosition: MapCameraPosition = .automatic
    @State private var startMapItem: MKMapItem?
    @State private var endMapItem: MKMapItem?
    @State private var fallbackTripRoute: MKRoute?
    @State private var isLoadingMap = false
    @State private var mapErrorMessage: String?
    @State private var showDeleteConfirmation = false

    private var trip: Trip? {
        store.trip(for: tripID)
    }

    var body: some View {
        Group {
            if let trip {
                Form {
                    Section("Trip Map") {
                        tripMapSection
                    }

                    Section("Summary") {
                        LabeledContent("Trip type", value: tripType.title)
                        LabeledContent("Source", value: trip.manuallyEntered ? "Manually entered" : "Recorded with GPS")
                        LabeledContent("Distance", value: computedDistanceText)
                        LabeledContent("Time", value: trip.duration.formattedDuration)
                        LabeledContent("Vehicle", value: vehicleName(for: selectedVehicleID))
                        LabeledContent("Driver", value: driverName(for: selectedDriverID))
                        LabeledContent("Driver details", value: trip.driverDetailsSummary)
                    }

                    Section("Trip") {
                        TextField("Trip name", text: $tripName)
                        Picker("Type", selection: $tripType) {
                            ForEach(TripType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                        Picker("Vehicle", selection: $selectedVehicleID) {
                            ForEach(store.availableVehicles) { vehicle in
                                Text(vehicle.displayName).tag(Optional(vehicle.id))
                            }
                        }
                        Picker("Driver", selection: $selectedDriverID) {
                            ForEach(store.availableDrivers) { driver in
                                Text(driver.name).tag(Optional(driver.id))
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trip Reason")
                                .font(.headline)
                            TextField(
                                tripType == .business ? "Client visit, site inspection, delivery..." : "Why did you take this trip?",
                                text: $tripDetails,
                                axis: .vertical
                            )
                            .lineLimit(3...5)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )

                            Text(tripType == .business ? "Describe the business purpose clearly for your records." : "Add context to make this trip easier to recognize later.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start Address")
                                .font(.headline)
                            PlaceAutocompleteField(prompt: "Start address", text: $startAddress)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("End Address")
                                .font(.headline)
                            PlaceAutocompleteField(prompt: "End address", text: $endAddress)
                        }
                    }

                    Section("Odometer") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start odometer reading")
                                .font(.headline)
                            TextField("Enter the trip start reading", text: $odometerStart)
                                .keyboardType(.decimalPad)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("End odometer reading")
                                .font(.headline)
                            TextField("Enter the trip end reading", text: $odometerEnd)
                                .keyboardType(.decimalPad)
                        }
                        Text("Changing odometer values updates adjacent trips for this vehicle so there are no gaps.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if tripType == .business && tripDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Section {
                            Label("Business trips should include trip details such as a customer visit.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("Trip Details")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Delete", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(!store.canModifyDemoData || !store.canCurrentUserDeleteTrips)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Save") {
                            saveTapped()
                        }
                        .disabled(!canSave)
                    }
                }
                .onAppear {
                    load(from: trip)
                }
                .onChange(of: trip.id, initial: false) { _, _ in
                    load(from: trip)
                }
                .task(id: mapTaskID) {
                    await loadTripMap()
                }
                .alert("Save Odometer Changes?", isPresented: $showOdometerWarning) {
                    Button("Discard", role: .destructive) {
                        load(from: trip, force: true)
                    }
                    Button("Save") {
                        commitChanges()
                    }
                } message: {
                    Text("The odometer reading of previous or next trips will change so there are no gaps between trips.")
                }
                .alert("Delete Trip?", isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        deleteTrip()
                    }
                } message: {
                    Text("This trip will be removed from your recent trips.")
                }
            } else {
                ContentUnavailableView("Trip Not Found", systemImage: "car")
            }
        }
    }

    @ViewBuilder
    private var tripMapSection: some View {
        if let trip, shouldShowRecordedRoute(for: trip) {
            let coordinates = trip.routePoints.map(\.coordinate)

            VStack(alignment: .leading, spacing: 12) {
                Map(position: $tripMapCameraPosition, interactionModes: []) {
                    if let startCoordinate = coordinates.first {
                        Marker("Start", coordinate: startCoordinate)
                            .tint(.green)
                    }

                    if let endCoordinate = coordinates.last {
                        Marker("End", coordinate: endCoordinate)
                            .tint(.red)
                    }

                    if coordinates.count >= 2 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.orange, lineWidth: 5)
                    }
                }
                .id("recorded-\(mapTaskID)")
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text("Showing the recorded route captured during this trip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if let startMapItem, let endMapItem {
            VStack(alignment: .leading, spacing: 12) {
                Map(position: $tripMapCameraPosition, interactionModes: []) {
                    Marker("Start", coordinate: startMapItem.location.coordinate)
                        .tint(.green)

                    Marker("End", coordinate: endMapItem.location.coordinate)
                        .tint(.red)

                    if let fallbackTripRoute {
                        MapPolyline(fallbackTripRoute)
                            .stroke(.orange, lineWidth: 5)
                    } else {
                        MapPolyline(
                            coordinates: [
                                startMapItem.location.coordinate,
                                endMapItem.location.coordinate
                            ]
                        )
                        .stroke(.orange.opacity(0.8), style: StrokeStyle(lineWidth: 4, dash: [8, 6]))
                    }
                }
                .id("resolved-\(mapTaskID)")
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(fallbackTripRoute == nil ? "This older trip does not include a recorded route, so the map is showing a direct line between the saved start and end points." : "This older trip does not include a recorded breadcrumb, so the map is showing the most likely route between the saved start and end points.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if isLoadingMap {
            HStack(spacing: 12) {
                ProgressView()
                Text("Loading trip map…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let mapErrorMessage {
            ContentUnavailableView("Map Unavailable", systemImage: "map", description: Text(mapErrorMessage))
        } else {
            ContentUnavailableView("Map Unavailable", systemImage: "map", description: Text("Add recognizable start and end addresses to preview this trip on the map."))
        }
    }

    private var canSave: Bool {
        parsedStartOdometer != nil && parsedEndOdometer != nil && (parsedEndOdometer ?? 0) >= (parsedStartOdometer ?? 0)
    }

    private var parsedStartOdometer: Double? {
        parseOdometer(odometerStart)
    }

    private var parsedEndOdometer: Double? {
        parseOdometer(odometerEnd)
    }

    private var computedDistanceText: String {
        if let start = parsedStartOdometer, let end = parsedEndOdometer {
            return store.unitSystem.distanceString(for: store.unitSystem.meters(forDisplayedDistance: max(end - start, 0)))
        }

        guard let trip else {
            return store.unitSystem.distanceString(for: 0)
        }

        let fallbackMeters = store.unitSystem.meters(forDisplayedDistance: max(trip.odometerEnd - trip.odometerStart, 0))
        let displayDistance = trip.distanceMeters > 0 ? trip.distanceMeters : fallbackMeters
        return store.unitSystem.distanceString(for: displayDistance)
    }

    private func saveTapped() {
        guard canSave else {
            return
        }

        if hasOdometerChanges {
            showOdometerWarning = true
        } else {
            commitChanges()
        }
    }

    private var hasOdometerChanges: Bool {
        guard let trip, let start = parsedStartOdometer, let end = parsedEndOdometer else {
            return false
        }

        return start != trip.odometerStart || end != trip.odometerEnd
    }

    private func commitChanges() {
        guard
            let trip,
            let start = parsedStartOdometer,
            let end = parsedEndOdometer
        else {
            return
        }

        let updatedTrip = Trip(
            id: trip.id,
            name: tripName,
            type: tripType,
            vehicleID: selectedVehicleID,
            vehicleProfileName: vehicleName(for: selectedVehicleID),
            driverID: selectedDriverID,
            driverName: driverName(for: selectedDriverID),
            driverDateOfBirth: store.driver(for: selectedDriverID)?.dateOfBirth ?? trip.driverDateOfBirth,
            driverLicenceNumber: store.driver(for: selectedDriverID)?.licenceNumber ?? trip.driverLicenceNumber,
            startAddress: startAddress,
            endAddress: endAddress,
            details: tripDetails,
            odometerStart: start,
            odometerEnd: end,
            distanceMeters: store.unitSystem.meters(forDisplayedDistance: max(end - start, 0)),
            duration: trip.duration,
            date: trip.date,
            routePoints: trip.routePoints,
            manuallyEntered: trip.manuallyEntered
        )

        store.updateTrip(updatedTrip)
        dismiss()
    }

    private func deleteTrip() {
        store.deleteTrip(id: tripID)
        dismiss()
    }

    private func load(from trip: Trip, force: Bool = false) {
        guard !hasLoaded || force else {
            return
        }

        tripName = trip.name
        tripType = trip.type
        selectedVehicleID = trip.vehicleID
        selectedDriverID = trip.driverID
        startAddress = trip.effectiveStartAddress
        endAddress = trip.effectiveEndAddress
        tripDetails = trip.details
        odometerStart = formatOdometer(trip.odometerStart)
        odometerEnd = formatOdometer(trip.odometerEnd)
        hasLoaded = true
    }

    private var mapTaskID: String {
        if let trip {
            return "\(trip.id.uuidString)|\(trip.routePoints.count)|\(trip.effectiveStartAddress)|\(trip.effectiveEndAddress)|\(startAddress)|\(endAddress)"
        }

        return "\(startAddress)|\(endAddress)"
    }

    private func loadTripMap() async {
        if let trip, shouldShowRecordedRoute(for: trip) {
            startMapItem = nil
            endMapItem = nil
            fallbackTripRoute = nil
            mapErrorMessage = nil
            isLoadingMap = false
            tripMapCameraPosition = .rect(mapRectCovering(trip.routePoints.map(\.coordinate)))
            return
        }

        let trimmedStartAddress = startAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndAddress = endAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedStartAddress.isEmpty, !trimmedEndAddress.isEmpty else {
            startMapItem = nil
            endMapItem = nil
            fallbackTripRoute = nil
            mapErrorMessage = nil
            tripMapCameraPosition = .automatic
            return
        }

        startMapItem = nil
        endMapItem = nil
        fallbackTripRoute = nil
        tripMapCameraPosition = .automatic
        isLoadingMap = true
        mapErrorMessage = nil

        do {
            async let startItem = geocodeMapItem(for: trimmedStartAddress)
            async let endItem = geocodeMapItem(for: trimmedEndAddress)

            let resolvedStartItem = try await startItem
            let resolvedEndItem = try await endItem

            startMapItem = resolvedStartItem
            endMapItem = resolvedEndItem
            do {
                let route = try await calculateRoute(from: resolvedStartItem, to: resolvedEndItem)
                fallbackTripRoute = route
                tripMapCameraPosition = .rect(route.polyline.boundingMapRect.insetBy(dx: -1_500, dy: -1_500))
            } catch {
                fallbackTripRoute = nil
                tripMapCameraPosition = .rect(mapRectCovering(resolvedStartItem.location.coordinate, resolvedEndItem.location.coordinate))
            }
        } catch {
            startMapItem = nil
            endMapItem = nil
            fallbackTripRoute = nil
            tripMapCameraPosition = .automatic
            mapErrorMessage = "The app couldn't resolve one or both saved addresses."
        }

        isLoadingMap = false
    }

    private func shouldShowRecordedRoute(for trip: Trip) -> Bool {
        guard !trip.routePoints.isEmpty else {
            return false
        }

        let savedStartAddress = trip.effectiveStartAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedEndAddress = trip.effectiveEndAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let editedStartAddress = startAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let editedEndAddress = endAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        return savedStartAddress == editedStartAddress && savedEndAddress == editedEndAddress
    }

    private func parseOdometer(_ value: String) -> Double? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let number = odometerNumberFormatter.number(from: trimmedValue) {
            return number.doubleValue
        }

        let normalizedValue = trimmedValue.replacingOccurrences(of: ",", with: "")
        return Double(normalizedValue)
    }

    private func formatOdometer(_ value: Double) -> String {
        odometerNumberFormatter.string(from: NSNumber(value: value))
            ?? value.formatted(.number.precision(.fractionLength(1)))
    }

    private func geocodeMapItem(for address: String) async throws -> MKMapItem {
        guard let request = MKGeocodingRequest(addressString: address) else {
            throw CocoaError(.coderInvalidValue)
        }

        guard let mapItem = try await request.mapItems.first else {
            throw MKError(.placemarkNotFound)
        }

        return mapItem
    }

    private func calculateRoute(from start: MKMapItem, to end: MKMapItem) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = start
        request.destination = end
        request.transportType = .automobile

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else {
            throw MKError(.directionsNotFound)
        }

        return route
    }

    private func mapRectCovering(_ start: CLLocationCoordinate2D, _ end: CLLocationCoordinate2D) -> MKMapRect {
        let startPoint = MKMapPoint(start)
        let endPoint = MKMapPoint(end)
        let points = [startPoint, endPoint]
        let rect = points.reduce(MKMapRect.null) { partialResult, point in
            partialResult.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }

        return rect.isNull ? MKMapRect.world : rect.insetBy(dx: -1_500, dy: -1_500)
    }

    private func mapRectCovering(_ coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let points = coordinates.map(MKMapPoint.init)
        let rect = points.reduce(MKMapRect.null) { partialResult, point in
            partialResult.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }

        return rect.isNull ? MKMapRect.world : rect.insetBy(dx: -1_500, dy: -1_500)
    }

    private func vehicleName(for id: UUID?) -> String {
        store.vehicle(for: id)?.displayName ?? "Not selected"
    }

    private func driverName(for id: UUID?) -> String {
        store.driver(for: id)?.name ?? "Not selected"
    }
}

private struct ManualTripEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MileageStore
    let defaultTripType: TripType

    @State private var tripName = ""
    @State private var tripType: TripType = .business
    @State private var startAddress = ""
    @State private var endAddress = ""
    @State private var tripDetails = ""
    @State private var endOdometer = ""
    @State private var startOdometer = ""

    var body: some View {
        Form {
            Section("Trip") {
                TextField("Trip name", text: $tripName)
                Picker("Type", selection: $tripType) {
                    ForEach(TripType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                TextField(
                    tripType == .business ? "Client visit, site inspection, delivery..." : "Why did you take this trip?",
                    text: $tripDetails,
                    axis: .vertical
                )
                .lineLimit(3...5)
            }

            Section("Route") {
                LabeledContent("Start odometer", value: startOdometer)
                Text("The current vehicle odometer is used as the starting point for this manual trip.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("End odometer", text: $endOdometer)
                    .keyboardType(.decimalPad)

                Text("You can enter an end odometer above the current reading. The newest trip's end odometer becomes the vehicle's current odometer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Start Address")
                        .font(.headline)
                    PlaceAutocompleteField(prompt: "Start address", text: $startAddress)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("End Address")
                        .font(.headline)
                    PlaceAutocompleteField(prompt: "End address", text: $endAddress)
                }
            }

            Section {
                Text("Manual trips are marked in your records so they are easy to distinguish from GPS-recorded trips.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add Manual Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveTrip()
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            tripName = "Manual Trip \(Date.now.formatted(date: .abbreviated, time: .shortened))"
            let currentOdometer = store.currentBaseOdometerReading()
            startOdometer = currentOdometer.formatted(.number.precision(.fractionLength(1)))
            endOdometer = currentOdometer.formatted(.number.precision(.fractionLength(1)))
            tripType = defaultTripType
        }
    }

    private var parsedStartOdometer: Double? {
        Double(startOdometer.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ""))
    }

    private var parsedEndOdometer: Double? {
        Double(endOdometer.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        guard
            store.isReadyToDrive,
            store.canAddMoreTrips,
            let start = parsedStartOdometer,
            let end = parsedEndOdometer
        else {
            return false
        }

        return !tripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !startAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !endAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            end >= start
    }

    private func saveTrip() {
        guard let start = parsedStartOdometer, let end = parsedEndOdometer else {
            return
        }

        let trip = Trip(
            name: tripName.trimmingCharacters(in: .whitespacesAndNewlines),
            type: tripType,
            vehicleID: store.activeVehicle?.id,
            vehicleProfileName: store.activeVehicle?.displayName ?? "",
            driverID: store.activeDriver?.id,
            driverName: store.activeDriver?.name ?? "",
            driverDateOfBirth: store.activeDriver?.dateOfBirth,
            driverLicenceNumber: store.activeDriver?.licenceNumber ?? "",
            startAddress: startAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            endAddress: endAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            details: tripDetails.trimmingCharacters(in: .whitespacesAndNewlines),
            odometerStart: start,
            odometerEnd: end,
            distanceMeters: store.unitSystem.meters(forDisplayedDistance: max(end - start, 0)),
            duration: 0,
            date: .now,
            manuallyEntered: true
        )

        store.addTrip(trip)
        dismiss()
    }
}

private struct MonthGroupedItems<Item: Identifiable>: Identifiable {
    let monthStart: Date
    let items: [Item]

    var id: Date { monthStart }

    var title: String {
        monthStart.formatted(.dateTime.month(.wide).year())
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(monthStart, equalTo: .now, toGranularity: .month)
    }
}

private extension Array where Element: Identifiable {
    func groupedByMonth(using keyPath: KeyPath<Element, Date>) -> [MonthGroupedItems<Element>] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: self) { element in
            let date = element[keyPath: keyPath]
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
        }

        return grouped
            .map { MonthGroupedItems(monthStart: $0.key, items: $0.value.sorted { $0[keyPath: keyPath] > $1[keyPath: keyPath] }) }
            .sorted { $0.monthStart > $1.monthStart }
    }
}

private struct MonthlyDisclosureSection<Item: Identifiable, Content: View>: View {
    let group: MonthGroupedItems<Item>
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        if group.isCurrentMonth {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.items) { item in
                    content(item)
                }
            }
        } else {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(group.items) { item in
                        content(item)
                    }
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Text(group.title)
                        .font(.headline)
                    Spacer()
                    Text("\(group.items.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
        }
    }
}

private extension NumberFormatter {
    static var tripEditorOdometer: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter
    }
}

private struct AllowanceBalanceBanner: View {
    let title: String
    let vehicleName: String
    let summary: AllowanceBalanceSummary
    let currencyString: (Double) -> String

    private var remainingColor: Color {
        summary.remainingBalance >= 0 ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(vehicleName)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text(currencyString(summary.remainingBalance))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(remainingColor)
            }

            ProgressView(value: summary.utilizationProgress)
                .tint(summary.remainingBalance >= 0 ? .orange : .red)

            Text("Received \(currencyString(summary.receivedAllowance)) • Spent \(currencyString(summary.spentAmount))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct FuelView: View {
    @Bindable var store: MileageStore
    let tripTracker: TripTracker
    @Bindable var cloudSync: CloudSyncManager
    @State private var isPresentingAddFuel = false
    @State private var editingFuelEntry: FuelEntry?
    @State private var isPresentingCamera = false
    @State private var isPresentingCameraAlert = false
    @State private var stationName = ""
    @State private var fuelVolumeInput = ""
    @State private var paidAmount = ""
    @State private var odometerInput = ""
    @State private var isResolvingStation = false
    @State private var selectedReceiptItem: PhotosPickerItem?
    @State private var receiptImageData: Data?
    @State private var previewingReceiptImageData: Data?
    @State private var cameraAlertMessage = ""

    private var allowanceSummary: AllowanceBalanceSummary? {
        store.allowanceBalanceSummary(for: store.activeVehicleID)
    }

    private var activeVehicleFuelEntries: [FuelEntry] {
        store.fuelEntriesForActiveVehicle()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let allowanceSummary, let activeVehicle = store.activeVehicle {
                    AllowanceBalanceBanner(
                        title: "Allowance Balance",
                        vehicleName: activeVehicle.displayName,
                        summary: allowanceSummary,
                        currencyString: store.currencyString(for:)
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    fuelSummaryCard(
                        title: store.currentTaxYearLabel,
                        value: store.currencyString(for: store.currentTaxYearFuelSpendForActiveVehicle),
                        caption: "Total fuel spending"
                    )

                    fuelSummaryCard(
                        title: "Monthly Avg",
                        value: store.monthlyAverageFuelEconomyTextForActiveVehicle,
                        caption: "Fuel economy"
                    )
                }

                Button {
                    isPresentingAddFuel = true
                } label: {
                    Label("Add Fuel-up", systemImage: "plus.circle.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .disabled(!store.canAddMoreFuelEntries)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Recent Fuel-ups")
                        .font(.title3.weight(.semibold))

                    if activeVehicleFuelEntries.isEmpty {
                        Text(store.activeVehicle == nil ? "Select a vehicle to view fuel-ups." : "No fuel-ups recorded yet for this vehicle.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        ForEach(activeVehicleFuelEntries.groupedByMonth(using: \.date)) { group in
                            MonthlyDisclosureSection(group: group) { entry in
                                fuelEntryRow(entry)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Fuel Overview")
                        .font(.title3.weight(.semibold))
                    Text("Use the add button to log fuel purchases. The bar above tracks fuel spend for the current tax year and the average fuel economy across months with enough fill-up data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.isDemoModeEnabled {
                        Text("Demo limit: up to \(MileageStore.demoFuelEntryLimit) fuel-ups. Existing demo fuel-ups can't be deleted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isPresentingAddFuel) {
            NavigationStack {
                Form {
                    fuelEntryForm(isEditing: false)
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
                .task {
                    await prepareFuelEntry()
                }
                .fullScreenCover(isPresented: $isPresentingCamera) {
                    ReceiptCameraPicker(onImagePicked: { image in
                        receiptImageData = normalizedReceiptData(from: image)
                        isPresentingCamera = false
                    }, onDismiss: {
                        isPresentingCamera = false
                    })
                }
            }
        }
        .sheet(item: $editingFuelEntry) { entry in
            NavigationStack {
                Form {
                    fuelEntryForm(isEditing: true)
                }
                .navigationTitle("Edit Fuel-up")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismissFuelSheet()
                            editingFuelEntry = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEditedFuelEntry(entry)
                        }
                        .disabled(!canSaveFuelEntry || stationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .task(id: entry.id) {
                    loadFuelEntryForEditing(entry)
                }
                .fullScreenCover(isPresented: $isPresentingCamera) {
                    ReceiptCameraPicker(onImagePicked: { image in
                        receiptImageData = normalizedReceiptData(from: image)
                        isPresentingCamera = false
                    }, onDismiss: {
                        isPresentingCamera = false
                    })
                }
            }
        }
        .alert("Camera Unavailable", isPresented: $isPresentingCameraAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraAlertMessage)
        }
        .sheet(isPresented: previewingReceiptSheetBinding) {
            if let receiptData = previewingReceiptImageData {
                ReceiptImagePreviewSheet(imageData: receiptData)
            }
        }
        .onAppear {
            resetFuelInteractionStateIfNeeded()
        }
        .onChange(of: selectedReceiptItem, initial: false) { _, item in
            guard let item else {
                return
            }

            Task {
                await loadReceiptImage(from: item)
            }
        }
    }

    private var canSaveFuelEntry: Bool {
        guard editingFuelEntry != nil || store.activeVehicle != nil else {
            return false
        }

        return parseDecimalInput(fuelVolumeInput) != nil &&
            parseDecimalInput(paidAmount) != nil &&
            parseDecimalInput(odometerInput) != nil
    }

    private func saveFuelEntry() {
        guard
            let activeVehicle = store.activeVehicle,
            let displayedVolume = parseDecimalInput(fuelVolumeInput),
            let totalCost = parseDecimalInput(paidAmount),
            let odometer = parseDecimalInput(odometerInput)
        else {
            return
        }

        store.addFuelEntry(
            FuelEntry(
                vehicleID: activeVehicle.id,
                vehicleProfileName: activeVehicle.displayName,
                station: stationName,
                volume: store.liters(fromDisplayedFuelVolume: displayedVolume),
                totalCost: totalCost,
                odometer: odometer,
                date: .now,
                receiptImageData: receiptImageData
            )
        )
        dismissFuelSheet()
    }

    private func saveEditedFuelEntry(_ originalEntry: FuelEntry) {
        guard
            let displayedVolume = parseDecimalInput(fuelVolumeInput),
            let totalCost = parseDecimalInput(paidAmount),
            let odometer = parseDecimalInput(odometerInput)
        else {
            return
        }

        store.updateFuelEntry(
            FuelEntry(
                id: originalEntry.id,
                vehicleID: originalEntry.vehicleID,
                vehicleProfileName: originalEntry.vehicleProfileName,
                station: stationName.trimmingCharacters(in: .whitespacesAndNewlines),
                volume: store.liters(fromDisplayedFuelVolume: displayedVolume),
                totalCost: totalCost,
                odometer: odometer,
                date: originalEntry.date,
                receiptImageData: receiptImageData
            )
        )

        dismissFuelSheet()
        editingFuelEntry = nil
    }

    private func dismissFuelSheet() {
        isPresentingAddFuel = false
        isPresentingCamera = false
        isPresentingCameraAlert = false
        cameraAlertMessage = ""
        stationName = ""
        fuelVolumeInput = ""
        paidAmount = ""
        odometerInput = ""
        isResolvingStation = false
        selectedReceiptItem = nil
        receiptImageData = nil
    }

    private func loadFuelEntryForEditing(_ entry: FuelEntry) {
        stationName = entry.station
        fuelVolumeInput = formatDecimalInput(store.displayedFuelVolume(for: entry.volume), fractionDigits: 2)
        paidAmount = formatDecimalInput(entry.totalCost, fractionDigits: 2)
        odometerInput = formatDecimalInput(entry.odometer, fractionDigits: 1)
        isResolvingStation = false
        selectedReceiptItem = nil
        receiptImageData = entry.receiptImageData
    }

    private func prepareFuelEntry() async {
        let currentOdometer = store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
        odometerInput = String(Int(currentOdometer.rounded()))
        stationName = "Nearby fuel stop"
        isResolvingStation = true
        defer { isResolvingStation = false }

        guard let location = tripTracker.currentLocation else {
            return
        }

        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 100)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])

        do {
            let response = try await MKLocalSearch(request: request).start()
            let closestStation = response.mapItems
                .compactMap { item -> (String, CLLocationDistance)? in
                    guard let name = item.name else {
                        return nil
                    }

                    let poiLocation = item.location
                    let distance = location.distance(from: poiLocation)
                    guard distance <= 100 else {
                        return nil
                    }

                    return (name, distance)
                }
                .min { $0.1 < $1.1 }

            if let closestStation {
                stationName = closestStation.0
            } else if let currentAddress = await tripTracker.currentAddress() {
                stationName = currentAddress
            }
        } catch {
            if let currentAddress = await tripTracker.currentAddress() {
                stationName = currentAddress
            }
        }
    }

    @ViewBuilder
    private func fuelEntryForm(isEditing: Bool) -> some View {
        Section("Fuel-up Details") {
            if isEditing {
                labeledFuelField("Station") {
                    PlaceAutocompleteField(prompt: "Station", text: $stationName, axis: .vertical)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                LabeledContent("Station") {
                    if isResolvingStation {
                        ProgressView()
                    } else {
                        Text(stationName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            labeledFuelField("Odometer") {
                TextField("Odometer", text: $odometerInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }

            if !isEditing {
                Text("Auto-filled from the current odometer, but you can adjust it if you are logging the fuel-up later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            labeledFuelField(store.fuelVolumeUnit.title) {
                TextField(store.fuelVolumeUnit.title, text: $fuelVolumeInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }

            labeledFuelField("Paid Amount") {
                TextField("Paid Amount", text: $paidAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }

        Section("Receipt") {
            if let receiptImage = receiptPreviewImage {
                Button {
                    previewingReceiptImageData = receiptImageData
                } label: {
                    receiptImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("No receipt attached.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await requestReceiptCameraAccess()
                }
            } label: {
                Label("Scan Receipt", systemImage: "camera")
            }

            PhotosPicker(selection: $selectedReceiptItem, matching: .images) {
                Label("Upload From Photos", systemImage: "photo.on.rectangle")
            }

            if receiptImageData != nil {
                Button("Remove Receipt", role: .destructive) {
                    receiptImageData = nil
                    selectedReceiptItem = nil
                }
            }
        }
    }

    private func fuelSummaryCard(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.yellow.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        )
    }

    private func labeledFuelField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer()
            content()
        }
    }

    private func fuelEntryRow(_ entry: FuelEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.station)
                        .font(.headline)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if shouldShowPendingBadge(for: entry) {
                    pendingCloudSyncBadge
                } else if shouldShowUploadedBadge(for: entry) {
                    uploadedToCloudBadge
                }
                Spacer()
                Text(store.currencyString(for: entry.totalCost))
                    .font(.headline.weight(.semibold))
            }

            HStack {
                Text(store.fuelVolumeString(for: entry.volume, fractionDigits: 2))
                Spacer()
                Text("Odo \(entry.odometer.formatted(.number.precision(.fractionLength(1))))")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let fuelEconomyText = store.fuelEconomyText(for: entry) {
                Label("Fuel economy \(fuelEconomyText)", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if entry.receiptImageData != nil {
                Button {
                    previewingReceiptImageData = entry.receiptImageData
                } label: {
                    Label("View receipt", systemImage: "doc.viewfinder")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    editingFuelEntry = entry
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    store.deleteFuelEntry(id: entry.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(!store.canModifyDemoData || !store.canCurrentUserDeleteFuelEntries)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func shouldShowUploadedBadge(for entry: FuelEntry) -> Bool {
        cloudSync.uploadedFuelEntryIDs.contains(entry.id)
    }

    private func shouldShowPendingBadge(for entry: FuelEntry) -> Bool {
        cloudSync.pendingFuelEntryIDs.contains(entry.id)
    }

    private var uploadedToCloudBadge: some View {
        Image(systemName: "checkmark.icloud.fill")
            .font(.caption2)
            .foregroundStyle(.green)
            .accessibilityLabel("Uploaded to Firebase")
    }

    private var pendingCloudSyncBadge: some View {
        Image(systemName: "icloud.and.arrow.up.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
            .accessibilityLabel("Pending Firebase upload")
    }

    private var receiptPreviewImage: Image? {
        previewImage(for: receiptImageData)
    }

    private var previewingReceiptSheetBinding: Binding<Bool> {
        Binding(
            get: { previewingReceiptImageData != nil },
            set: { isPresented in
                if !isPresented {
                    previewingReceiptImageData = nil
                }
            }
        )
    }

    private func previewImage(for data: Data?) -> Image? {
        guard
            let data,
            let image = UIImage(data: data)
        else {
            return nil
        }

        return Image(uiImage: image)
    }

    private func normalizedReceiptData(from image: UIImage) -> Data? {
        optimizedReceiptData(from: image)
    }

    private func loadReceiptImage(from item: PhotosPickerItem) async {
        defer {
            selectedReceiptItem = nil
        }

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                return
            }

            receiptImageData = normalizedReceiptData(from: image)
        } catch {
            return
        }
    }

    private func resetFuelInteractionStateIfNeeded() {
        guard !isPresentingAddFuel, editingFuelEntry == nil else {
            return
        }

        isPresentingCameraAlert = false
        cameraAlertMessage = ""
        isResolvingStation = false
        isPresentingCamera = false
        selectedReceiptItem = nil
    }

    private func parseDecimalInput(_ value: String) -> Double? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        if let number = formatter.number(from: trimmedValue) {
            return number.doubleValue
        }

        return Double(trimmedValue.replacingOccurrences(of: ",", with: ""))
    }

    private func formatDecimalInput(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value))
            ?? value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    private func isValidEmail(_ emailAddress: String) -> Bool {
        let emailPattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return emailAddress.range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func requestReceiptCameraAccess() async {
        guard hasCameraUsageDescription else {
            cameraAlertMessage = "Camera access is currently unavailable. You can still attach a receipt from Photos."
            isPresentingCameraAlert = true
            return
        }

        guard VNDocumentCameraViewController.isSupported else {
            cameraAlertMessage = "Document scanning is not available on this device. Use Upload From Photos instead."
            isPresentingCameraAlert = true
            return
        }

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorizationStatus {
        case .authorized:
            presentFuelReceiptCamera()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                presentFuelReceiptCamera(afterPermissionPrompt: true)
            } else {
                cameraAlertMessage = "Camera access was denied. Enable it in Settings to scan receipts."
                isPresentingCameraAlert = true
            }
        case .denied, .restricted:
            cameraAlertMessage = "Camera access is turned off for this app. Enable camera access in Settings to scan receipts."
            isPresentingCameraAlert = true
        @unknown default:
            cameraAlertMessage = "Camera access is currently unavailable."
            isPresentingCameraAlert = true
        }
    }

    private var hasCameraUsageDescription: Bool {
        guard let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String else {
            return false
        }

        return !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func presentFuelReceiptCamera(afterPermissionPrompt: Bool = false) {
        Task { @MainActor in
            if afterPermissionPrompt {
                try? await Task.sleep(for: .milliseconds(250))
            }
            isPresentingCamera = true
        }
    }
}

private struct MaintenanceView: View {
    @Bindable var store: MileageStore
    let tripTracker: TripTracker
    @Bindable var cloudSync: CloudSyncManager
    @State private var isPresentingAddMaintenance = false
    @State private var editingMaintenanceRecord: MaintenanceRecord?
    @State private var shopName = ""
    @State private var maintenanceOdometerInput = ""
    @State private var maintenanceCost = ""
    @State private var maintenanceDate = Date.now
    @State private var maintenanceType: MaintenanceType = .oilChange
    @State private var otherDescription = ""
    @State private var maintenanceNotes = ""
    @State private var reminderEnabled = true
    @State private var nextServiceOdometerInput = ""
    @State private var nextServiceDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    @State private var selectedReceiptItem: PhotosPickerItem?
    @State private var receiptImageData: Data?
    @State private var previewingReceiptImageData: Data?
    @State private var isPresentingCamera = false
    @State private var isPresentingCameraAlert = false
    @State private var cameraAlertMessage = ""
    @State private var isResolvingShop = false
    @State private var selectedReminderID: UUID?
    @State private var reminderResetTask: Task<Void, Never>?

    private var currentOdometer: Double {
        store.currentOdometerReading(activeTripDistanceMeters: tripTracker.currentTripDistance)
    }

    private var nextReminderRecord: MaintenanceRecord? {
        store.nextMaintenanceReminder(currentOdometer: currentOdometer)
    }

    private var activeReminderRecords: [MaintenanceRecord] {
        store.activeMaintenanceReminders(currentOdometer: currentOdometer)
            .filter { $0.vehicleID == store.activeVehicleID }
    }

    private var activeVehicleMaintenanceRecords: [MaintenanceRecord] {
        store.maintenanceRecordsForActiveVehicle()
    }

    private var allowanceSummary: AllowanceBalanceSummary? {
        store.allowanceBalanceSummary(for: store.activeVehicleID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let allowanceSummary, let activeVehicle = store.activeVehicle {
                    AllowanceBalanceBanner(
                        title: "Allowance Balance",
                        vehicleName: activeVehicle.displayName,
                        summary: allowanceSummary,
                        currencyString: store.currencyString(for:)
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    maintenanceSummaryCard(
                        title: store.currentTaxYearLabel,
                        value: store.currencyString(for: store.currentTaxYearMaintenanceSpendForActiveVehicle),
                        caption: "Maintenance spend"
                    )

                    maintenanceReminderCard
                }

                Button {
                    isPresentingAddMaintenance = true
                } label: {
                    Label("Add Maintenance", systemImage: "plus.circle.fill")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .disabled(!store.canAddMoreMaintenanceRecords)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Recent Maintenance")
                        .font(.title3.weight(.semibold))

                    if activeVehicleMaintenanceRecords.isEmpty {
                        Text(store.activeVehicle == nil ? "Select a vehicle to view maintenance records." : "No maintenance records added yet for this vehicle.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        ForEach(activeVehicleMaintenanceRecords.groupedByMonth(using: \.date)) { group in
                            MonthlyDisclosureSection(group: group) { record in
                                maintenanceRow(record)
                            }
                        }
                    }
                }

                if store.isDemoModeEnabled {
                    Text("Demo limit: up to \(MileageStore.demoMaintenanceRecordLimit) maintenance items. Existing demo maintenance records can't be deleted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isPresentingAddMaintenance) {
            NavigationStack {
                Form {
                    maintenanceForm(isEditing: false)
                }
                .navigationTitle("Add Maintenance")
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
                        .disabled(!canSaveMaintenanceRecord)
                    }
                }
                .task {
                    await prepareMaintenanceRecord()
                }
                .fullScreenCover(isPresented: $isPresentingCamera) {
                    ReceiptCameraPicker { image in
                        receiptImageData = normalizedReceiptData(from: image)
                    } onDismiss: {
                        isPresentingCamera = false
                    }
                    .ignoresSafeArea()
                }
                .alert("Camera Unavailable", isPresented: $isPresentingCameraAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(cameraAlertMessage)
                }
            }
        }
        .sheet(item: $editingMaintenanceRecord) { record in
            NavigationStack {
                Form {
                    maintenanceForm(isEditing: true)
                }
                .navigationTitle("Edit Maintenance")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismissMaintenanceSheet()
                            editingMaintenanceRecord = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveEditedMaintenanceRecord(record)
                        }
                        .disabled(!canSaveMaintenanceRecord)
                    }
                }
                .task(id: record.id) {
                    loadMaintenanceRecordForEditing(record)
                }
                .fullScreenCover(isPresented: $isPresentingCamera) {
                    ReceiptCameraPicker { image in
                        receiptImageData = normalizedReceiptData(from: image)
                    } onDismiss: {
                        isPresentingCamera = false
                    }
                    .ignoresSafeArea()
                }
                .alert("Camera Unavailable", isPresented: $isPresentingCameraAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(cameraAlertMessage)
                }
            }
        }
        .sheet(isPresented: previewingReceiptSheetBinding) {
            if let receiptData = previewingReceiptImageData {
                ReceiptImagePreviewSheet(imageData: receiptData)
            }
        }
        .onChange(of: selectedReceiptItem, initial: false) { _, item in
            guard let item else {
                return
            }

            Task {
                await loadReceiptImage(from: item)
            }
        }
        .onChange(of: maintenanceType, initial: false) { _, newType in
            if !newType.supportsReminder {
                reminderEnabled = false
            }
        }
        .onAppear {
            syncReminderSelection()
        }
        .onChange(of: activeReminderRecords.map(\.id), initial: true) { _, _ in
            syncReminderSelection()
        }
    }

    private var canSaveMaintenanceRecord: Bool {
        guard editingMaintenanceRecord != nil || store.activeVehicle != nil else {
            return false
        }

        guard Double(maintenanceOdometerInput) != nil, Double(maintenanceCost) != nil else {
            return false
        }

        if maintenanceType == .other && otherDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }

        if reminderEnabled && maintenanceType.supportsReminder && Double(nextServiceOdometerInput) == nil {
            return false
        }

        return true
    }

    private var maintenanceReminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEXT SERVICE")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if !activeReminderRecords.isEmpty {
                TabView(selection: reminderSelectionBinding) {
                    ForEach(activeReminderRecords) { record in
                        maintenanceReminderPage(for: record)
                            .tag(Optional(record.id))
                            .contentShape(Rectangle())
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if activeReminderRecords.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(activeReminderRecords.enumerated()), id: \.element.id) { index, record in
                            Circle()
                                .fill(record.id == selectedReminderID ? Color.primary : Color.secondary.opacity(0.28))
                                .frame(width: record.id == selectedReminderID ? 8 : 6, height: record.id == selectedReminderID ? 8 : 6)
                                .overlay(alignment: .bottom) {
                                    if index == 0 && record.id == selectedReminderID {
                                        EmptyView()
                                    }
                                }
                        }

                        Spacer()

                        Text(reminderPositionText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text("No reminder set")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Add an oil change or scheduled service with a next-service odometer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.14), Color.cyan.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.blue.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func maintenanceReminderPage(for record: MaintenanceRecord) -> some View {
        if let distanceRemaining = record.distanceRemaining(from: currentOdometer) {
            VStack(alignment: .leading, spacing: 10) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                IntegerOdometerView(value: abs(distanceRemaining))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(0.78, anchor: .leading)
                    .frame(height: 28)

                Text(record.nextServiceDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func maintenanceForm(isEditing: Bool) -> some View {
        Section("Maintenance Details") {
            labeledMaintenanceField("Shop") {
                PlaceAutocompleteField(prompt: "Dealer, mechanic, lube shop or address", text: $shopName, axis: .vertical)
                    .multilineTextAlignment(.trailing)
            }

            if isResolvingShop {
                HStack {
                    ProgressView()
                    Text("Finding nearby service location...")
                        .foregroundStyle(.secondary)
                }
            }

            labeledMaintenanceField("Odometer") {
                TextField("Odometer", text: $maintenanceOdometerInput)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }

            if !isEditing {
                Text("Auto-filled from the current odometer, but you can adjust it if the maintenance was added later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            labeledMaintenanceField("Date") {
                DatePicker("", selection: $maintenanceDate, displayedComponents: .date)
                    .labelsHidden()
            }

            labeledMaintenanceField("Paid Amount") {
                TextField("Paid Amount", text: $maintenanceCost)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }

            Picker("Type", selection: $maintenanceType) {
                ForEach(MaintenanceType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }

            if maintenanceType == .other {
                TextField("Description", text: $otherDescription)
            }

            TextField("Notes", text: $maintenanceNotes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
        }

        if maintenanceType.supportsReminder {
            Section("Maintenance Reminder") {
                Toggle("Turn on reminder", isOn: $reminderEnabled)

                if reminderEnabled {
                    labeledMaintenanceField("Next service odo") {
                        TextField("Next service odometer", text: $nextServiceOdometerInput)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker("Next service date", selection: $nextServiceDate, displayedComponents: .date)

                    Text("You will be reminded when the vehicle is within 1000 \(distanceUnitLabel) and again within 200 \(distanceUnitLabel) of the next service.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Receipt") {
            if let receiptPreviewImage {
                Button {
                    previewingReceiptImageData = receiptImageData
                } label: {
                    receiptPreviewImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                Text("No receipt attached.")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await requestReceiptCameraAccess()
                }
            } label: {
                Label("Scan Receipt", systemImage: "camera")
            }

            PhotosPicker(selection: $selectedReceiptItem, matching: .images) {
                Label("Upload From Photos", systemImage: "photo.on.rectangle")
            }

            if receiptImageData != nil {
                Button("Remove Receipt", role: .destructive) {
                    receiptImageData = nil
                    selectedReceiptItem = nil
                }
            }
        }
    }

    private func saveMaintenanceRecord() {
        guard
            let activeVehicle = store.activeVehicle,
            let odometer = Double(maintenanceOdometerInput),
            let totalCost = Double(maintenanceCost)
        else {
            return
        }

        let reminderOdometer = reminderEnabled && maintenanceType.supportsReminder ? Double(nextServiceOdometerInput) : nil

        store.addMaintenanceRecord(
            MaintenanceRecord(
                vehicleID: activeVehicle.id,
                vehicleProfileName: activeVehicle.displayName,
                shopName: shopName.trimmingCharacters(in: .whitespacesAndNewlines),
                odometer: odometer,
                date: maintenanceDate,
                type: maintenanceType,
                otherDescription: otherDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: maintenanceNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                totalCost: totalCost,
                receiptImageData: receiptImageData,
                reminderEnabled: reminderEnabled && maintenanceType.supportsReminder,
                nextServiceOdometer: reminderOdometer,
                nextServiceDate: reminderEnabled && maintenanceType.supportsReminder ? nextServiceDate : nil
            )
        )

        dismissMaintenanceSheet()
    }

    private func saveEditedMaintenanceRecord(_ originalRecord: MaintenanceRecord) {
        guard
            let odometer = Double(maintenanceOdometerInput),
            let totalCost = Double(maintenanceCost)
        else {
            return
        }

        let reminderOdometer = reminderEnabled && maintenanceType.supportsReminder ? Double(nextServiceOdometerInput) : nil

        store.updateMaintenanceRecord(
            MaintenanceRecord(
                id: originalRecord.id,
                vehicleID: originalRecord.vehicleID,
                vehicleProfileName: originalRecord.vehicleProfileName,
                shopName: shopName.trimmingCharacters(in: .whitespacesAndNewlines),
                odometer: odometer,
                date: maintenanceDate,
                type: maintenanceType,
                otherDescription: otherDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: maintenanceNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                totalCost: totalCost,
                receiptImageData: receiptImageData,
                reminderEnabled: reminderEnabled && maintenanceType.supportsReminder,
                nextServiceOdometer: reminderOdometer,
                nextServiceDate: reminderEnabled && maintenanceType.supportsReminder ? nextServiceDate : nil,
                hasSentThousandReminder: false,
                hasSentTwoHundredReminder: false
            )
        )

        dismissMaintenanceSheet()
        editingMaintenanceRecord = nil
    }

    private func dismissMaintenanceSheet() {
        isPresentingAddMaintenance = false
        shopName = ""
        maintenanceOdometerInput = ""
        maintenanceCost = ""
        maintenanceDate = .now
        maintenanceType = .oilChange
        otherDescription = ""
        maintenanceNotes = ""
        reminderEnabled = true
        nextServiceOdometerInput = ""
        nextServiceDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        selectedReceiptItem = nil
        receiptImageData = nil
        isResolvingShop = false
    }

    private func loadMaintenanceRecordForEditing(_ record: MaintenanceRecord) {
        shopName = record.shopName
        maintenanceOdometerInput = String(Int(record.odometer.rounded()))
        maintenanceCost = record.totalCost.formatted(.number.precision(.fractionLength(2)))
        maintenanceDate = record.date
        maintenanceType = record.type
        otherDescription = record.otherDescription
        maintenanceNotes = record.notes
        reminderEnabled = record.reminderEnabled
        nextServiceOdometerInput = record.nextServiceOdometer.map { String(Int($0.rounded())) } ?? ""
        nextServiceDate = record.nextServiceDate ?? (Calendar.current.date(byAdding: .year, value: 1, to: record.date) ?? .now)
        selectedReceiptItem = nil
        receiptImageData = record.receiptImageData
        isResolvingShop = false
    }

    private func prepareMaintenanceRecord() async {
        maintenanceOdometerInput = String(Int(currentOdometer.rounded()))
        maintenanceDate = .now
        nextServiceDate = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        shopName = ""
        isResolvingShop = true
        defer { isResolvingShop = false }

        guard let location = tripTracker.currentLocation else {
            return
        }

        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 100)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.automotiveRepair])

        do {
            let response = try await MKLocalSearch(request: request).start()
            let closestShop = response.mapItems
                .compactMap { item -> (String, CLLocationDistance)? in
                    guard let name = item.name else {
                        return nil
                    }

                    let distance = location.distance(from: item.location)
                    guard distance <= 100 else {
                        return nil
                    }

                    return (name, distance)
                }
                .min { $0.1 < $1.1 }

            if let closestShop {
                shopName = closestShop.0
            } else if let currentAddress = await tripTracker.currentAddress() {
                shopName = currentAddress
            }
        } catch {
            if let currentAddress = await tripTracker.currentAddress() {
                shopName = currentAddress
            }
        }
    }

    private func maintenanceSummaryCard(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 148, maxHeight: 148, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.18), Color.yellow.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        )
    }

    private func labeledMaintenanceField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer()
            content()
        }
    }

    private func maintenanceRow(_ record: MaintenanceRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.headline)
                    Text(record.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if shouldShowPendingBadge(for: record) {
                    pendingCloudSyncBadge
                } else if shouldShowUploadedBadge(for: record) {
                    uploadedToCloudBadge
                }
                Spacer()
                Text(store.currencyString(for: record.totalCost))
                    .font(.headline.weight(.semibold))
            }

            HStack {
                Text(record.type.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill), in: Capsule())

                Spacer()

                Text("Odo \(Int(record.odometer.rounded()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !record.shopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(record.shopName, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if record.reminderEnabled, let nextServiceOdometer = record.nextServiceOdometer {
                Text("Reminder set for \(Int(nextServiceOdometer.rounded())) on \(record.nextServiceDate?.formatted(date: .abbreviated, time: .omitted) ?? "No date")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !record.notes.isEmpty {
                Text(record.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if record.receiptImageData != nil {
                Button {
                    previewingReceiptImageData = record.receiptImageData
                } label: {
                    Label("View receipt", systemImage: "doc.viewfinder")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    editingMaintenanceRecord = record
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    store.deleteMaintenanceRecord(id: record.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(!store.canModifyDemoData || !store.canCurrentUserDeleteMaintenanceRecords)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func shouldShowUploadedBadge(for record: MaintenanceRecord) -> Bool {
        cloudSync.uploadedMaintenanceRecordIDs.contains(record.id)
    }

    private func shouldShowPendingBadge(for record: MaintenanceRecord) -> Bool {
        cloudSync.pendingMaintenanceRecordIDs.contains(record.id)
    }

    private var uploadedToCloudBadge: some View {
        Image(systemName: "checkmark.icloud.fill")
            .font(.caption2)
            .foregroundStyle(.green)
            .accessibilityLabel("Uploaded to Firebase")
    }

    private var pendingCloudSyncBadge: some View {
        Image(systemName: "icloud.and.arrow.up.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
            .accessibilityLabel("Pending Firebase upload")
    }

    private var distanceUnitLabel: String {
        store.unitSystem == .miles ? "miles" : "kilometers"
    }

    private var reminderSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedReminderID ?? activeReminderRecords.first?.id },
            set: { newValue in
                selectedReminderID = newValue
                scheduleReminderReset()
            }
        )
    }

    private var reminderPositionText: String {
        guard
            let selectedReminderID,
            let index = activeReminderRecords.firstIndex(where: { $0.id == selectedReminderID })
        else {
            return ""
        }

        return "\(index + 1) of \(activeReminderRecords.count)"
    }

    private func syncReminderSelection() {
        let reminderIDs = Set(activeReminderRecords.map(\.id))
        guard !activeReminderRecords.isEmpty else {
            selectedReminderID = nil
            reminderResetTask?.cancel()
            reminderResetTask = nil
            return
        }

        if let selectedReminderID, reminderIDs.contains(selectedReminderID) {
            return
        }

        selectedReminderID = activeReminderRecords.first?.id
    }

    private func scheduleReminderReset() {
        reminderResetTask?.cancel()
        guard activeReminderRecords.count > 1 else {
            return
        }

        reminderResetTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                selectedReminderID = activeReminderRecords.first?.id
            }
        }
    }

    private var receiptPreviewImage: Image? {
        previewImage(for: receiptImageData)
    }

    private var previewingReceiptSheetBinding: Binding<Bool> {
        Binding(
            get: { previewingReceiptImageData != nil },
            set: { isPresented in
                if !isPresented {
                    previewingReceiptImageData = nil
                }
            }
        )
    }

    private func previewImage(for data: Data?) -> Image? {
        guard
            let data,
            let image = UIImage(data: data)
        else {
            return nil
        }

        return Image(uiImage: image)
    }

    private func normalizedReceiptData(from image: UIImage) -> Data? {
        optimizedReceiptData(from: image)
    }

    private func loadReceiptImage(from item: PhotosPickerItem) async {
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                return
            }

            receiptImageData = normalizedReceiptData(from: image)
        } catch {
            return
        }
    }

    private func requestReceiptCameraAccess() async {
        guard hasCameraUsageDescription else {
            cameraAlertMessage = "Camera access is currently unavailable. You can still attach a receipt from Photos."
            isPresentingCameraAlert = true
            return
        }

        guard VNDocumentCameraViewController.isSupported else {
            cameraAlertMessage = "Document scanning is not available on this device. Use Upload From Photos instead."
            isPresentingCameraAlert = true
            return
        }

        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorizationStatus {
        case .authorized:
            isPresentingCamera = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                isPresentingCamera = true
            } else {
                cameraAlertMessage = "Camera access was denied. Enable it in Settings to scan receipts."
                isPresentingCameraAlert = true
            }
        case .denied, .restricted:
            cameraAlertMessage = "Camera access is turned off for this app. Enable camera access in Settings to scan receipts."
            isPresentingCameraAlert = true
        @unknown default:
            cameraAlertMessage = "Camera access is currently unavailable."
            isPresentingCameraAlert = true
        }
    }

    private var hasCameraUsageDescription: Bool {
        guard let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String else {
            return false
        }

        return !usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct LogsView: View {
    private enum ExportDestination {
        case download
        case email
    }

    private enum ExportLogType: String, CaseIterable, Identifiable {
        case mileage
        case financial

        var id: String { rawValue }

        var title: String {
            switch self {
            case .mileage:
                return "Mileage Log"
            case .financial:
                return "Financial Log"
            }
        }

        var progressMessage: String {
            switch self {
            case .mileage:
                return "Generating mileage log…"
            case .financial:
                return "Generating financial log…"
            }
        }

        var fileNamePrefix: String {
            switch self {
            case .mileage:
                return "meerkat-mileage-log"
            case .financial:
                return "meerkat-financial-log"
            }
        }
    }

    private enum AllowanceAdjustmentDirection: String, CaseIterable, Identifiable {
        case add
        case subtract

        var id: String { rawValue }

        var title: String {
            switch self {
            case .add:
                return "Add Funds"
            case .subtract:
                return "Subtract Funds"
            }
        }

        var multiplier: Double {
            switch self {
            case .add:
                return 1
            case .subtract:
                return -1
            }
        }
    }

    @Bindable var store: MileageStore
    @State private var selectedVehicleID: UUID?
    @State private var selectedDriverID: UUID?
    @State private var rangeStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var rangeEnd = Date.now
    @State private var isPresentingImporter = false
    @State private var isPresentingShareSheet = false
    @State private var isPresentingMailSheet = false
    @State private var isPresentingCSVPreview = false
    @State private var selectedExportLogType: ExportLogType = .mileage
    @State private var generatedCSV = ""
    @State private var csvPreviewTable: CSVPreviewTable?
    @State private var generatedFileURL: URL?
    @State private var exportDocument: CSVFileDocument?
    @State private var importerMessage: String?
    @State private var mailComposeResultMessage = ""
    @State private var isPreparingExport = false
    @State private var exportProgressMessage = ""
    @State private var allowanceAdjustmentDirection: AllowanceAdjustmentDirection = .add
    @State private var allowanceAdjustmentAmount = ""
    @State private var allowanceAdjustmentReason = ""

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let selectedVehicleWithAllowance, let allowanceSummary {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Allowance Balance Top Up")
                                .font(.title3.weight(.semibold))

                            Text("Manually add to or subtract from \(selectedVehicleWithAllowance.displayName)'s current allowance balance.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            AllowanceBalanceBanner(
                                title: "Current Balance",
                                vehicleName: selectedVehicleWithAllowance.displayName,
                                summary: allowanceSummary,
                                currencyString: store.currencyString(for:)
                            )

                            Picker("Adjustment Type", selection: $allowanceAdjustmentDirection) {
                                ForEach(AllowanceAdjustmentDirection.allCases) { direction in
                                    Text(direction.title).tag(direction)
                                }
                            }
                            .pickerStyle(.segmented)

                            TextField("Amount", text: $allowanceAdjustmentAmount)
                                .keyboardType(.decimalPad)

                            TextField("Reason", text: $allowanceAdjustmentReason, axis: .vertical)
                                .lineLimit(2 ... 4)

                            Button {
                                addAllowanceAdjustment()
                            } label: {
                                Label(allowanceAdjustmentDirection.title, systemImage: allowanceAdjustmentDirection == .add ? "plus.circle.fill" : "minus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSubmitAllowanceAdjustment || store.isDemoModeEnabled)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Web Portal")
                            .font(.title3.weight(.semibold))

                        Text("Use the Meerkat web portal to manage synced trips, fuel, maintenance, and exports from a computer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Link(destination: URL(string: "https://app.meerkatinnovations.ca")!) {
                            Label("Open app.meerkatinnovations.ca", systemImage: "desktopcomputer")
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Sign in with the same Meerkat account you use in the app to manage data and export logs online.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Export Logs")
                            .font(.title3.weight(.semibold))

                        Text("Exports follow \(store.selectedCountry.rawValue)'s configured tax-year rules and include country-specific filing metadata.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Log Type", selection: $selectedExportLogType) {
                            ForEach(ExportLogType.allCases) { logType in
                                Text(logType.title).tag(logType)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Vehicle", selection: $selectedVehicleID) {
                            Text("All Vehicles").tag(Optional<UUID>.none)
                            ForEach(store.availableVehicles) { vehicle in
                                Text(vehicle.displayName).tag(Optional(vehicle.id))
                            }
                        }

                        Picker("Driver", selection: $selectedDriverID) {
                            Text("All Drivers").tag(Optional<UUID>.none)
                            ForEach(store.availableDrivers) { driver in
                                Text(driver.name).tag(Optional(driver.id))
                            }
                        }

                        DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                        DatePicker("To", selection: $rangeEnd, in: rangeStart..., displayedComponents: .date)

                        Button {
                            startExport(for: .download)
                        } label: {
                            Label("Download \(selectedExportLogType.title)", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreparingExport || store.isDemoModeEnabled || !store.canCurrentUserExportLogs)

                        Button {
                            prepareCSVPreview()
                            if csvPreviewTable != nil {
                                isPresentingCSVPreview = true
                            }
                        } label: {
                            Label("View \(selectedExportLogType.title)", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingExport || store.isDemoModeEnabled || !store.canCurrentUserViewLogs)

                        Button {
                            startExport(for: .email)
                        } label: {
                            Label("Email \(selectedExportLogType.title)", systemImage: "envelope")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isPreparingExport || !MFMailComposeViewController.canSendMail() || store.isDemoModeEnabled || !store.canCurrentUserExportLogs)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Import Logs")
                            .font(.title3.weight(.semibold))

                        Text("Upload a CSV log file to add trips, fuel-ups, and maintenance records back into the app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            isPresentingImporter = true
                        } label: {
                            Label("Upload CSV", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isDemoModeEnabled)

                        if let importerMessage {
                            Text(importerMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    if store.isDemoModeEnabled {
                        Text("Demo Mode allows browsing and editing sample data, but export, import, and allowance adjustments are disabled.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Tax Year Status")
                            .font(.title3.weight(.semibold))

                        Text("Summary for \(store.currentTaxYearLabel)\(selectedVehicleName.map { " • \($0)" } ?? "").")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        taxYearStatusRow("Total trips", "\(taxYearSummary.totalTrips)")
                        taxYearStatusRow("Business trips", "\(taxYearSummary.totalBusinessTrips)")
                        taxYearStatusRow("Personal trips", "\(taxYearSummary.totalPersonalTrips)")
                        taxYearStatusRow("Business distance", store.unitSystem.distanceString(for: taxYearSummary.totalBusinessDistanceMeters))
                        taxYearStatusRow("Personal distance", store.unitSystem.distanceString(for: taxYearSummary.totalPersonalDistanceMeters))
                        taxYearStatusRow("Total distance", store.unitSystem.distanceString(for: taxYearSummary.totalCombinedDistanceMeters))
                        taxYearStatusRow("Fuel spend", store.currencyString(for: taxYearSummary.totalFuelSpend))
                        taxYearStatusRow("Maintenance spend", store.currencyString(for: taxYearSummary.totalMaintenanceSpend))
                        taxYearStatusRow("Total spend", store.currencyString(for: taxYearSummary.totalCombinedSpend))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(Color(.systemGroupedBackground))

            if isPreparingExport {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(exportProgressMessage)
                        .font(.headline)
                    Text("This can take a few seconds for larger date ranges.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .onAppear {
            applyDefaultTaxYearRange()
        }
        .onChange(of: store.selectedCountry, initial: false) { _, _ in
            applyDefaultTaxYearRange()
        }
        .onChange(of: selectedVehicleID, initial: false) { _, _ in
            allowanceAdjustmentAmount = ""
            allowanceAdjustmentReason = ""
            allowanceAdjustmentDirection = .add
        }
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText, .excelWorkbook],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $isPresentingShareSheet,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFileName.replacingOccurrences(of: ".csv", with: "")
        ) { result in
            switch result {
            case .success:
                importerMessage = "\(selectedExportLogType.title) saved."
            case .failure(let error):
                importerMessage = "Could not save CSV file: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isPresentingCSVPreview) {
            NavigationStack {
                Group {
                    if let csvPreviewTable {
                        CSVPreviewView(table: csvPreviewTable)
                    } else {
                        ContentUnavailableView("No Preview Available", systemImage: "doc.text")
                    }
                }
                .navigationTitle("CSV Preview")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isPresentingCSVPreview = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingMailSheet) {
            if let generatedFileURL {
                MailComposeView(
                    subject: selectedExportLogType == .mileage ? "Mileage Log Export" : "Financial Log Export",
                    attachmentURL: generatedFileURL,
                    attachmentMimeType: "text/csv",
                    attachmentFileName: generatedFileURL.lastPathComponent,
                    resultMessage: $mailComposeResultMessage
                )
            }
        }
    }

    private func prepareCSVPreview() {
        switch selectedExportLogType {
        case .mileage:
            let payload = store.entriesForLogExport(
                vehicleID: selectedVehicleID,
                driverID: selectedDriverID,
                dateRange: dateRange
            )
            csvPreviewTable = LogCSVCodec.previewTable(from: payload)
        case .financial:
            let payload = store.entriesForFinancialLogExport(
                vehicleID: selectedVehicleID,
                driverID: selectedDriverID,
                dateRange: dateRange
            )
            csvPreviewTable = FinancialLogCSVCodec.previewTable(from: payload)
        }
    }

    private var taxYearSummary: TaxYearStatusSummary {
        store.taxYearStatusSummary(vehicleID: selectedVehicleID)
    }

    private var selectedVehicleName: String? {
        store.vehicle(for: selectedVehicleID)?.displayName
    }

    private var allowanceAdjustmentVehicleID: UUID? {
        selectedVehicleID ?? store.activeVehicleID
    }

    private var selectedVehicleWithAllowance: VehicleProfile? {
        guard let vehicle = store.vehicle(for: allowanceAdjustmentVehicleID), vehicle.allowancePlan != nil else {
            return nil
        }

        return vehicle
    }

    private var allowanceSummary: AllowanceBalanceSummary? {
        store.allowanceBalanceSummary(for: allowanceAdjustmentVehicleID)
    }

    private var parsedAllowanceAdjustmentAmount: Double? {
        guard let amount = Double(allowanceAdjustmentAmount), amount > 0 else {
            return nil
        }

        return amount
    }

    private var canSubmitAllowanceAdjustment: Bool {
        selectedVehicleWithAllowance != nil &&
        parsedAllowanceAdjustmentAmount != nil &&
        !allowanceAdjustmentReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func taxYearStatusRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func addAllowanceAdjustment() {
        guard
            let vehicle = selectedVehicleWithAllowance,
            let amount = parsedAllowanceAdjustmentAmount
        else {
            return
        }

        store.addAllowanceAdjustment(
            vehicleID: vehicle.id,
            amount: amount * allowanceAdjustmentDirection.multiplier,
            reason: allowanceAdjustmentReason
        )
        allowanceAdjustmentAmount = ""
        allowanceAdjustmentReason = ""
        allowanceAdjustmentDirection = .add
    }

    private func startExport(for destination: ExportDestination) {
        guard !isPreparingExport else {
            return
        }

        isPreparingExport = true
        exportProgressMessage = selectedExportLogType.progressMessage

        Task {
            await Task.yield()
            prepareCSVForFile()
            isPreparingExport = false

            guard generatedFileURL != nil else {
                return
            }

            switch destination {
            case .download:
                isPresentingShareSheet = true
            case .email:
                isPresentingMailSheet = true
            }
        }
    }

    private func prepareCSVForFile() {
        switch selectedExportLogType {
        case .mileage:
            let payload = store.entriesForLogExport(
                vehicleID: selectedVehicleID,
                driverID: selectedDriverID,
                dateRange: dateRange
            )
            generatedCSV = LogCSVCodec.makeCSV(from: payload)
        case .financial:
            let payload = store.entriesForFinancialLogExport(
                vehicleID: selectedVehicleID,
                driverID: selectedDriverID,
                dateRange: dateRange
            )
            generatedCSV = FinancialLogCSVCodec.makeCSV(from: payload)
        }
        exportDocument = CSVFileDocument(text: generatedCSV)
        generatedFileURL = writeCSVFile(named: exportFileName, contents: generatedCSV)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        Task {
            do {
                guard let url = try result.get().first else {
                    return
                }

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let csv = try LogImportFileDecoder.text(from: url)
                let parsedResult = try await LogCSVCodec.parseWithAIAssistanceIfNeeded(csv)
                store.importLogPayload(parsedResult.payload)
                let summary = "Imported \(parsedResult.payload.trips.count) trips, \(parsedResult.payload.fuelEntries.count) fuel-ups, and \(parsedResult.payload.maintenanceRecords.count) maintenance items."
                importerMessage = parsedResult.usedAIAssistance ? "\(summary) Apple Intelligence helped map the file into the app's schema." : summary
            } catch {
                importerMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private var dateRange: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: rangeStart)
        let end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: rangeEnd) ?? rangeEnd
        return start ... end
    }

    private func applyDefaultTaxYearRange() {
        let range = store.defaultLogDateRange()
        rangeStart = range.lowerBound
        rangeEnd = range.upperBound
    }

    private var exportFileName: String {
        let vehicleName = store.vehicle(for: selectedVehicleID)?.displayName.replacingOccurrences(of: " ", with: "-") ?? "all-vehicles"
        let driverName = store.driver(for: selectedDriverID)?.name.replacingOccurrences(of: " ", with: "-") ?? "all-drivers"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "\(selectedExportLogType.fileNamePrefix)-\(vehicleName)-\(driverName)-\(formatter.string(from: rangeStart))-\(formatter.string(from: rangeEnd)).csv"
    }

    private func writeCSVFile(named fileName: String, contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            importerMessage = "Could not create CSV file: \(error.localizedDescription)"
            return nil
        }
    }
}

private struct CSVPreviewView: View {
    private struct PreviewRecord: Identifiable {
        let id: String
        let recordType: String
        let values: [String: String]

        init(row: [String], headers: [String]) {
            let paddedRow = row + Array(repeating: "", count: max(0, headers.count - row.count))
            values = Dictionary(uniqueKeysWithValues: zip(headers, paddedRow))
            recordType = values["record_type"] ?? ""
            id = values["record_id"] ?? UUID().uuidString
        }

        func value(_ key: String) -> String {
            let value = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "—" : value
        }

        func displayValue(_ key: String) -> String {
            let rawValue = value(key)

            guard key == "duration_seconds", rawValue != "—", let duration = TimeInterval(rawValue) else {
                return rawValue
            }

            return duration.formattedDuration
        }

        func hasValue(_ key: String) -> Bool {
            !(values[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    let table: CSVPreviewTable
    private let records: [PreviewRecord]
    private let recordTypes: [String]
    @State private var selectedFilter = "all"

    init(table: CSVPreviewTable) {
        self.table = table
        let records = table.rows.map { PreviewRecord(row: $0, headers: table.headers) }
        self.records = records
        self.recordTypes = Array(Set(records.map(\.recordType))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Records", selection: $selectedFilter) {
                Text("All").tag("all")
                ForEach(recordTypes, id: \.self) { recordType in
                    Text(recordTypeTitle(recordType)).tag(recordType)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedFilter == "all" {
                        ForEach(recordTypes, id: \.self) { recordType in
                            let filteredRecords = records.filter { $0.recordType == recordType }
                            if !filteredRecords.isEmpty {
                                previewSection(recordTypeTitle(recordType), records: filteredRecords)
                            }
                        }
                    } else {
                        previewSection(
                            recordTypeTitle(selectedFilter),
                            records: records.filter { $0.recordType == selectedFilter }
                        )
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ title: String, records: [PreviewRecord]) -> some View {
        if records.isEmpty {
            ContentUnavailableView("\(title) Not Found", systemImage: "doc.text")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text("\(records.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                LazyVStack(spacing: 12) {
                    ForEach(records) { record in
                        switch record.recordType {
                        case "trip":
                            tripPreviewCard(record)
                        case "fuel":
                            if record.hasValue("amount") {
                                financialPreviewCard(record)
                            } else {
                                fuelPreviewCard(record)
                            }
                        case "maintenance":
                            if record.hasValue("amount") {
                                financialPreviewCard(record)
                            } else {
                                maintenancePreviewCard(record)
                            }
                        case "allowance", "allowance_adjustment", "payment", "insurance", "scheduled_expense":
                            financialPreviewCard(record)
                        default:
                            genericPreviewCard(record)
                        }
                    }
                }
            }
        }
    }

    private func tripPreviewCard(_ record: PreviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.value("trip_name"))
                        .font(.headline)
                    Text(record.value("date"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.value("trip_type").capitalized)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }

            previewRow("Vehicle", record.value("vehicle_name"))
            previewRow("Driver", record.value("driver_name"))
            previewRow("Start", record.value("start_address"))
            previewRow("End", record.value("end_address"))
            previewRow("Distance", record.value("distance_meters"))
            previewRow("Duration", record.displayValue("duration_seconds"))
            previewRow("Start Odo", record.value("odometer_start"))
            previewRow("End Odo", record.value("odometer_end"))

            if record.hasValue("trip_details") {
                previewRow("Reason", record.value("trip_details"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func fuelPreviewCard(_ record: PreviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.value("station_or_shop"))
                        .font(.headline)
                    Text(record.value("date"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.value("total_cost"))
                    .font(.headline.weight(.semibold))
            }

            previewRow("Vehicle", record.value("vehicle_name"))
            previewRow("Volume", record.value("volume_liters"))
            previewRow("Odometer", record.value("odometer"))
            previewRow("Receipt", record.hasValue("receipt_base64") ? "Attached" : "None")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func maintenancePreviewCard(_ record: PreviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.value("maintenance_type").capitalized)
                        .font(.headline)
                    Text(record.value("date"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.value("total_cost"))
                    .font(.headline.weight(.semibold))
            }

            previewRow("Vehicle", record.value("vehicle_name"))
            previewRow("Shop", record.value("station_or_shop"))
            previewRow("Odometer", record.value("odometer"))
            if record.hasValue("other_description") {
                previewRow("Description", record.value("other_description"))
            }
            if record.hasValue("notes") {
                previewRow("Notes", record.value("notes"))
            }
            previewRow("Reminder", record.value("reminder_enabled"))
            if record.hasValue("next_service_odometer") {
                previewRow("Next Service Odo", record.value("next_service_odometer"))
            }
            if record.hasValue("next_service_date") {
                previewRow("Next Service Date", record.value("next_service_date"))
            }
            previewRow("Receipt", record.hasValue("receipt_base64") ? "Attached" : "None")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func financialPreviewCard(_ record: PreviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.value("description"))
                        .font(.headline)
                    Text(record.value("date"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.value("amount"))
                    .font(.headline.weight(.semibold))
            }

            previewRow("Category", record.value("category"))
            previewRow("Vehicle", record.value("vehicle_name"))
            if record.hasValue("business_use_percent") {
                previewRow("Business Use", "\(record.value("business_use_percent"))%")
            }
            if record.hasValue("business_portion_amount") {
                previewRow("Business Portion", record.value("business_portion_amount"))
            }
            if record.hasValue("notes") {
                previewRow("Notes", record.value("notes"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func genericPreviewCard(_ record: PreviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recordTypeTitle(record.recordType))
                .font(.headline)

            ForEach(table.headers, id: \.self) { header in
                if record.hasValue(header), header != "record_type", header != "record_id" {
                    previewRow(prettyHeader(header), record.value(header))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func recordTypeTitle(_ recordType: String) -> String {
        switch recordType {
        case "trip":
            return "Trips"
        case "fuel":
            return "Fuel-ups"
        case "maintenance":
            return "Maintenance"
        case "allowance":
            return "Allowance"
        case "allowance_adjustment":
            return "Allowance Adjustments"
        case "payment":
            return "Payments"
        case "insurance":
            return "Insurance"
        case "scheduled_expense":
            return "Scheduled Expenses"
        default:
            return recordType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func prettyHeader(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func previewRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScheduledExpenseDraft: Identifiable {
    var id = UUID()
    var title = ""
    var amount = ""
    var frequency: VehicleScheduleFrequency = .monthly
    var startDate = Date.now
}

private enum VehicleArchiveReason: String, CaseIterable, Identifiable {
    case sold
    case accidentLoss
    case stolen
    case replaced
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sold:
            return "Sold"
        case .accidentLoss:
            return "Accident / Loss"
        case .stolen:
            return "Stolen"
        case .replaced:
            return "Replaced"
        case .other:
            return "Other"
        }
    }
}

private struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker
    @Bindable var vehicleConnectionManager: VehicleConnectionManager
    @Bindable var authSession: AuthSessionManager
    @Bindable var subscriptionManager: SubscriptionManager
    @Bindable var cloudSync: CloudSyncManager
    let onExitDemoMode: () -> Void
    let onClearRecordedAppData: () -> Void
    let onFactoryReset: () -> Void
    @State private var isPresentingAddVehicle = false
    @State private var isPresentingAddDriver = false
    @State private var isPresentingClearRecordedDataConfirmation = false
    @State private var isPresentingFactoryResetConfirmation = false
    @State private var editingVehicleID: UUID?
    @State private var editingDriverID: UUID?
    @State private var vehiclePendingArchive: VehicleProfile?
    @State private var pendingDriverEmployeeInvite: DriverProfile?
    @State private var vehicleArchiveReason: VehicleArchiveReason = .sold
    @State private var customVehicleArchiveReason = ""
    @State private var profileName = ""
    @State private var make = ""
    @State private var model = ""
    @State private var color = ""
    @State private var numberPlate = ""
    @State private var fleetNumber = ""
    @State private var startingOdometerReading = ""
    @State private var ownershipType: VehicleOwnershipType = .personal
    @State private var receivesAllowance = false
    @State private var allowanceAmount = ""
    @State private var allowanceFrequency: VehicleScheduleFrequency = .monthly
    @State private var allowanceStartDate = Date.now
    @State private var hasVehiclePayment = false
    @State private var vehiclePaymentKind: VehiclePaymentKind = .finance
    @State private var vehiclePaymentAmount = ""
    @State private var vehiclePaymentFrequency: VehicleScheduleFrequency = .monthly
    @State private var vehiclePaymentStartDate = Date.now
    @State private var hasInsurancePayment = false
    @State private var insuranceAmount = ""
    @State private var insuranceFrequency: VehicleScheduleFrequency = .monthly
    @State private var insuranceStartDate = Date.now
    @State private var otherScheduledExpenses: [ScheduledExpenseDraft] = []
    @State private var vehicleDetectionEnabled = false
    @State private var useCarPlayDetection = false
    @State private var useAudioRouteDetection = false
    @State private var useBluetoothPeripheralDetection = false
    @State private var selectedAudioRouteIdentifier = ""
    @State private var selectedAudioRouteName = ""
    @State private var selectedBluetoothPeripheralIdentifier = ""
    @State private var driverName = ""
    @State private var driverDateOfBirth = Date.now
    @State private var licenceNumber = ""
    @State private var driverLicenceClass = ""
    @State private var driverEmailAddress = ""
    @State private var driverPhoneNumber = ""

    var body: some View {
        Form {
            Section("General") {
                if authSession.isDemoModeEnabled {
                    Button("Exit Demo Mode") {
                        onExitDemoMode()
                    }
                }

                NavigationLink {
                    SettingsProfilePreferencesView(
                        store: store,
                        selectedCountryBinding: selectedCountryBinding
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Account Setup",
                        subtitle: "\(store.selectedCountry.rawValue) • \(store.preferredCurrency.rawValue) • \(store.unitSystem.title) • \(store.fuelVolumeUnit.title)",
                        systemImage: "person.crop.circle"
                    )
                }

                NavigationLink {
                    SettingsTrackingView(
                        store: store,
                        tripTracker: tripTracker,
                        vehicleConnectionManager: vehicleConnectionManager
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Tracking",
                        subtitle: "Location: \(tripTracker.authorizationLabel)",
                        systemImage: "location.fill"
                    )
                }

                NavigationLink {
                    SettingsVehicleDetectionView(
                        store: store,
                        tripTracker: tripTracker,
                        vehicleConnectionManager: vehicleConnectionManager
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Vehicle Detection",
                        subtitle: vehicleDetectionSummary,
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }

                NavigationLink {
                    SettingsSubscriptionView(subscriptionManager: subscriptionManager)
                } label: {
                    SettingsNavigationRow(
                        title: "Subscription",
                        subtitle: subscriptionManager.statusMessage,
                        systemImage: "creditcard"
                    )
                }

                NavigationLink {
                    SettingsAccountView(
                        authSession: authSession,
                        subscriptionManager: subscriptionManager,
                        cloudSync: cloudSync,
                        persistenceSnapshot: persistenceSnapshot,
                        onRestoreRequest: {
                            await restoreFromCloud()
                        },
                        onExitDemoMode: onExitDemoMode,
                        onDeleteAccountRequest: {
                            Task {
                                try? await SharedAppModel.shared.deleteCurrentAccount()
                            }
                        }
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Cloud & Security",
                        subtitle: authSession.canUseCloudSyncFeatures ? cloudSync.statusMessage : "Signed out",
                        systemImage: "icloud"
                    )
                }

                if hasBusinessPortalAccess {
                    NavigationLink {
                        SettingsOrganizationView(store: store, subscriptionManager: subscriptionManager)
                    } label: {
                        SettingsNavigationRow(
                            title: "Organization",
                            subtitle: organizationSummary,
                            systemImage: "building.2"
                        )
                    }
                }

                if hasBusinessPortalAccess {
                    NavigationLink {
                        SettingsBusinessPortalView(store: store)
                    } label: {
                        SettingsNavigationRow(
                            title: "Business Portal",
                            subtitle: "Meerkat - Milage Tracker for Business",
                            systemImage: "briefcase.fill"
                        )
                    }
                }
            }

            Section("Profiles") {
                NavigationLink {
                    SettingsVehiclesView(
                        store: store,
                        vehicleConnectionManager: vehicleConnectionManager,
                        activeVehicleBinding: activeVehicleBinding,
                        onAddVehicle: startAddingVehicle,
                        onEditVehicle: beginEditingVehicle,
                        onDeleteVehicle: beginArchivingVehicle
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Vehicles",
                        subtitle: vehicleSummary,
                        systemImage: "car.fill"
                    )
                }

                NavigationLink {
                    SettingsDriversView(
                        store: store,
                        activeDriverBinding: activeDriverBinding,
                        onAddDriver: startAddingDriver,
                        onEditDriver: beginEditingDriver,
                        onDeleteDriver: deleteDriver
                    )
                } label: {
                    SettingsNavigationRow(
                        title: "Drivers",
                        subtitle: driverSummary,
                        systemImage: "person.2.fill"
                    )
                }
            }

            Section("Support") {
                NavigationLink {
                    SettingsPrivacyLegalView()
                } label: {
                    SettingsNavigationRow(
                        title: "Privacy Policy & Legal",
                        subtitle: "Privacy, data use, terms, and legal notice",
                        systemImage: "lock.doc"
                    )
                }

                NavigationLink {
                    SettingsContactSupportView()
                } label: {
                    SettingsNavigationRow(
                        title: "Contact Support",
                        subtitle: "Get help or share feedback",
                        systemImage: "envelope"
                    )
                }

                NavigationLink {
                    SettingsCarPlayView()
                } label: {
                    SettingsNavigationRow(
                        title: "CarPlay",
                        subtitle: "Use Meerkat on your car display",
                        systemImage: "car.circle"
                    )
                }

                NavigationLink {
                    SettingsAboutView(store: store, cloudSync: cloudSync)
                } label: {
                    SettingsNavigationRow(
                        title: "About",
                        subtitle: "\(store.trips.count) trips tracked",
                        systemImage: "info.circle"
                    )
                }
            }

            Section("Danger Zone") {
                Button("Clear App Records", role: .destructive) {
                    isPresentingClearRecordedDataConfirmation = true
                }

                Text("Deletes trips, fuel logs, maintenance records, vehicles, drivers, allowances, and app logs while keeping your sign-in and preferences.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Delete All App Data", role: .destructive) {
                    isPresentingFactoryResetConfirmation = true
                }
                .disabled(authSession.isDemoModeEnabled)

                Text("Factory reset deletes all local trips, fuel logs, maintenance records, vehicles, drivers, preferences, and saved sign-in data from this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(appVersionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $isPresentingAddVehicle) {
            NavigationStack {
                Form {
                    Section("Profile") {
                        TextField("Profile name", text: $profileName)
                        Picker("Vehicle type", selection: $ownershipType) {
                            ForEach(VehicleOwnershipType.allCases) { type in
                                Text(type.title).tag(type)
                            }
                        }
                    }

                    Section("Vehicle Details") {
                        TextField("Make", text: $make)
                        TextField("Model", text: $model)
                        TextField("Colour", text: $color)
                        TextField("Number plate", text: $numberPlate)
                        TextField("Fleet number (optional)", text: $fleetNumber)
                        TextField("Starting odometer reading", text: $startingOdometerReading)
                            .keyboardType(.decimalPad)
                    }

                    Section("Vehicle Allowance") {
                        Toggle("Allowance received for this vehicle", isOn: $receivesAllowance)

                        if receivesAllowance {
                            recurringAmountFields(
                                amountTitle: "Amount received",
                                amount: $allowanceAmount,
                                frequency: $allowanceFrequency,
                                startDate: $allowanceStartDate,
                                dateTitle: "First allowance date"
                            )
                        }
                    }

                    Section("Finance Or Lease") {
                        Toggle("Vehicle has finance or lease payment", isOn: $hasVehiclePayment)

                        if hasVehiclePayment {
                            Picker("Payment type", selection: $vehiclePaymentKind) {
                                ForEach(VehiclePaymentKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }

                            recurringAmountFields(
                                amountTitle: "Amount paid",
                                amount: $vehiclePaymentAmount,
                                frequency: $vehiclePaymentFrequency,
                                startDate: $vehiclePaymentStartDate,
                                dateTitle: "First payment date"
                            )
                        }
                    }

                    Section("Insurance") {
                        Toggle("Insurance is being paid", isOn: $hasInsurancePayment)

                        if hasInsurancePayment {
                            recurringAmountFields(
                                amountTitle: "Amount paid",
                                amount: $insuranceAmount,
                                frequency: $insuranceFrequency,
                                startDate: $insuranceStartDate,
                                dateTitle: "First insurance date"
                            )
                        }
                    }

                    Section("Other Scheduled Expenses") {
                        if otherScheduledExpenses.isEmpty {
                            Text("Add recurring vehicle costs such as parking, toll plans, subscriptions, or inspections.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        ForEach($otherScheduledExpenses) { $expense in
                            TextField("Expense name", text: $expense.title)
                            TextField("Amount paid", text: $expense.amount)
                                .keyboardType(.decimalPad)
                            Picker("Frequency", selection: $expense.frequency) {
                                ForEach(VehicleScheduleFrequency.allCases) { frequency in
                                    Text(frequency.title).tag(frequency)
                                }
                            }
                            DatePicker("First payment date", selection: $expense.startDate, displayedComponents: .date)

                            Button("Remove Expense", role: .destructive) {
                                otherScheduledExpenses.removeAll { $0.id == expense.id }
                            }
                        }

                        Button {
                            otherScheduledExpenses.append(ScheduledExpenseDraft())
                        } label: {
                            Label("Add Expense", systemImage: "plus")
                        }
                    }

                    Section("Vehicle Detection") {
                        Toggle("Auto-select this vehicle from detector", isOn: $vehicleDetectionEnabled)

                        if vehicleDetectionEnabled {
                            Toggle("Use CarPlay", isOn: $useCarPlayDetection)
                            Toggle("Use connected car audio", isOn: $useAudioRouteDetection)
                            Toggle("Use Bluetooth peripheral or beacon", isOn: $useBluetoothPeripheralDetection)

                            if useAudioRouteDetection {
                                Button("Detect Connected Car Audio") {
                                    vehicleConnectionManager.refreshAudioRouteSnapshot()
                                }

                                Picker("Connected audio device", selection: $selectedAudioRouteIdentifier) {
                                    Text("Select connected audio device").tag("")
                                    ForEach(vehicleConnectionManager.connectedAudioRoutes) { route in
                                        Text(route.summary).tag(route.id)
                                    }
                                }
                                .onChange(of: selectedAudioRouteIdentifier) { _, newValue in
                                    selectedAudioRouteName = vehicleConnectionManager.connectedAudioRoutes
                                        .first(where: { $0.id == newValue })?
                                        .name ?? selectedAudioRouteName
                                }

                                Text("Connect your phone to the vehicle for calls or media, detect the active route, then assign it to this vehicle.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if useBluetoothPeripheralDetection {
                                Button("Request Bluetooth Access") {
                                    vehicleConnectionManager.requestBluetoothAccessIfNeeded()
                                }

                                Picker("Bluetooth device", selection: $selectedBluetoothPeripheralIdentifier) {
                                    Text("Select a device").tag("")
                                    ForEach(vehicleConnectionManager.visibleBluetoothDevices) { device in
                                        Text(device.name).tag(device.id.uuidString)
                                    }
                                }

                                Text("Choose the beacon or Bluetooth peripheral assigned to this vehicle. The app will auto-select this vehicle when that detector is nearby.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                if vehicleConnectionManager.hiddenUnknownBluetoothDeviceCount > 0 {
                                    Text("\(vehicleConnectionManager.hiddenUnknownBluetoothDeviceCount) unnamed device(s) hidden to keep the list clean.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(vehicleSheetTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismissVehicleSheet()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(vehicleSaveButtonTitle) {
                            saveVehicle()
                        }
                        .disabled(!canSaveVehicle)
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingAddDriver) {
            NavigationStack {
                Form {
                    TextField("Name", text: $driverName)
                    DatePicker("Date of birth", selection: $driverDateOfBirth, displayedComponents: .date)
                    TextField("Licence number", text: $licenceNumber)
                    TextField("Licence class", text: $driverLicenceClass)
                    TextField("Email", text: $driverEmailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Phone", text: $driverPhoneNumber)
                        .keyboardType(.phonePad)

                }
                .confirmationDialog(
                    "Add Driver As Employee?",
                    isPresented: Binding(
                        get: { pendingDriverEmployeeInvite != nil },
                        set: { if !$0 { pendingDriverEmployeeInvite = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    if let pendingDriverEmployeeInvite {
                        Button("Add As Employee & Send Invite") {
                            inviteDriverAsEmployee(pendingDriverEmployeeInvite)
                        }
                    }
                    Button("Driver Only", role: .cancel) {
                        pendingDriverEmployeeInvite = nil
                        dismissDriverSheet()
                    }
                } message: {
                    if let pendingDriverEmployeeInvite {
                        Text("Send an employee invite to \(pendingDriverEmployeeInvite.emailAddress)?")
                    }
                }
                .navigationTitle(driverSheetTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismissDriverSheet()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(driverSaveButtonTitle) {
                            saveDriver()
                        }
                        .disabled(!canSaveDriver)
                    }
                }
            }
        }
        .sheet(item: $vehiclePendingArchive) { vehicle in
            NavigationStack {
                Form {
                    Section("Archive Vehicle") {
                        Text(vehicle.displayName)
                            .font(.headline)
                        Picker("Reason", selection: $vehicleArchiveReason) {
                            ForEach(VehicleArchiveReason.allCases) { reason in
                                Text(reason.title).tag(reason)
                            }
                        }

                        if vehicleArchiveReason == .other {
                            TextField("Reason", text: $customVehicleArchiveReason)
                        }
                    }

                    Section("Retention") {
                        Text(vehicleArchiveRetentionMessage(for: vehicle))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Delete Vehicle")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            vehiclePendingArchive = nil
                            resetVehicleArchiveDraft()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Archive") {
                            archiveVehicle(vehicle)
                        }
                        .disabled(!store.canModifyDemoData || (vehicleArchiveReason == .other && customVehicleArchiveReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                }
            }
        }
        .alert("Delete All App Data?", isPresented: $isPresentingFactoryResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                onFactoryReset()
            }
        } message: {
            Text("This permanently deletes all app data stored on this device and signs you out. iCloud backups are not deleted.")
        }
        .alert("Clear App Records?", isPresented: $isPresentingClearRecordedDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Records", role: .destructive) {
                onClearRecordedAppData()
            }
        } message: {
            Text("This deletes trips, fuel logs, maintenance records, vehicles, drivers, allowances, and app logs, but keeps your sign-in and preferences.")
        }
        .onChange(of: tripTracker.backgroundTripTrackingEnabled, initial: false) { _, isEnabled in
            guard isEnabled else {
                return
            }

            tripTracker.requestPermissionsForCurrentTrackingMode()
            store.addLog("Background trip tracking enabled")
        }
    }

    private var activeVehicleBinding: Binding<UUID?> {
        Binding(
            get: { store.activeVehicleID },
            set: { store.activeVehicleID = $0 }
        )
    }

    private var selectedCountryBinding: Binding<SupportedCountry> {
        Binding(
            get: { store.selectedCountry },
            set: { store.applyCountryPreferences($0) }
        )
    }

    private var activeDriverBinding: Binding<UUID?> {
        Binding(
            get: { store.activeDriverID },
            set: { store.activeDriverID = $0 }
        )
    }

    private var vehicleSummary: String {
        if let activeVehicle = store.activeVehicle {
            return "\(store.availableVehicles.count) visible • Active: \(activeVehicle.displayName)"
        }

        return store.availableVehicles.isEmpty ? "No vehicles available" : "\(store.availableVehicles.count) vehicles"
    }

    private var driverSummary: String {
        if let activeDriver = store.activeDriver {
            return "\(store.availableDrivers.count) visible • Active: \(activeDriver.name)"
        }

        return store.availableDrivers.isEmpty ? "No drivers available" : "\(store.availableDrivers.count) drivers"
    }

    private var vehicleDetectionSummary: String {
        let enabledVehicleCount = store.vehicles.filter(\.detectionProfile.isEnabled).count
        let matchedVehicleName = store.vehicle(for: vehicleConnectionManager.matchedVehicleID)?.displayName ?? "None"

        if enabledVehicleCount == 0 {
            return "Not configured"
        }

        return "\(enabledVehicleCount) vehicle\(enabledVehicleCount == 1 ? "" : "s") • Active: \(matchedVehicleName)"
    }

    private var organizationSummary: String {
        guard let organization = store.currentOrganization,
              let membership = store.currentUserOrganizationMembership else {
            return isBusinessContext ? "Business account setup pending" : "Personal account"
        }

        return "\(organization.name) • \(membership.role.title)"
    }

    private var isBusinessContext: Bool {
        AppFeatureFlags.businessSubscriptionsEnabled
            && (
                store.accountSubscriptionType == .business
                    || subscriptionManager.selectedAccountType == .business
                    || subscriptionManager.hasBusinessSubscription
            )
    }

    private var hasBusinessPortalAccess: Bool {
        AppFeatureFlags.businessSubscriptionsEnabled
            && (
                subscriptionManager.hasBusinessSubscription
                    || store.isBusinessAccountActive
                    || store.currentUserOrganizationMembership != nil
            )
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private var vehicleSheetTitle: String {
        editingVehicleID == nil ? "Add Vehicle" : "Edit Vehicle"
    }

    private var vehicleSaveButtonTitle: String {
        editingVehicleID == nil ? "Save" : "Update"
    }

    private var driverSheetTitle: String {
        editingDriverID == nil ? "Add Driver" : "Edit Driver"
    }

    private var driverSaveButtonTitle: String {
        editingDriverID == nil ? "Save" : "Update"
    }

    private var canSaveVehicle: Bool {
        guard
            !make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !numberPlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            parseDecimalInput(startingOdometerReading) != nil
        else {
            return false
        }

        if receivesAllowance && parseDecimalInput(allowanceAmount) == nil {
            return false
        }

        if hasVehiclePayment && parseDecimalInput(vehiclePaymentAmount) == nil {
            return false
        }

        if hasInsurancePayment && parseDecimalInput(insuranceAmount) == nil {
            return false
        }

        if vehicleDetectionEnabled {
            if !useCarPlayDetection && !useAudioRouteDetection && !useBluetoothPeripheralDetection {
                return false
            }

            if useAudioRouteDetection && selectedAudioRouteIdentifier.isEmpty {
                return false
            }

            if useBluetoothPeripheralDetection && selectedBluetoothPeripheralIdentifier.isEmpty {
                return false
            }
        }

        for expense in otherScheduledExpenses {
            if expense.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parseDecimalInput(expense.amount) == nil {
                return false
            }
        }

        return true
    }

    private var canSaveDriver: Bool {
        let hasRequired = !driverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !licenceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let email = driverEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailPattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        let emailIsValid = email.isEmpty || email.range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil
        return hasRequired && emailIsValid
    }

    private var persistenceSnapshot: AppPersistenceSnapshot {
        AppPersistenceSnapshot(
            store: store.persistenceSnapshot,
            tripTracker: tripTracker.persistenceSnapshot
        )
    }

    private func saveVehicle() {
        guard let odometerReading = parseDecimalInput(startingOdometerReading) else {
            return
        }

        let allowancePlan = receivesAllowance ? makeAllowancePlan(amount: allowanceAmount, frequency: allowanceFrequency, startDate: allowanceStartDate) : nil
        let paymentPlan = hasVehiclePayment ? makePaymentPlan() : nil
        let insurancePlan = hasInsurancePayment ? makeAllowancePlan(amount: insuranceAmount, frequency: insuranceFrequency, startDate: insuranceStartDate) : nil
        let scheduledExpenses = otherScheduledExpenses.compactMap(makeRecurringExpense(from:))
        let detectionProfile = VehicleDetectionProfile(
            isEnabled: vehicleDetectionEnabled,
            allowedSources: Set([
                useCarPlayDetection ? VehicleConnectionSource.carPlay : nil,
                useAudioRouteDetection ? VehicleConnectionSource.audioRoute : nil,
                useBluetoothPeripheralDetection ? VehicleConnectionSource.bluetoothPeripheral : nil
            ].compactMap { $0 }),
            bluetoothPeripheralIdentifier: useBluetoothPeripheralDetection ? selectedBluetoothPeripheralIdentifier : nil,
            bluetoothPeripheralName: vehicleConnectionManager.discoveredBluetoothDevices
                .first(where: { $0.id.uuidString == selectedBluetoothPeripheralIdentifier })?
                .name ?? "",
            audioRouteIdentifier: useAudioRouteDetection ? selectedAudioRouteIdentifier : nil,
            audioRouteName: useAudioRouteDetection ? resolvedSelectedAudioRouteName() : ""
        )

        let vehicle = VehicleProfile(
            id: editingVehicleID ?? UUID(),
            profileName: profileName.trimmingCharacters(in: .whitespacesAndNewlines),
            make: make.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            color: color.trimmingCharacters(in: .whitespacesAndNewlines),
            numberPlate: numberPlate.trimmingCharacters(in: .whitespacesAndNewlines),
            fleetNumber: fleetNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            startingOdometerReading: odometerReading,
            ownershipType: ownershipType,
            allowancePlan: allowancePlan,
            paymentPlan: paymentPlan,
            insurancePlan: insurancePlan,
            otherScheduledExpenses: scheduledExpenses,
            detectionProfile: detectionProfile
        )

        if editingVehicleID == nil {
            store.addVehicle(vehicle)
        } else {
            store.updateVehicle(vehicle)
        }

        dismissVehicleSheet()
    }

    private func dismissVehicleSheet() {
        isPresentingAddVehicle = false
        editingVehicleID = nil
        profileName = ""
        make = ""
        model = ""
        color = ""
        numberPlate = ""
        fleetNumber = ""
        startingOdometerReading = ""
        ownershipType = .personal
        receivesAllowance = false
        allowanceAmount = ""
        allowanceFrequency = .monthly
        allowanceStartDate = .now
        hasVehiclePayment = false
        vehiclePaymentKind = .finance
        vehiclePaymentAmount = ""
        vehiclePaymentFrequency = .monthly
        vehiclePaymentStartDate = .now
        hasInsurancePayment = false
        insuranceAmount = ""
        insuranceFrequency = .monthly
        insuranceStartDate = .now
        otherScheduledExpenses = []
        vehicleDetectionEnabled = false
        useCarPlayDetection = false
        useAudioRouteDetection = false
        useBluetoothPeripheralDetection = false
        selectedAudioRouteIdentifier = ""
        selectedAudioRouteName = ""
        selectedBluetoothPeripheralIdentifier = ""
    }

    @ViewBuilder
    private func recurringAmountFields(
        amountTitle: String,
        amount: Binding<String>,
        frequency: Binding<VehicleScheduleFrequency>,
        startDate: Binding<Date>,
        dateTitle: String
    ) -> some View {
        TextField(amountTitle, text: amount)
            .keyboardType(.decimalPad)

        Picker("Frequency", selection: frequency) {
            ForEach(VehicleScheduleFrequency.allCases) { option in
                Text(option.title).tag(option)
            }
        }

        DatePicker(dateTitle, selection: startDate, displayedComponents: .date)
    }

    private func makeAllowancePlan(
        amount: String,
        frequency: VehicleScheduleFrequency,
        startDate: Date
    ) -> VehicleAllowancePlan? {
        guard let amount = parseDecimalInput(amount) else {
            return nil
        }

        return VehicleAllowancePlan(
            amount: amount,
            schedule: VehicleRecurringSchedule(
                frequency: frequency,
                startDate: startDate
            )
        )
    }

    private func makePaymentPlan() -> VehiclePaymentPlan? {
        guard let amount = parseDecimalInput(vehiclePaymentAmount) else {
            return nil
        }

        return VehiclePaymentPlan(
            kind: vehiclePaymentKind,
            amount: amount,
            schedule: VehicleRecurringSchedule(
                frequency: vehiclePaymentFrequency,
                startDate: vehiclePaymentStartDate
            )
        )
    }

    private func makeRecurringExpense(from draft: ScheduledExpenseDraft) -> VehicleRecurringExpense? {
        guard
            let amount = parseDecimalInput(draft.amount),
            !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return VehicleRecurringExpense(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            schedule: VehicleRecurringSchedule(
                frequency: draft.frequency,
                startDate: draft.startDate
            )
        )
    }

    private func resolvedSelectedAudioRouteName() -> String {
        if let route = vehicleConnectionManager.connectedAudioRoutes.first(where: { $0.id == selectedAudioRouteIdentifier }) {
            return route.name
        }

        return selectedAudioRouteName
    }

    private func saveDriver() {
        let isNewDriver = editingDriverID == nil
        let normalizedDriverEmail = driverEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let driver = DriverProfile(
            id: editingDriverID ?? UUID(),
            name: driverName,
            dateOfBirth: driverDateOfBirth,
            licenceNumber: licenceNumber,
            licenceClass: driverLicenceClass,
            emailAddress: normalizedDriverEmail,
            phoneNumber: driverPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            permissions: []
        )

        if editingDriverID == nil {
            store.addDriver(driver)
        } else {
            store.updateDriver(driver)
        }

        if shouldPromptToInviteDriverAsEmployee(driver: driver, isNewDriver: isNewDriver) {
            pendingDriverEmployeeInvite = driver
            return
        }

        dismissDriverSheet()
    }

    private func shouldPromptToInviteDriverAsEmployee(driver: DriverProfile, isNewDriver: Bool) -> Bool {
        guard isNewDriver else {
            return false
        }

        let isBusinessContext = AppFeatureFlags.businessSubscriptionsEnabled
            && (
                store.accountSubscriptionType == .business
                    || subscriptionManager.selectedAccountType == .business
                    || subscriptionManager.hasBusinessSubscription
            )
        guard isBusinessContext, isValidEmailAddress(driver.emailAddress) else {
            return false
        }

        return store.currentOrganizationMembers.first(where: {
            $0.normalizedEmailAddress == driver.emailAddress
        }) == nil
    }

    private func inviteDriverAsEmployee(_ driver: DriverProfile) {
        let normalizedDriverEmail = driver.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmailAddress(normalizedDriverEmail),
              let organizationID = ensureBusinessOrganizationSetupIfNeeded() else {
            pendingDriverEmployeeInvite = nil
            return
        }

        let membership: OrganizationMembership
        if let existingMembership = store.currentOrganizationMembers.first(where: {
            $0.normalizedEmailAddress == normalizedDriverEmail
        }) {
            var updatedMembership = existingMembership
            updatedMembership.displayName = driver.name
            updatedMembership.role = .employee
            updatedMembership.status = .invited
            updatedMembership.assignedDriverID = driver.id
            updatedMembership.permissions = driver.permissions
            updatedMembership.invitedAt = .now
            updatedMembership.activatedAt = nil
            updatedMembership.removedAt = nil
            store.upsertOrganizationMembership(updatedMembership)
            membership = updatedMembership
        } else {
            let newMembership = OrganizationMembership(
                organizationID: organizationID,
                emailAddress: normalizedDriverEmail,
                displayName: driver.name,
                role: .employee,
                status: .invited,
                assignedVehicleIDs: [],
                assignedDriverID: driver.id,
                permissions: driver.permissions,
                invitedAt: .now,
                activatedAt: nil,
                removedAt: nil
            )
            store.upsertOrganizationMembership(newMembership)
            membership = newMembership
        }

        deliverDriverInvite(for: membership)
    }

    private func deliverDriverInvite(for membership: OrganizationMembership) {
        Task { @MainActor in
            let wasDeliveredByBackend = await sendInviteUsingCloudFunction(for: membership)
            if !wasDeliveredByBackend {
                openDriverInviteEmail(for: membership)
            }
            pendingDriverEmployeeInvite = nil
            dismissDriverSheet()
        }
    }

    private func openDriverInviteEmail(for membership: OrganizationMembership) {
        guard let organization = store.currentOrganization else {
            return
        }

        let subject = "Invitation to join \(organization.name) on Meerkat Mileage Tracker"
        let body = """
        Hi \(membership.displayName.isEmpty ? "there" : membership.displayName),

        You've been invited to join \(organization.name) in Meerkat Mileage Tracker.

        Open the app and sign in with \(membership.emailAddress) to accept your invitation.
        """

        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(membership.emailAddress)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return
        }

        openURL(url)
    }

    private func sendInviteUsingCloudFunction(for membership: OrganizationMembership) async -> Bool {
        #if canImport(FirebaseFunctions) && canImport(FirebaseMessagingInterop)
        guard let organization = store.organizations.first(where: { $0.id == membership.organizationID }) else {
            return false
        }

        let payload: [String: Any] = [
            "organizationID": organization.id.uuidString,
            "inviteeEmail": membership.emailAddress,
            "displayName": membership.displayName
        ]

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPSCallableResult, Error>) in
                Functions.functions().httpsCallable("createOrganizationInvite").call(payload) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirebaseFunctions", code: -1))
                    }
                }
            }
            return true
        } catch {
            store.addLog("Cloud invite delivery failed. Falling back to email compose.")
            return false
        }
        #else
        return false
        #endif
    }

    @discardableResult
    private func ensureBusinessOrganizationSetupIfNeeded() -> UUID? {
        let hasBusinessAccess = subscriptionManager.hasBusinessSubscription
            || store.isBusinessAccountActive
            || store.currentUserOrganizationMembership != nil
        guard hasBusinessAccess else {
            return nil
        }

        let normalizedManagerEmail = resolvedManagerEmailAddress()
        guard isValidEmailAddress(normalizedManagerEmail) else {
            return nil
        }

        let organizationName = store.businessProfile?.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (store.businessProfile?.businessName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Business Organization")
            : "\(store.userName.trimmingCharacters(in: .whitespacesAndNewlines)) Organization"
        let organizationPlan: OrganizationSubscriptionPlan = subscriptionManager.activeTier == .businessYearly ? .businessYearly : .businessMonthly
        let organizationBillingStatus: OrganizationBillingStatus = subscriptionManager.hasBusinessSubscription ? .active : .pendingPayment

        var organization = store.currentOrganization
            ?? OrganizationProfile(name: organizationName, plan: organizationPlan, billingStatus: organizationBillingStatus, expiresAt: nil)
        organization.name = organizationName
        organization.plan = organizationPlan
        organization.billingStatus = organizationBillingStatus
        store.upsertOrganization(organization)
        store.activateOrganization(organization.id)

        if let existingManagerMembership = store.organizationMemberships.first(where: {
            $0.organizationID == organization.id && $0.normalizedEmailAddress == normalizedManagerEmail
        }) {
            var updatedMembership = existingManagerMembership
            updatedMembership.displayName = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedMembership.role = .accountManager
            updatedMembership.status = .active
            updatedMembership.permissions = []
            updatedMembership.activatedAt = .now
            updatedMembership.removedAt = nil
            store.upsertOrganizationMembership(updatedMembership)
        } else {
            let managerMembership = OrganizationMembership(
                organizationID: organization.id,
                emailAddress: normalizedManagerEmail,
                displayName: store.userName.trimmingCharacters(in: .whitespacesAndNewlines),
                role: .accountManager,
                status: .active,
                assignedVehicleIDs: [],
                assignedDriverID: nil,
                permissions: [],
                invitedAt: .now,
                activatedAt: .now,
                removedAt: nil
            )
            store.upsertOrganizationMembership(managerMembership)
        }

        return organization.id
    }

    private func resolvedManagerEmailAddress() -> String {
        let storeEmail = store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isValidEmailAddress(storeEmail) {
            return storeEmail
        }

        let signedInEmail = authSession.signedInEmailAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if isValidEmailAddress(signedInEmail) {
            if store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.emailAddress = signedInEmail
            }
            return signedInEmail
        }

        let appleEmail = authSession.appleEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isValidEmailAddress(appleEmail) {
            if store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.emailAddress = appleEmail
            }
            return appleEmail
        }

        return storeEmail
    }

    private func isValidEmailAddress(_ emailAddress: String) -> Bool {
        let emailPattern = #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#
        return emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: emailPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func dismissDriverSheet() {
        isPresentingAddDriver = false
        editingDriverID = nil
        driverName = ""
        driverDateOfBirth = .now
        licenceNumber = ""
        driverLicenceClass = ""
        driverEmailAddress = ""
        driverPhoneNumber = ""
    }

    private func startAddingVehicle() {
        dismissVehicleSheet()
        isPresentingAddVehicle = true
    }

    private func beginEditingVehicle(_ vehicle: VehicleProfile) {
        editingVehicleID = vehicle.id
        profileName = vehicle.profileName
        make = vehicle.make
        model = vehicle.model
        color = vehicle.color
        numberPlate = vehicle.numberPlate
        fleetNumber = vehicle.fleetNumber
        startingOdometerReading = formatDecimalInput(vehicle.startingOdometerReading, fractionDigits: 1)
        ownershipType = vehicle.ownershipType
        receivesAllowance = vehicle.allowancePlan != nil
        allowanceAmount = vehicle.allowancePlan.map { formatDecimalInput($0.amount, fractionDigits: 2) } ?? ""
        allowanceFrequency = vehicle.allowancePlan?.schedule.frequency ?? .monthly
        allowanceStartDate = vehicle.allowancePlan?.schedule.startDate ?? .now
        hasVehiclePayment = vehicle.paymentPlan != nil
        vehiclePaymentKind = vehicle.paymentPlan?.kind ?? .finance
        vehiclePaymentAmount = vehicle.paymentPlan.map { formatDecimalInput($0.amount, fractionDigits: 2) } ?? ""
        vehiclePaymentFrequency = vehicle.paymentPlan?.schedule.frequency ?? .monthly
        vehiclePaymentStartDate = vehicle.paymentPlan?.schedule.startDate ?? .now
        hasInsurancePayment = vehicle.insurancePlan != nil
        insuranceAmount = vehicle.insurancePlan.map { formatDecimalInput($0.amount, fractionDigits: 2) } ?? ""
        insuranceFrequency = vehicle.insurancePlan?.schedule.frequency ?? .monthly
        insuranceStartDate = vehicle.insurancePlan?.schedule.startDate ?? .now
        vehicleDetectionEnabled = vehicle.detectionProfile.isEnabled
        useCarPlayDetection = vehicle.detectionProfile.usesCarPlay
        useAudioRouteDetection = vehicle.detectionProfile.usesAudioRoute
        useBluetoothPeripheralDetection = vehicle.detectionProfile.usesBluetoothPeripheral
        selectedAudioRouteIdentifier = vehicle.detectionProfile.audioRouteIdentifier ?? ""
        selectedAudioRouteName = vehicle.detectionProfile.audioRouteName
        selectedBluetoothPeripheralIdentifier = vehicle.detectionProfile.bluetoothPeripheralIdentifier ?? ""
        otherScheduledExpenses = vehicle.otherScheduledExpenses.map {
            ScheduledExpenseDraft(
                id: $0.id,
                title: $0.title,
                amount: formatDecimalInput($0.amount, fractionDigits: 2),
                frequency: $0.schedule.frequency,
                startDate: $0.schedule.startDate
            )
        }
        isPresentingAddVehicle = true
    }

    private func parseDecimalInput(_ value: String) -> Double? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        if let number = formatter.number(from: trimmedValue) {
            return number.doubleValue
        }

        let normalizedValue = trimmedValue.replacingOccurrences(of: ",", with: "")
        return Double(normalizedValue)
    }

    private func formatDecimalInput(_ value: Double, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value))
            ?? value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    private func beginArchivingVehicle(_ vehicle: VehicleProfile) {
        vehiclePendingArchive = vehicle
        resetVehicleArchiveDraft()
    }

    private func archiveVehicle(_ vehicle: VehicleProfile) {
        let reason = vehicleArchiveReason == .other
            ? customVehicleArchiveReason.trimmingCharacters(in: .whitespacesAndNewlines)
            : vehicleArchiveReason.title
        store.archiveVehicle(id: vehicle.id, reason: reason)
        vehiclePendingArchive = nil
        resetVehicleArchiveDraft()
    }

    private func resetVehicleArchiveDraft() {
        vehicleArchiveReason = .sold
        customVehicleArchiveReason = ""
    }

    private func vehicleArchiveRetentionMessage(for vehicle: VehicleProfile) -> String {
        let associationCount = store.vehicleAssociationCount(for: vehicle.id)
        if associationCount > 0 {
            return "This vehicle has \(associationCount) linked record\(associationCount == 1 ? "" : "s"). It will remain archived with its historical data for at least 7 years for tax record retention."
        }

        return "The vehicle will be removed from active use and kept in the archive."
    }

    private func startAddingDriver() {
        dismissDriverSheet()
        isPresentingAddDriver = true
    }

    private func beginEditingDriver(_ driver: DriverProfile) {
        editingDriverID = driver.id
        driverName = driver.name
        driverDateOfBirth = driver.dateOfBirth
        licenceNumber = driver.licenceNumber
        driverLicenceClass = driver.licenceClass
        driverEmailAddress = driver.emailAddress
        driverPhoneNumber = driver.phoneNumber
        isPresentingAddDriver = true
    }

    private func deleteDriver(_ driver: DriverProfile) {
        store.deleteDriver(id: driver.id)
    }

    private func restoreFromCloud() async {
        guard let snapshot = await cloudSync.restoreFromCloud() else {
            return
        }

        SharedAppModel.shared.applyRestoredSnapshot(snapshot)
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SettingsProfilePreferencesView: View {
    @Bindable var store: MileageStore
    let selectedCountryBinding: Binding<SupportedCountry>

    private var availableFuelEconomyFormats: [FuelEconomyFormat] {
        switch store.unitSystem {
        case .miles:
            return [.milesPerGallon]
        case .kilometers:
            return [.kilometersPerLiter, .litersPer100Kilometers]
        }
    }

    private var fuelEconomyFormatBinding: Binding<FuelEconomyFormat> {
        Binding(
            get: { store.fuelEconomyFormat.compatibleFormat(for: store.unitSystem) },
            set: { store.fuelEconomyFormat = $0.compatibleFormat(for: store.unitSystem) }
        )
    }

    var body: some View {
        Form {
            Section("Account Setup") {
                Picker("Country", selection: selectedCountryBinding) {
                    ForEach(SupportedCountry.allCases) { country in
                        Text(country.rawValue).tag(country)
                    }
                }

                TextField("User name", text: $store.userName)
                    .textInputAutocapitalization(.words)

                TextField("Email address", text: $store.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Preferences") {
                Picker("Currency", selection: $store.preferredCurrency) {
                    ForEach(PreferredCurrency.allCases) { currency in
                        Text("\(currency.rawValue) • \(currency.title)").tag(currency)
                    }
                }

                Picker("Distance", selection: $store.unitSystem) {
                    ForEach(DistanceUnitSystem.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }

                Picker("Fuel Volume", selection: $store.fuelVolumeUnit) {
                    ForEach(FuelVolumeUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }

                Picker("Fuel Economy", selection: fuelEconomyFormatBinding) {
                    ForEach(availableFuelEconomyFormats) { format in
                        Text(format.title).tag(format)
                    }
                }
            }
        }
        .navigationTitle("Account Setup")
    }
}

private struct SettingsVehiclesView: View {
    @Bindable var store: MileageStore
    @Bindable var vehicleConnectionManager: VehicleConnectionManager
    let activeVehicleBinding: Binding<UUID?>
    let onAddVehicle: () -> Void
    let onEditVehicle: (VehicleProfile) -> Void
    let onDeleteVehicle: (VehicleProfile) -> Void

    var body: some View {
        Form {
            Section("Vehicles") {
                if store.availableVehicles.isEmpty {
                    Text(store.isBusinessAccountActive ? "No vehicles are assigned to this user." : "No vehicles added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Active Vehicle", selection: activeVehicleBinding) {
                        ForEach(store.availableVehicles) { vehicle in
                            Text(vehicle.displayName).tag(Optional(vehicle.id))
                        }
                    }

                    ForEach(store.availableVehicles) { vehicle in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(vehicle.displayName)
                                    .font(.headline)
                                Spacer()
                                Text(vehicle.ownershipType.title)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(.secondarySystemFill), in: Capsule())
                            }

                            Text(vehicle.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("Color: \(vehicle.color) • Current odometer: \(store.currentOdometerReading(for: vehicle.id).formatted(.number.precision(.fractionLength(1))))")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)

                            if vehicle.allowancePlan != nil || vehicle.paymentPlan != nil || vehicle.insurancePlan != nil || !vehicle.otherScheduledExpenses.isEmpty {
                                Text(vehicleFinancialSummary(vehicle))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            if vehicle.detectionProfile.isEnabled {
                                let isMatchedVehicle = vehicleConnectionManager.matchedVehicleID == vehicle.id
                                Text("Detection: \(vehicle.detectionProfile.summaryText)\(isMatchedVehicle ? " • Active now" : "")")
                                    .font(.footnote)
                                    .foregroundStyle(isMatchedVehicle ? .green : .secondary)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    onEditVehicle(vehicle)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!store.canCurrentUserManageVehicles)

                                Button(role: .destructive) {
                                    onDeleteVehicle(vehicle)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!store.canCurrentUserManageVehicles)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button {
                    onAddVehicle()
                } label: {
                    Label("Add Vehicle", systemImage: "plus")
                }
                .disabled(!store.canCurrentUserManageVehicles)
            }

            if !store.archivedVehicles.isEmpty {
                Section("Archived Vehicles") {
                    ForEach(store.archivedVehicles) { vehicle in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vehicle.displayName)
                                .font(.headline)
                            Text(vehicle.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(archivedVehicleSummary(vehicle))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Vehicles")
    }

    private func vehicleFinancialSummary(_ vehicle: VehicleProfile) -> String {
        var items: [String] = []

        if vehicle.allowancePlan != nil {
            items.append("Allowance")
        }

        if let paymentPlan = vehicle.paymentPlan {
            items.append(paymentPlan.kind.title)
        }

        if vehicle.insurancePlan != nil {
            items.append("Insurance")
        }

        if !vehicle.otherScheduledExpenses.isEmpty {
            items.append("\(vehicle.otherScheduledExpenses.count) other expense\(vehicle.otherScheduledExpenses.count == 1 ? "" : "s")")
        }

        return items.joined(separator: " • ")
    }

    private func archivedVehicleSummary(_ vehicle: VehicleProfile) -> String {
        let archivedDate = vehicle.archivedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date"
        let reason = vehicle.archiveReason ?? "Archived"
        return "\(reason) • Archived \(archivedDate)"
    }
}

private struct SettingsDriversView: View {
    @Bindable var store: MileageStore
    let activeDriverBinding: Binding<UUID?>
    let onAddDriver: () -> Void
    let onEditDriver: (DriverProfile) -> Void
    let onDeleteDriver: (DriverProfile) -> Void
    @State private var driverPendingDeletion: DriverProfile?

    var body: some View {
        Form {
            Section("Drivers") {
                if store.availableDrivers.isEmpty {
                    Text(store.isBusinessAccountActive ? "No drivers are assigned to this user." : "No drivers added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Active Driver", selection: activeDriverBinding) {
                        ForEach(store.availableDrivers) { driver in
                            Text(driver.name).tag(Optional(driver.id))
                        }
                    }

                    ForEach(store.availableDrivers) { driver in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(driver.name)
                                .font(.headline)
                            Text(driver.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button {
                                    onEditDriver(driver)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!store.canCurrentUserManageDrivers)

                                Button(role: .destructive) {
                                    driverPendingDeletion = driver
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .disabled(!store.canCurrentUserManageDrivers)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button {
                    onAddDriver()
                } label: {
                    Label("Add Driver", systemImage: "plus")
                }
                .disabled(!store.canCurrentUserManageDrivers)
            }

            if !store.archivedDrivers.isEmpty {
                Section("Archived Drivers") {
                    ForEach(store.archivedDrivers) { driver in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(driver.name)
                                .font(.headline)
                            Text(driver.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Archived \(driver.archivedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Drivers")
        .alert("Delete Driver?", isPresented: Binding(
            get: { driverPendingDeletion != nil },
            set: { if !$0 { driverPendingDeletion = nil } }
        ), presenting: driverPendingDeletion) { driver in
            Button("Cancel", role: .cancel) {
                driverPendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                onDeleteDriver(driver)
                driverPendingDeletion = nil
            }
            .disabled(!store.canModifyDemoData)
        } message: { driver in
            Text(driverDeleteMessage(for: driver))
        }
    }

    private func driverDeleteMessage(for driver: DriverProfile) -> String {
        let associationCount = store.driverAssociationCount(for: driver.id)
        if associationCount > 0 {
            return "\(driver.name) is linked to \(associationCount) trip\(associationCount == 1 ? "" : "s"). Deleting the driver removes it from the driver list, but existing trip records keep the copied driver details."
        }

        return "\(driver.name) will be removed from the driver list."
    }
}

private struct SettingsBusinessPortalView: View {
    private enum PortalFocus: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case vehicles = "Vehicles"
        case drivers = "Drivers / Employees"

        var id: String { rawValue }
    }

    @Bindable var store: MileageStore
    @State private var focus: PortalFocus = .overview
    @State private var selectedVehicleID: UUID?
    @State private var selectedDriverID: UUID?

    private var canSeeAllBusinessData: Bool {
        store.currentUserOrganizationMembership?.role == .accountManager
    }

    private var portalVehicles: [VehicleProfile] {
        let source = canSeeAllBusinessData ? store.vehicles : store.availableVehicles
        return source.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var portalDrivers: [DriverProfile] {
        let source = canSeeAllBusinessData ? store.drivers : store.availableDrivers
        return source.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedVehicles: [VehicleProfile] {
        guard let selectedVehicleID else {
            return portalVehicles
        }
        return portalVehicles.filter { $0.id == selectedVehicleID }
    }

    private var displayedDrivers: [DriverProfile] {
        guard let selectedDriverID else {
            return portalDrivers
        }
        return portalDrivers.filter { $0.id == selectedDriverID }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meerkat - Milage Tracker for Business")
                        .font(.headline)
                    Text("Business subscription portal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if canSeeAllBusinessData {
                        Text("Viewing organization-wide vehicles and drivers.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Showing your assigned vehicles and driver profile.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Data View") {
                Picker("Focus", selection: $focus) {
                    ForEach(PortalFocus.allCases) { entry in
                        Text(entry.rawValue).tag(entry)
                    }
                }
                .pickerStyle(.segmented)

                if focus != .drivers {
                    Picker("Vehicle", selection: $selectedVehicleID) {
                        Text("All vehicles").tag(Optional<UUID>.none)
                        ForEach(portalVehicles) { vehicle in
                            Text(vehicle.displayName).tag(Optional(vehicle.id))
                        }
                    }
                }

                if focus != .vehicles {
                    Picker("Driver / Employee", selection: $selectedDriverID) {
                        Text("All drivers").tag(Optional<UUID>.none)
                        ForEach(portalDrivers) { driver in
                            Text(driver.name).tag(Optional(driver.id))
                        }
                    }
                }
            }

            if focus != .drivers {
                Section("Vehicles (\(displayedVehicles.count))") {
                    if displayedVehicles.isEmpty {
                        Text("No vehicles available.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(displayedVehicles) { vehicle in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vehicle.displayName)
                                .font(.headline)
                            Text(vehicle.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(vehicleMetricsText(for: vehicle))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if focus != .vehicles {
                Section("Drivers / Employees (\(displayedDrivers.count))") {
                    if displayedDrivers.isEmpty {
                        Text("No drivers available.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(displayedDrivers) { driver in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(driver.name)
                                .font(.headline)
                            Text(driver.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(driverMetricsText(for: driver))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Business Portal")
        .onAppear {
            if selectedVehicleID == nil {
                selectedVehicleID = store.activeVehicleID
            }
            if selectedDriverID == nil {
                selectedDriverID = store.activeDriverID
            }
        }
    }

    private func vehicleMetricsText(for vehicle: VehicleProfile) -> String {
        let relatedTrips = store.trips.filter { $0.vehicleID == vehicle.id }
        let businessTrips = relatedTrips.filter { $0.type == .business }
        let totalDistance = relatedTrips.reduce(0) { $0 + $1.distanceMeters }
        let lastTripDate = relatedTrips.max(by: { $0.date < $1.date })?.date
        let lastTripText = lastTripDate?.formatted(date: .abbreviated, time: .omitted) ?? "No trips"
        let odometerText = store.currentOdometerReading(for: vehicle.id).formatted(.number.precision(.fractionLength(1)))

        return "\(relatedTrips.count) trips • \(businessTrips.count) business • \(store.unitSystem.distanceString(for: totalDistance)) • Odometer \(odometerText) • Last trip \(lastTripText)"
    }

    private func driverMetricsText(for driver: DriverProfile) -> String {
        let relatedTrips = store.trips.filter { $0.driverID == driver.id }
        let businessTrips = relatedTrips.filter { $0.type == .business }
        let totalDistance = relatedTrips.reduce(0) { $0 + $1.distanceMeters }
        let lastTripDate = relatedTrips.max(by: { $0.date < $1.date })?.date
        let lastTripText = lastTripDate?.formatted(date: .abbreviated, time: .omitted) ?? "No trips"

        return "\(relatedTrips.count) trips • \(businessTrips.count) business • \(store.unitSystem.distanceString(for: totalDistance)) • Last trip \(lastTripText)"
    }
}

private struct SettingsOrganizationView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MileageStore
    @Bindable var subscriptionManager: SubscriptionManager
    @State private var isPresentingInviteEmployeeSheet = false
    @State private var isPresentingBusinessMigrationSheet = false

    var body: some View {
        Form {
            if hasBusinessPortalAccess {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Meerkat - Milage Tracker for Business")
                            .font(.headline)
                        Text("Organization administration")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if hasBusinessPortalAccess,
               let organization = store.currentOrganization,
               let membership = store.currentUserOrganizationMembership {
                Section("Organization") {
                    LabeledContent("Name", value: organization.name)
                    LabeledContent("Plan", value: organization.plan.title)
                    LabeledContent("Billing", value: organization.billingStatus.title)
                    LabeledContent("Role", value: membership.role.title)
                    LabeledContent("Status", value: membership.status.title)
                    if let expiresAt = organization.expiresAt {
                        LabeledContent("Access Until", value: expiresAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    if !organization.hasActiveBilling {
                        Text("Business account access stays locked until billing becomes active for this organization.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if membership.role == .employee {
                        LabeledContent("Assigned Vehicles", value: assignedVehicleSummary(for: membership))
                        LabeledContent("Assigned Driver", value: assignedDriverSummary(for: membership))
                    }
                }

                Section("Permissions") {
                    permissionRow("Delete Trips", allowed: store.canCurrentUserDeleteTrips)
                    permissionRow("Delete Fuel-Ups", allowed: store.canCurrentUserDeleteFuelEntries)
                    permissionRow("Delete Maintenance", allowed: store.canCurrentUserDeleteMaintenanceRecords)
                    permissionRow("Download Logs", allowed: store.canCurrentUserExportLogs)
                    permissionRow("View Logs", allowed: store.canCurrentUserViewLogs)
                    permissionRow("Manage Vehicles", allowed: store.canCurrentUserManageVehicles)
                    permissionRow("Manage Drivers", allowed: store.canCurrentUserManageDrivers)
                    permissionRow("Manage Members", allowed: store.canCurrentUserManageMembers)
                }

                Section("Members") {
                    ForEach(store.currentOrganizationMembers) { member in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(member.displayName.isEmpty ? member.emailAddress : member.displayName)
                                .font(.headline)
                            Text(member.emailAddress)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(member.role.title) • \(member.status.title)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if member.status == .invited,
                               membership.role == .accountManager,
                               subscriptionManager.canInviteEmployees {
                                Button("Resend Invite") {
                                    resendInvite(for: member)
                                }
                                .buttonStyle(.bordered)
                                .disabled(!store.canCurrentUserManageMembers)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if membership.role == .accountManager,
                       subscriptionManager.canInviteEmployees {
                        Button("Invite Employee") {
                            isPresentingInviteEmployeeSheet = true
                        }
                        .disabled(!store.canCurrentUserManageMembers)
                    }
                }

                if membership.role == .accountManager && !subscriptionManager.canInviteEmployees {
                    Section("Business Plan Required") {
                        Text("Upgrade to a business subscription to invite employees and manage multi-user access.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Invitation Delivery") {
                    Text("Invites open your email app with a prefilled message so you can send them immediately.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Organization") {
                    if shouldShowBusinessPendingMessage {
                        Text("Business migration is in progress. Your existing trips, vehicles, drivers, fuel logs, and maintenance records stay intact during migration.")
                            .foregroundStyle(.secondary)
                        Button("Complete Business Migration") {
                            isPresentingBusinessMigrationSheet = true
                        }
                        .disabled(!subscriptionManager.hasBusinessSubscription)
                    } else {
                        Text("No business organization is linked to this signed-in profile yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                if shouldShowBusinessPendingMessage {
                    Section("Business Subscription Plans") {
                        Text("Select a business plan, then complete your business details to activate organization features.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        SubscriptionStoreView(
                            productIDs: [
                                SubscriptionManager.SubscriptionTier.businessMonthly.productID,
                                SubscriptionManager.SubscriptionTier.businessYearly.productID
                            ]
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Meerkat - Milage Tracker for Business")
                                    .font(.title3.weight(.semibold))
                                Text("Business subscriptions unlock organizations, employee permissions, and business portal features.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .subscriptionStoreButtonLabel(.multiline)
                        .frame(minHeight: 320)

                        Button("Refresh Subscription Status") {
                            Task {
                                await subscriptionManager.setSelectedAccountType(.business)
                                await subscriptionManager.refreshSubscriptionStatus()
                            }
                        }

                        if !subscriptionManager.hasBusinessSubscription {
                            Text("After purchase, tap refresh and then complete migration.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if shouldShowBusinessUpgradeForPersonal {
                    Section("Upgrade to Business") {
                        Text("Switch to business plans to unlock organizations, employee invites, and multi-user access.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("View Business Subscription Plans") {
                            SharedAppModel.shared.store.accountSubscriptionType = .business
                            Task {
                                await subscriptionManager.setSelectedAccountType(.business)
                                await subscriptionManager.refreshSubscriptionStatus()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Organization")
        .sheet(isPresented: $isPresentingInviteEmployeeSheet) {
            if hasBusinessPortalAccess,
               subscriptionManager.canInviteEmployees,
               let organizationID = store.currentOrganization?.id {
                InviteEmployeeSheet(store: store, organizationID: organizationID)
            } else {
                Text("Business subscription required for employee invites.")
                    .padding()
            }
        }
        .sheet(isPresented: $isPresentingBusinessMigrationSheet) {
            BusinessMigrationSheet(store: store, subscriptionManager: subscriptionManager)
        }
        .task {
            if shouldShowBusinessPendingMessage {
                await subscriptionManager.setSelectedAccountType(.business)
                await subscriptionManager.refreshSubscriptionStatus()
            }
        }
    }

    private var shouldShowBusinessPendingMessage: Bool {
        AppFeatureFlags.businessSubscriptionsEnabled
            && (
                store.accountSubscriptionType == .business
                    || subscriptionManager.selectedAccountType == .business
                    || subscriptionManager.hasBusinessSubscription
            )
    }

    private var shouldShowBusinessUpgradeForPersonal: Bool {
        AppFeatureFlags.businessSubscriptionsEnabled && !shouldShowBusinessPendingMessage
    }

    private var hasBusinessPortalAccess: Bool {
        AppFeatureFlags.businessSubscriptionsEnabled
            && (
                subscriptionManager.hasBusinessSubscription
                    || store.isBusinessAccountActive
                    || store.currentUserOrganizationMembership != nil
            )
    }

    private func assignedVehicleSummary(for membership: OrganizationMembership) -> String {
        let names = membership.assignedVehicleIDs.compactMap { store.vehicle(for: $0)?.displayName }
        return names.isEmpty ? "None assigned" : names.joined(separator: ", ")
    }

    private func assignedDriverSummary(for membership: OrganizationMembership) -> String {
        guard let assignedDriverID = membership.assignedDriverID else {
            return "None assigned"
        }

        return store.driver(for: assignedDriverID)?.name ?? "Unknown driver"
    }

    private func permissionRow(_ title: String, allowed: Bool) -> some View {
        LabeledContent(title, value: allowed ? "Allowed" : "Restricted")
    }

    private func resendInvite(for member: OrganizationMembership) {
        var updatedMembership = member
        updatedMembership.invitedAt = .now
        updatedMembership.status = .invited
        store.upsertOrganizationMembership(updatedMembership)
        deliverInvite(for: updatedMembership)
    }

    private func deliverInvite(for member: OrganizationMembership) {
        Task { @MainActor in
            let wasDeliveredByBackend = await sendInviteUsingCloudFunction(for: member)
            if !wasDeliveredByBackend {
                openInviteEmail(for: member)
            }
        }
    }

    private func openInviteEmail(for member: OrganizationMembership) {
        guard let organization = store.currentOrganization else {
            return
        }

        let subject = "Invitation to join \(organization.name) on Meerkat - Milage Tracker for Business"
        let body = """
        Hi \(member.displayName.isEmpty ? "there" : member.displayName),

        You've been invited to join \(organization.name) in Meerkat - Milage Tracker for Business.

        Open the app and sign in with \(member.emailAddress) to accept your invitation.
        """

        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(member.emailAddress)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return
        }

        openURL(url)
    }

    private func sendInviteUsingCloudFunction(for member: OrganizationMembership) async -> Bool {
        #if canImport(FirebaseFunctions) && canImport(FirebaseMessagingInterop)
        let payload: [String: Any] = [
            "organizationID": member.organizationID.uuidString,
            "inviteeEmail": member.emailAddress,
            "displayName": member.displayName
        ]

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPSCallableResult, Error>) in
                Functions.functions().httpsCallable("createOrganizationInvite").call(payload) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirebaseFunctions", code: -1))
                    }
                }
            }
            return true
        } catch {
            store.addLog("Cloud invite delivery failed. Falling back to email compose.")
            return false
        }
        #else
        return false
        #endif
    }
}

private struct BusinessMigrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MileageStore
    @Bindable var subscriptionManager: SubscriptionManager

    @State private var managerPhone = ""
    @State private var businessName = ""
    @State private var legalEntityName = ""
    @State private var taxRegistrationNumber = ""
    @State private var vatRegistrationNumber = ""
    @State private var billingAddressLine1 = ""
    @State private var billingAddressLine2 = ""
    @State private var billingCity = ""
    @State private var billingStateOrProvince = ""
    @State private var billingPostalCode = ""
    @State private var billingCountry = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Business Account") {
                    Text("Meerkat - Milage Tracker for Business")
                        .font(.headline)
                    Text("Complete business details to finish migration. Existing app data is preserved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Account Manager") {
                    LabeledContent("Name", value: store.userName)
                    LabeledContent("Email", value: resolvedManagerEmail)
                    TextField("Phone", text: $managerPhone)
                        .keyboardType(.phonePad)
                }

                Section("Business Details") {
                    TextField("Business name", text: $businessName)
                    TextField("Legal entity name", text: $legalEntityName)
                    TextField("Tax registration number", text: $taxRegistrationNumber)
                    TextField("VAT registration number (optional)", text: $vatRegistrationNumber)
                }

                Section("Billing Address") {
                    TextField("Address line 1", text: $billingAddressLine1)
                    TextField("Address line 2 (optional)", text: $billingAddressLine2)
                    TextField("City", text: $billingCity)
                    TextField("State / Province", text: $billingStateOrProvince)
                    TextField("Postal code", text: $billingPostalCode)
                    TextField("Country", text: $billingCountry)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Business Migration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish Migration") {
                        finishMigration()
                    }
                    .disabled(!canFinishMigration)
                }
            }
            .onAppear {
                prefillFromExistingProfileIfNeeded()
            }
        }
    }

    private var resolvedManagerEmail: String {
        let normalizedStoreEmail = store.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isValidEmailAddress(normalizedStoreEmail) {
            return normalizedStoreEmail
        }

        return SharedAppModel.shared.authSession.signedInEmailAddress?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private var canFinishMigration: Bool {
        AppFeatureFlags.businessSubscriptionsEnabled
            && subscriptionManager.hasBusinessSubscription
            && !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !legalEntityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !billingAddressLine1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !billingCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !billingCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isValidEmailAddress(resolvedManagerEmail)
    }

    private func prefillFromExistingProfileIfNeeded() {
        guard let profile = store.businessProfile else {
            return
        }

        managerPhone = profile.accountManagerPhone
        businessName = profile.businessName
        legalEntityName = profile.legalEntityName
        taxRegistrationNumber = profile.taxRegistrationNumber
        vatRegistrationNumber = profile.vatRegistrationNumber
        billingAddressLine1 = profile.billingAddressLine1
        billingAddressLine2 = profile.billingAddressLine2
        billingCity = profile.city
        billingStateOrProvince = profile.stateOrProvince
        billingPostalCode = profile.postalCode
        billingCountry = profile.country
    }

    private func finishMigration() {
        guard canFinishMigration else {
            validationMessage = "Complete required business details and ensure a Business subscription is active."
            return
        }

        store.accountSubscriptionType = .business
        store.businessProfile = BusinessAccountProfile(
            accountManagerName: store.userName.trimmingCharacters(in: .whitespacesAndNewlines),
            accountManagerEmail: resolvedManagerEmail,
            accountManagerPhone: managerPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            businessName: businessName.trimmingCharacters(in: .whitespacesAndNewlines),
            legalEntityName: legalEntityName.trimmingCharacters(in: .whitespacesAndNewlines),
            taxRegistrationNumber: taxRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            vatRegistrationNumber: vatRegistrationNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            billingAddressLine1: billingAddressLine1.trimmingCharacters(in: .whitespacesAndNewlines),
            billingAddressLine2: billingAddressLine2.trimmingCharacters(in: .whitespacesAndNewlines),
            city: billingCity.trimmingCharacters(in: .whitespacesAndNewlines),
            stateOrProvince: billingStateOrProvince.trimmingCharacters(in: .whitespacesAndNewlines),
            postalCode: billingPostalCode.trimmingCharacters(in: .whitespacesAndNewlines),
            country: billingCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        _ = ensureBusinessOrganizationSetupIfNeeded()
        store.addLog("Business migration completed. Existing account data retained.")
        dismiss()
    }

    private func ensureBusinessOrganizationSetupIfNeeded() -> UUID? {
        guard AppFeatureFlags.businessSubscriptionsEnabled,
              store.accountSubscriptionType == .business || subscriptionManager.hasBusinessSubscription else {
            return nil
        }

        let organizationName = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOrganizationName = organizationName.isEmpty
            ? "\(store.userName.trimmingCharacters(in: .whitespacesAndNewlines)) Organization"
            : organizationName
        let managerEmail = resolvedManagerEmail
        guard isValidEmailAddress(managerEmail) else {
            return nil
        }

        let organizationPlan: OrganizationSubscriptionPlan = subscriptionManager.activeTier == .businessYearly ? .businessYearly : .businessMonthly
        let organizationBillingStatus: OrganizationBillingStatus = subscriptionManager.hasBusinessSubscription ? .active : .pendingPayment
        var organization = store.currentOrganization
            ?? OrganizationProfile(name: resolvedOrganizationName, plan: organizationPlan, billingStatus: organizationBillingStatus, expiresAt: nil)
        organization.name = resolvedOrganizationName
        organization.plan = organizationPlan
        organization.billingStatus = organizationBillingStatus
        store.upsertOrganization(organization)
        store.activateOrganization(organization.id)

        if let existingMembership = store.organizationMemberships.first(where: {
            $0.organizationID == organization.id && $0.normalizedEmailAddress == managerEmail
        }) {
            var updatedMembership = existingMembership
            updatedMembership.displayName = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
            updatedMembership.role = .accountManager
            updatedMembership.status = .active
            updatedMembership.permissions = []
            updatedMembership.activatedAt = .now
            updatedMembership.removedAt = nil
            store.upsertOrganizationMembership(updatedMembership)
        } else {
            let membership = OrganizationMembership(
                organizationID: organization.id,
                emailAddress: managerEmail,
                displayName: store.userName.trimmingCharacters(in: .whitespacesAndNewlines),
                role: .accountManager,
                status: .active,
                assignedVehicleIDs: [],
                assignedDriverID: nil,
                permissions: [],
                invitedAt: .now,
                activatedAt: .now,
                removedAt: nil
            )
            store.upsertOrganizationMembership(membership)
        }

        return organization.id
    }

    private func isValidEmailAddress(_ email: String) -> Bool {
        guard let atIndex = email.firstIndex(of: "@"), atIndex != email.startIndex else {
            return false
        }
        let domain = email[email.index(after: atIndex)...]
        return domain.contains(".")
    }
}

private struct InviteEmployeeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Bindable var store: MileageStore
    let organizationID: UUID
    @State private var employeeEmailAddress = ""
    @State private var employeeDisplayName = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Employee") {
                    TextField("Email", text: $employeeEmailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    TextField("Display Name", text: $employeeDisplayName)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Invite Employee")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") {
                        inviteEmployee()
                    }
                }
            }
        }
    }

    private func inviteEmployee() {
        guard AppFeatureFlags.businessSubscriptionsEnabled,
              SharedAppModel.shared.subscriptionManager.canInviteEmployees,
              store.canCurrentUserManageMembers,
              store.currentUserOrganizationMembership?.role == .accountManager else {
            errorMessage = "Business subscription required to invite employees."
            return
        }

        let normalizedEmail = employeeEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValid(email: normalizedEmail) else {
            errorMessage = "Enter a valid employee email address."
            return
        }

        let trimmedDisplayName = employeeDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingMembership = store.currentOrganizationMembers.first {
            $0.normalizedEmailAddress == normalizedEmail
        }

        if var existingMembership {
            existingMembership.displayName = trimmedDisplayName
            existingMembership.role = .employee
            existingMembership.status = .invited
            existingMembership.permissions = []
            existingMembership.invitedAt = .now
            existingMembership.activatedAt = nil
            existingMembership.removedAt = nil
            store.upsertOrganizationMembership(existingMembership)
            deliverInvite(for: existingMembership)
        } else {
            let membership = OrganizationMembership(
                organizationID: organizationID,
                emailAddress: normalizedEmail,
                displayName: trimmedDisplayName,
                role: .employee,
                status: .invited,
                assignedVehicleIDs: [],
                assignedDriverID: nil,
                permissions: [],
                invitedAt: .now,
                activatedAt: nil,
                removedAt: nil
            )
            store.upsertOrganizationMembership(membership)
            deliverInvite(for: membership)
        }

        dismiss()
    }

    private func deliverInvite(for membership: OrganizationMembership) {
        Task { @MainActor in
            let wasDeliveredByBackend = await sendInviteUsingCloudFunction(for: membership)
            if !wasDeliveredByBackend {
                openInviteEmail(for: membership)
            }
        }
    }

    private func openInviteEmail(for membership: OrganizationMembership) {
        guard let organization = store.organizations.first(where: { $0.id == organizationID }) else {
            return
        }

        let subject = "Invitation to join \(organization.name) on Meerkat - Milage Tracker for Business"
        let body = """
        Hi \(membership.displayName.isEmpty ? "there" : membership.displayName),

        You've been invited to join \(organization.name) in Meerkat - Milage Tracker for Business.

        Open the app and sign in with \(membership.emailAddress) to accept your invitation.
        """

        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(membership.emailAddress)?subject=\(encodedSubject)&body=\(encodedBody)") else {
            return
        }

        openURL(url)
    }

    private func sendInviteUsingCloudFunction(for membership: OrganizationMembership) async -> Bool {
        #if canImport(FirebaseFunctions) && canImport(FirebaseMessagingInterop)
        let payload: [String: Any] = [
            "organizationID": membership.organizationID.uuidString,
            "inviteeEmail": membership.emailAddress,
            "displayName": membership.displayName
        ]

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPSCallableResult, Error>) in
                Functions.functions().httpsCallable("createOrganizationInvite").call(payload) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let result {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: NSError(domain: "FirebaseFunctions", code: -1))
                    }
                }
            }
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    private func isValid(email: String) -> Bool {
        guard let atIndex = email.firstIndex(of: "@"), atIndex != email.startIndex else {
            return false
        }
        let domain = email[email.index(after: atIndex)...]
        return domain.contains(".")
    }
}

private struct SettingsTrackingView: View {
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker
    @Bindable var vehicleConnectionManager: VehicleConnectionManager

    var body: some View {
        Form {
            Section("Tracking") {
                Toggle("Auto-start trips", isOn: $tripTracker.autoStartEnabled)
                Toggle("Background trip tracking", isOn: $tripTracker.backgroundTripTrackingEnabled)
                Toggle("Use Motion & Fitness", isOn: $tripTracker.motionActivityEnabled)
                Stepper(
                    value: $tripTracker.autoStartSpeedThresholdKilometersPerHour,
                    in: 5 ... 130,
                    step: 5
                ) {
                    LabeledContent(
                        "Auto-start speed",
                        value: "\(tripTracker.autoStartSpeedThresholdKilometersPerHour.formatted(.number.precision(.fractionLength(0)))) km/h"
                    )
                }
                Stepper(
                    value: $tripTracker.autoStopDelayMinutes,
                    in: 1 ... 60,
                    step: 1
                ) {
                    LabeledContent(
                        "Auto-stop delay",
                        value: "\(tripTracker.autoStopDelayMinutes.formatted(.number.precision(.fractionLength(0)))) min"
                    )
                }
                Toggle("Keep screen awake on trip", isOn: $store.preventAutoLock)
            }

            Section("Permissions") {
                HStack {
                    Text("Location access")
                    Spacer()
                    Text(tripTracker.authorizationLabel)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Motion & Fitness")
                    Spacer()
                    Text(tripTracker.motionAuthorizationLabel)
                        .foregroundStyle(.secondary)
                }
                Button("Request Location Access") {
                    tripTracker.requestPermissionsForCurrentTrackingMode()
                    store.addLog("Manual location permission request")
                }
                Button("Request Motion & Fitness Access") {
                    tripTracker.requestPermissionsForCurrentTrackingMode()
                    store.addLog("Manual motion and fitness permission request")
                }
                Text("Background trip tracking is on by default. When enabled, the app requests the location access needed to keep recording or auto-start a trip in the background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Motion & Fitness improves automotive detection while the app is already running or relaunched by background location. iPhone still relies on Always location authorization to relaunch a terminated app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("If your speed stays below the auto-start speed for the configured delay, the active trip is finished and saved automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Vehicle Detection") {
                LabeledContent("Bluetooth", value: vehicleConnectionManager.bluetoothStatusLabel)
                LabeledContent("Detected vehicle", value: store.vehicle(for: vehicleConnectionManager.matchedVehicleID)?.displayName ?? "None")
                Text(vehicleConnectionManager.statusSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tracking")
    }
}

private struct SettingsVehicleDetectionView: View {
    @Bindable var store: MileageStore
    @Bindable var tripTracker: TripTracker
    @Bindable var vehicleConnectionManager: VehicleConnectionManager
    @State private var bluetoothDevicePendingAssignment: VehicleConnectionManager.DiscoveredBluetoothDevice?
    @State private var notificationAuthorizationLabel = "Checking..."

    private var configuredVehicles: [VehicleProfile] {
        store.vehicles.filter(\.detectionProfile.isEnabled)
    }

    private var matchedVehicleName: String {
        store.vehicle(for: vehicleConnectionManager.matchedVehicleID)?.displayName ?? "None"
    }

    var body: some View {
        Form {
            statusSection
            setupSection
            reliabilitySection
            configuredVehiclesSection
            nearbyBluetoothDevicesSection
        }
        .navigationTitle("Vehicle Detection")
        .onAppear {
            SharedAppModel.shared.refreshVehicleConnectionConfiguration()
            Task {
                await refreshNotificationAuthorizationLabel()
            }
        }
        .onChange(of: store.vehicleDetectionEnabled) { _, isEnabled in
            if isEnabled {
                vehicleConnectionManager.startManualBluetoothScan()
            } else {
                vehicleConnectionManager.stopManualBluetoothScan()
            }
            SharedAppModel.shared.refreshVehicleConnectionConfiguration()
        }
        .sheet(item: $bluetoothDevicePendingAssignment) { device in
            NavigationStack {
                Form {
                    Section("Bluetooth Device") {
                        Text(device.name)
                            .font(.headline)
                        Text(device.id.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Section("Assign to Vehicle") {
                        if store.vehicles.isEmpty {
                            Text("Add a vehicle before assigning a Bluetooth detector.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.vehicles) { vehicle in
                                Button(vehicle.displayName) {
                                    assignBluetoothDevice(device, to: vehicle)
                                    bluetoothDevicePendingAssignment = nil
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Assign Device")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            bluetoothDevicePendingAssignment = nil
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            Toggle("Enable vehicle detection", isOn: $store.vehicleDetectionEnabled)
            LabeledContent("Bluetooth", value: vehicleConnectionManager.bluetoothStatusLabel)
            LabeledContent("CarPlay", value: vehicleConnectionManager.isCarPlayConnected ? "Connected" : "Not connected")
            LabeledContent("Notifications", value: notificationAuthorizationLabel)
            LabeledContent("Detected vehicle", value: matchedVehicleName)
            LabeledContent(
                "Auto-start gate",
                value: vehicleConnectionManager.requiresVehicleSignalForAutoStart ? "Vehicle required" : "No vehicle required"
            )

            Text(vehicleConnectionManager.statusSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var setupSection: some View {
        Section("Setup") {
            if store.vehicleDetectionEnabled {
                Button(vehicleConnectionManager.isManualBluetoothScanActive ? "Stop Bluetooth Scan" : "Scan for Bluetooth Devices") {
                    if vehicleConnectionManager.isManualBluetoothScanActive {
                        vehicleConnectionManager.stopManualBluetoothScan()
                    } else {
                        vehicleConnectionManager.startManualBluetoothScan()
                    }
                }
            }

            if vehicleConnectionManager.bluetoothAuthorization == .notDetermined {
                Button("Request Bluetooth Access") {
                    vehicleConnectionManager.requestBluetoothAccessIfNeeded()
                }
            }

            if notificationAuthorizationLabel != "Allowed" {
                Button("Enable Detector Notifications") {
                    Task {
                        await SharedAppModel.shared.maintenanceReminderManager.requestNotificationAuthorization()
                        await refreshNotificationAuthorizationLabel()
                    }
                }
            }

            Text("Link a nearby Bluetooth accessory to a vehicle from this screen, or open Settings > Vehicles for per-vehicle CarPlay and Bluetooth configuration. When vehicle detection is enabled, trip auto-start only records while a configured vehicle signal is active. Manual trip start still works without a detector.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !tripTracker.autoStartEnabled {
                Text("Auto-start trips is currently off, so detection can auto-select a vehicle but will not start recording until auto-start is enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var reliabilitySection: some View {
        if !vehicleConnectionManager.detectorReliabilityIssues.isEmpty {
            Section("Detector Reliability") {
                ForEach(vehicleConnectionManager.detectorReliabilityIssues) { issue in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.vehicle(for: issue.vehicleID)?.displayName ?? "Assigned vehicle")
                            .font(.headline)
                        Text(issue.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Reliable alternatives: dedicated BLE beacon, iBeacon-compatible tag, USB-powered BLE beacon, or CarPlay plus a stable BLE beacon.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var configuredVehiclesSection: some View {
        Section("Configured Vehicles") {
            if configuredVehicles.isEmpty {
                Text("No vehicles have detection enabled yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(configuredVehicles) { vehicle in
                    configuredVehicleRow(vehicle)
                }
            }
        }
    }

    @ViewBuilder
    private var nearbyBluetoothDevicesSection: some View {
        Section("Nearby Bluetooth Devices") {
            if vehicleConnectionManager.visibleBluetoothDevices.isEmpty {
                Text("No Bluetooth peripherals discovered yet. Power on the beacon or accessory and keep it nearby so the app can discover it.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vehicleConnectionManager.visibleBluetoothDevices) { device in
                    bluetoothDeviceRow(device)
                }
            }
            if vehicleConnectionManager.hiddenUnknownBluetoothDeviceCount > 0 {
                Text("\(vehicleConnectionManager.hiddenUnknownBluetoothDeviceCount) unnamed device(s) hidden to reduce clutter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func assignedVehicle(for device: VehicleConnectionManager.DiscoveredBluetoothDevice) -> VehicleProfile? {
        store.vehicles.first { vehicle in
            vehicle.detectionProfile.bluetoothPeripheralIdentifier == device.id.uuidString
        }
    }

    @ViewBuilder
    private func configuredVehicleRow(_ vehicle: VehicleProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(vehicle.displayName)
                    .font(.headline)
                Spacer()
                if vehicleConnectionManager.matchedVehicleID == vehicle.id {
                    Text("Active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            Text(vehicle.detectionProfile.summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if vehicle.detectionProfile.usesBluetoothPeripheral {
                Text(vehicle.detectionProfile.bluetoothPeripheralName.isEmpty ? "Bluetooth device not selected" : vehicle.detectionProfile.bluetoothPeripheralName)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                if let reliabilityIssue = vehicleConnectionManager.detectorReliabilityIssues.first(where: { $0.vehicleID == vehicle.id }) {
                    Text(reliabilityIssue.message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button("Remove Bluetooth Device", role: .destructive) {
                    unassignBluetoothDevice(from: vehicle)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func bluetoothDeviceRow(_ device: VehicleConnectionManager.DiscoveredBluetoothDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                    Text(device.id.uuidString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let assignedVehicle = assignedVehicle(for: device) {
                        Text("Assigned to \(assignedVehicle.displayName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Assign") {
                    bluetoothDevicePendingAssignment = device
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.vehicles.isEmpty)
            }

            Text("RSSI \(device.rssi) • Last seen \(device.lastSeen.formatted(date: .omitted, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func assignBluetoothDevice(
        _ device: VehicleConnectionManager.DiscoveredBluetoothDevice,
        to vehicle: VehicleProfile
    ) {
        clearBluetoothAssignment(for: device.id.uuidString, excluding: vehicle.id)

        var updatedVehicle = vehicle
        var detectionProfile = updatedVehicle.detectionProfile
        var allowedSources = detectionProfile.allowedSources
        allowedSources.insert(.bluetoothPeripheral)
        detectionProfile.isEnabled = true
        detectionProfile.allowedSources = allowedSources
        detectionProfile.bluetoothPeripheralIdentifier = device.id.uuidString
        detectionProfile.bluetoothPeripheralName = device.name
        updatedVehicle.detectionProfile = detectionProfile

        store.vehicleDetectionEnabled = true
        store.updateVehicle(updatedVehicle)
        SharedAppModel.shared.refreshVehicleConnectionConfiguration()
    }

    private func unassignBluetoothDevice(from vehicle: VehicleProfile) {
        var updatedVehicle = vehicle
        var detectionProfile = updatedVehicle.detectionProfile
        var allowedSources = detectionProfile.allowedSources
        allowedSources.remove(.bluetoothPeripheral)
        detectionProfile.allowedSources = allowedSources
        detectionProfile.bluetoothPeripheralIdentifier = nil
        detectionProfile.bluetoothPeripheralName = ""
        if allowedSources.isEmpty {
            detectionProfile.isEnabled = false
        }
        updatedVehicle.detectionProfile = detectionProfile

        store.updateVehicle(updatedVehicle)
        SharedAppModel.shared.refreshVehicleConnectionConfiguration()
    }

    private func clearBluetoothAssignment(for identifier: String, excluding vehicleID: UUID) {
        for vehicle in store.vehicles where vehicle.id != vehicleID && vehicle.detectionProfile.bluetoothPeripheralIdentifier == identifier {
            var updatedVehicle = vehicle
            var detectionProfile = updatedVehicle.detectionProfile
            var allowedSources = detectionProfile.allowedSources
            allowedSources.remove(.bluetoothPeripheral)
            detectionProfile.allowedSources = allowedSources
            detectionProfile.bluetoothPeripheralIdentifier = nil
            detectionProfile.bluetoothPeripheralName = ""
            if allowedSources.isEmpty {
                detectionProfile.isEnabled = false
            }
            updatedVehicle.detectionProfile = detectionProfile
            store.updateVehicle(updatedVehicle)
        }
    }

    private func refreshNotificationAuthorizationLabel() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationLabel = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            "Allowed"
        case .denied:
            "Denied"
        case .notDetermined:
            "Not Set"
        @unknown default:
            "Unknown"
        }
    }
}

private struct SettingsSubscriptionView: View {
    @Bindable var subscriptionManager: SubscriptionManager
    @State private var isPresentingManageSubscriptions = false

    var body: some View {
        Form {
            Section("Subscription Access") {
                LabeledContent("Access", value: subscriptionAccessLabel)
                LabeledContent("Status", value: subscriptionManager.statusMessage)
                if subscriptionManager.hasActiveSubscription {
                    LabeledContent("Renews On", value: subscriptionManager.activeRenewalDateLabel)
                }

                if subscriptionManager.hasLoadedStatus {
                    if let upgradeProductID {
                        SubscriptionStoreView(productIDs: [upgradeProductID]) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(upgradeTitle)
                                    .font(.title3.weight(.semibold))
                                Text("If you change plans, App Store billing timing and proration are controlled by Apple.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .subscriptionStoreButtonLabel(.multiline)
                        .frame(minHeight: 320)
                    } else if !subscriptionManager.hasActiveSubscription {
                        SubscriptionStoreView(productIDs: subscriptionManager.productIDs) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Choose a plan")
                                    .font(.title3.weight(.semibold))
                                Text("Subscriptions unlock the full app and renew through your App Store account.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .subscriptionStoreButtonLabel(.multiline)
                        .frame(minHeight: 360)
                    }
                } else {
                    ProgressView("Loading subscriptions...")
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                SubscriptionReviewDisclosureView(subscriptionManager: subscriptionManager)

                Button(subscriptionManager.isRefreshing ? "Restoring..." : "Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                }
                .disabled(subscriptionManager.isRefreshing)

                if subscriptionManager.hasActiveSubscription {
                    Button("Manage Subscription") {
                        isPresentingManageSubscriptions = true
                    }
                }
            }
        }
        .navigationTitle("Subscription")
        .task {
            if let activeTier = subscriptionManager.activeTier {
                let activeAccountType: AccountSubscriptionType = activeTier.isBusiness ? .business : .personal
                await subscriptionManager.setSelectedAccountType(activeAccountType)
            }
            await subscriptionManager.refreshSubscriptionStatus()
        }
        .manageSubscriptionsSheet(isPresented: $isPresentingManageSubscriptions)
    }

    private var subscriptionAccessLabel: String {
        if SharedAppModel.shared.authSession.hasOwnerAccess {
            return "Owner access"
        }

        if SharedAppModel.shared.authSession.hasApprovedBetaAccess {
            return "Beta access"
        }

        if subscriptionManager.hasBusinessSubscription {
            return "Business plan active"
        }

        return subscriptionManager.hasActiveSubscription ? "Active" : "Subscription required"
    }

    private var upgradeProductID: String? {
        switch subscriptionManager.activeTier {
        case .businessMonthly:
            return SubscriptionManager.SubscriptionTier.businessYearly.productID
        case .personalMonthly:
            return SubscriptionManager.SubscriptionTier.personalYearly.productID
        case .businessYearly, .personalYearly, nil:
            return nil
        }
    }

    private var upgradeTitle: String {
        switch subscriptionManager.activeTier {
        case .businessMonthly:
            return "Upgrade to Business Yearly"
        case .personalMonthly:
            return "Upgrade to Personal Yearly"
        case .businessYearly, .personalYearly, nil:
            return "Upgrade Plan"
        }
    }
}

private struct SettingsAccountView: View {
    @Bindable var authSession: AuthSessionManager
    @Bindable var subscriptionManager: SubscriptionManager
    @Bindable var cloudSync: CloudSyncManager
    let persistenceSnapshot: AppPersistenceSnapshot
    let onRestoreRequest: () async -> Void
    let onExitDemoMode: () -> Void
    let onDeleteAccountRequest: () -> Void
    @State private var isPresentingDeleteAccountConfirmation = false
    @State private var isPresentingRestoreConfirmation = false

    var body: some View {
        Form {
            Section("Subscription") {
                LabeledContent("Access", value: subscriptionAccessLabel)
                LabeledContent("Status", value: subscriptionManager.statusMessage)

                Button(subscriptionManager.isRefreshing ? "Restoring..." : "Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                }
                .disabled(subscriptionManager.isRefreshing)
            }

            Section("Account") {
                LabeledContent("Sign-in", value: accountStatusLabel)
                LabeledContent("Cloud", value: cloudSync.statusMessage)

                if authSession.isDemoModeEnabled {
                    Text("Demo Mode uses local sample data only. Cloud backup and account actions are unavailable until you exit demo mode.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Exit Demo Mode", role: .destructive) {
                        onExitDemoMode()
                    }
                } else if authSession.canUseCloudSyncFeatures {
                    Button(cloudSync.isSyncing ? "Backing Up..." : backupButtonTitle) {
                        Task {
                            await cloudSync.backupToCloud(snapshot: persistenceSnapshot)
                        }
                    }
                    .disabled(cloudSync.isSyncing)

                    Button(cloudSync.isSyncing ? "Restoring..." : restoreButtonTitle) {
                        isPresentingRestoreConfirmation = true
                    }
                    .disabled(cloudSync.isSyncing)

                    Button("Sign Out", role: .destructive) {
                        authSession.signOut()
                    }

                    Button("Delete Account", role: .destructive) {
                        isPresentingDeleteAccountConfirmation = true
                    }
                } else if authSession.isEmailPasswordAuthenticated {
                    LabeledContent("Email", value: authSession.signedInEmailAddress ?? "Unknown")

                    Text("Email/password accounts support secure cloud backup and cross-device access.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("Sign Out", role: .destructive) {
                        authSession.signOut()
                    }

                    Button("Delete Account", role: .destructive) {
                        isPresentingDeleteAccountConfirmation = true
                    }
                } else {
                    Button("Open Sign-In") {
                        authSession.isPresentingLoginSheet = true
                    }
                }
            }

            Section("Web Portal") {
                Text("Manage synced trips, fuel, maintenance, and exports from a computer at the Meerkat web portal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://app.meerkatinnovations.ca")!) {
                    Label("Open app.meerkatinnovations.ca", systemImage: "desktopcomputer")
                }
            }
        }
        .navigationTitle("Cloud & Security")
        .alert("Delete Account?", isPresented: $isPresentingDeleteAccountConfirmation) {
            Button("Delete Account", role: .destructive) {
                onDeleteAccountRequest()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteAccountMessage)
        }
        .alert(restoreConfirmationTitle, isPresented: $isPresentingRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task {
                    await onRestoreRequest()
                }
            }
            .disabled(authSession.isDemoModeEnabled || cloudSync.isSyncing)
        } message: {
            Text(restoreConfirmationMessage)
        }
    }

    private var accountStatusLabel: String {
        if authSession.isDemoModeEnabled {
            return "Demo mode"
        }

        if authSession.hasOwnerAccess {
            return "Owner access"
        }

        if authSession.hasApprovedBetaAccess {
            return "Beta access"
        }

        if authSession.isEmailPasswordAuthenticated {
            return "Email/password account"
        }

        return authSession.isSignedIn ? "Apple ID connected" : "Signed out"
    }

    private var deleteAccountMessage: String {
        if authSession.isEmailPasswordAuthenticated || authSession.isConnectedToFirebase || authSession.canUseCloudSyncFeatures {
            return "This deletes your app data from this device and removes its cloud backup for this account."
        }

        return "This removes the locally stored account from this device and deletes its saved app data."
    }

    private var backupButtonTitle: String {
        "Back Up To Cloud"
    }

    private var restoreButtonTitle: String {
        "Restore From Cloud"
    }

    private var restoreConfirmationTitle: String {
        "Restore Cloud Backup?"
    }

    private var restoreConfirmationMessage: String {
        "This replaces the current device data with the latest cloud backup."
    }

    private var subscriptionAccessLabel: String {
        if authSession.hasOwnerAccess {
            return "Owner access"
        }

        if authSession.hasApprovedBetaAccess {
            return "Beta access"
        }

        if subscriptionManager.hasBusinessSubscription {
            return "Business plan active"
        }

        return subscriptionManager.hasActiveSubscription ? "Active" : "Inactive"
    }
}

private struct SettingsPrivacyLegalView: View {
    private let companyName = "Meerkat Innovations"
    private let website = "meerkatinnovations.ca"
    private let adminEmail = "admin@meerkatinnovations.ca"
    private let appName = "Meerkat - Milage Tracker"

    var body: some View {
        Form {
            Section("Privacy Policy") {
                policyBlock(
                    title: "1. Overview",
                    text: "\(appName) is provided by \(companyName). This policy explains how the app collects, stores, uses, and shares information when you use mileage tracking, trip history, fuel logging, maintenance logging, cloud backup, and related features."
                )
                policyBlock(
                    title: "2. Information Collected",
                    text: "The app may collect trip locations, route breadcrumbs, addresses, odometer readings, trip classifications, vehicle and driver profiles, fuel records, maintenance records, receipts, account preferences, and any information you voluntarily enter in support requests."
                )
                policyBlock(
                    title: "3. Location Data",
                    text: "Location access is used to detect movement, record mileage, create trip maps, suggest addresses and points of interest, and support optional background trip tracking. Location data is used only to operate the app’s mileage-tracking features."
                )
                policyBlock(
                    title: "4. Storage and Backups",
                    text: "App data is stored locally on your device. If you choose to use Apple sign-in and iCloud backup features, your data may also be stored in your private Apple iCloud account through Apple services."
                )
                policyBlock(
                    title: "5. Sharing",
                    text: "\(companyName) does not sell your trip or vehicle data. Data may only be shared when required to provide Apple platform services you enable, when you export logs, email support, or where disclosure is required by law."
                )
                policyBlock(
                    title: "6. Retention and Control",
                    text: "You control the trip, fuel, maintenance, and exported log records you keep in the app. You may edit or delete records in the app and may stop using cloud features at any time by signing out."
                )
                policyBlock(
                    title: "7. Security",
                    text: "Reasonable measures are used to protect app data, including Apple platform security, device protections, optional biometric access, and Apple-managed services where enabled. No method of storage or transmission is guaranteed to be completely secure."
                )
                policyBlock(
                    title: "8. Contact",
                    text: "Questions about privacy may be sent to \(adminEmail) or through the support page in the app. Company website: \(website)."
                )
            }

            Section("Legal Notice") {
                policyBlock(
                    title: "Use of Information",
                    text: "Mileage, fuel, maintenance, address, and log information shown or exported by the app is provided as a recordkeeping tool. You remain responsible for reviewing the accuracy of all records, classifications, odometer entries, and tax-related reports before relying on them for legal, tax, employment, reimbursement, or regulatory purposes."
                )
                policyBlock(
                    title: "No Professional Advice",
                    text: "\(appName) does not provide legal, tax, accounting, payroll, employment, or regulatory advice. You should consult a qualified professional for jurisdiction-specific requirements."
                )
                policyBlock(
                    title: "Third-Party Services",
                    text: "The app may rely on Apple services such as Maps, Sign in with Apple, Photos, Camera, Mail, Notifications, and cloud backup services. Those services remain subject to Apple’s terms, permissions, and availability."
                )
                policyBlock(
                    title: "Limitation of Liability",
                    text: "To the fullest extent permitted by applicable law, \(companyName) is not liable for indirect, incidental, special, consequential, or data-loss-related damages arising from use of the app, exported logs, device loss, sync issues, or inaccurate user-entered information."
                )
                policyBlock(
                    title: "Jurisdiction and Updates",
                    text: "\(companyName) may update this notice and policy from time to time. Continued use of the app after updates constitutes acceptance of the revised notice to the extent permitted by law."
                )
            }

            Section("Company") {
                LabeledContent("App", value: appName)
                LabeledContent("Company", value: companyName)
                LabeledContent("Website", value: website)
                LabeledContent("Admin Email", value: adminEmail)
            }
        }
        .navigationTitle("Privacy & Legal")
    }

    private func policyBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SettingsContactSupportView: View {
    @Environment(\.openURL) private var openURL

    @State private var senderName = ""
    @State private var senderEmail = ""
    @State private var topic = "Support Request"
    @State private var message = ""
    @State private var resultMessage = ""
    @State private var isPresentingMailSheet = false

    private let adminEmail = "admin@meerkatinnovations.ca"
    private let appName = "Meerkat - Milage Tracker"

    var body: some View {
        Form {
            Section("Contact Support") {
                Text("Use this form to send concerns, bug reports, feature suggestions, or general feedback to Meerkat Innovations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Your name", text: $senderName)
                    .textInputAutocapitalization(.words)

                TextField("Your email", text: $senderEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Topic", text: $topic)

                TextField("Message", text: $message, axis: .vertical)
                    .lineLimit(6, reservesSpace: true)
            }

            Section("Support Details") {
                LabeledContent("Admin Email", value: adminEmail)
                LabeledContent("Website", value: "meerkatinnovations.ca")
            }

            Section {
                Button("Email Support") {
                    presentSupportEmail()
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !resultMessage.isEmpty {
                    Text(resultMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Contact Support")
        .sheet(isPresented: $isPresentingMailSheet) {
            SupportMailComposeView(
                recipient: adminEmail,
                subject: supportSubject,
                body: supportBody,
                resultMessage: $resultMessage
            )
        }
    }

    private var supportSubject: String {
        "[\(appName)] \(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Support Request" : topic)"
    }

    private var supportBody: String {
        """
        App: \(appName)
        Name: \(senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not provided" : senderName)
        Email: \(senderEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not provided" : senderEmail)

        Message:
        \(message.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    private func presentSupportEmail() {
        if MFMailComposeViewController.canSendMail() {
            isPresentingMailSheet = true
            return
        }

        guard let subject = supportSubject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let body = supportBody.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "mailto:\(adminEmail)?subject=\(subject)&body=\(body)") else {
            resultMessage = "Unable to prepare support email."
            return
        }

        openURL(url)
        resultMessage = "Opened your email app to contact support."
    }
}

private struct SettingsCarPlayView: View {
    var body: some View {
        Form {
            Section("CarPlay") {
                LabeledContent("Status", value: "Available")
                Text("Use Meerkat on a compatible CarPlay display to view trip status, recent trips, fuel information, and in-car controls.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Using CarPlay") {
                Text("1. Connect your iPhone to your vehicle's CarPlay system.")
                Text("2. Open Meerkat from the CarPlay app screen.")
                Text("3. Use the dashboard, trips, and fuel tabs while parked or when passenger-safe actions are available.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("CarPlay")
    }
}

private struct SupportMailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    @Binding var resultMessage: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: SupportMailComposeView

        init(parent: SupportMailComposeView) {
            self.parent = parent
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            if let error {
                parent.resultMessage = error.localizedDescription
            } else {
                switch result {
                case .cancelled:
                    parent.resultMessage = "Support email cancelled."
                case .saved:
                    parent.resultMessage = "Support email draft saved."
                case .sent:
                    parent.resultMessage = "Support email sent."
                case .failed:
                    parent.resultMessage = "Support email failed."
                @unknown default:
                    parent.resultMessage = ""
                }
            }

            parent.dismiss()
        }
    }
}

private struct SettingsAboutView: View {
    @Bindable var store: MileageStore
    @Bindable var cloudSync: CloudSyncManager

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("Tracked trips", value: "\(store.trips.count)")
                LabeledContent("Last sync", value: cloudSync.statusMessage)
            }
        }
        .navigationTitle("About")
    }
}

private struct FlipOdometerView: View {
    let value: Double

    private var formattedValue: String {
        let boundedValue = max(value, 0)
        return String(format: "%07.1f", boundedValue)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(formattedValue.enumerated()), id: \.offset) { _, character in
                if character == "." {
                    Text(".")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .frame(width: 12, height: 56, alignment: .bottom)
                        .padding(.bottom, 6)
                } else {
                    FlipDigitView(character: character)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct IntegerOdometerView: View {
    let value: Double

    private var formattedValue: String {
        let boundedValue = max(Int(value.rounded()), 0)
        return String(format: "%05d", boundedValue)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(formattedValue.enumerated()), id: \.offset) { _, character in
                CompactOdometerDigitView(character: character)
            }
        }
    }
}

private struct CompactOdometerDigitView: View {
    let character: Character

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.72))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.top, 19)
                Spacer()
            }
            Text(String(character))
                .font(.system(size: 24, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 38)
        .shadow(color: .black.opacity(0.14), radius: 6, y: 4)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct CSVFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

private func optimizedReceiptData(from image: UIImage) -> Data? {
    let maxDimension: CGFloat = 1600
    let largestSide = max(image.size.width, image.size.height)
    let targetImage: UIImage

    if largestSide > maxDimension {
        let scale = maxDimension / largestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        targetImage = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    } else {
        targetImage = image
    }

    return targetImage.jpegData(compressionQuality: 0.65)
}

private struct ReceiptImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let imageData: Data

    private var image: UIImage? {
        UIImage(data: imageData)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                    }
                    .background(Color.black.opacity(0.96))
                } else {
                    ContentUnavailableView("Receipt Unavailable", systemImage: "doc")
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let attachmentURL: URL
    let attachmentMimeType: String
    let attachmentFileName: String
    @Binding var resultMessage: String
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.setSubject(subject)
        if let data = try? Data(contentsOf: attachmentURL) {
            controller.addAttachmentData(data, mimeType: attachmentMimeType, fileName: attachmentFileName)
        }
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView

        init(parent: MailComposeView) {
            self.parent = parent
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            if let error {
                parent.resultMessage = error.localizedDescription
            } else {
                switch result {
                case .cancelled:
                    parent.resultMessage = "Email cancelled."
                case .saved:
                    parent.resultMessage = "Email draft saved."
                case .sent:
                    parent.resultMessage = "Email sent."
                case .failed:
                    parent.resultMessage = "Email failed."
                @unknown default:
                    parent.resultMessage = ""
                }
            }

            parent.dismiss()
        }
    }
}

private struct FlipDigitView: View {
    let character: Character

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.72))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.top, 28)
                Spacer()
            }
            Text(String(character))
                .font(.system(size: 34, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 56)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
    }
}

private struct ReceiptCameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ReceiptCameraPicker

        init(parent: ReceiptCameraPicker) {
            self.parent = parent
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onDismiss()
            parent.dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            if let image = mergedImage(from: scan) {
                parent.onImagePicked(image)
            }

            parent.onDismiss()
            parent.dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onDismiss()
            parent.dismiss()
        }

        private func mergedImage(from scan: VNDocumentCameraScan) -> UIImage? {
            guard scan.pageCount > 0 else {
                return nil
            }

            let pages = (0 ..< scan.pageCount).map(scan.imageOfPage(at:))
            guard let firstPage = pages.first else {
                return nil
            }

            if pages.count == 1 {
                return firstPage
            }

            let targetWidth = pages.map(\.size.width).max() ?? firstPage.size.width
            let scaledHeights = pages.map { page in
                page.size.height * (targetWidth / max(page.size.width, 1))
            }
            let totalHeight = scaledHeights.reduce(0, +)
            let format = UIGraphicsImageRendererFormat()
            format.scale = firstPage.scale

            return UIGraphicsImageRenderer(
                size: CGSize(width: targetWidth, height: totalHeight),
                format: format
            ).image { _ in
                var yOffset = 0.0
                for (page, scaledHeight) in zip(pages, scaledHeights) {
                    page.draw(in: CGRect(x: 0, y: yOffset, width: targetWidth, height: scaledHeight))
                    yOffset += scaledHeight
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
