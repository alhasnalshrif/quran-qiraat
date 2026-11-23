import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { App } from '../src/App.js';

describe('admin workspace', () => {
  it('renders the dashboard heading', () => {
    render(<App />);
    expect(screen.getByRole('heading', { name: 'لوحة التحكم' })).toBeDefined();
  });
});
