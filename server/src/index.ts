// ShortLib proxy: бесплатный пересказ без ключа пользователя.
// Пересылает запросы Messages API в Anthropic с ключом разработчика (wrangler secret),
// ведёт бюджет устройства, лимиты по IP и общий дневной потолок расходов.
import { Ledger } from "./ledger";

export { Ledger };

export interface Env {
  ANTHROPIC_API_KEY: string;
  LEDGER: DurableObjectNamespace<Ledger>;
  /** Бюджет устройства во «взвешенных токенах» (вход + 5 × выход для Haiku). */
  DEVICE_BUDGET?: string;
  /** Общий потолок расходов в сутки, USD. */
  DAILY_CAP_USD?: string;
  /** Запросов в минуту с одного IP. */
  IP_REQUESTS_PER_MINUTE?: string;
  /** Новых устройств в сутки с одного IP. */
  IP_DEVICES_PER_DAY?: string;
}

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION = "2023-06-01";

/** Цены USD за 1 млн токенов. Только эти модели доступны в бесплатном режиме. */
const MODELS: Record<string, { input: number; output: number }> = {
  "claude-haiku-5-5": { input: 0.1, output: 0.5 },
};
/** База «взвешенного токена» — входной токен Haiku. */
const BASE_PRICE = MODELS["claude-haiku-5-5"].input;

const MAX_OUTPUT_TOKENS = 8000;
const MAX_INPUT_TOKENS = 60_000;
/** Грубая верхняя оценка: ~2,5 символа на токен (кириллица токенизируется плотнее латиницы). */
const CHARS_PER_TOKEN = 2.5;
const MAX_BODY_BYTES = 512 * 1024;
/** Средняя глава во взвешенных токенах — для поля chaptersLeft. */
const TOKENS_PER_CHAPTER = 54_000;

const ALLOWED_FIELDS = new Set([
  "model", "max_tokens", "system", "messages", "temperature", "stop_sequences", "metadata", "thinking",
]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type ErrorCode =
  | "bad_request" | "quota_exceeded" | "rate_limited" | "daily_cap"
  | "upstream_busy" | "upstream_error" | "not_found";

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
    readonly retryAfter?: number,
  ) {
    super(message);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);
      if (request.method === "POST" && url.pathname === "/v1/messages") return await messages(request, env);
      if (request.method === "GET" && url.pathname === "/v1/quota") return await quota(request, env);
      if (request.method === "GET" && url.pathname === "/health") return json({ ok: true });
      throw new HttpError(404, "not_found", "Неизвестный адрес.");
    } catch (e) {
      if (e instanceof HttpError) return errorResponse(e);
      console.error("unhandled", e);
      return errorResponse(new HttpError(502, "upstream_error", "Сервер ShortLib временно недоступен. Попробуйте позже."));
    }
  },
} satisfies ExportedHandler<Env>;

// MARK: - Handlers

async function quota(request: Request, env: Env): Promise<Response> {
  const installId = requireInstallId(request);
  const limit = deviceBudget(env);
  const left = await ledger(env, `dev:${installId}`).left(limit);
  return json({
    chaptersLeft: Math.ceil(left / TOKENS_PER_CHAPTER),
    tokensLeft: left,
    plan: "free",
  });
}

