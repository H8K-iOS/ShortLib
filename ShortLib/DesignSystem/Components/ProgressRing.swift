import SwiftUI

/// Кольцо прогресса. Анимируется только `trim` (дёшево), без бесконечных вращений.
struct ProgressRing: View {
    let progress: Double
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Circle().stroke(DS.Color.line, lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(DS.Color.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(DS.Motion.respecting(DS.Motion.progress), value: progress)
            VStack(spacing: 2) {
                Text(title).font(DS.Font.number)
                Text(subtitle).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
            }
        }
        .frame(width: 140, height: 140)
    }
}

struct LinearProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.Color.line)
                Capsule().fill(DS.Color.accent)
                    .frame(width: proxy.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 4)
        .animation(DS.Motion.respecting(DS.Motion.progress), value: progress)
    }
}
