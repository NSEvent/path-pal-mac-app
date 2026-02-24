import SwiftUI

struct SettingsView: View {
    @State private var settings = SettingsService.shared
    @State private var launchAtLogin = LaunchAtLoginService.shared.isEnabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginService.shared.isEnabled = newValue
                    }

                LabeledContent("Max recent folders") {
                    Stepper(value: Binding(
                        get: { settings.maxRecentFolders },
                        set: { settings.maxRecentFolders = $0 }
                    ), in: 10...100, step: 10) {
                        Text("\(settings.maxRecentFolders)")
                    }
                }

                LabeledContent("Max recent files") {
                    Stepper(value: Binding(
                        get: { settings.maxRecentFiles },
                        set: { settings.maxRecentFiles = $0 }
                    ), in: 10...100, step: 10) {
                        Text("\(settings.maxRecentFiles)")
                    }
                }
            }

            Section("Open/Save Dialogs") {
                Toggle("Highlight Finder windows", isOn: Binding(
                    get: { settings.highlightFinderWindows },
                    set: { settings.highlightFinderWindows = $0 }
                ))
                Toggle("Show Finder window paths on hover", isOn: Binding(
                    get: { settings.showFinderWindowNames },
                    set: { settings.showFinderWindowNames = $0 }
                ))
                Toggle("Click Finder window to navigate", isOn: Binding(
                    get: { settings.clickFinderWindowToChoose },
                    set: { settings.clickFinderWindowToChoose = $0 }
                ))
                Toggle("Click desktop to navigate to ~/Desktop", isOn: Binding(
                    get: { settings.clickDesktopToChoose },
                    set: { settings.clickDesktopToChoose = $0 }
                ))
                Toggle("Auto-select last file in Open dialogs", isOn: Binding(
                    get: { settings.autoSelectLastFile },
                    set: { settings.autoSelectLastFile = $0 }
                ))
                Toggle("Default Save to document's folder", isOn: Binding(
                    get: { settings.defaultToDocumentFolder },
                    set: { settings.defaultToDocumentFolder = $0 }
                ))
            }

            Section("Path Bar") {
                Toggle("Enable Cmd+L path bar (Finder only)", isOn: Binding(
                    get: { settings.pathBarHotKeyEnabled },
                    set: { settings.pathBarHotKeyEnabled = $0 }
                ))
            }

            Section("Permissions") {
                HStack {
                    Text("Accessibility")
                    Spacer()
                    if PermissionsService.shared.isAccessibilityGranted {
                        Text("Granted").foregroundStyle(.green)
                    } else {
                        Button("Grant Access") {
                            PermissionsService.shared.requestAccessibility()
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("PathPal")
                        .font(.headline)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
    }
}
