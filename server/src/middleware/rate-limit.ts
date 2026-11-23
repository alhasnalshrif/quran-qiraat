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
/**
 * The client address for rate limiting.
 *
 * Behind Cloudflare and Traefik there are several hops, and the left-most
 * entry in X-Forwarded-For is whatever the client claimed — easy to forge and
 * easy to vary per request, which would give a fresh bucket every time and
 * defeat the limit. `CF-Connecting-IP` is set by Cloudflare and is the real
 * client, so it wins; then X-Real-IP from the proxy; then the right-most
 * forwarded entry (the closest hop we can trust); then a constant.
 */
export function clientKey(req: {
  header: (name: string) => string | undefined;
}): string {
  const cf = req.header('cf-connecting-ip')?.trim();
  if (cf) return cf;

  const real = req.header('x-real-ip')?.trim();
  if (real) return real;

  const forwarded = req.header('x-forwarded-for');
  if (forwarded) {
    const parts = forwarded.split(',').map((part) => part.trim()).filter(Boolean);
    // The right-most hop is the one added by our own proxy.
    const closest = parts[parts.length - 1];
    if (closest) return closest;
  }

  return 'unknown';
}
