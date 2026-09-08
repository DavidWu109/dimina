# JSSDK Build Source

This document records the provenance of the bundled JSSDK artifact.

## Current bundled release: Furina 1.0.39 + local iOS WebView overlay

- Version name/code: `1.0.39 / 40` (published release identifiers).
- Artifact: `shared/jssdk/main.zip`.
- Patched SHA-256: `c78cdb4979c7b4a7c0c7e466e8daff6a3ce91ea142fa5c81b722ab6419d3cb23`.
- Source: 胡腾, 千岛小程序技术委员会, 2026-09-07 17:47,
  [release message](https://applink.feishu.cn/client/chat/open?openChatId=oc_ef6342abd9e2bce977c92080c40e226c&position=7845).
- Message ID: `om_x100b66dccde7747cc393375d7f53c97`.
- Published outer archive SHA-256: `6771d425825775c5a13d55b81831b56045a525991250bee401b17a46568fd585`.
- Published `main.zip` SHA-256: `1d82b6b41287f3c9433a97c92648740a7cc40a1b7280c4cea2902101ba2733f3`.

### Local overlay and reproducibility

The published artifact is the baseline, not the older `fe/` working tree. The
Furina repository HEAD inspected was `63c5cacdf2ac48883441a99703bdbbbd234b4c61`;
its tracked SDK configuration is still `1.0.38 / 39`. An exact source commit for
the published 1.0.39 build was not provided. Do not regenerate this release with
the local `generate-sdk.js`: doing so would replace the release with older code.

`fe/scripts/patch-jssdk-1.0.39-ios.mjs` checks the published SHA-256 and patches
only the WebView component in `main/assets/pageFrame.js`. All other release files
and all code outside that component remain unchanged. This is a version-pinned
vendor artifact overlay, not an upstream source merge. Port it to the matching
Furina source when that release source is available; do not reuse the minified
anchors on a different release.

Preserved local fixes:

- On component id change, unmount the previous native instance and mount the new
  one after Vue's DOM update (`flush: 'post'`); src-only changes remain updates.
- Unmount the actual mounted id and ignore changes after disposal.
- Forward native `errMsg` in WebView error events.
- Retain `parentWebViewId` alongside the release's `bridgeId`.

Reproduce from the original downloaded `jssdk.zip`:

```bash
node fe/scripts/patch-jssdk-1.0.39-ios.mjs /path/to/jssdk.zip /path/to/output
JSSDK_ARCHIVE=/path/to/output/main.zip node --test fe/scripts/test-jssdk-1.0.39-ios.mjs
```

ZIP timestamps are normalized so repeated runs produce the same hash. This local
overlay keeps release versionCode 40, which upgrades the previous local code 27.
A sandbox already holding code 40 will not be recopied by `prepareSdk`; it needs
the normal SDK-cache reset for local testing. Do not treat this patched artifact
as byte-identical to the official 1.0.39 archive.

### Verification and integration boundaries

- Seven artifact-level tests pass; the unpatched release fails the three local
  overlay checks (parent identifier, id-change lifecycle, error details).
- JavaScript syntax check and ZIP integrity check pass.
- Native `NativeComponentAPI` already accepts both parent-id fields and handles
  the mount/update/unmount contract; no native changes were required here.
- The actual service bundle dynamically registers host-provided methods, including
  `requireEchoAuthorize`; the EchoWebKit handler remains the implementation.
- No app build, simulator UI, keyboard, or physical-device regression run was made.
- Kuril currently pins remote Dimina `v1.4.13`; its local Dimina mapping is disabled.
  These changes update the sibling Dimina source artifact, not the installed pod
  or an already-built app. Podfile and build configurations were not changed.
- Pre-replacement local files were preserved at
  `/Users/davidagent/Work/jssdk-backups/dimina-before-furina-1.0.39.fEfN4u/`.
  Existing local frontend and native source edits were left intact.

### Product-confirmed iOS WebView presentation

The product decision after the SDK update requires a fixed full-content WebView
and standard native navigation, including pages configured with custom navigation.
This is enforced in the native container, not through overridable business CSS:

- While a native WebView component is mounted, `DMPPageController` keeps its
  standard navigation bar visible and places the render viewport below it.
- The embedded WebView fills that viewport, ignoring business rect/position and
  z-index. Host bounds changes relayout it, including rotation and container resize.
- Presence is tracked per render WebView; after the final component is removed,
  the page's original navigation configuration is restored. The callback is cleared
  before returning a render WebView to the pool.
- Map/video layout and ordinary page navigation are unchanged.
- Four presentation-policy XCTest cases passed in an isolated macOS harness
  compiling the actual portable presentation helper (not the full iOS module).
  The JavaScript release and
  its overlay do not need another change for this native enforcement.
- Simulator/device UI verification is still pending; policy tests do not validate
  navigation animation, safe-area rendering, or the keyboard visually.

## Previous local build (retained for provenance)

### Release

- JSSDK version: `1.0.26`
- Version code: `27`
- Artifact: `shared/jssdk/main.zip`
- SHA-256: `e730d0da4b53444ce444cf9a5d4e4e0cf7a675ab6945875df9ea6f5e0aad86ed`

### Source

- Repository baseline: `34e336c591868a850a72b89d7ed386f8406cf515`
- Upstream repository baseline: `da90d3d54c935ea5920c2e85e485200577623d27`
- Upstream Slider fix: `fix(fe,component): align slider behavior with native implementation (#297)`
- Company patch commit: `68e67065524045746b4b60d4cdde620604536cd1`
- Working-tree capability: iOS `native/webview` layout, lifecycle, event and bridge context forwarding.

The Slider implementation is taken directly from the upstream baseline. It is not maintained as a company-specific patch.

The generated artifact contains the existing host integration patches for orientation, resize, location, map and Canvas behavior, plus the iOS native WebView component contract. When an equivalent implementation lands upstream, remove the corresponding company patch instead of maintaining two implementations.

### Build

From the repository `fe` directory:

```bash
corepack pnpm install --no-frozen-lockfile
corepack pnpm --filter container... build --mode production
node scripts/generate-sdk.js
```

The generator increments `shared/jssdk/config.json`; the pre-build value was `1.0.25 / 26`, producing `1.0.26 / 27`.

### Verification

- WebView component contract and adjacent component tests: 12 passed.
- Production workspace build: passed.
- iOS Simulator generic build: passed.
- Artifact inspection confirmed `native/webview`, `parentWebViewId`, and viewport layout metadata are present.
