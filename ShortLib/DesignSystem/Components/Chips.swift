import SwiftUI

struct FocusChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Font.label)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .foregroundColor(isOn ? DS.Color.background : DS.Color.ink)
                .background(isOn ? DS.Color.ink : DS.Color.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isOn ? DS.Color.ink : DS.Color.line, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .animation(DS.Motion.respecting(DS.Motion.tap), value: isOn)
    }
}

/// Вкладка категорий с иконкой и подчёркиванием.
struct CategoryTab: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.xs) {
                Image(systemName: systemImage).font(DS.Font.icon)
                Text(title).font(DS.Font.caption)
                Rectangle().fill(isOn ? DS.Color.ink : SwiftUI.Color.clear).frame(height: 2)
            }
            .foregroundColor(isOn ? DS.Color.ink : DS.Color.secondary)
            .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

enum BadgeStyle { case neutral, success, accent }

struct StatusBadge: View {
    let text: String
    var style: BadgeStyle = .neutral
    var systemImage: String?

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(DS.Font.caption.weight(.bold))
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .foregroundColor(foreground)
        .background(background)
        .clipShape(Capsule())
    }

    private var foreground: SwiftUI.Color {
        switch style {
        case .neutral: return DS.Color.ink
        case .success: return DS.Color.success
        case .accent:  return DS.Color.accent
        }
    }

    private var background: SwiftUI.Color {
        switch style {
        case .neutral: return DS.Color.card
        case .success: return DS.Color.successSoft
        case .accent:  return DS.Color.accentSoft
        }
    }
}

/// Плитка-виджет с крупной цифрой: «37 / МИН / ПЕРЕСКАЗ».
struct StatTile: View {
    let value: String
    var unit: String? = nil
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(label).dsOverline()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(DS.Font.number).foregroundColor(DS.Color.ink)
                if let unit {
                    Text(unit).font(DS.Font.caption).foregroundColor(DS.Color.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.m)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous).stroke(DS.Color.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
