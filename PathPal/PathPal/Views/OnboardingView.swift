import SwiftUI

struct OnboardingView: View {
    @State private var isAccessibilityGranted = PermissionsService.shared.isAccessibilityGranted
    @State private var isAutomationGranted = false
    @State private var isFullDiskAccessGranted = PermissionsService.shared.isFullDiskAccessGranted
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0.0
    @State private var pollTimer: Timer?
    @State private var automationCheckInFlight = false
    let onComplete: () -> Void

    private var requiredGrantedCount: Int {
        [isAccessibilityGranted, isAutomationGranted].filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 28) {
            // App icon with entrance animation
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .shadow(color: .blue.opacity(0.25), radius: 12, y: 4)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        iconScale = 1.0
                    }
                    withAnimation(.easeOut(duration: 0.5)) {
                        iconOpacity = 1.0
                    }
                }

            VStack(spacing: 8) {
                Text("Welcome to PathPal")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Enhances macOS Open/Save dialogs with quick\nfolder navigation and Finder integration.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            // Progress over the two required permissions
            Text(requiredGrantedCount == 2
                 ? "All set — Full Disk Access is optional"
                 : "\(requiredGrantedCount) of 2 required permissions granted")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(requiredGrantedCount == 2 ? .green : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(.quaternary)
                )

            // Permission steps as a vertical timeline
            VStack(spacing: 0) {
                permissionStep(
                    number: 1,
                    title: "Accessibility",
                    description: "Detect Open/Save dialogs and navigate them",
                    isGranted: isAccessibilityGranted,
                    isLast: false,
                    action: { PermissionsService.shared.requestAccessibility() },
                    settingsAction: { PermissionsService.shared.openAccessibilityPreferences() }
                )

                permissionStep(
                    number: 2,
                    title: "Automation (Finder)",
                    description: "Read Finder window paths and navigate",
                    isGranted: isAutomationGranted,
                    isLast: false,
                    action: { checkAutomation() },
                    settingsAction: { PermissionsService.shared.openAutomationPreferences() }
                )

                permissionStep(
                    number: 3,
                    title: "Full Disk Access",
                    description: "Optional — read Finder sidebar favorites",
                    isGranted: isFullDiskAccessGranted,
                    isLast: true,
                    action: { PermissionsService.shared.openFullDiskAccessPreferences() },
                    settingsAction: nil
                )
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )
            }

            Button {
                SettingsService.shared.hasCompletedOnboarding = true
                onComplete()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isAccessibilityGranted)
        }
        .padding(40)
        .frame(width: 500, height: 580)
        .onAppear {
            checkAutomation()
            startPolling()
        }
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    /// Re-check all permissions once a second so the UI recovers on its own
    /// when the user denies a prompt and later grants access in System Settings.
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let accessibility = PermissionsService.shared.isAccessibilityGranted
            let fullDisk = PermissionsService.shared.isFullDiskAccessGranted
            DispatchQueue.main.async {
                if accessibility != isAccessibilityGranted {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isAccessibilityGranted = accessibility
                    }
                }
                if fullDisk != isFullDiskAccessGranted {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isFullDiskAccessGranted = fullDisk
                    }
                    if fullDisk {
                        FinderFavoritesService.shared.refresh()
                    }
                }
            }
            if !isAutomationGranted {
                checkAutomation()
            }
        }
    }

    private func checkAutomation() {
        guard !automationCheckInFlight else { return }
        automationCheckInFlight = true
        PermissionsService.shared.checkAutomationPermission { granted in
            automationCheckInFlight = false
            if granted != isAutomationGranted {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isAutomationGranted = granted
                }
            }
        }
    }

    // MARK: - Permission Step with Timeline

    private func permissionStep(
        number: Int,
        title: String,
        description: String,
        isGranted: Bool,
        isLast: Bool,
        action: @escaping () -> Void,
        settingsAction: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Timeline indicator
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isGranted ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary))
                        .frame(width: 28, height: 28)

                    if isGranted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(number)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if !isLast {
                    Rectangle()
                        .fill(isGranted ? AnyShapeStyle(Color.green.opacity(0.3)) : AnyShapeStyle(.quaternary))
                        .frame(width: 2, height: 36)
                }
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.body)
                        .fontWeight(.semibold)
                    Spacer()
                    if isGranted {
                        Text("Granted")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant") { action() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Escape hatch if the system prompt was denied — TCC won't re-prompt,
                // so the only path forward is flipping the toggle in System Settings.
                if !isGranted, let settingsAction {
                    Button("Denied the prompt? Open System Settings…") { settingsAction() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}
