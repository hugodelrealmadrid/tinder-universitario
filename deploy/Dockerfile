# Construir desde la raíz: docker build -f deploy/Dockerfile -t tinder-api .
FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app/tool
COPY tool/package.json tool/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && node -e "require('sharp')"
COPY tool/backend ./backend
USER node
ENV NODE_ENV=production
CMD ["node", "backend/hosted-server.mjs"]
