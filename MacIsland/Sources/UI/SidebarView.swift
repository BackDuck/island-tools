import SwiftUI

struct SidebarView: View {
    @Binding var selected: IslandTab
    @Binding var showingSettings: Bool
    var onSelectTab: (IslandTab) -> Void
    @Environment(\.themePalette) private var palette

    /// Визуальный размер иконки.
    private let iconVisual: CGFloat = 28
    /// Зона клика — компактнее, чтобы 4 вкладки + gear влезли в 280pt с padding.
    private let hitSize: CGFloat = 34
    private let itemGap: CGFloat = 4

    var body: some View {
        ZStack(alignment: .top) {
            palette.sidebarFill

            VStack(spacing: itemGap) {
                ForEach(IslandTab.allCases) { tab in
                    tabButton(tab)
                }
                Spacer(minLength: 0)
                settingsButton
            }
            .padding(.top, IslandTheme.contentTopInset + 2)
            .padding(.bottom, IslandTheme.contentBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(IslandShape.sidebar)
    }

    private func tabButton(_ tab: IslandTab) -> some View {
        let active = !showingSettings && selected == tab
        return Button {
            onSelectTab(tab)
        } label: {
            Image(systemName: tab.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? palette.primaryText : palette.secondaryText)
                .frame(width: iconVisual, height: iconVisual)
                .background {
                    if active {
                        Circle()
                            .fill(palette.accentFill)
                    }
                }
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.shortTitle)
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(showingSettings ? palette.primaryText : palette.secondaryText)
                .frame(width: iconVisual, height: iconVisual)
                .background {
                    if showingSettings {
                        Circle()
                            .fill(palette.accentFill)
                    }
                }
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Настройки")
    }
}
