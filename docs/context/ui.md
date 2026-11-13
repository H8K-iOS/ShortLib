# ShortLib — UI

Общий контекст — `CLAUDE.md` в корне репозитория.

## Зона ответственности
Экраны, компоненты, дизайн-система, анимации, тёмная тема, доступность, лукбук. Код UI — SwiftUI в `ShortLib/Features/*/…View.swift` и `ShortLib/DesignSystem/`.

## Гайдлайны пользователя (обязательны)
1. **Лёгкие анимации**, не нагружающие ядро: только `DS.Motion` (`standard` 0.2 c, `tap` 0.12 c, `progress` 0.3 c, ease-out); анимируем opacity/scale/offset/trim; без `repeatForever`, пружин и вращающихся спиннеров; всегда `DS.Motion.respecting(_:)` (Reduce Motion).
2. **Один лаконичный шрифт** на всех экранах: SF Pro через `DS.Font` (largeTitle, title, headline, body, callout, caption, label, number, icon). Никаких `.font(.system…)` в фичах.
3. **Одна палитра**: только `DS.Color` / `DS.UIColorToken`, значения в `Assets.xcassets/Colors` (светлая + тёмная).

Скрипт `scripts/check-guidelines.sh` выдаёт warning в Xcode при нарушении. Подробно — `GUIDELINES.md`.

## Палитра
| Токен | Светлая | Тёмная |
|---|---|---|
| Accent | #E5405E | #FF5C77 |
| AccentDeep | #C81E4A | #FF7A90 |
| AccentSoft | #FDECEF | #3A1A21 |
| Ink | #222222 | #F2F2F2 |
| Secondary | #6A6A6A | #A6A6A6 |
| Line | #E2E2E2 | #333333 |
| Background / Card | #FFFFFF | #121212 / #202020 |
| Surface | #F7F7F7 | #1C1C1C |
| Success | #1F8A5B | #4CC38A |

Акцент — только главная кнопка экрана и активная вкладка. Обложки книг — градиенты из палитры (`DS.Color.covers`).

## Экраны
- Таб-бар: Библиотека · Добавить (открывает импорт модально) · Пересказы · Профиль
- Библиотека: поисковая плашка, вкладки категорий, карточки книг как объявления Airbnb
- Карточка книги: обложка, источник, факты, список глав, липкая нижняя панель «Пересказать / Читать»
- Импорт: EPUB или ссылка на оглавление, превью найденных глав
- Настройки пересказа (bottom sheet): движок + оценка токенов, детальность (сегменты + слайдер), фокус (чипы), спойлеры, главы
- Прогресс: кольцо, этапы, «Свернуть» (генерация продолжается)
- Чтение: вкладки Кратко / По главам / Персонажи, блоки связей между главами, «Поделиться»
- Профиль: ключ Claude API, модель, язык пересказа, детальность по умолчанию

## Компоненты (`DesignSystem/Components`)
PrimaryButton, SecondaryButton, TextLinkButton, CircleIconButton, FooterBar, SearchPill, FocusChip, CategoryTab, StatusBadge, BookCover, DetailLevelPicker, ProgressRing, LinearProgress, FlowLayout, SettingsGroup.

## Лукбук
HTML-лукбук «Читалка» (ранний макет до переименования в ShortLib) лежит у пользователя в `4italka\chitalka-lookbook.html` (Windows).

## Открытые задачи
- Иконка приложения (`AppIcon` пустая)
- Проверить вёрстку на iPhone SE и с крупным Dynamic Type
- Пустые состояния и ошибки сети — единый стиль
- Обновить лукбук под название ShortLib

## Решения
- 2026-11-13. Детальность показывается диапазоном слов на главу (`DetailLevel.wordRangeText`, «≈ 400–700 слов»), а не процентом:
  длину задаёт `DetailLevel.wordRange`, процент ползунка — только ориентир («≈ 12% от оригинала», мелким текстом).
  Так же в бейдже экрана прогресса: «Баланс · ≈ 400–700 слов».
