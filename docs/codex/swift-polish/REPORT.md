# RouteRev Swift package polish

> QA evidence (`docs/qa/`) was moved out of the repo on 2026-10-04 to `/Volumes/10X_WORKSPACE/Agent Work/review-2026-10-04/codex-qa-archive/routerev-swift/qa/`. Paths below refer to that archive.

## Summary

Bundled the privacy manifest and tested its declared data/reasons from Bundle.module.
Added the default collector, preserving explicit-endpoint configuration and delivery behavior.
Added SwiftUI appearance tracking and dependency-free RevenueCat attributes.
Updated README, two DocC articles and four-release changelog; strict iOS compilation passes.
Job is blocked only on the exact SwiftPM command's tool warning; all implementation and other acceptance checks pass.

## Done when

| Item | Result | Evidence |
| --- | --- | --- |
| 1 | ✅ | Original build exit 0; tests 13 total, 12 pass / 1 collector skip, zero failures. Logs: `docs/qa/baseline-build.log`, `baseline-test.log`. Two original async NSLock warnings in test fake recorded. Package/public API snapshots retained before edits. |
| 2 | ✅ | `swift build` and `swift test` pass; collector integration stays skipped without its environment variable. Evidence: `docs/qa/final-build.log` and `final-test.log`: exits 0, 18 pass / 1 collector skip. |
| 3 | ❌ | `swift build -Xswiftc -swift-version -Xswiftc 6` passes with zero warnings; retain output. First attempt compiles but Swift Build emits a flag-override planning warning; native-backend strict build finished (exit 0, backend-deprecation warning, `docs/qa/swift6-native-build.log`). Exact final command exit 0 with a planning warning (`final-swift6-build.log`); strict iOS exit 0 with zero warnings (`ios-swift6-build.log`). No warning hidden. |
| 4 | ✅ | iOS package build passes through `ios-dev-build routerev-swift codex -- -scheme RouteRev -destination 'generic/platform=iOS Simulator' build`; if package unsupported, record exact reason and use authorized external DerivedData fallback. Evidence: exact wrapper command exit 0, BUILD SUCCEEDED, arm64 + x86_64, `docs/qa/ios-build.log`; wrapper accepts the package. No simulator started. |
| 5 | ✅ | Privacy manifest is valid plist, copied resource, loaded and parsed by a bundle test; UserDefaults CA92.1 and linked/not-tracking Analytics Product Interaction/User ID declared. Audit other required-reason APIs. Evidence: `plutil -lint` passes; `testBundledPrivacyManifestDeclaresReasonsAndCollectedData` loads Bundle.module and checks all fields. Source audit finds no file timestamp, boot-time or disk-space APIs; Apple CA92.1 checked. |
| 6 | ✅ | Default endpoint and new configure overload tested; unchanged old configure call compiles. Evidence: `PolishTests` verifies default/custom config and unchanged limits; compile-only closures call both old signatures and both new signatures, without persistent storage or real transport. |
| 7 | ✅ | SwiftUI per-appearance and RevenueCat helpers have doc comments and tests. Evidence: `PolishTests` checks isolated identity state before/after and compiles Text routeRevScreen with both argument forms. |
| 8 | ✅ | README pins 0.2.1/latest-tag advice, default setup, optional subdomain, helpers, privacy and release checklist; two DocC articles; history-based CHANGELOG. Evidence: README and matching GettingStarted article include all requested sections; overview links public topics; CHANGELOG follows four tagged commits. |
| 9 | ✅ | Generate documentation if plugin available; otherwise record unavailable and validate catalog during build. Evidence: plugin unavailable (exit 64, `docs/qa/docc-plugin.log`); bundled `xcrun docc convert --warnings-as-errors` exit 0, no diagnostics (`docc-convert.log`), using built symbol graphs. |
| 10 | ✅ | Compare original/final dump-package and public symbols; preserve all existing public names/signatures and package compatibility. Evidence: `api-comparison.txt` shows no removed explicit public declarations; final own-source filter includes SwiftUI extension. Manifest diff adds only resource; tools/platforms/products/dependencies unchanged. |
| 11 | ✅ | No git tag created. Evidence: baseline tag list matches final list; only four original releases. |

## Screenshots

Not applicable: this is a library package. The spec excludes example apps, UI tests and simulator startup. No app UI or screenshots are claimed. SwiftUI view construction was compiled and executed without rendering/onAppear.

## How to run

From this worktree, with collector integration variables unset:

```sh
swift build
env -u ROUTEREV_E2E_ENDPOINT -u ROUTEREV_E2E_KEY swift test
swift build -Xswiftc -swift-version -Xswiftc 6
/Users/10x/bin/ios-dev-build routerev-swift codex -- -scheme RouteRev -destination 'generic/platform=iOS Simulator' build
/Users/10x/bin/ios-dev-build routerev-swift codex -- -scheme RouteRev -destination 'generic/platform=iOS Simulator' SWIFT_VERSION=6 build
plutil -lint Sources/RouteRev/PrivacyInfo.xcprivacy
xcrun docc convert Sources/RouteRev/RouteRev.docc --additional-symbol-graph-dir .build/out/symbolgraph --output-dir '/Volumes/10X_WORKSPACE/Agent Work/codex-queue/routerev-swift.doccarchive' --warnings-as-errors
```

