# ShortLib — код и архитектура

Общий контекст — `CLAUDE.md` в корне репозитория.

## Зона ответственности
Структура проекта, координаторы, ViewModel, сервисы, хранение данных, ошибки сборки Xcode, git/GitHub, CI.

## Ограничения iOS 16
- ViewModel — `@MainActor final class: ObservableObject` + `@Published` (не `@Observable`, это iOS 17)
- Хранение — JSON в Documents (`BookRepository`); не SwiftData (iOS 17). Core Data — возможная замена за протоколом `BookRepositoryProtocol`
- Можно: `Layout` (FlowLayout), `ShareLink`, `UISheetPresentationController` detents, async/await
- Не использовать `MainActor.assumeIsolated` и прочие API iOS 17+

## Навигация (UIKit)
```
AppCoordinator ── UITabBarController
 ├─ LibraryCoordinator      Библиотека → Карточка книги
 │   └─ SummaryCoordinator  Настройки (sheet) → Прогресс → Чтение
 ├─ ImportCoordinator       модально: EPUB / ссылка
 ├─ SummariesCoordinator    Пересказы → Чтение
 └─ Профиль (ProfileView + ProfileViewModel)
```
- `Router` оборачивает UINavigationController: SwiftUI-экраны через UIHostingController, системная навбар скрыта, свайп назад работает, `onPop`-колбэки завершают дочерние координаторы
- ViewModel сообщает о переходах замыканиями (`onSelectBook`, `onCreate`, `onBack`…) и не знает про UIKit
- Генерация пересказа живёт в `SummaryGenerationService` (`deps.generation`), а не в экранах (решено 2026-11-13):
  - один `SummaryJob` на книгу (`ObservableObject`: `progress`, `state`, `readyChapters`, `estimatedRemaining`); `runningBookIDs` — для бейджей;
  - `start(bookID:preset:)` возвращает уже идущую задачу с тем же пресетом; частичный пересказ с другим пресетом сбрасывается;
    `resume(bookID:)` продолжает с `Book.partialSummary`; `cancel` оставляет готовые главы;
  - после каждой главы движок вызывает `onPartial`, и сервис сохраняет `Book.partialSummary` (всегда поверх свежей копии книги из репозитория).
    Готовый `Summary` удаляет partial. Ошибка движка (в т. ч. `freeQuotaExceeded` посреди книги) оставляет partial — «Продолжить пересказ»
    со своим ключом идёт с `partial.preset` (не с новым пресетом из настроек). Урезанный `Summary` тоже не удаляет partial (страховка).
    Поздние `onPartial` после завершения или отмены игнорируются. Все главы диапазона загружаются до вызова движка, иначе в partial будет дыра;
  - экран прогресса, читалка и карточка книги только наблюдают за задачей; при уходе с экрана координатор завершается, а генерация продолжается;
  - приложение свернули: `beginBackgroundTask` (~30 с) даёт дописать и сохранить главу. Если сеть оборвалась из-за остановки iOS,
    при возврате задача сама продолжается с сохранённой главы (один раз). После перезапуска — `canResume` и кнопка «Продолжить пересказ»
    (`SummaryCoordinator.Mode.resume`). Фоновый режим на всю книгу не обещаем.

## Структура
```
ShortLib/
├─ App/            AppDelegate, SceneDelegate, AppDependencies (DI, выбор движка пересказа)
├─ Coordinators/   Coordinator, Router, App/Library/Import/Summary(+Summaries)
├─ Features/       Library, Import, Summary, Summaries, Profile — View + ViewModel
├─ Domain/         Book, Chapter, Summary (+SummaryPreset, DetailLevel, SummaryProgress), SampleData
├─ Services/       BookRepository, ZipReader, EPUBParser, HTMLText, WebNovelScraper,
│                  SummaryEngine (Extractive), SummaryGenerationService, Preferences, LLM/ (AnthropicClient, KeychainStore,
│                  LLMSummaryEngine, Prompts)
├─ DesignSystem/   DS + Components
└─ Resources/      Assets.xcassets, Info.plist
scripts/check-guidelines.sh   — Build Phase «Check Guidelines»
.github/workflows/ios.yml     — CI
```

