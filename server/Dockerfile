FROM node:20-alpine

LABEL maintainer="Mert Biricik"
LABEL description="ANDA AKE — Safety-Critical SAR Alarm Server"

WORKDIR /app

# Copy package files first for better Docker layer caching
COPY package.json package-lock.json* ./

# Install production dependencies only
RUN npm ci --omit=dev 2>/dev/null || npm install --omit=dev

# Copy application code
COPY server.js ./

# Health check — Safety-Critical: detect if server is unresponsive
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/health || exit 1

EXPOSE 3000

# Run as non-root user for security
RUN addgroup -g 1001 anda && adduser -u 1001 -G anda -s /bin/sh -D anda
USER anda

CMD ["node", "server.js"]
