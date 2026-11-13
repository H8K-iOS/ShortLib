import { DurableObject } from "cloudflare:workers";

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Счётчик с атомарными операциями. Один объект на ключ:
 *  - `dev:<installId>` — бюджет устройства (бессрочно);
 *  - `ip:<ip>:<дата>`  — лимиты по IP (удаляется через 2 суток);
 *  - `day:<дата>`      — дневной потолок расходов в µ$.
 * Durable Object обрабатывает вызовы по одному, поэтому read-modify-write здесь без гонок.
 */
export class Ledger extends DurableObject {
  /** Резервирует `amount`, если остаток позволяет. */
  async reserve(amount: number, limit: number): Promise<{ ok: boolean; left: number }> {
    const spent = (await this.ctx.storage.get<number>("spent")) ?? 0;
    const reserved = (await this.ctx.storage.get<number>("reserved")) ?? 0;
    const left = limit - spent - reserved;
    if (amount > left) return { ok: false, left: Math.max(0, left) };
    await this.ctx.storage.put("reserved", reserved + amount);
    return { ok: true, left: left - amount };
  }

  /** Снимает резерв и списывает фактический расход. */
  async settle(reservedAmount: number, actual: number): Promise<void> {
    const spent = (await this.ctx.storage.get<number>("spent")) ?? 0;
    const reserved = (await this.ctx.storage.get<number>("reserved")) ?? 0;
    await this.ctx.storage.put({
      spent: spent + actual,
      reserved: Math.max(0, reserved - reservedAmount),
    });
  }

  async left(limit: number): Promise<number> {
    const spent = (await this.ctx.storage.get<number>("spent")) ?? 0;
    const reserved = (await this.ctx.storage.get<number>("reserved")) ?? 0;
    return Math.max(0, limit - spent - reserved);
  }

  /** Фиксированное окно: не больше `max` вызовов за `windowSec`. */
  async hit(windowSec: number, max: number): Promise<{ ok: boolean; retryAfter: number }> {
    await this.scheduleCleanup();
    const now = Date.now();
    const start = (await this.ctx.storage.get<number>("windowStart")) ?? 0;
    const count = (await this.ctx.storage.get<number>("windowCount")) ?? 0;
    if (now - start >= windowSec * 1000) {
      await this.ctx.storage.put({ windowStart: now, windowCount: 1 });
      return { ok: true, retryAfter: 0 };
    }
    if (count >= max) return { ok: false, retryAfter: Math.ceil((start + windowSec * 1000 - now) / 1000) };
    await this.ctx.storage.put("windowCount", count + 1);
    return { ok: true, retryAfter: 0 };
  }

  /** Множество с ограничением размера (устройства с одного IP за сутки). */
  async addMember(id: string, max: number): Promise<boolean> {
    await this.scheduleCleanup();
    const members = (await this.ctx.storage.get<string[]>("members")) ?? [];
    if (members.includes(id)) return true;
    if (members.length >= max) return false;
    members.push(id);
    await this.ctx.storage.put("members", members);
    return true;
  }

  private async scheduleCleanup(): Promise<void> {
    if ((await this.ctx.storage.getAlarm()) === null) {
      await this.ctx.storage.setAlarm(Date.now() + 2 * DAY_MS);
    }
  }

  async alarm(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}
