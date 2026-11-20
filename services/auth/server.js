const express = require("express");
const jwt = require("jsonwebtoken");
const { createClient } = require("redis");
const tracing = require("./tracing");

const PORT = process.env.PORT || 3000;
// In AWS this value is injected from Secrets Manager by the ECS task definition.
const JWT_SECRET = process.env.JWT_SECRET || "dev-only-secret-change-me";
const REDIS_URL = process.env.REDIS_URL; // e.g. redis://my-cache.xxxxxx.use1.cache.amazonaws.com:6379

// Demo users. Replace with a real user store (RDS/DynamoDB) later.
const USERS = {
  alice: "password123",
  bob: "password456",
};

const app = express();
app.use(express.json());
app.use(tracing.openSegment("auth"));

// `redis` stays null until a connection has actually succeeded, so a failed
// startup connection can never leave a half-working client behind.
let redis = null;
async function initRedis() {
  if (!REDIS_URL) {
    console.log("REDIS_URL not set, sessions will not be stored");
    return;
  }
  const client = createClient({
    url: REDIS_URL,
    socket: { reconnectStrategy: (retries) => Math.min(retries * 200, 2000) },
    // Fail commands immediately while disconnected (so the handlers below can
    // answer 503) instead of queueing them until Redis comes back.
    disableOfflineQueue: true,
  });
  let lastError = "";
  client.on("error", (err) => {
    // Log each distinct error once, not on every reconnect attempt.
    if (err.message !== lastError) console.error("Redis error:", err.message);
    lastError = err.message;
  });
  client.on("ready", () => {
    lastError = "";
  });

  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error("timed out connecting to Redis")), 10000);
  });
  try {
    await Promise.race([client.connect(), timeout]);
  } finally {
    clearTimeout(timer);
  }
  redis = client;
  console.log("Connected to Redis");
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "auth" });
});

app.post("/auth/login", async (req, res) => {
  const { username, password } = req.body || {};
  if (!username || USERS[username] !== password) {
    return res.status(401).json({ error: "Invalid credentials" });
  }
  const token = jwt.sign({ sub: username }, JWT_SECRET, { expiresIn: "1h" });
  if (redis) {
    try {
      await redis.set(`session:${username}`, token, { EX: 3600 });
    } catch (err) {
      console.error("Could not store session:", err.message);
      return res.status(503).json({ error: "Session store unavailable" });
    }
  }
  res.json({ token });
});

app.post("/auth/verify", async (req, res) => {
  const { token } = req.body || {};
  if (!token) return res.status(400).json({ error: "token is required" });

  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch (err) {
    return res.status(401).json({ valid: false, error: "Invalid or expired token" });
  }

  if (redis) {
    try {
      const stored = await redis.get(`session:${payload.sub}`);
      if (stored !== token) {
        return res.status(401).json({ valid: false, error: "Session not found" });
      }
    } catch (err) {
      console.error("Could not read session:", err.message);
      return res.status(503).json({ valid: false, error: "Session store unavailable" });
    }
  }
  res.json({ valid: true, user: payload.sub });
});

app.use(tracing.closeSegment());

initRedis()
  .then(() => {
    app.listen(PORT, () => console.log(`auth service listening on ${PORT}`));
  })
  .catch((err) => {
    // REDIS_URL is set but Redis is unreachable. Crash with a clear message so
    // the orchestrator (ECS, Docker) restarts the task instead of leaving a
    // half-working service behind.
    console.error("Startup failed:", err.message);
    process.exit(1);
  });
