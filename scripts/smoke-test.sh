#!/usr/bin/env bash
# End-to-end smoke test of the login -> order -> notification flow.
#
#   ./scripts/smoke-test.sh                    local docker compose (ports 3001-3003)
#   ./scripts/smoke-test.sh http://<alb-dns>   deployed stack, everything through the ALB
#
# Exit code 0 = all checks passed.
set -u

BASE="${1:-}"
if [ -n "$BASE" ]; then
  BASE="${BASE%/}"
  AUTH="$BASE"; ORDERS="$BASE"; NOTIF="$BASE"
else
  AUTH="http://localhost:3001"; ORDERS="http://localhost:3002"; NOTIF="http://localhost:3003"
fi

JSON='Content-Type: application/json'
failed=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; failed=1; }
status() { curl -s -o /dev/null -w '%{http_code}' -m 10 "$@"; }
check() { # description expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 (expected $2, got $3)"; fi
}

# Wait until the auth service answers (a wrong password gives 401 once it is up).
echo "Waiting for the services to answer..."
ready=0
for _ in $(seq 1 60); do
  code=$(status -X POST "$AUTH/auth/login" -H "$JSON" -d '{"username":"x","password":"x"}')
  if [ "$code" = "401" ]; then ready=1; break; fi
  sleep 5
done
[ "$ready" = "1" ] || { echo "FAIL  services did not become ready in time (last status: $code)"; exit 1; }

check "login with a wrong password is rejected" 401 \
  "$(status -X POST "$AUTH/auth/login" -H "$JSON" -d '{"username":"alice","password":"wrong"}')"

TOKEN=$(curl -s -m 10 -X POST "$AUTH/auth/login" -H "$JSON" \
  -d '{"username":"alice","password":"password123"}' | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
if [ -n "$TOKEN" ]; then pass "login returns a token"; else fail "login returned no token"; exit 1; fi

ITEM="smoke-$$-$(date +%s)"
ORDER_BODY="{\"item\":\"$ITEM\",\"quantity\":2}"

check "order without a token is rejected" 401 \
  "$(status -X POST "$ORDERS/orders" -H "$JSON" -d "$ORDER_BODY")"
check "order with an invalid token is rejected" 401 \
  "$(status -X POST "$ORDERS/orders" -H "$JSON" -H 'Authorization: Bearer not-a-token' -d "$ORDER_BODY")"
check "order with a valid token is created" 201 \
  "$(status -X POST "$ORDERS/orders" -H "$JSON" -H "Authorization: Bearer $TOKEN" -d "$ORDER_BODY")"
check "invalid order is rejected" 400 \
  "$(status -X POST "$ORDERS/orders" -H "$JSON" -H "Authorization: Bearer $TOKEN" -d '{"item":"x","quantity":0}')"

# The notification is sent asynchronously, so give it a few seconds.
found=0
for _ in $(seq 1 10); do
  if curl -s -m 10 "$NOTIF/notifications" | grep -q "$ITEM"; then found=1; break; fi
  sleep 1
done
if [ "$found" = "1" ]; then pass "orders triggered a notification"; else fail "no notification found for $ITEM"; fi

echo
if [ "$failed" = "0" ]; then echo "All checks passed."; else echo "Some checks FAILED."; fi
exit "$failed"
