# Getting started with RouteRev

Swift client for [RouteRev](https://github.com/alexmorris10x/routerev): revenue-attributed analytics with no dependencies. iOS 15+ and macOS 12+.

## Install

Add the package in Xcode → Add Package, or in XcodeGen `project.yml`:

```yaml
packages:
  RouteRev:
    url: https://github.com/alexmorris10x/routerev-swift
    from: "0.3.0"
```

Use the latest published tag. See the package's `CHANGELOG.md` for what changed in each version.

## Configure at launch

Every app sends to its **own collector subdomain**, CNAME'd to RouteRev (for example `e.yourapp.com`). Set the subdomain up for your product in RouteRev, add its DNS-only CNAME, then pass its `/e` URL with the product's public key:

```swift
import RouteRev

// Call once at launch.
RouteRev.configure(
    key: "YOUR_PRODUCT_KEY",
    endpoint: URL(string: "https://e.yourapp.com/e")!
)
```

The package has no built-in server address, so a shipped build never depends on a RouteRev domain: a move is a DNS change, and requests look first-party to blockers. Configuration creates the install identity and queues the automatic first-open event. Events flush in the background without blocking the UI.

### Consent

If your app asks before collecting analytics, configure with collection off and turn it on when the user agrees:

```swift
var options = RouteRev.Options()
options.enabled = userHasConsented   // your own stored answer
RouteRev.configure(key: "YOUR_PRODUCT_KEY", endpoint: URL(string: "https://e.yourapp.com/e")!, options: options)

// Later, when the user agrees:
RouteRev.isEnabled = true
```

While disabled, **nothing is sent**: screen, goal and identify calls are dropped, queued events wait on the device, and `first_open` (with its Search Ads token) waits. Turning collection on sends `first_open` once for the install. `isEnabled = false` stops sending again at any time. Either switch set to false keeps collection off, including `isEnabled = false` set before `configure`. The flag isn't saved, so set it from your stored consent at each launch.

## Track screens and goals

```swift
// When the paywall opens:
RouteRev.screen("Paywall", ["placement": "onboarding"])

// Only after sign-up succeeds:
RouteRev.goal("sign_up", ["method": "apple"])

// After signing in, use your own account ID (not an email):
RouteRev.identify("YOUR_INTERNAL_USER_ID")

// When the user signs out:
RouteRev.reset()
```

Use the same `signupGoal` name configured for the product in RouteRev (default `sign_up`). Screens appear under Top pages as `/ScreenName`. RouteRev accepts string, number and boolean properties as `[String: RouteRevValue]`.

SwiftUI can record a screen on each appearance:

```swift
import SwiftUI
import RouteRev

struct Paywall: View {
    var body: some View {
        Text("Choose your plan")
            .routeRevScreen("Paywall", ["placement": "onboarding"])
    }
}
```

Returning to the screen records another appearance; ordinary body updates do not record events. Attach the modifier to the screen container. Use it or `RouteRev.screen` for that appearance, so it is counted once.

For an onboarding acquisition survey:

```swift
RouteRev.acquisitionSurvey(.reddit)
// AcquisitionSource.allCases and .label provide the answer choices.
```

## Link RevenueCat purchases

After configuring both SDKs, set the install attribute in your app:

```swift
Purchases.shared.attribution.setAttributes(RouteRev.revenueCatAttributes)
```

The helper returns `["rr_install_id": installId]` after configure, or an empty dictionary before an install ID exists. RouteRev has no RevenueCat dependency; your app supplies its existing RevenueCat integration. RouteRev reads the attribute from RevenueCat webhooks to attribute purchases to the install.

## Behavior and options

- **First open:** queues `first_open` once per install, with a deterministic ID for collector deduplication. On a physical iOS device, AdServices can supply Apple's Search Ads attribution token; the collector resolves its campaign and keyword. No IDFA is requested. Set `Options.searchAdsAttribution = false` to omit the token.
- **Identity:** the install ID is stored in the Keychain, with a UserDefaults fallback, and can survive reinstall on the same device. `reset()` clears the user ID and starts a session while retaining the install ID.
- **Sessions:** roll over after 30 minutes without events.
- **Delivery:** queues JSON in Application Support; flushes every 15 seconds, at 20 events, and on backgrounding. Network/server errors back off from **10 seconds**, doubling up to 5 minutes. Invalid batches (400/404/413/422) are dropped. The default queue limit is 1,000 unsent events; oldest events beyond the limit are dropped.
- **Limits:** names up to 120 characters, 20 properties, keys up to 64 characters and strings up to 500 characters.
- **Enabled flag:** `Options.enabled = false` or `RouteRev.isEnabled = false` sends nothing at all until collection is turned on (see <doc:GettingStarted#Consent>). `reset()` still works while disabled, since it only clears local state.

`Options` also exposes `flushInterval`, `batchSize` and `maxQueuedEvents`. `await RouteRev.flush()` requests delivery now.

## Privacy manifest

`PrivacyInfo.xcprivacy` is copied into the package's resource bundle, and Xcode merges it into your app's privacy report. It declares no tracking and no tracking domains, and app-private **UserDefaults** access (reason `CA92.1`) for the install's session and first-open state. The package uses no other required-reason API (no file timestamps, boot time or disk space).

It declares these collected data types, each **linked to the user** (through the install ID), **not used for tracking**, purpose **Analytics**:

| Data type | What RouteRev collects |
| --- | --- |
| Product Interaction | Screens, goals and sessions your app records, with their properties. |
| User ID | The account ID you pass to `identify`, linking the install to your user. |
| Device ID | The install ID: a random ID RouteRev creates and keeps in the Keychain, so it can survive a reinstall on the same device. Not the IDFA or IDFV. |
| Coarse Location | Country, region and city, which the collector derives from the request's IP address. The IP itself is never stored. |
| Advertising Data | For installs from Apple Search Ads: the campaign, ad group and keyword, which the collector looks up from the attribution token sent with `first_open`. The token itself isn't stored. Turn off with `Options.searchAdsAttribution = false`. |

Each event also carries the app version, language, time zone and screen width, and the collector notes the OS and device class (phone or tablet) from the request; the UA string isn't stored. RouteRev never asks for the IDFA, shares data with third parties for advertising, or fingerprints the device, so it needs no App Tracking Transparency prompt.

### What to put in your App Store privacy label

The manifest doesn't fill in the App Store privacy label for you. For RouteRev, declare:

| Data type (App Store Connect) | Linked to user | Used for tracking | Purpose |
| --- | --- | --- | --- |
| Usage Data → Product Interaction | Yes | No | Analytics |
| Identifiers → User ID (if you call `identify`) | Yes | No | Analytics |
| Identifiers → Device ID | Yes | No | Analytics |
| Location → Coarse Location | Yes | No | Analytics |
| Usage Data → Advertising Data (unless `searchAdsAttribution` is off) | Yes | No | Analytics |
| Purchases → Purchase History (if you link RevenueCat purchases) | Yes | No | Analytics |

The package never reads StoreKit, but linking RevenueCat with `rr_install_id` lets RouteRev attribute your purchases to the install, so add Analytics as a purpose of the Purchase History you already declare for RevenueCat. Add anything else your app sends in event properties, and the data your other SDKs collect. Keep personal or sensitive values (emails, names, free text) out of properties.

## Checklist before release

- Set the correct RouteRev product public key and your own collector subdomain endpoint.
- Match the successful sign-up goal name to the product's `signupGoal`.
- Set the RevenueCat install attribute after configuration, if using RevenueCat.
- If you ask for analytics consent, configure with `Options.enabled` from the stored answer.
- Complete the App Store privacy label (see <doc:GettingStarted#What-to-put-in-your-App-Store-privacy-label>).

## With ios-boilerplate

Map the app's analytics service to RouteRev:

| App service | RouteRev |
| --- | --- |
| Set signed-in user | `RouteRev.identify(id)` |
| Sign out | `RouteRev.reset()` |
| Track event | `RouteRev.goal(event.name, props)` |
| Track screen | `RouteRev.screen(name)` |

Convert `[String: Any]` properties to `[String: RouteRevValue]`.

## Test

```bash
swift build
swift test
swift build -Xswiftc -swift-version -Xswiftc 6
```

Unit tests use in-memory stores and fake transports. The collector integration test is skipped unless both `ROUTEREV_E2E_ENDPOINT` and `ROUTEREV_E2E_KEY` are set; leave them unset for offline checks. The public `configure` starts Keychain storage and real delivery, so tests drive an internal configure with an in-memory store and a fake transport instead.
