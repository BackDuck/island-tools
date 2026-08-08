import SwiftUI
import AppKit

struct MusicTabView: View {
    let info: NowPlayingInfo
    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onPrev: () -> Void
    var onSeek: (Double) -> Void

    @Environment(\.themePalette) private var palette

    /// Локальный прогресс пока тянем — polling не дёргает бар обратно.
    @State private var scrubFraction: Double?
    @State private var isScrubbing = false
    /// База для интерполяции elapsed между внешними refresh.
    @State private var syncedElapsed: TimeInterval = 0
    @State private var syncedAt: Date = .now
    @State private var syncedPlaying = false
    @State private var syncedDuration: TimeInterval = 0
    /// Какое поле сейчас переливается после копирования.
    @State private var flashedField: CopiedField?

    private enum CopiedField: Equatable {
        case title
        case subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(IslandTab.music.title)
                    .font(IslandTheme.headerFont)
                    .tracking(1.2)
                    .foregroundStyle(palette.tertiaryText)
                Spacer(minLength: 12)
                if !info.appName.isEmpty {
                    Text(info.appName.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(palette.tertiaryText)
                        .lineLimit(1)
                }
            }

            // Метаданные важнее обложки: показываем плеер при любом валидном Now Playing.
            if info.isAvailable {
                playingContent
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, IslandTheme.contentHorizontalPadding)
        .onAppear { resync(from: info) }
        .onChange(of: info) { _, new in
            // Внешний refresh (JXA/MR) — пересинхронизируем базу, scrub не трогаем.
            if !isScrubbing {
                resync(from: new)
            }
        }
    }

    private func resync(from info: NowPlayingInfo) {
        syncedElapsed = info.elapsed
        syncedAt = Date()
        syncedPlaying = info.isPlaying
        syncedDuration = info.duration
    }

    /// Elapsed с учётом wall-clock, пока играет.
    private func liveElapsed(at date: Date) -> TimeInterval {
        if let scrubFraction {
            return scrubFraction * max(syncedDuration, 0)
        }
        guard syncedPlaying else { return syncedElapsed }
        let predicted = syncedElapsed + date.timeIntervalSince(syncedAt)
        if syncedDuration > 0 {
            return min(max(predicted, 0), syncedDuration)
        }
        return max(predicted, 0)
    }

    private func liveFraction(at date: Date) -> Double {
        if let scrubFraction { return scrubFraction }
        guard syncedDuration > 0 else { return 0 }
        return min(max(liveElapsed(at: date) / syncedDuration, 0), 1)
    }

    private var playingContent: some View {
        // ~8 Hz тик прогресса; пока пауза liveElapsed просто держит базу.
        TimelineView(.periodic(from: .now, by: 0.125)) { timeline in
            let elapsed = liveElapsed(at: timeline.date)
            let fraction = liveFraction(at: timeline.date)

            VStack(alignment: .leading, spacing: IslandTheme.contentBlockGap) {
                HStack(alignment: .center, spacing: 16) {
                    artworkView
                        .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: 5) {
                        copyableLine(info.title, field: .title, font: IslandTheme.titleFont, color: palette.primaryText, limit: 2)
                        copyableLine(
                            info.subtitle.isEmpty ? " " : info.subtitle,
                            field: .subtitle,
                            font: IslandTheme.subtitleFont,
                            color: palette.secondaryText,
                            limit: 2,
                            enabled: !info.subtitle.isEmpty
                        )
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                scrubber(fraction: fraction, elapsed: elapsed)

                HStack(spacing: 32) {
                    Spacer(minLength: 0)
                    controlButton("backward.fill", action: onPrev)
                    controlButton(info.isPlaying ? "pause.fill" : "play.fill", size: 20, action: onPlayPause)
                    controlButton("forward.fill", action: onNext)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "music.note")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(palette.tertiaryText)
            Text("Сейчас ничего не играет")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.secondaryText)
            Text("Музыка / Spotify / Chrome — что угодно с Now Playing")
                .font(.system(size: 11))
                .foregroundStyle(palette.tertiaryText)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var artworkView: some View {
        Group {
            if let data = info.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    // SwiftUI кэширует Image(nsImage:) — без id обложка может не обновиться.
                    .id(data.count ^ (info.title.hashValue &* 31))
            } else {
                ZStack {
                    palette.rowFill
                    Image(systemName: "music.note")
                        .font(.system(size: 28))
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func scrubber(fraction: Double, elapsed: TimeInterval) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let trackH: CGFloat = isScrubbing ? 7 : 5
                let thumb: CGFloat = isScrubbing ? 14 : 10
                let x = geo.size.width * CGFloat(fraction)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.scrubberTrack)
                        .frame(height: trackH)

                    Capsule()
                        .fill(palette.scrubberFill)
                        .frame(width: max(trackH, x), height: trackH)

                    Circle()
                        .fill(palette.accentTint)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                        .position(
                            x: min(max(thumb / 2, x), geo.size.width - thumb / 2),
                            y: geo.size.height / 2
                        )
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let f = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                            isScrubbing = true
                            scrubFraction = f
                        }
                        .onEnded { value in
                            let f = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                            scrubFraction = f
                            // Локально фиксируем базу под scrub, пока MR не ответит.
                            syncedElapsed = f * max(syncedDuration, 0)
                            syncedAt = Date()
                            onSeek(f)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                isScrubbing = false
                                scrubFraction = nil
                            }
                        }
                )
            }
            .frame(height: 18)

            HStack {
                Text(formatTime(elapsed))
                Spacer()
                Text(formatTime(syncedDuration > 0 ? syncedDuration : info.duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(palette.tertiaryText)
        }
    }

    private func copyableLine(
        _ text: String,
        field: CopiedField,
        font: Font,
        color: Color,
        limit: Int,
        enabled: Bool = true
    ) -> some View {
        let flashing = flashedField == field
        return Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(limit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
            .copyShimmer(flashing, cornerRadius: 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard enabled else { return }
                copyField(field, text)
            }
            .help(enabled ? "Скопировать" : "")
    }

    private func copyField(_ field: CopiedField, _ text: String) {
        ClipboardCopy.copyString(text)
        flashedField = field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if flashedField == field {
                flashedField = nil
            }
        }
    }

    private func controlButton(_ systemName: String, size: CGFloat = 15, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(palette.primaryText)
                .frame(width: 40, height: 40)
                .background(Circle().fill(palette.controlFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