async function messages(request: Request, env: Env): Promise<Response> {
  const installId = requireInstallId(request);
  if (!request.headers.get("X-ShortLib-Version")) {
    throw new HttpError(400, "bad_request", "Обновите приложение ShortLib.");
  }
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const day = new Date().toISOString().slice(0, 10);

  // 1. Тело запроса и белый список.
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) throw new HttpError(400, "bad_request", "Глава слишком длинная для бесплатного режима.");
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new HttpError(400, "bad_request", "Некорректный запрос.");
  }
  const { model, maxTokens, inputTokens } = validate(body);
  const price = MODELS[model];

  // 2. Лимиты по IP.
  const ipLedger = ledger(env, `ip:${ip}:${day}`);
  const rpm = intVar(env.IP_REQUESTS_PER_MINUTE, 30);
  const hit = await ipLedger.hit(60, rpm);
  if (!hit.ok) {
    throw new HttpError(429, "rate_limited", "Слишком много запросов. Подождите минуту.", hit.retryAfter);
  }
  const devicesOk = await ipLedger.addMember(installId, intVar(env.IP_DEVICES_PER_DAY, 3));
  if (!devicesOk) {
    throw new HttpError(429, "rate_limited", "С этой сети сегодня уже использованы бесплатные пересказы. Попробуйте завтра.", 3600);
  }

  // 3. Резерв бюджета устройства и дневного потолка (атомарно в Durable Objects).
  const estWeighted = weighted(price, inputTokens, maxTokens);
  const estMicroUsd = microUsd(price, inputTokens, maxTokens);

  const device = ledger(env, `dev:${installId}`);
  const devReserve = await device.reserve(estWeighted, deviceBudget(env));
  if (!devReserve.ok) {
    throw new HttpError(402, "quota_exceeded", "Бесплатные главы закончились. Добавьте свой ключ Claude в Профиле или оформите подписку.");
  }
  const global = ledger(env, `day:${day}`);
  const globalReserve = await global.reserve(estMicroUsd, dailyCapMicroUsd(env));
  if (!globalReserve.ok) {
    await device.settle(estWeighted, 0);
    throw new HttpError(503, "daily_cap", "Бесплатный лимит сервиса на сегодня исчерпан. Попробуйте завтра или добавьте свой ключ в Профиле.");
  }

  // 4. Запрос в Anthropic; списание по фактическому usage.
  let actualWeighted = 0;
  let actualMicroUsd = 0;
  try {
    const upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": ANTHROPIC_VERSION,
      },
      body: JSON.stringify(body),
    });
    const text = await upstream.text();

    if (upstream.ok) {
      const usage = parseUsage(text);
      if (usage) {
        actualWeighted = weighted(price, usage.input, usage.output);
        actualMicroUsd = microUsd(price, usage.input, usage.output);
      } else {
        // usage не нашли — списываем оценку, чтобы не раздавать бесплатно.
        actualWeighted = estWeighted;
        actualMicroUsd = estMicroUsd;
      }
      return new Response(text, {
        status: 200,
        headers: {
          "content-type": "application/json",
          "X-ShortLib-Tokens-Left": String(Math.max(0, devReserve.left + estWeighted - actualWeighted)),
        },
      });
    }

    // Ошибки Anthropic не тарифицируются.
    console.warn("upstream", upstream.status, text.slice(0, 300));
    if (upstream.status === 429 || upstream.status === 529 || upstream.status >= 500) {
      const ra = Number(upstream.headers.get("retry-after"));
      throw new HttpError(503, "upstream_busy", "Сервис пересказа перегружен. Повторяем…", Number.isFinite(ra) && ra > 0 ? ra : 5);
    }
    if (upstream.status === 400) {
      throw new HttpError(400, "bad_request", "Запрос отклонён моделью. Попробуйте ещё раз или выберите другую главу.");
    }
    // 401/403/402 — проблема ключа разработчика или баланса: пользователю не показываем детали.
    throw new HttpError(502, "upstream_error", "Сервер ShortLib временно недоступен. Попробуйте позже.");
  } finally {
    await Promise.all([
      device.settle(estWeighted, actualWeighted),
      global.settle(estMicroUsd, actualMicroUsd),
    ]);
  }
}

// MARK: - Validation

