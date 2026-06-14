FROM node:20-alpine
WORKDIR /repo

COPY package.json package-lock.json ./
COPY apps/api/package.json apps/api/package.json
COPY packages/shared/package.json packages/shared/package.json
RUN npm ci --workspace @word-game/api --workspace @word-game/shared

COPY apps/api apps/api
COPY packages/shared packages/shared

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

CMD ["node", "apps/api/src/index.js"]
