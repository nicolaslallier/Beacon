FROM node:20-alpine AS deps

WORKDIR /app
COPY package.json ./
RUN npm install

FROM deps AS dev
COPY . .
CMD ["npm", "run", "dev", "--", "--host", "--port", "3011"]

FROM deps AS build
COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.27-alpine AS prod
COPY --from=build /app/dist /usr/share/nginx/html

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost:8080/ || exit 1
