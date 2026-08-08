import SwiftUI
import AppKit

/// Кладёт строку в системный буфер. Дедуп истории не трогаем — монитор сам подхватит.
enum ClipboardCopy {
    static func copyString(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}

/// Короткий shimmer после копирования (~0.5с).
@MainActor
final class CopyFlashController: ObservableObject {
    @Published private(set) var activeID: UUID?
    private var generation = 0

    func flash(_ id: UUID, duration: TimeInterval = 0.5, completion: (() -> Void)? = nil) {
        generation += 1
        let gen = generation
        activeID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.generation == gen else { return }
            if self.activeID == id {
                self.activeID = nil
            }
            completion?()
        }
    }

    func isFlashing(_ id: UUID) -> Bool {
        activeID == id
    }
}

/// Горизонтальный блик (переливание) по строке.
struct ShimmerSweep: View {
    var cornerRadius: CGFloat = 10
    @Environment(\.themePalette) private var palette
    @State private var progress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let peak = palette.isLight ? Color.black.opacity(0.18) : Color.white.opacity(0.32)
            let mid = palette.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08)
            LinearGradient(
                colors: [
                    .clear,
                    mid,
                    peak,
                    mid,
                    .clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: max(w * 0.45, 48))
            .offset(x: -w * 0.45 + progress * (w + w * 0.45))
            .frame(width: w, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .onAppear {
            progress = 0
            withAnimation(.easeInOut(duration: 0.5)) {
                progress = 1
            }
        }
    }
}

extension View {
    /// Короткое переливание поверх строки/ячейки после копирования.
    func copyShimmer(_ active: Bool, cornerRadius: CGFloat = 10) -> some View {
        overlay {
            if active {
                ShimmerSweep(cornerRadius: cornerRadius)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: active)
    }
}
