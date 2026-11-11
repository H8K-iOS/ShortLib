import SwiftUI

struct SearchPill: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.m) {
                Image(systemName: "magnifyingglass").font(DS.Font.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.Font.headline)
                    Text(subtitle).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(DS.Font.caption)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(DS.Color.line, lineWidth: 1))
            }
            .foregroundColor(DS.Color.ink)
            .padding(.vertical, 10)
            .padding(.horizontal, DS.Space.l)
            .background(DS.Color.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DS.Color.line, lineWidth: 1))
            .shadow(color: DS.Color.ink.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(PressScaleStyle())
    }
}
