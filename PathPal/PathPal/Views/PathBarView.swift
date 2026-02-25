import SwiftUI
import AppKit

enum OpenTarget: String, CaseIterable {
    case finder = "Finder"
    case iTerm = "iTerm"
}

struct PathBarView: View {
    @State private var inputText: String = NSHomeDirectory() + "/"
    @State private var completions: [String] = []
    @State private var selectedIndex: Int = 0
    @State private var openTarget: OpenTarget = .finder
    let onNavigate: (String) -> Void
    let onOpen: (String, OpenTarget) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                FocusedTextField(
                    text: $inputText,
                    onSubmit: { openCurrent(target: openTarget) },
                    onArrowDown: { moveSelection(1) },
                    onArrowUp: { moveSelection(-1) },
                    onTab: { acceptCompletion() },
                    onEscape: { onDismiss() }
                )
                .font(.system(size: 16, design: .monospaced))
                .onChange(of: inputText) { _, newValue in
                    updateCompletions(for: newValue)
                }

                if !inputText.isEmpty {
                    Button(action: { inputText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !completions.isEmpty {
                Divider()
                let visible = Array(completions.prefix(10))
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.offset) { index, path in
                                let isDir = path.hasSuffix("/")
                                HStack {
                                    Image(systemName: isDir ? "folder.fill" : "doc")
                                        .foregroundStyle(isDir ? .blue : .secondary)
                                        .frame(width: 16)
                                    Text((path as NSString).lastPathComponent.replacingOccurrences(of: "/", with: ""))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(abbreviatePath(path))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(4)
                                .id(index)
                                .onTapGesture {
                                    selectItem(at: index)
                                }
                            }
                        }
                        .padding(4)
                    }
                    .frame(height: CGFloat(visible.count) * 30)
                    .onChange(of: selectedIndex) { _, newIndex in
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            Divider()

            // Hints bar
            HStack(spacing: 12) {
                hintLabel("Tab", "complete")
                hintLabel("Enter", "open")

                Spacer()

                // Open target segmented control
                HStack(spacing: 0) {
                    ForEach(OpenTarget.allCases, id: \.self) { target in
                        Button(action: { openTarget = target }) {
                            Text(target.rawValue)
                                .font(.system(size: 10, weight: target == openTarget ? .semibold : .regular))
                                .foregroundStyle(target == openTarget ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(target == openTarget ? Color.accentColor.opacity(0.2) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 500)
        .frame(maxHeight: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 20)
        .onAppear {
            updateCompletions(for: inputText)
        }
    }

    private func hintLabel(_ key: String, _ action: String) -> some View {
        HStack(spacing: 2) {
            Text(key)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(3)
            Text(action)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func updateCompletions(for input: String) {
        completions = PathBarService.completions(for: input)
        selectedIndex = 0
    }

    private func moveSelection(_ delta: Int) {
        guard !completions.isEmpty else { return }
        let count = min(completions.count, 10)
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func acceptCompletion() {
        guard !completions.isEmpty, selectedIndex < completions.count else { return }
        let path = completions[selectedIndex]
        inputText = path
        updateCompletions(for: path)
    }

    private func selectItem(at index: Int) {
        guard index < completions.count else { return }
        let path = completions[index]
        if path.hasSuffix("/") {
            inputText = path
            updateCompletions(for: path)
        } else {
            onNavigate(path)
        }
    }

    private func openCurrent(target: OpenTarget) {
        let path: String
        if !completions.isEmpty, selectedIndex < completions.count {
            path = completions[selectedIndex]
        } else {
            path = (inputText as NSString).expandingTildeInPath
        }
        // For files, open the parent directory
        let dirPath = path.hasSuffix("/") ? String(path.dropLast()) : (path as NSString).deletingLastPathComponent
        onOpen(dirPath, target)
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - NSTextField wrapper for auto-focus and key handling

struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onTab: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = KeyInterceptingTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        field.placeholderString = "Enter path..."
        field.stringValue = text
        field.coordinator = context.coordinator

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            field.window?.makeFirstResponder(field)
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: field.stringValue.count, length: 0)
            }
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
            if let editor = nsView.currentEditor() {
                editor.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedTextField

        init(_ parent: FocusedTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp()
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}

class KeyInterceptingTextField: NSTextField {
    weak var coordinator: FocusedTextField.Coordinator?
}
