# RouteRev Swift package polish

Goal: an app maker can add the package in five minutes, with privacy declarations, a default collector, SwiftUI and RevenueCat helpers, and accurate docs, while preserving existing API and delivery behavior.

Source: `RouteRev - Swift package polish.md`, read in full; no images linked. Base: `origin/main` / `a9db8dc`. SanDisk identity check passed. Worktree: `codex/routerev-swift-polish`. Library read-only; no keys, real collector calls, tags, merge or push.

## Done when

- [x] 1. Original build exit 0; tests 13 total, 12 pass / 1 collector skip, zero failures. Logs: `docs/qa/baseline-build.log`, `baseline-test.log`. Two original async NSLock warnings in test fake recorded. Package/public API snapshots retained before edits.
- [x] 2. `swift build` and `swift test` pass; collector integration stays skipped without its environment variable. Evidence: `docs/qa/final-build.log` and `final-test.log`: exits 0, 18 pass / 1 collector skip.
- [ ] 3. `swift build -Xswiftc -swift-version -Xswiftc 6` passes with zero warnings; retain output. First attempt compiles but Swift Build emits a flag-override planning warning; native-backend strict build finished (exit 0, backend-deprecation warning, `docs/qa/swift6-native-build.log`). Exact final command exit 0 with a planning warning (`final-swift6-build.log`); strict iOS exit 0 with zero warnings (`ios-swift6-build.log`). No warning hidden.
- [x] 4. iOS package build passes through `ios-dev-build routerev-swift codex -- -scheme RouteRev -destination 'generic/platform=iOS Simulator' build`; if package unsupported, record exact reason and use authorized external DerivedData fallback. Evidence: exact wrapper command exit 0, BUILD SUCCEEDED, arm64 + x86_64, `docs/qa/ios-build.log`; wrapper accepts the package. No simulator started.
- [x] 5. Privacy manifest is valid plist, copied resource, loaded and parsed by a bundle test; UserDefaults CA92.1 and linked/not-tracking Analytics Product Interaction/User ID declared. Audit other required-reason APIs. Evidence: `plutil -lint` passes; `testBundledPrivacyManifestDeclaresReasonsAndCollectedData` loads Bundle.module and checks all fields. Source audit finds no file timestamp, boot-time or disk-space APIs; Apple CA92.1 checked.
- [x] 6. Default endpoint and new configure overload tested; unchanged old configure call compiles. Evidence: `PolishTests` verifies default/custom config and unchanged limits; compile-only closures call both old signatures and both new signatures, without persistent storage or real transport.
- [x] 7. SwiftUI per-appearance and RevenueCat helpers have doc comments and tests. Evidence: `PolishTests` checks isolated identity state before/after and compiles Text routeRevScreen with both argument forms.
- [x] 8. README pins 0.2.1/latest-tag advice, default setup, optional subdomain, helpers, privacy and release checklist; two DocC articles; history-based CHANGELOG. Evidence: README and matching GettingStarted article include all requested sections; overview links public topics; CHANGELOG follows four tagged commits.
- [x] 9. Generate documentation if plugin available; otherwise record unavailable and validate catalog during build. Evidence: plugin unavailable (exit 64, `docs/qa/docc-plugin.log`); bundled `xcrun docc convert --warnings-as-errors` exit 0, no diagnostics (`docc-convert.log`), using built symbol graphs.
- [x] 10. Compare original/final dump-package and public symbols; preserve all existing public names/signatures and package compatibility. Evidence: `api-comparison.txt` shows no removed explicit public declarations; final own-source filter includes SwiftUI extension. Manifest diff adds only resource; tools/platforms/products/dependencies unchanged.
- [x] 11. No git tag created. Evidence: baseline tag list matches final list; only four original releases.

## Acceptance and quality

- [x] Build and all applicable unit tests pass, without real API calls. No UI tests, example apps or simulator startup (package spec). Evidence: Final build/test exits 0, 18 pass / 1 intentional collector skip; both iOS builds pass, all environments whitelisted.
- [x] Independent fresh reviewer checks full diff; fix actionable findings. Evidence: Fresh review_routerev_swift found no functional bugs; its two evidence findings corrected or explicitly blocked.
- [x] No event format, batching/retry, Keychain/queue storage or dependency change. Evidence: Full diff inspection; Client/Event/Transport/AcquisitionSource unchanged; Storage comments only; manifest adds only resource.
- [x] Public examples compile and explain lifecycle accurately; no placeholders or misleading privacy claims. Evidence: Both configure signatures and SwiftUI compile tests; docs distinguish Unreleased, sign-up success/sign-in/sign-out, 10-second backoff and enabled behavior.
- [x] README, DocC and REPORT cover scope, evidence, decisions and remaining limits. Evidence: DocC warnings-as-errors exit 0; README/GettingStarted bodies identical; REPORT includes the one remaining toolchain acceptance gap.

## Blocked on Alex

Done-when 3 requires zero warnings from the exact `swift build -Xswiftc -swift-version -Xswiftc 6` command. Apple Swift 6.4 / Xcode 27 defaults to Swift Build, which emits a language-override planning warning even when the manifest declares both Swift 5 and 6. The native backend compiles all package sources cleanly but emits its own backend-deprecation warning. Those experimental manifest language settings were reverted; package compatibility is preserved. Logs retain every warning, with no suppression.

Alex/Claude must accept the tool warning for this criterion or provide a toolchain whose SwiftPM command does not emit it. No installation or toolchain change was attempted. The iOS wrapper with `SWIFT_VERSION=6` builds arm64 and x86_64 with zero warnings (`docs/qa/ios-swift6-build.log`), confirming strict UIKit/SwiftUI compilation.

## Log

- 2026-10-04: Read full spec, checked SanDisk, fetched origin, created exact branch/worktree at a9db8dc; starting baseline before source edits.

- 2026-10-04: 18 unit tests pass and collector skipped; privacy/config/helpers/docs implemented; iOS normal and Swift 6 builds pass, DocC warnings-as-errors passes; exact SwiftPM zero-warning criterion blocked by tool diagnostics, no warning hidden.
