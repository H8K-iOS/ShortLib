# Гайдлайны ShortLib

Три правила, которые действуют на всех экранах. Проверка `scripts/check-guidelines.sh`
запускается при каждой сборке (Build Phase «Check Guidelines») и выводит warning в Xcode,
если правило нарушено.

## 1. Лёгкие анимации

- Только токены `DS.Motion`: `standard` (0.2 c), `tap` (0.12 c), `progress` (0.3 c), все ease-out.
- Анимируем только `opacity`, `scale`/`offset` и `trim` — это композиция на GPU, без перерасчёта layout.
- Запрещено: `repeatForever`, пружины (`.spring`, `interpolatingSpring`), `withAnimation {}` без токена.
- Вместо вращающегося спиннера — статичный индикатор этапа.
- Всегда через `DS.Motion.respecting(_:)`: при включённом «Уменьшении движения» анимации нет.
- Обложки рисуются с `.drawingGroup()` — один растр на карточку, скролл не нагружает CPU.

## 2. Один шрифт

- Системный SF Pro, одно семейство на всех экранах, с поддержкой Dynamic Type.
- Только стили `DS.Font`: `largeTitle`, `title`, `headline`, `body`, `callout`, `caption`, `label`, `number`, `icon`.
- Запрещено: `.font(.system(...))`, `.font(.title)` и другие системные стили напрямую, `Font.custom`, `UIFont(name:)`.
- Для UIKit — `DS.UIFontToken`.

## 3. Одна палитра

- Цвета — только `DS.Color` (SwiftUI) и `DS.UIColorToken` (UIKit), значения лежат в `Assets.xcassets/Colors`
  со светлым и тёмным вариантом.
- Коралловый `accent` — только для главного действия на экране и активной вкладки.
- Запрещено: `Color(red:)`, `UIColor(red:)`, `#colorLiteral`, `.white`, `.black` и другие системные цвета в фичах.
- Обложки книг тоже берут цвета из палитры (`DS.Color.covers`).

| Токен | Светлая | Тёмная |
|---|---|---|
| Accent | `#E5405E` | `#FF5C77` |
| AccentDeep | `#C81E4A` | `#FF7A90` |
| Ink | `#222222` | `#F2F2F2` |
| Secondary | `#6A6A6A` | `#A6A6A6` |
| Line | `#E2E2E2` | `#333333` |
| Background | `#FFFFFF` | `#121212` |
| Surface | `#F7F7F7` | `#1C1C1C` |
| Success | `#1F8A5B` | `#4CC38A` |
