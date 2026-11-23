import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Database-backed suites share one Postgres database, so they must not
    // truncate tables while another suite is mid-test.
    fileParallelism: false,
  },
});
