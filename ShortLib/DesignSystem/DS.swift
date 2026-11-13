import SwiftUI
import UIKit

/// Единая дизайн-система ShortLib.
///
/// Правила (см. GUIDELINES.md):
/// 1. Цвета только из `DS.Color` — никаких литералов `Color(red:)` / `UIColor(red:)` в фичах.
/// 2. Шрифт только из `DS.Font` — одно семейство (SF Pro, системный) на всех экранах.
/// 3. Анимации только из `DS.Motion` — короткие, без бесконечных циклов,
///    анимируются только opacity / transform / trim, учитывается Reduce Motion.
enum DS {}

// MARK: - Color

extension DS {
    enum Color {
        static let accent      = SwiftUI.Color("Accent")
        static let accentDeep  = SwiftUI.Color("AccentDeep")
        static let accentSoft  = SwiftUI.Color("AccentSoft")
        static let onAccent    = SwiftUI.Color("OnAccent")
        static let ink         = SwiftUI.Color("Ink")
        /// Длинный текст для чтения (пересказ главы) — на тон спокойнее заголовков.
        static let inkSoft     = SwiftUI.Color("InkSoft")
        static let secondary   = SwiftUI.Color("Secondary")
        static let line        = SwiftUI.Color("Line")
        static let background  = SwiftUI.Color("Background")
        static let surface     = SwiftUI.Color("Surface")
        static let card        = SwiftUI.Color("Card")
        static let success     = SwiftUI.Color("Success")
        static let successSoft = SwiftUI.Color("SuccessSoft")

        /// Текст и затемнение поверх обложек (обложки всегда тёмные).
        static let onCover     = SwiftUI.Color.white
        static let coverShade  = SwiftUI.Color.black.opacity(0.45)

        /// Градиент главной кнопки.
        static let cta = LinearGradient(colors: [accent, accentDeep], startPoint: .leading, endPoint: .trailing)

        /// «Тёплый свет»: подсвечивает один главный элемент экрана (кольцо прогресса, «Сейчас читаете»).
        static let glowWarm = SwiftUI.Color("GlowWarm")
        static let glowSoft = SwiftUI.Color("GlowSoft")

        /// Неподвижное свечение за главным элементом. Без анимации — рисуется один раз.
        static func glow(radius: CGFloat) -> RadialGradient {
            RadialGradient(colors: [glowSoft.opacity(0.45), accent.opacity(0.16), SwiftUI.Color.clear],
                           center: .center, startRadius: 0, endRadius: radius)
        }

        /// Тёплая дуга прогресса: от коралла к персиковому.
        static let progressArc = AngularGradient(colors: [accent, glowWarm, glowSoft],
                                                 center: .center, startAngle: .degrees(0), endAngle: .degrees(360))

        /// Блик «переливания» поверх главной кнопки.
        static let shimmer = LinearGradient(colors: [SwiftUI.Color.clear, SwiftUI.Color.white.opacity(0.45), SwiftUI.Color.clear],
                                            startPoint: .leading, endPoint: .trailing)

        /// Обложки книг — тоже часть палитры, отдельных цветов в фичах нет.
        static let covers: [[SwiftUI.Color]] = [
            [SwiftUI.Color("Cover1A"), SwiftUI.Color("Cover1B")],
            [accent, accentDeep],
            [SwiftUI.Color("Cover3A"), SwiftUI.Color("Cover3B")],
            [SwiftUI.Color("Cover4A"), SwiftUI.Color("Cover4B")]
        ]
    }

    enum UIColorToken {
        static let accent     = UIKit.UIColor(named: "Accent") ?? .systemPink
        static let ink        = UIKit.UIColor(named: "Ink") ?? .label
        static let secondary  = UIKit.UIColor(named: "Secondary") ?? .secondaryLabel
        static let background = UIKit.UIColor(named: "Background") ?? .systemBackground
        static let line       = UIKit.UIColor(named: "Line") ?? .separator
    }
}

// MARK: - Typography (одно семейство: SF Pro, Dynamic Type)

extension DS {
    enum Font {
        static let largeTitle = SwiftUI.Font.system(.title, design: .default, weight: .heavy)
        static let title      = SwiftUI.Font.system(.title3, design: .default, weight: .bold)
        static let headline   = SwiftUI.Font.system(.subheadline, design: .default, weight: .semibold)
        static let body       = SwiftUI.Font.system(.body, design: .default, weight: .regular)
        static let callout    = SwiftUI.Font.system(.callout, design: .default, weight: .regular)
        static let caption    = SwiftUI.Font.system(.caption, design: .default, weight: .medium)
        static let label      = SwiftUI.Font.system(.footnote, design: .default, weight: .semibold)
        static let icon       = SwiftUI.Font.system(size: 22, weight: .regular)
        static let number     = SwiftUI.Font.system(.title, design: .default, weight: .heavy).monospacedDigit()
    }

    enum UIFontToken {
        static func tabBar() -> UIKit.UIFont { .systemFont(ofSize: 10, weight: .semibold) }
        static func navTitle() -> UIKit.UIFont { .systemFont(ofSize: 17, weight: .bold) }
    }
}

// MARK: - Layout

extension DS {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

// MARK: - Motion (лёгкие анимации)

extension DS {
    enum Motion {
        /// Стандартный переход: 0.2 c, ease-out. Не дороже одного кадра GPU-композиции.
        static let standard: Animation = .easeOut(duration: 0.2)
        /// Быстрая реакция на нажатие.
        static let tap: Animation = .easeOut(duration: 0.12)
        /// Плавное заполнение прогресса.
        static let progress: Animation = .easeOut(duration: 0.3)
        /// Один проход блика по кнопке (не цикл): 0.9 c, только offset.
        static let shimmer: Animation = .easeOut(duration: 0.9)

        /// Возвращает анимацию или nil, если включено «Уменьшение движения».
        static func respecting(_ animation: Animation) -> Animation? {
            UIAccessibility.isReduceMotionEnabled ? nil : animation
        }
    }
}

// MARK: - Common modifiers

extension View {
    /// Карточка с тонкой границей — единственный «объект» на экране.
    func dsCard(radius: CGFloat = DS.Radius.l) -> some View {
        self
            .background(DS.Color.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(DS.Color.line, lineWidth: 1))
    }

    /// Фон экрана.
    func dsScreen() -> some View {
        self
            .background(DS.Color.background.ignoresSafeArea())
            .foregroundColor(DS.Color.ink)
    }
}
