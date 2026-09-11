import SwiftUI

struct IDEEditorTabsBar: View {
    @EnvironmentObject private var workspace: IDEWorkspace

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspace.activePaneTabs) { tab in
                    IDEEditorTabItem(tab: tab) {
                        workspace.selectTab(tab.id)
                    } onClose: {
                        workspace.closeTab(tab.id)
                    }
                }
            }
        }
        .frame(height: IDEAppearance.Spacing.tabHeight)
        .background(IDEAppearance.ColorToken.tabBar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(IDEAppearance.ColorToken.border)
                .frame(height: 1)
        }
        .focusable(false)
    }

}

private struct IDEEditorTabItem: View {
    let tab: IDETabRow
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: IDEAppearance.Spacing.sm) {
            Button(tab.title, action: onSelect)
                .buttonStyle(.plain)
                .foregroundStyle(tab.isSelected ? IDEAppearance.ColorToken.foreground : IDEAppearance.ColorToken.muted)
                .lineLimit(1)

            if tab.isDirty {
                Text("•")
                    .foregroundStyle(IDEAppearance.ColorToken.muted)
                    .accessibilityHidden(true)
            }

            Button("Close Tab", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(IDEAppearance.ColorToken.muted)
                .frame(width: 16, height: 16)
        }
        .padding(.horizontal, IDEAppearance.Spacing.md)
        .frame(minWidth: 120, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay(alignment: .top) {
            if tab.isSelected {
                Rectangle()
                    .fill(IDEAppearance.ColorToken.accent)
                    .frame(height: 2)
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var backgroundColor: Color {
        if tab.isSelected {
            return IDEAppearance.ColorToken.tabActive
        }
        if isHovering {
            return IDEAppearance.ColorToken.tabHover
        }
        return IDEAppearance.ColorToken.tabInactive
    }
}

#Preview {
    IDEEditorTabsBar()
        .environmentObject({
            let workspace = IDEWorkspace()
            workspace.activePaneTabs = [
                IDETabRow(id: UUID(), title: "sample.js", isDirty: true, isSelected: true),
                IDETabRow(id: UUID(), title: "README.md", isDirty: false, isSelected: false)
            ]
            return workspace
        }())
        .preferredColorScheme(.dark)
}
