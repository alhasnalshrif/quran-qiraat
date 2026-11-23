# Builds the server and the dashboard, then runs a small runtime image (S-12).
FROM node:22-bookworm-slim AS base
RUN corepack enable
WORKDIR /app

# ---------------------------------------------------------------------------
# Install every workspace dependency once, using the committed lockfile.
# ---------------------------------------------------------------------------
FROM base AS deps
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/contracts/package.json packages/contracts/
COPY server/package.json server/
COPY admin/package.json admin/
RUN pnpm install --frozen-lockfile

# ---------------------------------------------------------------------------
# Build contracts, the dashboard and the server.
# ---------------------------------------------------------------------------
FROM deps AS build
COPY . .
RUN pnpm --filter @quran/contracts build \
 && pnpm --filter @quran/admin build \
 && pnpm --filter @quran/server build

# ---------------------------------------------------------------------------
# Runtime: production dependencies only, plus the built artifacts.
# ---------------------------------------------------------------------------
FROM base AS runtime
ENV NODE_ENV=production
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/contracts/package.json packages/contracts/
COPY server/package.json server/
COPY admin/package.json admin/
RUN pnpm install --frozen-lockfile --prod

COPY --from=build /app/packages/contracts/dist packages/contracts/dist
COPY --from=build /app/server/dist server/dist
COPY --from=build /app/server/drizzle server/drizzle
COPY --from=build /app/admin/dist admin/dist

# The dashboard is served from here by server/src/app.ts.
ENV ADMIN_DIST=/app/admin/dist

WORKDIR /app/server
EXPOSE 8787
USER node
CMD ["node", "dist/main.js"]