## Проект Xcode
- `ShortLib.xcodeproj` изначально сгенерирован скриптом (не XcodeGen). Новые файлы — через Xcode или правкой `project.pbxproj` (PBXFileReference + PBXBuildFile + группа + Sources phase).
- Bundle ID `com.shortlib.app`, deployment target 16.0, Swift 5, `ENABLE_USER_SCRIPT_SANDBOXING = NO` (для скрипта гайдлайнов)
- `DEVELOPMENT_TEAM` в репо пустой; у пользователя локально выставлен свой Team — не коммитить.

## Сервер-прокси (бесплатный лимит, 2026-11-13)
- Код — `server/` (Cloudflare Worker, TypeScript), инструкция деплоя — `server/README.md`. Ключ Anthropic — `wrangler secret`, в репо его нет.
- Счётчики — один класс Durable Object `Ledger` (SQLite, бесплатный тариф). Имя объекта задаёт роль:
  `dev:<installId>` — бюджет устройства, `ip:<ip>:<дата>` — лимиты по IP (удаляется alarm'ом через 2 суток), `day:<дата>` — потолок в µ$.
- Учёт во «взвешенных токенах»: вход (с кешем) + 5 × выход, это нормировка на цену входа Haiku. Устройству дают 270 000.
  Перед запросом в Anthropic резервируется оценка (символы / 2.5 + 5 × max_tokens), после ответа списывается фактический `usage`.
- iOS: `ProxyConfig.baseURL` берётся из Info.plist `ShortLibProxyURL` (пусто — прокси выключен); `InstallID` хранится в Keychain;
  `LLMConfig.auth` — `.apiKey` или `.proxy`. Выбор движка — `AppDependencies.engineKind`: `.ownKey` / `.freeProxy` / `.extractive`.
  Остаток (`freeQuota`) кешируется: обновляется при запуске, перед настройками пересказа (если ещё не загружен) и после пересказа.
- Размышления модели выключены во всех запросах: Haiku 5.5 — `thinking: {type: "disabled"}`, Sonnet 5.5 — `{type: "between_tools"}` (`disabled` у него даёт 400). Прокси подставляет `disabled` сам и другие значения отклоняет. Ответ со `stop_reason: max_tokens` возвращается как есть.
- Ошибки прокси: `APIError.freeQuotaExceeded` (402), `.serviceLimit` (daily_cap или долгий rate_limited), `.proxy`.
  503 `daily_cap` не повторяется; `rate_limited` и `upstream_busy` повторяются, только если пауза ≤ 60 с.
- Этап 2: App Attest (`X-ShortLib-Attest`) — после покупки Apple Developer.
- **Развёрнут 2026-11-16:** `https://shortlib-proxy.shortlib-proxy.workers.dev` (вписан в Info.plist). Секрет `ANTHROPIC_API_KEY` задан,
  `/health`, `/v1/quota` и тестовый `/v1/messages` отвечают 200. Повторный деплой: `cd server && npx wrangler deploy`.
  `@cloudflare/workers-types` поднят до 5.x (иначе конфликт peer-зависимостей с wrangler 4.163).

## Git
- Push в `main` напрямую (одиночный разработчик). Перед push — `git pull --rebase`.
- Обновление на Mac: `git stash && git pull origin main && git stash pop`.

## Открытые задачи
- Прокси: проверить бесплатный пересказ из приложения на iPhone
- Нет unit-тестов (кандидаты: ZipReader/EPUBParser, TagParser, WebNovelScraper.extractChapterLinks, SummaryCostEstimate)
- Фон: `BGProcessingTask` + локальное уведомление «Пересказ готов»
- Share Extension для ссылок из Safari
