FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json ./
RUN npm install --production && npm cache clean --force
COPY . .

FROM node:20-alpine
RUN addgroup --system --gid 1001 appgroup  && adduser  --system --uid 1001 --ingroup appgroup appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /app .
USER appuser
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3   CMD wget --no-verbose --tries=1 --spider http://localhost:3002/health || exit 1
CMD ["node", "app.js"]
