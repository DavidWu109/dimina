# Bundled JSSDK provenance

## Official Furina 1.0.40

- Version: `1.0.40 / versionCode 41`.
- Source: 胡腾, 千岛小程序技术委员会, 2026-09-08 14:36.
- [Release message](https://applink.feishu.cn/client/chat/open?openChatId=oc_ef6342abd9e2bce977c92080c40e226c&position=7872).
- Published outer archive SHA-256: `769b5ea4a8408de6053bc455d806ae48305c5ef2fb326e9fdc2ea9523cd8ffc5`.
- Bundled main.zip SHA-256: `b7b287e9433a57ee70a9c9c0c307c9d285741017b5c58a7401c73873be063b85`.

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

The official 1.0.40 release is adopted without JS modifications. versionCode 41
advances the previously integrated versionCode 40, allowing the normal SDK upgrade
flow to replace older cache entries.
