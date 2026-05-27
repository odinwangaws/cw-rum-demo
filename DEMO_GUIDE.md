# Demo Walkthrough

This guide walks you through running the demo and explains what each feature does, where to see the data in CloudWatch, and what's happening behind the scenes.

---

## Step 0: Deploy & Launch

```bash
# Deploy AWS resources (~60s)
./setup.sh

# Start local server
cd app && python3 -m http.server 8888

# Open demo page
open http://localhost:8888
```

Open the CloudWatch RUM console in a second tab (URL printed by setup.sh):
```
https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#rum:dashboard/cw-rum-demo
```

> **Tip**: Console data takes 1-2 minutes to appear after the first page load. Refresh the console if you don't see data immediately.

---

## Feature 1: Performance Monitoring (Auto-Collected)

### What happens
The moment the page loads, the RUM client automatically captures:

| Metric | What It Measures |
|--------|-----------------|
| DNS | Time to resolve domain name |
| TCP | Time to establish TCP connection |
| TTFB (Time to First Byte) | Server response time |
| DOM Interactive | Time until page is interactive |
| DOM Complete | Time until all resources loaded |
| Load | Full page load including onload handlers |
| LCP (Largest Contentful Paint) | Time until largest visible element renders |
| CLS (Cumulative Layout Shift) | Visual stability score |

### Where to see it in CloudWatch
- **Console** → Performance tab → Page load time chart
- **Console** → Performance tab → Web Vitals (LCP, FID, CLS)

### Behind the scenes
The RUM client hooks into the browser's [Performance API](https://developer.mozilla.org/en-US/docs/Web/API/Performance_API) (`performance.getEntriesByType('navigation')`) and [PerformanceObserver](https://developer.mozilla.org/en-US/docs/Web/API/PerformanceObserver) for Web Vitals. No code required — just enabling the `performance` telemetry is enough.

---

## Feature 2: HTTP Request Monitoring

### What happens
Click any of the three buttons to fire real HTTP requests:

| Button | Target | Expected Result |
|--------|--------|----------------|
| **GET 200** | jsonplaceholder.typicode.com/posts/1 | Successful response |
| **GET 404** | jsonplaceholder.typicode.com/posts/99999 | Not found |
| **GET 500** | httpstat.us/500 | Server error |

### Where to see it in CloudWatch
- **Console** → HTTP requests tab → shows each request URL, status code, and duration
- **Console** → Errors tab → HTTP errors (4xx/5xx) show up as error events

### Behind the scenes
The RUM client monkey-patches `window.fetch` and `XMLHttpRequest`. Every outgoing request is automatically intercepted, timed, and reported — including URL, method, status code, and duration. You don't need to wrap your fetch calls.

### What to point out in a demo
- "Notice the 500 and 404 both appear as errors in the dashboard — you can set alarms on HTTP error rates."
- "The timing breakdown shows if slowness is DNS, connection, or server processing."

---

## Feature 3: JavaScript Error Capture

### What happens
Click any error button to throw an unhandled exception:

| Button | Error Type | Simulated Scenario |
|--------|-----------|-------------------|
| **TypeError** | `null.property` | Accessing property on null (common in real apps) |
| **ReferenceError** | `undefinedVariable.method()` | Using an undeclared variable |
| **Custom Error** | `throw new Error('PaymentService: ...')` | Application-level error |

### Where to see it in CloudWatch
- **Console** → Errors tab → JavaScript errors table with stack traces
- **Console** → Errors tab → Error count over time chart
- Each error shows: error message, type, page URL, browser, and timestamp

### Behind the scenes
The RUM client registers a global `window.onerror` and `window.onunhandledrejection` handler. Any uncaught exception is captured with its full stack trace and sent as an error event.

### What to point out in a demo
- "In production, you'd see real error messages like 'Cannot read property X of undefined' with the exact page and browser info."
- "You can filter by error type to focus on what matters — TypeError vs network errors vs your own thrown errors."

---

## Feature 4: SPA Navigation & User Journey

### What happens
Click navigation buttons to simulate single-page app route changes, or click **"Simulate User Journeys (×10)"** to auto-generate 10 user journeys with different paths:

| Button | Route | Simulates |
|--------|-------|-----------|
| **/dashboard** | `/dashboard` | User navigates to dashboard |
| **/settings** | `/settings` | User opens settings |
| **/checkout** | `/checkout` | User enters checkout flow |
| **/ (home)** | `/` | User returns home |
| **Simulate (×10)** | Multiple | Batch generate path data for User Journey tab |

### Where to see it in CloudWatch
- **Console** → Page views tab → each route shows as a separate page with view count
- **Console** → User Journey tab → visual path diagram showing entry/exit pages and navigation flow
- **Console** → Sessions tab → waterfall view of individual session

### Behind the scenes
For SPAs (React, Vue, etc.), there's no full page reload on navigation. The RUM client listens to `history.pushState` and `history.replaceState` to detect route changes. The demo calls `awsRum.recordPageView(path)` to ensure the page ID matches the route.

The User Journey tab aggregates page_view events across multiple sessions to build a Sankey-style flow diagram showing how users move between pages.

### What to point out in a demo
- "Even without full page reloads, RUM tracks which pages users visit and in what order."
- "The User Journey tab shows your actual navigation funnel — where users drop off, which paths lead to conversion."
- "Click 'Simulate' to pre-populate path data, then open User Journey tab to see the visualization."

---

## Feature 5: Session & User Context (Automatic)

### What happens
Nothing to click — this is captured automatically for every event.

