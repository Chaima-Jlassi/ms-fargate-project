FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY server.js tracing.js ./

# Run as the unprivileged user that ships with the node image
USER node

ENV PORT=3000
EXPOSE 3000
RUN npm ls -g tar
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
