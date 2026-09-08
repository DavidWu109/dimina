# Bundled JSSDK provenance

## Official Furina 1.0.39

- Version: `1.0.39 / versionCode 40`.
- Source: 胡腾, 千岛小程序技术委员会, 2026-09-07 17:47.
- [Release message](https://applink.feishu.cn/client/chat/open?openChatId=oc_ef6342abd9e2bce977c92080c40e226c&position=7845).
- Published outer archive SHA-256: `6771d425825775c5a13d55b81831b56045a525991250bee401b17a46568fd585`.
- Bundled main.zip SHA-256: `1d82b6b41287f3c9433a97c92648740a7cc40a1b7280c4cea2902101ba2733f3`.

The bundled main.zip and config.json are copied byte-for-byte from the published
archive. No local JavaScript overlay is included. An exact source commit for this
published release is unavailable; do not rebuild it from the older local fe/ tree.

## Scope of the current feature

By product request, the additional WebView JavaScript source changes, artifact
patcher and their JavaScript tests are excluded. Native WebView support, fixed
content-area layout, forced native navigation and screenshot protection remain.
The native message/layout XCTest checks remain in Tests/DiminaTests.

The official JS release does not include our parentWebViewId, id-change remount
and errMsg forwarding additions. Native code accepts the official bridgeId field,
but cannot supply JS lifecycle or event changes that the release does not emit.
Those JS fixes have been shared with the mobile miniapp group for later coordination.

1.0.40 was inspected separately and has not been adopted by this feature.
SDK cache entries at versionCode 40 are not automatically replaced by another code-40
artifact; existing local installations need the standard SDK cache reset for testing.
