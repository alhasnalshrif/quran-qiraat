import { describe, expect, it } from 'vitest';

import { serverInfo } from '../src/main.js';

describe('server workspace', () => {
  it('reads the protocol version from contracts', () => {
    expect(serverInfo.protocol).toBe(1);
  });
});
