import SwiftUI

/// Кольцо прогресса в стиле «тёплый свет»: толстая тёплая дуга и неподвижное свечение за ней.
/// Анимируется только `trim` (дёшево), без бесконечных вращений.
struct ProgressRing: View {
    let progress: Double
    let title: String
    let subtitle: String
    var size: CGFloat = 180
    var lineWidth: CGFloat = 16

    var body: some View {
        ZStack {
            // Свечение рисуется один раз и не анимируется.
            Circle()
                .fill(DS.Color.glow(radius: size * 0.75))
                .frame(width: size * 1.6, height: size * 1.6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Circle().stroke(DS.Color.line, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(DS.Color.progressArc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(DS.Motion.respecting(DS.Motion.progress), value: progress)
            VStack(spacing: 2) {
                Text(title).font(DS.Font.number)
                Text(subtitle).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(width: size, height: size)
    }
}

/// Элемент можно потянуть пальцем — он упруго тянется и наклоняется, а после отпускания
/// возвращается на место (ease-out 0.2 с, без пружин). Двигаются только offset и поворот.
struct ElasticDrag: ViewModifier {
    /// Максимальный сдвиг в точках, дальше — сопротивление.
    var limit: CGFloat = 70
    @State private var offset: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(Double(offset.width) / 5), axis: (x: 0, y: 1, z: 0))
            .rotation3DEffect(.degrees(Double(-offset.height) / 5), axis: (x: 1, y: 0, z: 0))
            .offset(offset)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        offset = CGSize(width: rubber(value.translation.width), height: rubber(value.translation.height))
                    }
                    .onEnded { _ in
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        withAnimation(DS.Motion.respecting(DS.Motion.standard)) { offset = .zero }
                    }
            )
    }

    /// «Резина»: чем дальше тянешь, тем сильнее сопротивление; не уходит дальше `limit`.
    private func rubber(_ x: CGFloat) -> CGFloat {
        let sign: CGFloat = x < 0 ? -1 : 1
        return sign * limit * (1 - 1 / (abs(x) / limit * 0.55 + 1))
    }
}

/// Один проход блика по элементу — при появлении и при каждой смене `trigger`. Не цикл.
struct ShimmerOnce<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    var isActive = true
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { proxy in
                    let band = proxy.size.width * 0.45
                    DS.Color.shimmer
                        .frame(width: band)
                        .offset(x: -band + phase * (proxy.size.width + band))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            )
            .onAppear(perform: run)
            .onChange(of: trigger) { _ in run() }
    }

    private func run() {
        guard isActive, let animation = DS.Motion.respecting(DS.Motion.shimmer) else { return }
        withAnimation(nil) { phase = 0 }
        DispatchQueue.main.async {
            withAnimation(animation) { phase = 1 }
        }
    }
}

extension View {
    /// Потянуть и отпустить: элемент возвращается на место.
    func dsElasticDrag(limit: CGFloat = 70) -> some View { modifier(ElasticDrag(limit: limit)) }
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

/// Подпись оставшегося времени: «Примерно 12 мин», «Меньше минуты» или «Считаем время…».
enum WaitTimeText {
    static func text(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "Считаем время…" }
        if seconds < 60 { return "Меньше минуты" }
        return "Примерно \(Int((seconds / 60).rounded())) мин"
    }

    /// Короткая форма для бейджей: «≈ 12 мин», «< 1 мин»; `nil`, пока оценки нет.
    static func short(_ seconds: TimeInterval?) -> String? {
        guard let seconds else { return nil }
        return seconds < 60 ? "< 1 мин" : "≈ \(Int((seconds / 60).rounded())) мин"
    }
}
