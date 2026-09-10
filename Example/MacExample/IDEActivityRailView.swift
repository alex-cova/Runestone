import SwiftUI

struct IDEActivityRailView: View {
    @EnvironmentObject private var workspace: IDEWorkspace

    var body: some View {
        VStack(spacing: IDEAppearance.Spacing.sm) {
            ForEach(IDEActivityItem.allCases) { item in
                Button(item.title, systemImage: item.symbolName) {
                    workspace.selectActivity(item)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(IDEActivityButtonStyle(isSelected: workspace.selectedActivity == item))
                .help(item.title)
                .frame(width: IDEAppearance.Spacing.railWidth, height: IDEAppearance.Spacing.railWidth)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, IDEAppearance.Spacing.sm)
        .frame(width: IDEAppearance.Spacing.railWidth)
        .background(IDEAppearance.ColorToken.activityRail)
    }
}

private struct IDEActivityButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(isSelected ? Color.white : IDEAppearance.ColorToken.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: IDEAppearance.Radius.control, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            }
            .contentShape(RoundedRectangle(cornerRadius: IDEAppearance.Radius.control, style: .continuous))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return IDEAppearance.ColorToken.selection.opacity(0.55)
        }
        if isPressed {
            return IDEAppearance.ColorToken.tabHover
        }
        return .clear
    }
}

#Preview {
    IDEActivityRailView()
        .environmentObject(IDEWorkspace())
        .frame(height: 420)
        .preferredColorScheme(.dark)
}
