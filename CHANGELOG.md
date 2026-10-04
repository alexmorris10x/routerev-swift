# Changelog

## 0.3.0

- Bundle a privacy manifest: app-private UserDefaults (`CA92.1`) and linked, non-tracking Analytics data (Product Interaction, User ID, Device ID, Coarse Location, Advertising Data). The README lists what to put in your App Store privacy label.
- **Behavior change:** disabled now sends nothing. With `Options.enabled = false` or `isEnabled = false` (before or after `configure`), no events, queued events or `first_open` (with its Search Ads token) leave the device; enabling later sends `first_open` once per install. Previously `first_open` and queued events were still sent. `reset()` now also works while disabled.
- `configure(key:endpoint:options:)` is unchanged and still the only way to configure: apps pass their own collector subdomain. No built-in server address.
- Add SwiftUI per-appearance screen tracking and dependency-free RevenueCat attributes.
- Make UIKit background-task isolation explicit for Swift 6; remove async-locking warnings in test fakes.
- Refresh installation, lifecycle and privacy guidance; add DocC and compatibility/resource tests.

## 0.2.1

- Give `first_open` a fixed event ID per install for collector deduplication (`a9db8dc`).

## 0.2.0

- Send Apple Search Ads attribution and acquisition survey answers (`4c558d1`).

## 0.1.1

- Send an identify event only when the user changes (`2db5d60`).

## 0.1.0

- Introduce the Swift client, identity, sessions, persistent queue, batching, retry and tests (`6f578f9`).
