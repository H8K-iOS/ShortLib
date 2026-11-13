import SwiftUI

struct DetailLevelPicker: View {
    @Binding var level: DetailLevel
    @Binding var ratio: Double

    private var percent: Int { Int((ratio * 100).rounded()) }
    private static let minWords = "\(DetailLevel.allCases.first?.wordRange.lowerBound ?? 0) слов"
    private static let maxWords = "\(DetailLevel.allCases.last?.wordRange.upperBound ?? 0) слов"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: 0) {
                ForEach(DetailLevel.allCases) { item in
                    Button {
                        withAnimation(DS.Motion.respecting(DS.Motion.standard)) {
                            level = item
                            ratio = item.defaultRatio
                        }
                    } label: {
                        Text(item.title)
                            .font(DS.Font.label)
                            .foregroundColor(level == item ? DS.Color.ink : DS.Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(level == item ? DS.Color.card : SwiftUI.Color.clear)
                                    .shadow(color: DS.Color.ink.opacity(level == item ? 0.12 : 0), radius: 2, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).stroke(DS.Color.line, lineWidth: 1))

            // Длина задаётся диапазоном слов уровня; процент — только ориентир.
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Длина главы в пересказе").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(level.wordRangeText).font(DS.Font.title.monospacedDigit())
                    Spacer()
                    Text("≈ \(percent)% от оригинала").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Slider(value: $ratio, in: DetailLevel.ratioRange, step: 0.01)
                .tint(DS.Color.accent)
                .onChange(of: ratio) { newValue in
                    level = DetailLevel.nearest(to: newValue)
                }
                .accessibilityLabel("Детальность")
                .accessibilityValue("\(level.title), \(level.wordRangeText) на главу")
            HStack {
                Text("тезисы · \(Self.minWords)")
                Spacer()
                Text("\(Self.maxWords) · подробно")
            }
            .accessibilityHidden(true)
            .font(DS.Font.caption)
            .foregroundColor(DS.Color.secondary)
        }
    }
}

extension DetailLevel {
    /// Подпись длины пересказа главы для интерфейса: «≈ 400–700 слов».
    var wordRangeText: String { "≈ \(wordRange.lowerBound)–\(wordRange.upperBound) слов" }
}
