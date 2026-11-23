import type { Channel } from './packs.js';

/**
 * The OneSignal REST surface the server needs (D18). Sending is wrapped so
 * tests can point it at a local HTTP server and the admin page never holds
 * the secret key.
 */
export interface OneSignalConfig {
  appIdStable: string;
  appIdBeta: string;
  keyStable: string;
  keyBeta: string;
  /** Override for tests; defaults to the real API. */
  baseUrl?: string;
}

export interface NotificationPayload {
  channel: Extract<Channel, 'stable' | 'beta'>;
  title: string;
  body: string;
  /** Deep link carried in `data.link` (03 §12). */
  link?: string | null;
  platforms: string[];
  minBuild?: number | null;
  maxBuild?: number | null;
  /** Set for a scheduled send; omitted means immediate. */
  sendAfter?: Date | null;
  /** A single OneSignal subscription id, for the test send. */
  includeSubscriptionIds?: string[];
}

export interface SendResult {
  id: string;
  recipients: number;
}

export class OneSignalError extends Error {}

/**
 * Builds the `filters` array from our own fields: channel, platform and build
 * (02 §5). No other tag is ever sent (README rule 3).
 */
export function buildFilters(
  payload: Pick<NotificationPayload, 'channel' | 'platforms' | 'minBuild' | 'maxBuild'>,
): unknown[] {
  const filters: unknown[] = [{ field: 'tag', key: 'channel', relation: '=', value: payload.channel }];
  const platforms = payload.platforms.filter((value) => value === 'ios' || value === 'android');
  const platformFilter = platforms.map((value) => ({
    field: 'tag',
    key: 'platform',
    relation: '=',
    value,
  }));
  if (platformFilter.length > 0) {
    filters.push({ operator: 'OR' }, ...platformFilter);
  }
  if (typeof payload.minBuild === 'number') {
    filters.push({ field: 'tag', key: 'build', relation: '>=', value: String(payload.minBuild) });
  }
  if (typeof payload.maxBuild === 'number') {
    filters.push({ field: 'tag', key: 'build', relation: '<=', value: String(payload.maxBuild) });
  }
  return filters;
}

export class OneSignal {
  constructor(
    private readonly config: OneSignalConfig,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {}

  private keyFor(channel: 'stable' | 'beta'): string {
    return channel === 'stable' ? this.config.keyStable : this.config.keyBeta;
  }

  private appIdFor(channel: 'stable' | 'beta'): string {
    return channel === 'stable' ? this.config.appIdStable : this.config.appIdBeta;
  }

  private get baseUrl(): string {
    return this.config.baseUrl ?? 'https://api.onesignal.com';
  }

  /** Sends or schedules a notification; returns OneSignal's id and audience. */
  async send(payload: NotificationPayload): Promise<SendResult> {
    const body: Record<string, unknown> = {
      app_id: this.appIdFor(payload.channel),
      headings: { ar: payload.title },
      contents: { ar: payload.body },
      target_channel: 'push',
      filters: buildFilters(payload),
      data: payload.link ? { link: payload.link } : {},
    };
    if (payload.includeSubscriptionIds?.length) {
      delete body.filters;
      body.include_subscription_ids = payload.includeSubscriptionIds;
    }
    if (payload.sendAfter) {
      body.send_after = payload.sendAfter.toISOString();
    }

    const response = await this.fetchImpl(`${this.baseUrl}/notifications`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Key ${this.keyFor(payload.channel)}`,
      },
      body: JSON.stringify(body),
    });

    const text = await response.text();
    if (!response.ok) {
      throw new OneSignalError(`OneSignal refused the send (${response.status}): ${text}`);
    }
    const parsed = safeJson(text) as { id?: string; recipients?: number };
    if (!parsed?.id) throw new OneSignalError('OneSignal returned no notification id.');
    return { id: parsed.id, recipients: parsed.recipients ?? 0 };
  }

  /** Cancels a scheduled notification that has not gone out yet. */
  async cancel(channel: 'stable' | 'beta', id: string): Promise<void> {
    const response = await this.fetchImpl(
      `${this.baseUrl}/notifications/${id}?app_id=${encodeURIComponent(this.appIdFor(channel))}`,
      {
        method: 'DELETE',
        headers: { authorization: `Key ${this.keyFor(channel)}` },
      },
    );
    if (!response.ok) {
      const text = await response.text();
      throw new OneSignalError(`OneSignal refused the cancel (${response.status}): ${text}`);
    }
  }
}

function safeJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}
