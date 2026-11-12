# TikTok Duo

Layout controls for TikTok on foldable iPhones, including the folded display,
unfolded portrait, and unfolded half-screen windows.
Choose a layout in **iOS Settings → Apps → TikTok → Layout Mode**, then fully
close and reopen TikTok. For a separately named app, open that app's Settings entry.

| Mode | Tabs | Content area |
| --- | --- | --- |
| Classic | Standard bottom tabs | System status area retained |
| Native | Floating glass tabs, with a right-side rail where supported | System status area retained |
| Fullscreen | Standard bottom tabs | Full available width with horizontal system bars |

Tab placement adapts to the current window size and orientation. In Native mode,
windows that do not use a vertical rail retain floating bottom tabs.

Includes advanced controls for adaptive fold layout and video cropping. Native mode
preserves the current bottom safe area for video metadata and progress.

The extension uses Objective-C runtime hooks and narrowly validated native
reader pointers, with Apple system frameworks as its only dependencies.
Preferences are available in iOS Settings.

## Compatibility

This initial release targets **TikTok 47.7.0, build 477034**, with MusicallyCore
UUID `81156393-0F58-38C4-8723-0B15CF11EC16`. Overrides stay inactive for other
versions or framework identities. Individual hooks also validate signatures,
bytes and memory mappings. Updating the version string alone is insufficient
for supporting a new TikTok build.

The source builds an arm64 iOS library with a minimum deployment target of iOS
15. That deployment target does **not** imply layout support on all iOS versions
or devices. The native layouts depend on TikTok and OS/device eligibility.
Local build and fixture tests pass; **on-device validation is pending**.
Layout behavior must be checked in each display configuration. The advanced
crop experiment's visible behavior is unverified.

## Build

Requires macOS, full Xcode with an iPhoneOS SDK selected by `xcode-select`, and
Python 3.10 or newer. No package-manager dependencies are needed.

```sh
./build.sh
./tests/run-all.sh
```

Output: `build/TikTokDuo.dylib`. Its ad-hoc signature is for build
validation; the entire app must be signed for your device before installation.

## Package for your own device

Supply your own clean, decrypted TikTok IPA matching the compatibility entry.
No TikTok IPA, vendor framework, third-party tweak, signing certificate, or
provisioning profile is distributed here.

Run from the repository root:

```sh
python3 scripts/package.py \
  --ipa /path/to/TikTok-47.7.0.ipa \
  --dylib build/TikTokDuo.dylib \
  --out /path/to/TikTok-Duo.ipa
```

The helper verifies the app version, bundle ID, framework UUID and encryption
state, adds a real Mach-O load command, and includes the library and
`Settings.bundle`. It preserves the app's resources and extensions. It refuses
to overwrite an output, existing Settings bundle, or previously injected tweak.
It cannot decrypt an App Store download.

Re-sign the resulting IPA using your normal signing workflow. When using
Sideloadly, load the **already patched output**, keep additional dylib injection
off, and retain the account and bundle-ID mapping for your existing installation.
The helper does not sign or install the app. Installing only the dylib without
its `Settings.bundle` will not expose the preferences page. A jailbreak package
or standalone Preferences.app bundle is not provided in this release.

## Settings and startup

The extension stores its settings under `TCLCover.*` preference keys in the
app's standard user defaults. Each app installation maintains its own settings.

Settings changes apply after a full app restart. Diagnostics show the last
recorded session, not a live inspection. Counts and geometry are not proof of
a visible layout. Saved choices survive quick exits and restarts. To return to
the standard layout, select Classic in iOS Settings and restart the app.

## Development and distribution

`tests/run-all.sh` covers mode selection, unsupported identities, ABI guards,
cache behavior, glass readers, system-bar routing, safe-area spacing, startup preference preservation, and synthetic IPA packaging. Tests do not download or execute TikTok.
GitHub Actions runs the same checks and builds the extension; it does not publish
an IPA or install anything.

`python3 scripts/release.py` creates separate **source** and **extension** ZIPs
in `dist/`. The extension ZIP contains the compiled dylib, Settings resources,
README and license. Share these ZIPs or this source repository—not a patched
TikTok IPA. The release helper scans the source allowlist for accidental private
paths, device identifiers, and credential patterns.

See [ARCHITECTURE.md](ARCHITECTURE.md) for implementation details and
[CHANGELOG.md](CHANGELOG.md) for release details.

MIT licensed. Unofficial and not affiliated with TikTok or its owners. The
license covers this extension's code, not the proprietary app it modifies.
