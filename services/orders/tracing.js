// Optional AWS X-Ray tracing.
//
// Enabled only when AWS_XRAY_DAEMON_ADDRESS is set. On ECS the X-Ray daemon runs
// as a sidecar container in every task, so tracing is ON in AWS and OFF in the
// local docker-compose stack, with no code changes.
const enabled = Boolean(process.env.AWS_XRAY_DAEMON_ADDRESS);

let AWSXRay;
let xrayExpress;
if (enabled) {
  AWSXRay = require("aws-xray-sdk-core");
  xrayExpress = require("aws-xray-sdk-express");
  // Manual mode: the segment is passed explicitly on `req.segment`. This is
  // reliable with async/await and Node's built-in fetch (automatic mode relies
  // on continuation-local storage, which does not follow fetch).
  AWSXRay.enableManualMode();
  // Trace every request. Fine for a demo; use the default sampling in production.
  AWSXRay.middleware.setSamplingRules({
    version: 1,
    default: { fixed_target: 1, rate: 1 },
    rules: [],
  });
}

const passThrough = (_req, _res, next) => next();

// Express middleware: starts one X-Ray segment per request.
function openSegment(serviceName) {
  return enabled ? xrayExpress.openSegment(serviceName) : passThrough;
}

// Express error middleware: must be registered after the routes.
function closeSegment() {
  return enabled ? xrayExpress.closeSegment() : passThrough;
}

// fetch() that records the call as a "remote" subsegment and forwards the trace
// header, so the downstream service joins the same trace and the X-Ray service
// map draws an edge between the two services.
async function tracedFetch(req, remoteName, url, options = {}) {
  const parent = enabled && req && req.segment;
  if (!parent) return fetch(url, options);

  const sub = parent.addNewSubsegment(remoteName);
  sub.namespace = "remote";
  const traceHeader = `Root=${parent.trace_id};Parent=${sub.id};Sampled=${parent.notTraced ? 0 : 1}`;

  try {
    const res = await fetch(url, {
      ...options,
      headers: { ...options.headers, "X-Amzn-Trace-Id": traceHeader },
    });
    if (res.status >= 500) sub.addFaultFlag();
    else if (res.status >= 400) sub.addErrorFlag();
    sub.close();
    return res;
  } catch (err) {
    sub.close(err);
    throw err;
  }
}

module.exports = { openSegment, closeSegment, tracedFetch };
