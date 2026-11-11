import SwiftUI

struct DetailLevelPicker: View {
    @Binding var level: DetailLevel
    @Binding var ratio: Double

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

            HStack {
                Text("Объём от оригинала").font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                Spacer()
                Text("\(Int((ratio * 100).rounded()))%").font(DS.Font.title.monospacedDigit())
            }
            Slider(value: $ratio, in: DetailLevel.ratioRange, step: 0.01)
                .tint(DS.Color.accent)
                .onChange(of: ratio) { newValue in
                    level = DetailLevel.nearest(to: newValue)
                }
            HStack {
                Text("3% · тезисы")
                Spacer()
                Text("25% · подробно")
            }
            .font(DS.Font.caption)
            .foregroundColor(DS.Color.secondary)
        }
    }
}
