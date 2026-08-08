import SwiftUI
import AppKit

/// Экран настроек в основной зоне панели.
struct SettingsTabView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("НАСТРОЙКИ")
                .font(IslandTheme.headerFont)
                .tracking(1.2)
                .foregroundStyle(palette.tertiaryText)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    startupSection
                    limitsSection
                    animationSection
                    folderSection
                    themeSection
                    versionSection
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, IslandTheme.contentHorizontalPadding)
    }

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("При открытии")
            Picker("", selection: $settings.startupScreen) {
                ForEach(StartupScreen.allCases) { screen in
                    Text(screen.title).tag(screen)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 280, alignment: .leading)
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("История буфера")

            sliderRow(
                title: "Макс. строк текста",
                value: $settings.maxTextItems,
                range: 1...100
            )
            sliderRow(
                title: "Макс. скринов / картинок",
                value: $settings.maxImageItems,
                range: 1...100
            )
        }
    }

    private var animationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Анимация")
            Toggle("Анимация при копировании", isOn: $settings.clipboardWaveEnabled)
                .font(.system(size: 12))
                .foregroundStyle(palette.primaryText)
                .toggleStyle(.switch)
                .tint(palette.accentTint)
                .help("Кольцевая вспышка у island при новой записи в буфер обмена")
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Файлы")
            Button {
                NSWorkspace.shared.open(ClipboardStore.shared.imagesDirectory)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .medium))
                    Text("Открыть папку скринов")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(palette.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.controlFill)
                )
            }
            .buttonStyle(.plain)
            .help("Открыть папку изображений в Application Support")
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Тема")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(AppTheme.allCases) { theme in
                    themeSwatch(theme)
                }
            }
        }
    }

    private func themeSwatch(_ theme: AppTheme) -> some View {
        let selected = settings.theme == theme
        return Button {
            settings.theme = theme
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(theme.swatchColor)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .strokeBorder(palette.primaryText.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 0.5)
                    )
                    .shadow(color: .black.opacity(theme == .white ? 0.15 : 0), radius: 1)
                Text(theme.title)
                    .font(.system(size: 9, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? palette.primaryText : palette.tertiaryText)
                    .lineLimit(1)
            }
            .frame(width: 52)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? palette.accentFill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(theme.title)
    }

    private var versionSection: some View {
        HStack {
            Text("Версия")
                .font(.system(size: 11))
                .foregroundStyle(palette.tertiaryText)
            Spacer()
            Text(settings.appVersion)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.top, 4)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.secondaryText)
    }

    private func sliderRow(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(palette.secondaryText)
                    .frame(minWidth: 28, alignment: .trailing)
            }
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            .tint(palette.accentTint)
        }
    }
}
