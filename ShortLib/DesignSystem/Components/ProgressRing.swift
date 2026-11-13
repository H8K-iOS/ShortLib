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

/// Остаток бесплатных глав: «Бесплатные главы  3 из 5» и полоска.
struct QuotaMeter: View {
    let left: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Бесплатные главы").font(DS.Font.callout)
                Spacer()
                Text("\(left) из \(total)").font(DS.Font.headline.monospacedDigit())
            }
            LinearProgress(progress: total > 0 ? Double(left) / Double(total) : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Бесплатно осталось \(RussianPlural.chapters(left)) из \(total)")
    }
}

/// Склонение счётчиков в подписях интерфейса.
enum RussianPlural {
    static func chapters(_ count: Int) -> String {
        "\(count) " + form(count, one: "глава", few: "главы", many: "глав")
    }

    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        let n = abs(count) % 100, last = n % 10
        if (11...14).contains(n) { return many }
        if last == 1 { return one }
        if (2...4).contains(last) { return few }
        return many
    }
}