### What's captured
| Field | Example Value | Source |
|-------|--------------|--------|
| Session ID | `82b1d056-ce26-...` | Generated per browser session |
| User ID | `c2db2748-df71-...` | Persistent across sessions (cookie) |
| Browser | Chrome 148.0.0.0 | User-Agent parsing |
| OS | Mac OS 10.15.7 | User-Agent parsing |
| Device Type | desktop | User-Agent parsing |
| Country | HK | IP geolocation |
| City | Hung Hom | IP geolocation |
| Page URL | / | `window.location` |

### Where to see it in CloudWatch
- **Console** → Overview → Users & Sessions cards
- **Console** → any event detail → shows full metadata

### What to point out in a demo
- "RUM gives you geographic distribution without any analytics SDK."
- "The session concept groups all events from one user visit — you can replay their journey."

---

## Feature 6: Session Replay

### What happens
Interact with the forms, counter, and todo list on the demo page. Every DOM mutation and user interaction is recorded by rrweb and sent to CloudWatch RUM.

### What's recorded
| Element | Captured As |
|---------|------------|
| DOM snapshot | Full initial page state (HTML, CSS, structure) |
| DOM mutations | Incremental changes (text updates, element add/remove) |
| User interactions | Clicks, scrolls, input focus, form submissions |
| Viewport changes | Resize, scroll position |
| CSS transitions | Style changes, animations |

### Privacy protection (enforced, cannot be disabled)
- All text input is masked (`maskAllInputs: true`)
- All displayed text is masked (`maskTextSelector: '*'`)
- Images are not inlined by default

### Where to see it in CloudWatch
- **Console** → Session replay tab → list of recorded sessions
- Click a session to open the replay player with timeline
- Playback controls: 1x/2x/4x/8x speed, skip inactive periods

### Technical setup
Session Replay requires the NPM-based approach (not CDN snippet):
```javascript
import { AwsRum, RRWebPlugin } from 'aws-rum-web';

const config = {
  // ... standard config ...
  eventPluginsToLoad: [new RRWebPlugin()]
};
```
- Package: `aws-rum-web@3.0.0` (includes `@rrweb/record@2.0.0-alpha.20`)
- Bundle size: ~275KB minified
- App Monitor must have CustomEvents enabled

### What to point out in a demo
- "Session Replay lets you literally watch what the user saw — no screen recording SDK needed."
- "Privacy is enforced at the SDK level — all text is masked before it leaves the browser."
- "The recording is lightweight: only DOM diffs are sent, not screenshots."

---

## Feature 7: CloudWatch Metrics (Extended)

### What happens
The demo configures extended metrics that publish RUM data into CloudWatch Metrics (namespace `AWS/RUM`), broken down by page ID. This populates the **Metrics** tab.

### Metrics configured
| Metric Name | Event Type | Dimension |
|-------------|-----------|-----------|
| PageViewCount | page_view_event | PageId |
| JsErrorCount | js_error_event | PageId |
| Http4xxCount | http_event | PageId |
| Http5xxCount | http_event | PageId |

### Where to see it in CloudWatch
- **Console** → Metrics tab → default + extended metrics graphs
- **CloudWatch Metrics** → Namespace `AWS/RUM` → per-page breakdowns
- You can export these to custom dashboards or set alarms on them

### Behind the scenes
`setup.sh` calls `put-rum-metrics-destination` (enable CloudWatch as destination) + `batch-create-rum-metric-definitions` (define which dimensions to publish). Extended metrics are billed as CloudWatch custom metrics.

### What to point out in a demo
- "Default RUM metrics appear automatically. Extended metrics let you slice by page, browser, country — then set alarms on them."
- "These are real CloudWatch Metrics — you can put them on dashboards, create composite alarms, or pipe to EventBridge."

---

## Console Dashboard Overview

Once data is flowing, the CW RUM console dashboard shows:

```
┌─────────────────────────────────────────────────────────┐
│  Overview                                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│  │ Sessions │ │ Pages    │ │ Errors   │ │ Users    │   │
│  │  count   │ │ /sec     │ │ count    │ │ unique   │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │
├─────────────────────────────────────────────────────────┤
│  Tabs:                                                   │
│  [Performance] [Errors] [HTTP requests] [Sessions]       │
│  [Page views]  [Browsers & devices]                      │
└─────────────────────────────────────────────────────────┘
```

---

## Known Limitations

| Feature | Status | Reason |
|---------|--------|--------|
| X-Ray Tracing | Disabled (easy to enable) | Requires `addXRayTraceIdHeader: true` which can break CORS on cross-origin requests. Enable in `infra/template.yaml` if your backend is on the same origin. |
| Mobile RUM | Not covered | CW RUM supports iOS/Android via separate SDKs — this demo is web-only. |
| Session Replay dependency | Works but alpha | `aws-rum-web@3.0.0` depends on `@rrweb/record@2.0.0-alpha.20`. Functional in Chrome 148+/Firefox/Safari but technically pre-release. |

---

## Talking Points for Sharing

1. **Time-to-value**: "From zero to real telemetry in under 5 minutes — one CloudFormation stack + one script tag."

2. **Zero code instrumentation**: "The `<script>` tag is all you need. Performance, errors, HTTP — all auto-captured. No SDK wrapping required."

3. **Cost**: "At $1/100K events, a site with 10K daily users generates ~$3/month in RUM costs."

4. **Privacy-safe**: "All data stays in your AWS account. No third-party JS analytics. Cookies are optional and first-party only."

5. **Composition with AWS ecosystem**: "Add X-Ray for backend traces, set CloudWatch Alarms on error spikes, pipe to EventBridge for automated responses."

---

## Cleanup

When done, tear down all AWS resources:

```bash
./cleanup.sh
```

This deletes the App Monitor, Cognito Identity Pool, and IAM Role. No ongoing charges after cleanup.
