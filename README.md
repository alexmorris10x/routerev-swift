# RouteRev for iOS

Swift client for [RouteRev](https://github.com/alexmorris10x/routerev): first-party, revenue-attributed analytics.
No dependencies. iOS 15+.

## Install

Add the package (Xcode → Add Package, or in XcodeGen `project.yml`):

```yaml
packages:
  RouteRev:
    url: https://github.com/alexmorris10x/routerev-swift
    from: 0.1.0
```

## Use

```swift
import RouteRev

// At launch. The endpoint is the product's own collector subdomain (a DNS-only CNAME to RouteRev).
RouteRev.configure(key: "pk_memex_…", endpoint: URL(string: "https://e.trymemex.com/e")!)

RouteRev.screen("Paywall")                       // shows under Top pages as /Paywall
RouteRev.goal("sign_up", ["method": "apple"])    // goals and funnels
RouteRev.identify(user.id)                       // joins this install with the user's web visits
RouteRev.reset()                                 // on sign-out

// Link RevenueCat purchases to this install (RouteRev reads it from the webhook):
Purchases.shared.attribution.setAttributes(["rr_install_id": RouteRev.installId ?? ""])
```

Use the same `signupGoal` name the product has in RouteRev (default `sign_up`) so sign-ups count in the funnel.

### With `ios-boilerplate`

Fill in the TODOs in `Core/Services/AnalyticsService.swift`:

| AnalyticsService | RouteRev |
|---|---|
| `setUserId(id)` | `id.map(RouteRev.identify) ?? RouteRev.reset()` |
| `track(event)` | `RouteRev.goal(event.name, props)` |
| `trackScreen(name, …)` | `RouteRev.screen(name)` |

Convert `[String: Any]` properties to `[String: RouteRevValue]` (strings, numbers, booleans).

## Behavior

- **Install ID** in the Keychain, so it survives reinstalls; exposed as `RouteRev.installId`.
- **Sessions** end after 30 minutes without events.
- **Queue** on disk; sent every 15 s, at 20 events, and when the app goes to the background. Network and 5xx errors retry with backoff (5 s doubling to 5 min). A batch the collector rejects as invalid (400/404/413/422) is dropped so it can't block the queue. At most 1,000 unsent events are kept.
- **Limits** match the collector: names ≤ 120 chars, ≤ 20 props, keys ≤ 64, strings ≤ 500.
- **Privacy:** no IDFA, no fingerprinting, nothing shared with third parties, so no App Tracking Transparency prompt is expected. Declare "Product Interaction" and "User ID" (linked, not used for tracking) in the App Store privacy label.
- `RouteRev.isEnabled = false` pauses collection (for example, until consent).

## Test

```bash
swift test
# Against a running collector (sends real events):
ROUTEREV_E2E_ENDPOINT=http://localhost:3000/e ROUTEREV_E2E_KEY=pk_dev_… swift test --filter CollectorIntegrationTests
```
