FROM node:20-alpine AS build
WORKDIR /repo

ARG VITE_ENTRA_CLIENT_ID
ARG VITE_ENTRA_AUTHORITY
ARG VITE_ENTRA_REDIRECT_URI
ARG VITE_ENTRA_POST_LOGOUT_REDIRECT_URI
ARG VITE_ENTRA_SCOPES

ENV VITE_ENTRA_CLIENT_ID=$VITE_ENTRA_CLIENT_ID
ENV VITE_ENTRA_AUTHORITY=$VITE_ENTRA_AUTHORITY
ENV VITE_ENTRA_REDIRECT_URI=$VITE_ENTRA_REDIRECT_URI
ENV VITE_ENTRA_POST_LOGOUT_REDIRECT_URI=$VITE_ENTRA_POST_LOGOUT_REDIRECT_URI
ENV VITE_ENTRA_SCOPES=$VITE_ENTRA_SCOPES

COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/package.json
RUN npm ci --workspace @word-game/web

COPY apps/web apps/web
RUN npm --workspace @word-game/web run build

FROM nginx:1.27-alpine
COPY apps/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /repo/apps/web/dist /usr/share/nginx/html

EXPOSE 8080
