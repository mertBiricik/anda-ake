FROM node:20-bullseye-slim

LABEL maintainer="Mert Biricik"
LABEL description="ANDA AKE — Safety-Critical SAR Alarm Server"

WORKDIR /app

# Install OpenSSL and Curl (required for Prisma and Healthcheck)
RUN apt-get update -y && apt-get install -y openssl curl && rm -rf /var/lib/apt/lists/*

# Copy package files first for better Docker layer caching
COPY package.json package-lock.json* ./

# Install dependencies (including Prisma)
RUN npm install

# Copy application code and Prisma schema
COPY server.js ./
COPY prisma ./prisma/
COPY public ./public/

# Generate Prisma Client
RUN npx prisma generate

# Health check — Safety-Critical: detect if server is unresponsive
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/api/health || exit 1

EXPOSE 3000

# Run as non-root user for security
RUN groupadd -g 1001 anda && useradd -u 1001 -g anda -s /bin/bash -m anda
USER anda

CMD ["node", "server.js"]
