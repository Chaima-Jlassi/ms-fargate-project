const express = require("express");
const crypto = require("crypto");
const tracing = require("./tracing");

const PORT = process.env.PORT || 3000;
// Service discovery: in ECS these resolve through AWS Cloud Map private DNS
// (for example http://auth.local:3000). Locally docker-compose provides the names.
const AUTH_URL = process.env.AUTH_SERVICE_URL || "http://auth:3000";
const NOTIFICATIONS_URL =
  process.env.NOTIFICATIONS_SERVICE_URL || "http://notifications:3000";
const CALL_TIMEOUT_MS = 3000; // never let a slow dependency hang a request

const app = express();
app.use(express.json());
app.use(tracing.openSegment("orders"));

// In-memory store for the demo. Swap for RDS/DynamoDB when you add the database tier.
const orders = new Map();

async function authenticate(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: "Missing bearer token" });

  try {
    const response = await tracing.tracedFetch(req, "auth", `${AUTH_URL}/auth/verify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
      signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
    });
    // 401 = the token is bad. Anything else = auth itself is unhealthy (502),
    // so a Redis outage is not reported to the user as "unauthorized".
    if (response.status === 401) return res.status(401).json({ error: "Unauthorized" });
    if (!response.ok) return res.status(502).json({ error: "Auth service unavailable" });
    const data = await response.json();
    req.user = data.user;
    next();
  } catch (err) {
    console.error("Auth service unreachable:", err.message);
    res.status(502).json({ error: "Auth service unavailable" });
  }
}

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "orders" });
});

app.post("/orders", authenticate, async (req, res) => {
  const { item, quantity } = req.body || {};
  if (!item || !Number.isInteger(quantity) || quantity < 1) {
    return res.status(400).json({ error: "item and a positive integer quantity are required" });
  }

  const order = {
    id: crypto.randomUUID(),
    user: req.user,
    item,
    quantity,
    createdAt: new Date().toISOString(),
  };
  orders.set(order.id, order);

  // Fire and forget: a notification failure must not fail the order.
  tracing.tracedFetch(req, "notifications", `${NOTIFICATIONS_URL}/notify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      user: order.user,
      message: `Order ${order.id} placed: ${quantity} x ${item}`,
    }),
    signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
  }).catch((err) => console.error("Notification failed:", err.message));

  res.status(201).json(order);
});

app.get("/orders", authenticate, (req, res) => {
  const mine = [...orders.values()].filter((o) => o.user === req.user);
  res.json(mine);
});

app.use(tracing.closeSegment());

app.listen(PORT, () => console.log(`orders service listening on ${PORT}`));
