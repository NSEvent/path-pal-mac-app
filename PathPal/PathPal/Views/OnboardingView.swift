import SwiftUI

struct OnboardingView: View {
    @State private var isAccessibilityGranted = PermissionsService.shared.isAccessibilityGranted
    @State private var isAutomationGranted = false
    @State private var isFullDiskAccessGranted = PermissionsService.shared.isFullDiskAccessGranted
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to PathPal")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("PathPal enhances macOS Open/Save dialogs with quick folder navigation, recent items, and Finder window integration.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    title: "Accessibility",
                    description: "Required to detect Open/Save dialogs and navigate them",
                    isGranted: isAccessibilityGranted,
                    action: {
                        PermissionsService.shared.requestAccessibility()
                        // Poll for change
                        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                            if PermissionsService.shared.isAccessibilityGranted {
                                isAccessibilityGranted = true
                                timer.invalidate()
                            }
                        }
                    }
                )

                permissionRow(
                    title: "Automation (Finder)",
                    description: "Required to read Finder window paths and navigate",
                    isGranted: isAutomationGranted,
                    action: {
                        // This triggers the system permission dialog
                        let granted = PermissionsService.shared.requestAndCheckAutomationPermission()
                        isAutomationGranted = granted
                        if !granted {
                            // Poll in case user grants it in the dialog
                            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                                if PermissionsService.shared.requestAndCheckAutomationPermission() {
                                    isAutomationGranted = true
                                    timer.invalidate()
                                }
                            }
                        }
                    }
                )

                permissionRow(
                    title: "Full Disk Access",
                    description: "Optional — enables reading Finder sidebar favorites",
                    isGranted: isFullDiskAccessGranted,
                    action: {
                        PermissionsService.shared.openFullDiskAccessPreferences()
                        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
                            if PermissionsService.shared.isFullDiskAccessGranted {
                                isFullDiskAccessGranted = true
                                timer.invalidate()
                            }
                        }
                    }
                )
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))

            Button("Get Started") {
                SettingsService.shared.hasCompletedOnboarding = true
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isAccessibilityGranted)
        }
        .padding(40)
        .frame(width: 500, height: 500)
        .onAppear {
            // Check automation on appear (may already be granted)
            isAutomationGranted = PermissionsService.shared.requestAndCheckAutomationPermission()
        }
    }

    private func permissionRow(title: String, description: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            } else {
                Button("Grant") { action() }
                    .buttonStyle(.bordered)
            }
        }
    }
}
