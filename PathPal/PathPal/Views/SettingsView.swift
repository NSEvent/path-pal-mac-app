import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsService.shared
    @State private var launchAtLogin = LaunchAtLoginService.shared.isEnabled
    @State private var isAccessibilityGranted = PermissionsService.shared.isAccessibilityGranted
    @State private var isAutomationGranted = false
    @State private var isFullDiskAccessGranted = PermissionsService.shared.isFullDiskAccessGranted
    @State private var permissionsTimer: Timer?
    @State private var excludedApps: [String] = []

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

                settingsCard(icon: "command", iconColor: .orange, title: "Keyboard") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsToggle("Cmd+L path bar (Finder & dialogs)", isOn: Binding(
                            get: { settings.pathBarHotKeyEnabled },
                            set: {
                                settings.pathBarHotKeyEnabled = $0
                                NotificationCenter.default.post(name: .pathPalHotKeysChanged, object: nil)
                            }
                        ))
                        VStack(alignment: .leading, spacing: 2) {
                            settingsToggle("Cmd+Return opens folders / Quick Looks files in Finder", isOn: Binding(
                                get: { settings.finderOpenFolderHotKeyEnabled },
                                set: {
                                    settings.finderOpenFolderHotKeyEnabled = $0
                                    NotificationCenter.default.post(name: .pathPalHotKeysChanged, object: nil)
                                }
                            ))
                            Text("Arrow-key to an item, then Cmd+Return: open a folder in place, or Quick Look a file — browse without the mouse.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            settingsToggle("Backspace goes to the parent folder in Finder", isOn: Binding(
                                get: { settings.finderBackspaceToParentEnabled },
                                set: {
                                    settings.finderBackspaceToParentEnabled = $0
                                    NotificationCenter.default.post(name: .pathPalHotKeysChanged, object: nil)
                                }
                            ))
                            Text("Like Windows Explorer. Ignored while renaming or searching, so it never eats a real backspace.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

                settingsCard(icon: "nosign", iconColor: .red, title: "Excluded Apps") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PathPal leaves Open/Save dialogs from these apps alone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(excludedApps, id: \.self) { bundleID in
                            HStack(spacing: 8) {
                                Text(appDisplayName(for: bundleID))
                                    .font(.system(size: 12))
                                Text(bundleID)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    SettingsService.shared.excludedBundleIDs.removeAll { $0 == bundleID }
                                    refreshExclusions()
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Menu("Add Running App…") {
                            ForEach(runningAppChoices(), id: \.bundleID) { app in
                                Button(app.name) {
                                    var excluded = SettingsService.shared.excludedBundleIDs
                                    if !excluded.contains(app.bundleID) {
                                        excluded.append(app.bundleID)
                                        SettingsService.shared.excludedBundleIDs = excluded
                                    }
                                    refreshExclusions()
                                }
                            }
                        }
                        .frame(maxWidth: 180)
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
            refreshExclusions()
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

    private func refreshExclusions() {
        excludedApps = SettingsService.shared.excludedBundleIDs
    }

    private func appDisplayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    private func runningAppChoices() -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return (bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
