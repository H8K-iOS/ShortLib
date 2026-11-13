# ShortLib proxy (Cloudflare Workers)

Бесплатный пересказ без ключа пользователя: приложение шлёт запросы сюда, сервер добавляет ключ
разработчика и пересылает их в Anthropic. Ключ хранится только в секретах Cloudflare.

## Что делает
- `POST /v1/messages`: тело как у Anthropic Messages API. Обязательные заголовки — `X-ShortLib-Install` (UUID) и `X-ShortLib-Version`.
- `GET /v1/quota` → `{"chaptersLeft": 5, "tokensLeft": 270000, "plan": "free"}`.
- Модели: только `claude-haiku-5-5`. `max_tokens` ≤ 8000, вход ≤ ~60 тыс. токенов, только текст, без `stream` и `tools`.
- Бюджет устройства — 270 000 «взвешенных токенов» (вход + 5 × выход), это примерно 5 глав. Выдаётся один раз.
  Перед запросом сервер резервирует оценку, после ответа списывает фактический `usage`.
- Лимиты по IP: 30 запросов в минуту, не больше 3 новых устройств в сутки.
- Общий потолок расходов — `DAILY_CAP_USD` в сутки (по умолчанию $5).
- Ошибки: `{"error": {"code": "...", "message": "по-русски"}}`.
  Коды: `quota_exceeded` 402, `rate_limited` 429, `daily_cap` 503, `upstream_busy` 503, `bad_request` 400, `upstream_error` 502.
- Счётчики хранятся в Durable Objects (SQLite, бесплатный тариф): атомарно, без гонок.

## Деплой (один раз)
Нужен Node.js 20+ (https://nodejs.org).

1. Зарегистрируйтесь на https://dash.cloudflare.com (бесплатный план Workers подходит).
2. Установите зависимости и войдите в аккаунт:
   ```bash
   cd server
   npm install
   npx wrangler login
   ```
3. Создайте отдельный ключ API на https://console.anthropic.com (Settings → API Keys) и задайте на нём
   лимит расходов (Settings → Limits). Сохраните ключ как секрет — он не попадёт в репозиторий:
   ```bash
   npx wrangler secret put ANTHROPIC_API_KEY
   ```
4. Опубликуйте Worker:
   ```bash
   npx wrangler deploy
   ```
   Wrangler напечатает адрес вида `https://shortlib-proxy.<ваш-поддомен>.workers.dev`.
5. Проверьте, что сервер отвечает:
   ```bash
   curl https://shortlib-proxy.<ваш-поддомен>.workers.dev/health
   curl -H "X-ShortLib-Install: 00000000-0000-4000-8000-000000000000" https://shortlib-proxy.<ваш-поддомен>.workers.dev/v1/quota
   ```
6. Впишите этот адрес в `ShortLib/Resources/Info.plist`, ключ `ShortLibProxyURL` (без `/` в конце), и пересоберите приложение.

## Настройка и наблюдение
- Лимиты меняются в `wrangler.toml` → `[vars]`, затем снова `npx wrangler deploy`.
- Логи в реальном времени: `npx wrangler tail`.
- Проверка типов: `npm run typecheck`. Локальный запуск: создайте `.dev.vars` со строкой `ANTHROPIC_API_KEY=...` и выполните `npm run dev`.

## Этап 2
Apple App Attest (заголовок `X-ShortLib-Attest`) — после покупки Apple Developer.