function validate(body: Record<string, unknown>): { model: string; maxTokens: number; inputTokens: number } {
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    throw new HttpError(400, "bad_request", "Некорректный запрос.");
  }
  for (const key of Object.keys(body)) {
    if (!ALLOWED_FIELDS.has(key)) throw new HttpError(400, "bad_request", `Поле «${key}» недоступно в бесплатном режиме.`);
  }
  const model = body.model;
  if (typeof model !== "string" || !(model in MODELS)) {
    throw new HttpError(400, "bad_request", "Эта модель недоступна в бесплатном режиме.");
  }
  const maxTokens = body.max_tokens;
  if (typeof maxTokens !== "number" || !Number.isInteger(maxTokens) || maxTokens < 1 || maxTokens > MAX_OUTPUT_TOKENS) {
    throw new HttpError(400, "bad_request", `max_tokens должен быть от 1 до ${MAX_OUTPUT_TOKENS}.`);
  }

  // Haiku 5.5 по умолчанию «думает» (adaptive, effort medium): скрытые токены оплачиваются как выход
  // и съедают max_tokens. В бесплатном режиме размышления всегда выключены.
  if (body.thinking !== undefined) {
    const t = body.thinking as { type?: unknown };
    if (typeof t !== "object" || t === null || Object.keys(t).length !== 1 || t.type !== "disabled") {
      throw new HttpError(400, "bad_request", "В бесплатном режиме размышления модели недоступны.");
    }
  }
  body.thinking = { type: "disabled" };

  let chars = textLength(body.system, "system");
  const msgs = body.messages;
  if (!Array.isArray(msgs) || msgs.length === 0 || msgs.length > 20) {
    throw new HttpError(400, "bad_request", "Некорректный запрос: messages.");
  }
  for (const m of msgs) {
    if (typeof m !== "object" || m === null) throw new HttpError(400, "bad_request", "Некорректный запрос: messages.");
    const { role, content } = m as { role?: unknown; content?: unknown };
    if (role !== "user" && role !== "assistant") throw new HttpError(400, "bad_request", "Некорректный запрос: role.");
    chars += textLength(content, "content");
  }

  const inputTokens = Math.ceil(chars / CHARS_PER_TOKEN) + 50;
  if (inputTokens > MAX_INPUT_TOKENS) {
    throw new HttpError(400, "bad_request", "Глава слишком длинная для бесплатного режима.");
  }
  return { model, maxTokens, inputTokens };
}

/** Длина текста в строке или в массиве текстовых блоков; другие типы блоков (картинки, tools) запрещены. */
function textLength(value: unknown, field: string): number {
  if (value === undefined && field === "system") return 0;
  if (typeof value === "string") return value.length;
  if (Array.isArray(value)) {
    let n = 0;
    for (const block of value) {
      const b = block as { type?: unknown; text?: unknown };
      if (b?.type !== "text" || typeof b.text !== "string") {
        throw new HttpError(400, "bad_request", "В бесплатном режиме доступен только текст.");
      }
      n += b.text.length;
    }
    return n;
  }
  throw new HttpError(400, "bad_request", `Некорректный запрос: ${field}.`);
}

function parseUsage(text: string): { input: number; output: number } | null {
  try {
    const u = JSON.parse(text)?.usage;
    if (!u || typeof u.output_tokens !== "number") return null;
    // Кеш считаем как обычный вход — с запасом.
    const input = (u.input_tokens ?? 0) + (u.cache_creation_input_tokens ?? 0) + (u.cache_read_input_tokens ?? 0);
    return { input, output: u.output_tokens };
  } catch {
    return null;
  }
}

// MARK: - Helpers

function requireInstallId(request: Request): string {
  const id = request.headers.get("X-ShortLib-Install") ?? "";
  if (!UUID_RE.test(id)) throw new HttpError(400, "bad_request", "Обновите приложение ShortLib.");
  return id.toLowerCase();
}

function weighted(price: { input: number; output: number }, input: number, output: number): number {
  return Math.ceil((input * price.input + output * price.output) / BASE_PRICE);
}

/** Стоимость в микродолларах: цена за 1 млн токенов = µ$ за токен. */
function microUsd(price: { input: number; output: number }, input: number, output: number): number {
  return Math.ceil(input * price.input + output * price.output);
}

function deviceBudget(env: Env): number {
  return intVar(env.DEVICE_BUDGET, 270_000);
}

function dailyCapMicroUsd(env: Env): number {
  const usd = Number(env.DAILY_CAP_USD ?? "5");
  return Math.round((Number.isFinite(usd) && usd > 0 ? usd : 5) * 1_000_000);
}

function intVar(value: string | undefined, fallback: number): number {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function ledger(env: Env, name: string): DurableObjectStub<Ledger> {
  return env.LEDGER.get(env.LEDGER.idFromName(name));
}

function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

function errorResponse(e: HttpError): Response {
  const headers: Record<string, string> = {};
  if (e.retryAfter) headers["retry-after"] = String(Math.ceil(e.retryAfter));
  return json({ error: { code: e.code, message: e.message } }, e.status, headers);
}
