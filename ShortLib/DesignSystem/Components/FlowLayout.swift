import SwiftUI

/// Перенос чипов по строкам (Layout доступен с iOS 16).
struct FlowLayout: Layout {
    var spacing: CGFloat = DS.Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Заголовок группы настроек + разделитель.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text(title).font(DS.Font.title)
            content
            Rectangle().fill(DS.Color.line).frame(height: 1).padding(.top, DS.Space.s)
        }
    }
}

/// Карточка-объяснение: иконка, заголовок, текст и действия.
/// Для пустых состояний, ошибок и ограничений (например, «Бесплатные главы закончились»).
struct NoticeCard<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: systemImage)
                .font(DS.Font.icon)
                .foregroundColor(DS.Color.secondary)
                .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                Text(title).font(DS.Font.headline)
                Text(message)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            actions
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Space.l)
        .dsCard()
    }
}
