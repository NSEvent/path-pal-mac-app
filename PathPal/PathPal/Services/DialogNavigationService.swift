import ApplicationServices
import Carbon

final class DialogNavigationService {

    /// Navigate an Open/Save dialog to the specified path using Cmd+Shift+G keystroke simulation.
    func navigateDialog(pid: pid_t, toPath path: String) {
        // Step 1: Send Cmd+Shift+G to open "Go to Folder" sheet
        DialogNavigationService.sendCmdShiftG(to: pid)

        // Step 2: Wait for the sheet to appear, then type the path
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            DialogNavigationService.typePath(path, toPid: pid)

            // Step 3: Press Return to confirm
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                DialogNavigationService.pressReturn(toPid: pid)
            }
        }
    }

    private static func sendCmdShiftG(to pid: pid_t) {
        // Key code for 'G' is 5
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 5, keyDown: true)
        keyDown?.flags = [.maskCommand, .maskShift]
        keyDown?.postToPid(pid)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 5, keyDown: false)
        keyUp?.flags = [.maskCommand, .maskShift]
        keyUp?.postToPid(pid)
    }

    private static func typePath(_ path: String, toPid pid: pid_t) {
        // First, select all existing text (Cmd+A)
        let selectAllDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        selectAllDown?.flags = .maskCommand
        selectAllDown?.postToPid(pid)

        let selectAllUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        selectAllUp?.flags = .maskCommand
        selectAllUp?.postToPid(pid)

        // Type the path using unicode string events
        let chars = Array(path.utf16)
        let chunkSize = 20
        for i in stride(from: 0, to: chars.count, by: chunkSize) {
            let end = min(i + chunkSize, chars.count)
            let chunk = Array(chars[i..<end])

            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            var mutableChunk = chunk
            event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &mutableChunk)
            event?.postToPid(pid)

            let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            upEvent?.postToPid(pid)
        }
    }

    private static func pressReturn(toPid pid: pid_t) {
        // Return key code is 36
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)
        keyDown?.postToPid(pid)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)
        keyUp?.postToPid(pid)
    }
}
