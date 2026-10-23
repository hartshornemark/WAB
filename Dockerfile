# syntax=docker/dockerfile:1.7

FROM node:22-bookworm-slim AS node-base

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

RUN corepack enable \
    && corepack prepare pnpm@11.19.0 --activate

WORKDIR /app


FROM node-base AS dependencies

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./

RUN --mount=type=cache,id=pnpm-store,target=/pnpm/store \
    pnpm install --frozen-lockfile


FROM node-base AS application-builder

COPY --from=dependencies /app/node_modules ./node_modules
COPY . .

# NEXT_PUBLIC values are compiled into the browser bundle by Next.js. They are
# intentionally public configuration, not secrets. The hosting platform supplies
# service variables during the image build and again at runtime.
ARG NEXT_PUBLIC_SUPABASE_URL
ARG NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
ENV NEXT_PUBLIC_SUPABASE_URL=$NEXT_PUBLIC_SUPABASE_URL
ENV NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=$NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY

RUN pnpm build


FROM node:22-bookworm-slim AS solver-dependencies

RUN apt-get update \
    && apt-get install --yes --no-install-recommends python3 python3-venv ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY solver/requirements.txt /tmp/requirements.txt
COPY solver/staging/requirements.txt /tmp/staging/requirements.txt

RUN python3 -m venv /opt/wabiqa-solver \
    && /opt/wabiqa-solver/bin/pip install --no-cache-dir --requirement /tmp/staging/requirements.txt


FROM node:22-bookworm-slim AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV HOSTNAME=0.0.0.0
ENV WAB_SOLVER_PYTHON=/opt/wabiqa-solver/bin/python

RUN apt-get update \
    && apt-get install --yes --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 nodejs \
    && useradd --system --uid 1001 --gid nodejs --home-dir /app nextjs

COPY --from=solver-dependencies /opt/wabiqa-solver /opt/wabiqa-solver
COPY --from=application-builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=application-builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=application-builder --chown=nextjs:nodejs /app/public ./public

# These files are opened by absolute paths derived from process.cwd() at
# runtime, so they must remain at the same project-relative locations.
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/cp_sat_solver.py ./solver/cp_sat_solver.py
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/cargo_capacity.py ./solver/cargo_capacity.py
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/staging/app_worker.py ./solver/staging/app_worker.py
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/staging/search_profile.py ./solver/staging/search_profile.py
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/staging/supabase-ca.crt ./solver/staging/supabase-ca.crt
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs ./solver/verification/a350-v2-seven-scenarios-2026-10-23/final/inputs
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json ./solver/verification/a350-v2-seven-scenarios-2026-10-23/final/results.json
COPY --from=application-builder --chown=nextjs:nodejs /app/solver/requirements.txt ./solver/requirements.txt
COPY --from=application-builder --chown=nextjs:nodejs /app/src/infrastructure/aircraft-layouts ./src/infrastructure/aircraft-layouts
COPY --from=application-builder --chown=nextjs:nodejs /app/src/assets/aircraft-layouts ./src/assets/aircraft-layouts

USER nextjs

EXPOSE 3000

# The hosting platform supplies PORT; Next.js standalone server.js reads it.
CMD ["node", "server.js"]
