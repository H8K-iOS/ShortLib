import SwiftUI

/// Обложка из палитры: градиент + крупный круг. Рисуется один раз, без анимаций.
struct BookCover: View {
    let title: String
    let caption: String
    let style: Int
    var showsText = true

    var body: some View {
        let colors = DS.Color.covers[abs(style) % DS.Color.covers.count]
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { proxy in
                Circle()
                    .fill(DS.Color.accentSoft.opacity(0.85))
                    .frame(width: proxy.size.width * 0.28)
                    .position(x: proxy.size.width * 0.72, y: proxy.size.height * 0.3)
            }
            LinearGradient(colors: [.clear, DS.Color.coverShade], startPoint: .center, endPoint: .bottom)
            if showsText {
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption.uppercased()).font(DS.Font.caption).opacity(0.85)
                    Text(title).font(DS.Font.title).lineLimit(2)
                }
                .foregroundColor(DS.Color.onCover)
                .padding(DS.Space.l)
            }
        }
        .drawingGroup() // растеризуем один раз — дешевле при скролле
    }
}
