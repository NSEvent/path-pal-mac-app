import SwiftUI

struct PathBarView: View {
    @State private var inputText: String = ""
    @State private var completions: [String] = []
    @State private var selectedIndex: Int = 0
    let onNavigate: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Enter path...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, design: .monospaced))
                    .onSubmit {
                        let path = (inputText as NSString).expandingTildeInPath
                        onNavigate(path)
                    }
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(completions.prefix(10).enumerated()), id: \.offset) { index, path in
                            HStack {
                                let isDir = path.hasSuffix("/")
                                Image(systemName: isDir ? "folder.fill" : "doc")
                                    .foregroundStyle(isDir ? .blue : .secondary)
                                    .frame(width: 16)
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Text(path)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(index == selectedIndex ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(4)
                            .onTapGesture {
                                inputText = path
                                if path.hasSuffix("/") {
                                    updateCompletions(for: path)
                                } else {
                                    onNavigate(path)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
            }
        }
        .frame(width: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 20)
    }

    private func updateCompletions(for input: String) {
        completions = PathBarService.completions(for: input)
        selectedIndex = 0
    }
}