The package scheme is `RouteRev`. Both iOS builds used the wrapper's external `routerev-swift/codex/DerivedData` lane; no fallback or simulator startup needed. Unit tests use MemoryStore and MockTransport. No public configure call, Keychain, actual collector/model call or real key was exercised. The collector integration test is intentionally skipped. Final unit evidence: 19 total, 18 passed, one skipped, zero failures (`docs/qa/final-test.log`).

`swift package generate-documentation` is unavailable (exit 64, unknown plugin, `docs/qa/docc-plugin.log`); no dependency added. The bundled DocC compiler independently compiled the catalog and symbol graphs with warnings treated as errors, exit 0/no diagnostics (`docs/qa/docc-convert.log`). The archive stays in external scratch, not Git.

## Decisions

- Extracted the existing configuration construction as an internal pure function. Legacy/default call closures compile without execution, avoiding real storage/network side effects. The default overload delegates to the unchanged explicit-endpoint API.
- Tested RevenueCat's accessor with an isolated State and MemoryStore identity, plus the public helper's initial empty value. No global state, timers or notification observers are installed in tests.
- Made the existing main-queue notification guarantee explicit with MainActor.assumeIsolated and isolated BackgroundTask to MainActor. Retained lock-protected unchecked Sendable types with safety comments.
- Removed original async NSLock warnings in the fake transport by moving locked work to a synchronous function and providing locked body snapshots.
- Corrected two pre-existing documentation claims: retry starts at 10 seconds; enabled=false gates API collection but does not stop automatic first-open or queued delivery. No delivery behavior was changed.
- Kept 0.2.1 install guidance as specified and clearly labelled new features Unreleased, so readers are not promised APIs absent from that tag.
- Kept package tools/language defaults unchanged after verifying that experimental explicit Swift 5/6 language selection did not resolve the Swift Build warning.

## Public compatibility

`docs/qa/baseline-package.json` / `final-package.json` retain tools 5.9, iOS 15/macOS 12, the RouteRev library/test targets, no dependencies and language defaults. Only the copied resource is added.

`docs/qa/api-comparison.txt` reports no removed explicit public declarations. Raw baseline symbol snapshot is retained; cleaned comparison excludes compiler-generated protocol/literal members and imported CoreVideo extension noise, and includes the SwiftUI extension graph. Existing conformances and synthesized behavior remain unchanged because Event.swift and AcquisitionSource.swift are untouched.

Preserved: Options.init and its five properties; configure(key:endpoint:options:); acquisitionSurvey, screen, goal, identify, reset, async flush, installId and read/write isEnabled; all RouteRevValue cases, literal initializers and Codable methods; all AcquisitionSource cases/raw values and label. Added only defaultEndpoint, configure(key:options:), revenueCatAttributes and View.routeRevScreen(_:_:) (MainActor). No tag was created; final tag list equals the four-tag baseline.

## Privacy audit

The manifest uses app-private UserDefaults reason CA92.1, as required by the spec and supported by [Apple's required-reason API list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). DeviceStore reads/writes RouteRev-prefixed app state; it does not read other apps' defaults. Source inspection found no file timestamp, boot-time/uptime or disk-space APIs. Reading/writing the queue file and wall-clock Date values do not add those categories.

Product Interaction and User ID are linked, non-tracking Analytics declarations matching [Apple's collected-data identifiers](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype) and the requested README advice. No App Store submission or privacy certification is claimed; the full app must assess its properties and other SDKs.

## Known gaps and bugs

- **Blocked on Alex: Done-when 3's exact zero-warning CLI criterion.** Apple Swift 6.4 (swiftlang-6.4.0.34.1), Xcode 27, emits one Swift Build language-override planning warning for the exact requested command even with explicit Swift 6 manifest support. Native backend compiles every source cleanly but emits a backend-deprecation warning. Final and experimental logs preserve both warnings. Neither was suppressed. The normal build/test and both iOS builds have zero warnings; iOS SWIFT_VERSION=6 proves strict concurrency for UIKit and SwiftUI (`ios-swift6-build.log`). Alex/Claude must accept the tool diagnostic for the CLI criterion or supply a toolchain that does not emit it.
- Existing enabled flag is not a consent/delivery barrier; documented rather than changing queue/first-open behavior outside scope.
- No physical-device/runtime lifecycle, network collector or RevenueCat integration acceptance was attempted. Package spec asks for compile-only SwiftUI tests.
- Fresh independent reviewer found no functional source/docs bugs. Its warning and API snapshot findings are reflected above.

## Questions for Alex

- Accept the recorded SwiftPM tool warning, or provide a toolchain for the exact warning-free CLI check?
- After review/merge, decide the next release tag (spec suggests 0.3.0). No tag, merge or push occurred here.
