import SwiftUI

struct IDESidebarPanel: View {
    @EnvironmentObject private var workspace: IDEWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: IDEAppearance.Spacing.sm) {
            Text("EXPLORER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(IDEAppearance.ColorToken.sidebarHeading)
                .padding(.horizontal, IDEAppearance.Spacing.lg)
                .padding(.top, IDEAppearance.Spacing.md)

            if workspace.sidebarDocuments.isEmpty {
                VStack(spacing: IDEAppearance.Spacing.sm) {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundStyle(IDEAppearance.ColorToken.muted)
                    Text("No Open Files")
                        .font(.subheadline)
                        .foregroundStyle(IDEAppearance.ColorToken.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(workspace.sidebarDocuments) { document in
                            Button {
                                workspace.selectSidebarDocument(document.id)
                            } label: {
                                HStack(spacing: IDEAppearance.Spacing.sm) {
                                    Image(systemName: iconName(for: document.title))
                                        .foregroundStyle(IDEAppearance.ColorToken.muted)
                                        .frame(width: 16)
                                    Text(document.title)
                                        .lineLimit(1)
                                        .foregroundStyle(IDEAppearance.ColorToken.foreground)
                                    Spacer(minLength: 0)
                                    if document.isDirty {
                                        Circle()
                                            .fill(IDEAppearance.ColorToken.foreground)
                                            .frame(width: 6, height: 6)
                                            .accessibilityLabel("Edited")
                                    }
                                }
                                .padding(.horizontal, IDEAppearance.Spacing.lg)
                                .padding(.vertical, IDEAppearance.Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    document.isSelected
                                        ? IDEAppearance.ColorToken.selection.opacity(0.45)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .frame(width: IDEAppearance.Spacing.sidebarWidth)
        .background(IDEAppearance.ColorToken.sidebar)
        .focusable(false)
    }

    private func iconName(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "swift": "swift"
        case "js", "jsx", "ts", "tsx": "curlybraces"
        case "json": "curlybraces.square"
        case "md", "markdown": "text.book.closed"
        case "py": "chevron.left.forwardslash.chevron.right"
        default: "doc.text"
        }
    }
}

#Preview {
    IDESidebarPanel()
        .environmentObject({
            let workspace = IDEWorkspace()
            workspace.sidebarDocuments = [
                IDEDocumentRow(id: UUID(), title: "sample.js", languageIdentifier: "javascript", isDirty: true, isSelected: true),
                IDEDocumentRow(id: UUID(), title: "README.md", languageIdentifier: "markdown", isDirty: false, isSelected: false)
            ]
            return workspace
        }())
        .frame(height: 420)
        .preferredColorScheme(.dark)
}
