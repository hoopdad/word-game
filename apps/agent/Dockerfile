FROM node:20-alpine
WORKDIR /repo

COPY package.json package-lock.json ./
COPY apps/agent/package.json apps/agent/package.json
COPY packages/shared/package.json packages/shared/package.json
RUN npm ci --workspace @word-game/agent --workspace @word-game/shared

COPY apps/agent apps/agent
COPY packages/shared packages/shared

ENV NODE_ENV=production
CMD ["node", "apps/agent/src/index.js"]
