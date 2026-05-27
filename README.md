# CloudWatch RUM — End-to-End Demo

A minimal, self-contained demo that deploys Amazon CloudWatch RUM and a single-page web app to demonstrate real user monitoring capabilities in under 5 minutes.

## What It Does

Opens a local web page that sends real telemetry to CloudWatch RUM. You can trigger various event types and immediately see them in the CloudWatch console.

| Telemetry Type | How It's Triggered |
|---|---|
| Performance / Web Vitals | Auto-collected on page load (LCP, CLS, TTFB, navigation timing) |
| HTTP requests | Click buttons to fire fetch() with 200/404/500 responses |
| JavaScript errors | Click buttons to throw TypeError / ReferenceError / custom exceptions |
| Page views (SPA) | Click navigation buttons that call `history.pushState` |
| Session Replay | Interact with forms/buttons on replay.html — DOM mutations recorded via rrweb |

## Architecture

```
┌──────────────┐       HTTPS        ┌─────────────────────────────────┐
│  Browser     │ ──────────────────→ │  CloudWatch RUM Data Plane      │
│  (localhost) │   PutRumEvents      │  (dataplane.rum.region.aws.com) │
└──────┬───────┘                     └────────────────┬────────────────┘
       │                                              │
       │  Cognito Identity                            ▼
       │  (unauthenticated)              ┌────────────────────────┐
       └────────────────────────────────→│  CloudWatch RUM Console │
         temp credentials via STS        │  (dashboard + metrics)  │
                                         └────────────────────────┘
```

**Resources created:**
- CloudWatch RUM App Monitor
- Cognito Identity Pool (unauthenticated access)
- IAM Role with `rum:PutRumEvents` permission (scoped to the app monitor)

## Prerequisites

- AWS CLI v2 configured with credentials
- Python 3 (for local HTTP server)
- A modern browser (Chrome/Firefox/Safari)

## Quick Start

```bash
# 1. Deploy infrastructure (takes ~60 seconds)
chmod +x setup.sh cleanup.sh
./setup.sh

# 2. Start the local server
cd app && python3 -m http.server 8888

# 3. Open in browser
open http://localhost:8888
```

The setup script will print the CloudWatch RUM console URL — open it to see events arriving in real time.

> **New to this demo?** Read [`DEMO_GUIDE.md`](DEMO_GUIDE.md) for a full walkthrough of each feature, what to click, where to look in the console, and talking points for presenting.

## Customization

### Deploy to a different region

```bash
AWS_REGION=eu-west-1 ./setup.sh
```

### Use a custom name

```bash
./setup.sh my-app-rum-monitor
```

### Deploy for a real domain

```bash
./setup.sh my-app-monitor example.com
```

Then embed the generated snippet (from `app/index.html`) into your real application.

### Enable X-Ray Tracing

Edit `infra/template.yaml`, set `EnableXRay: true`, and add `addXRayTraceIdHeader: true` to the HTTP telemetry config in the template HTML.

## Project Structure

```
.
├── README.md                   # Project overview & quick start
├── DEMO_GUIDE.md               # Hands-on walkthrough (each feature explained)
├── setup.sh                    # One-command deploy (CFN + npm build + generate HTML)
├── cleanup.sh                  # One-command teardown
├── infra/
│   └── template.yaml           # CloudFormation template (all AWS resources)
└── app/
    ├── index.template.html     # Demo page template with {{placeholders}}
    ├── index.html              # Generated with live config (git-ignored)
    ├── package.json            # NPM deps (aws-rum-web v3 + esbuild)
    └── src/
        └── rum-init.js         # Entry point: AwsRum + RRWebPlugin init
```

## How It Works

The demo uses `aws-rum-web@3.0.0` via NPM (required for Session Replay):

```javascript
import { AwsRum, RRWebPlugin } from 'aws-rum-web';

const config = {
  sessionSampleRate: 1,
  identityPoolId: 'POOL_ID',
  endpoint: 'https://dataplane.rum.REGION.amazonaws.com',
  telemetries: ['performance', 'errors', ['http', { recordAllRequests: true }]],
  allowCookies: true,
  sessionEventLimit: 0,
  eventPluginsToLoad: [new RRWebPlugin()]  // Session Replay
};

new AwsRum('APP_MONITOR_ID', '1.0.0', 'REGION', config);
```

Bundled with esbuild → single `dist/rum-bundle.js` (~275KB minified).

## Selective Privacy Masking (Session Replay)

By default, AWS enforces full text masking in Session Replay — all text and inputs appear as `***` in playback. This demo includes a local patch that enables **selective masking**: only elements marked with `data-rum-mask` are masked; everything else is recorded in clear text.

### How it works

Add `data-rum-mask` to any sensitive HTML element:

```html
<!-- Masked in replay -->
<input type="email" placeholder="Email" data-rum-mask>
<p data-rum-mask>SSN: 123-45-6789</p>

<!-- Visible in replay (no attribute) -->
<button>Submit</button>
<h1>Dashboard</h1>
```

### Technical details

The patch modifies `ENFORCED_PRIVACY_OPTIONS` in `@aws-rum/web-core` before bundling:

- `maskTextSelector: '[data-rum-mask]'` — only mask text inside marked elements
- `maskInputOptions: { text: true, email: true, ... }` — enable per-type input checking
- `maskInputFn` — returns original text unless element has `data-rum-mask`

> **Note**: This patch lives in `node_modules` and is reapplied on each build. Running `npm install` without rebuilding will revert to AWS's default full-masking behavior. The patch is for demo/internal use — AWS intentionally enforces full masking in production for compliance reasons.

## Cleanup

```bash
./cleanup.sh
```

This deletes the CloudFormation stack and all associated resources (App Monitor, Identity Pool, IAM Role).

## Cost

- **Free tier**: First 1M RUM events per account (one-time trial)
- **After free tier**: $1.00 per 100,000 web events
- **This demo**: A few clicks = ~50 events total, effectively free

## Useful Links

- [CloudWatch RUM Console](https://console.aws.amazon.com/cloudwatch/home#rum:dashboard)
- [CW RUM Web Client (GitHub)](https://github.com/aws-observability/aws-rum-web)
- [CW RUM Pricing](https://aws.amazon.com/cloudwatch/pricing/#Real-User_Monitoring)
- [CW RUM Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-RUM.html)
