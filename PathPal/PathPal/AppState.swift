import Foundation
import Observation

@Observable
final class AppState {
    var recentFolders: [RecentFolder] = []
    var recentFiles: [RecentFile] = []
    var finderWindows: [FinderWindow] = []
    var currentDialog: DialogInfo?
    var isAccessibilityGranted: Bool = false
    var hasCompletedOnboarding: Bool = false
}
