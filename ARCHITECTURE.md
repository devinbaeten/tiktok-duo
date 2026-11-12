# Implementation

- `TCLCoverEngine.m` owns mode mapping, preference snapshots, startup preference preservation,
  Objective-C experiment getters, and the vertical-tab bottom-safe-area fix.
- `TCLCoverNative.m` checks the exact MusicallyCore image and native byte
  signatures before replacing two validated reader slots. It applies adaptive
  thresholds and refreshes glass eligibility caches without bypassing the
  OS/device eligibility result.
- `TCLCoverChrome.m` requests horizontal system bars from the app's root
  controller for Fullscreen and restores inherited behavior when disabled.
- `Settings.bundle` is read by iOS Settings; the app writes passive diagnostics
  using its standard user defaults.

Compatibility is deliberately narrow. The framework UUID, method ABIs, reader
prefixes, key bytes, segment protections, and expected original pointers each
provide a rejection point. Unsupported callers retain original behavior. Never
extend support by merely deleting these checks; trace and test the new artifact.

## Validation boundaries

Most tests run Objective-C runtime and C fixtures on macOS. They validate the
hook contracts and mode mappings, not all UIKit behavior in the real app.
Packaging tests use synthetic arm64 Mach-O files with known load-command
padding. The built library is restricted to Apple system dependencies. On-device
validation is required before a release should be described as device-tested.

When reporting bugs, include the extension version, TikTok version/build, OS,
selected mode, display configuration (folded, unfolded portrait, or unfolded
half-screen), window size, and relevant diagnostic values.
Remove personal identifiers and unrelated content before sharing device logs.
