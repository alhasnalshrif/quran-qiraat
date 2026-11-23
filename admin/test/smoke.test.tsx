import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';

import { App } from '../src/App.js';

// The shell asks /me on mount; without a session it must show the login page.
vi.stubGlobal(
  'fetch',
  vi.fn(async () =>
    new Response(JSON.stringify({ error: { code: 'not_found', message: 'x' } }), {
      status: 401,
      headers: { 'content-type': 'application/json' },
    }),
  ),
);

describe('admin shell (S-10)', () => {
  it('shows the Arabic login form when there is no session', async () => {
    render(
      <MemoryRouter>
        <App />
      </MemoryRouter>,
    );

    expect(await screen.findByText('لوحة التحكم')).toBeDefined();
    expect(await screen.findByText('دخول')).toBeDefined();
  });
});
