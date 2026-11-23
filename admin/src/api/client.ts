/** The admin API client: one session cookie plus a CSRF header on writes (02 §5). */

export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

interface Session {
  email: string;
  role: 'owner' | 'editor';
}

export interface Me {
  user: Session;
  csrfToken: string;
}

let csrfToken: string | null = null;

export function setCsrfToken(token: string | null): void {
  csrfToken = token;
}

/** GET with no CSRF token: reads never change state (02 §5). */
export async function getJson<T>(path: string): Promise<T> {
  const response = await fetch(`/admin/api${path}`, {
    credentials: 'same-origin',
    headers: { accept: 'application/json' },
  });
  return parse<T>(response);
}

/** A write, always carrying the session's CSRF token. */
export async function sendJson<T>(
  method: 'POST' | 'PUT' | 'DELETE',
  path: string,
  body?: unknown,
): Promise<T> {
  const response = await fetch(`/admin/api${path}`, {
    method,
    credentials: 'same-origin',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      ...(csrfToken ? { 'X-CSRF-Token': csrfToken } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return parse<T>(response);
}

async function parse<T>(response: Response): Promise<T> {
  const text = await response.text();
  const body = text ? (JSON.parse(text) as unknown) : null;

  if (!response.ok) {
    const error = (body as { error?: { code?: string; message?: string } } | null)?.error;
    throw new ApiError(
      response.status,
      error?.code ?? 'internal',
      error?.message ?? `Request failed (${response.status}).`,
    );
  }
  return body as T;
}

export async function login(email: string, password: string): Promise<Me> {
  const me = await sendJson<Me>('POST', '/login', { email, password });
  setCsrfToken(me.csrfToken);
  return me;
}

export async function logout(): Promise<void> {
  await sendJson<{ ok: boolean }>('POST', '/logout');
  setCsrfToken(null);
}

export async function me(): Promise<Me | null> {
  try {
    const current = await getJson<Me>('/me');
    setCsrfToken(current.csrfToken);
    return current;
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) return null;
    throw error;
  }
}
