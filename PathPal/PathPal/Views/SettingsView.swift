import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsService.shared
    @State private var launchAtLogin = LaunchAtLoginService.shared.isEnabled
    @State private var isAccessibilityGranted = PermissionsService.shared.isAccessibilityGranted
    @State private var isAutomationGranted = false
    @State private var isFullDiskAccessGranted = PermissionsService.shared.isFullDiskAccessGranted
    @State private var permissionsTimer: Timer?

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                settingsCard(icon: "gearshape", iconColor: .gray, title: "General") {
                    VStack(spacing: 12) {
                        settingsToggle("Launch at login", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, newValue in
                                LaunchAtLoginService.shared.isEnabled = newValue
                            }

                        Divider()

                        settingsStepper(
                            label: "Max recent folders",
                            value: Binding(
                                get: { settings.maxRecentFolders },
                                set: { settings.maxRecentFolders = $0 }
                            ),
                            range: 10...100,
                            step: 10
                        )

                        settingsStepper(
                            label: "Max recent files",
                            value: Binding(
                                get: { settings.maxRecentFiles },
                                set: { settings.maxRecentFiles = $0 }
                            ),
                            range: 10...100,
                            step: 10
                        )
                    }
                }

                settingsCard(icon: "macwindow.on.rectangle", iconColor: .blue, title: "Open/Save Dialogs") {
                    VStack(spacing: 12) {
                        settingsToggle("Highlight Finder windows", isOn: Binding(
                            get: { settings.highlightFinderWindows },
                            set: { settings.highlightFinderWindows = $0 }
                        ))
                        settingsToggle("Show Finder window paths on hover", isOn: Binding(
                            get: { settings.showFinderWindowNames },
                            set: { settings.showFinderWindowNames = $0 }
                        ))
                        settingsToggle("Click Finder window to navigate", isOn: Binding(
                            get: { settings.clickFinderWindowToChoose },
                            set: { settings.clickFinderWindowToChoose = $0 }
                        ))

                        Divider()

                        settingsToggle("Click desktop to navigate to ~/Desktop", isOn: Binding(
                            get: { settings.clickDesktopToChoose },
                            set: { settings.clickDesktopToChoose = $0 }
                        ))
                        settingsToggle("Auto-select last file in Open dialogs", isOn: Binding(
                            get: { settings.autoSelectLastFile },
                            set: { settings.autoSelectLastFile = $0 }
                        ))
                        settingsToggle("Default Save to document's folder", isOn: Binding(
                            get: { settings.defaultToDocumentFolder },
                            set: { settings.defaultToDocumentFolder = $0 }
                        ))
                    }
                }

                settingsCard(icon: "command", iconColor: .orange, title: "Path Bar") {
                    settingsToggle("Enable Cmd+L path bar (Finder only)", isOn: Binding(
                        get: { settings.pathBarHotKeyEnabled },
                        set: { settings.pathBarHotKeyEnabled = $0 }
                    ))
                }

                settingsCard(icon: "tray.full", iconColor: .indigo, title: "File Drawer") {
                    VStack(alignment: .leading, spacing: 6) {
                        settingsToggle("Enable file drawer", isOn: Binding(
                            get: { settings.fileDrawerEnabled },
                            set: {
                                settings.fileDrawerEnabled = $0
                                FileDrawerService.shared.setEnabled($0)
                            }
                        ))
                        Text("A floating shelf: drag files onto it to park them, then drag them out to Finder, dialogs, or other apps.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard(icon: "lock.shield", iconColor: .green, title: "Permissions") {
                    VStack(spacing: 12) {
                        permissionRow("Accessibility", isGranted: isAccessibilityGranted) {
                            PermissionsService.shared.requestAccessibility()
                            PermissionsService.shared.openAccessibilityPreferences()
                        }
                        permissionRow("Automation (Finder)", isGranted: isAutomationGranted) {
                            refreshAutomationStatus()
                            PermissionsService.shared.openAutomationPreferences()
                        }
                        permissionRow("Full Disk Access", detail: "Optional", isGranted: isFullDiskAccessGranted) {
                            PermissionsService.shared.openFullDiskAccessPreferences()
                        }
                    }
                }

                // App identity footer
                HStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text("PathPal \(appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(24)
        }
        .frame(width: 480, height: 540)
        .onAppear {
            refreshPermissionStatuses()
            permissionsTimer?.invalidate()
            permissionsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                refreshPermissionStatuses()
            }
        }
        .onDisappear {
            permissionsTimer?.invalidate()
            permissionsTimer = nil
        }
    }

    private func refreshPermissionStatuses() {
        isAccessibilityGranted = PermissionsService.shared.isAccessibilityGranted
        let fullDisk = PermissionsService.shared.isFullDiskAccessGranted
        if fullDisk != isFullDiskAccessGranted {
            isFullDiskAccessGranted = fullDisk
            if fullDisk {
                FinderFavoritesService.shared.refresh()
            }
        }
        refreshAutomationStatus()
    }

    private func refreshAutomationStatus() {
        PermissionsService.shared.checkAutomationPermission { granted in
            isAutomationGranted = granted
        }
    }

    private func permissionRow(_ name: String, detail: String? = nil, isGranted: Bool, grantAction: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.body)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isGranted {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.5), radius: 3)
                    Text("Active")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
            } else {
                Button("Grant Access") { grantAction() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Card Container

    private func settingsCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )
        }
    }

    // MARK: - Reusable Controls

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .font(.body)
    }

    private func settingsStepper(label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .monospacedDigit()
            }
        }
    }
}
