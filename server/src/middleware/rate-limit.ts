/**
 * In-memory rate limiting for `/v1` (02 §4): 60 requests per minute per IP.
 *
 * D5 runs a single server, so memory is enough. The key is the daily IP hash
 * from `dailyIpHash`, never the address itself, and entries are dropped after
 * their window so nothing accumulates.
 */
export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  /** Seconds until the window resets. */
  retryAfter: number;
}

interface Bucket {
  count: number;
  resetAt: number;
}

export class RateLimiter {
  private readonly buckets = new Map<string, Bucket>();
  private readonly limit: number;
  private readonly windowMs: number;
  private readonly now: () => number;
  private lastSweep = 0;

  constructor(limit = 60, windowMs = 60_000, now: () => number = Date.now) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.now = now;
  }

  /** Counts one request for [key] and reports whether it may proceed. */
  consume(key: string): RateLimitResult {
    const time = this.now();
    this.sweep(time);

    const existing = this.buckets.get(key);
    if (!existing || existing.resetAt <= time) {
      this.buckets.set(key, { count: 1, resetAt: time + this.windowMs });
      return { allowed: true, remaining: this.limit - 1, retryAfter: 0 };
    }

    if (existing.count >= this.limit) {
      return {
        allowed: false,
        remaining: 0,
        retryAfter: Math.ceil((existing.resetAt - time) / 1000),
      };
    }

    existing.count += 1;
    return { allowed: true, remaining: this.limit - existing.count, retryAfter: 0 };
  }

  /** Drops expired buckets at most once per window, so the map stays bounded. */
  private sweep(time: number): void {
    if (time - this.lastSweep < this.windowMs) return;
    this.lastSweep = time;
    for (const [key, bucket] of this.buckets) {
      if (bucket.resetAt <= time) this.buckets.delete(key);
    }
  }

  get size(): number {
    return this.buckets.size;
  }
}

/**
 * The client address for rate limiting. Behind the reverse proxy this is the
 * first forwarded address; a missing header falls back to a constant so a
 * direct client cannot dodge the limiter by omitting it.
 */
export function clientKey(req: {
  header: (name: string) => string | undefined;
}): string {
  const forwarded = req.header('x-forwarded-for')?.split(',')[0]?.trim();
  const real = req.header('x-real-ip')?.trim();
  return forwarded || real || 'unknown';
}
