import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isFullWidth = false
    var isEnabled = true
    /// Если задан — по кнопке проходит блик при появлении и при каждой смене значения.
    var shimmerTrigger: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.onAccent)
                // Главная кнопка всегда в одну строку: сжимается соседний текст, а не она.
                .lineLimit(1)
                .fixedSize(horizontal: !isFullWidth, vertical: false)
                .padding(.vertical, 14)
                .padding(.horizontal, DS.Space.xl)
                .frame(maxWidth: isFullWidth ? .infinity : nil)
                .background(DS.Color.cta)
                .modifier(ShimmerOnce(trigger: shimmerTrigger ?? 0, isActive: shimmerTrigger != nil))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!isEnabled)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.headline)
                .foregroundColor(DS.Color.ink)
                .padding(.vertical, 13)
                .padding(.horizontal, DS.Space.xl)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous).stroke(DS.Color.ink, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct TextLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(DS.Font.headline).underline().foregroundColor(DS.Color.ink)
        }
    }
}

/// Лёгкая реакция на нажатие: только scale, 0.12 c.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.Motion.respecting(DS.Motion.tap), value: configuration.isPressed)
    }
}

/// Нижняя «липкая» панель как на странице объявления.
struct FooterBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Color.line).frame(height: 1)
            HStack(spacing: DS.Space.m) {
                leading
                Spacer(minLength: DS.Space.s)
                trailing
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.m)
        }
        .background(DS.Color.background)
    }
}

/// Круглая кнопка навигации (назад, закрыть, поделиться).
struct CircleIconButton: View {
    let systemImage: String
    var accessibilityTitle: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(DS.Font.label)
                .foregroundColor(DS.Color.ink)
                .frame(width: 34, height: 34)
                .background(DS.Color.card)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(accessibilityTitle)
    }
}
