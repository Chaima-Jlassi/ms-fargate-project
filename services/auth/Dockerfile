FROM node:22-alpine

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm \
              /usr/local/bin/npm /usr/local/bin/npx \
              /opt/yarn-v1.22.22 /usr/local/bin/yarn /usr/local/bin/yarnpkg

COPY server.js tracing.js ./

# Run as the unprivileged user that ships with the node image
USER node

ENV PORT=3000
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
