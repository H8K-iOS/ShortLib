# ShortLib

iOS-приложение для кратких пересказов книг: EPUB-файлы и веб-новеллы по ссылке на оглавление.
Пользователь выбирает детальность (3–25% от оригинала), фокус (сюжет, персонажи, мир, цитаты)
и диапазон глав.

- **iOS 16+**, Swift 5, SwiftUI + UIKit
- **MVVM + Router / Coordinator**
- Без внешних зависимостей

## Запуск

1. Откройте `ShortLib.xcodeproj` в Xcode 15 или новее (на Mac).
2. Target ShortLib → Signing & Capabilities → выберите свою команду (Team).
3. Выберите симулятор iPhone и нажмите Run (⌘R).

При первом запуске в библиотеке есть пример книги, на нём можно сразу проверить пересказ.

## Архитектура

```
AppCoordinator ── UITabBarController
 ├─ LibraryCoordinator      Библиотека → Карточка книги
 │   └─ SummaryCoordinator  Настройки (sheet) → Прогресс → Чтение
 ├─ ImportCoordinator       модально: EPUB из «Файлов» / ссылка на новеллу
 └─ SummariesCoordinator    Готовые пересказы → Чтение
```

- **Coordinator** владеет сценарием и создаёт ViewModel. ViewModel сообщает о переходах через замыкания
  (`onSelectBook`, `onCreate`, …) и ничего не знает о UIKit.
- **Router** оборачивает `UINavigationController`: экраны на SwiftUI встраиваются через `UIHostingController`,
  системная панель скрыта, жест «назад» работает.
- **ViewModel** — `@MainActor final class: ObservableObject` (без `@Observable`, он требует iOS 17).
- **Хранилище** — `BookRepository` (JSON в Documents) за протоколом; Core Data можно подключить без изменения экранов.

```
ShortLib/
├─ App/            AppDelegate, SceneDelegate, AppDependencies (DI)
├─ Coordinators/   Coordinator, Router, App/Library/Import/Summary
├─ Features/       Library, Import, Summary, Summaries, Profile (View + ViewModel)
├─ Domain/         Book, Chapter, Summary, SummaryPreset
├─ Services/       ZipReader, EPUBParser, WebNovelScraper, SummaryEngine, BookRepository
├─ DesignSystem/   DS (цвета, шрифт, отступы, анимации) + компоненты
└─ Resources/      Assets.xcassets, Info.plist
```

## Как работает пересказ

1. **EPUB** распаковывается встроенным `ZipReader` (Apple Compression, без сторонних библиотек),
   затем читаются `container.xml` → OPF → главы из spine.
2. **Веб-новелла**: со страницы оглавления собираются ссылки на главы; тексты глав загружаются
   по одной во время пересказа и кешируются.
3. `ExtractiveSummaryEngine` работает офлайн: делит главы на предложения (NaturalLanguage),
   выбирает самые значимые с учётом фокуса и собирает общую сводку.
   Чтобы получить пересказ своими словами, добавьте реализацию `SummaryEngine` на базе LLM API
   и подставьте её в `AppDependencies`.

## Гайдлайны

Лёгкие анимации, один шрифт, одна палитра — подробно в [GUIDELINES.md](GUIDELINES.md).
Проверяются при каждой сборке.

## Что дальше

- LLM-движок пересказа (с учётом настройки «Без спойлеров»)
- Фоновое продолжение через `BGProcessingTask` и уведомление «Пересказ готов»
- Share Extension: отправить ссылку на новеллу из Safari
- Правила парсинга под конкретные сайты новелл
- Иконка приложения (`AppIcon` пока пустая)
