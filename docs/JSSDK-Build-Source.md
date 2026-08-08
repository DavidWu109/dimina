# JSSDK Build Source

This document records the provenance of the bundled JSSDK artifact.

## Release

- JSSDK version: `1.0.24`
- Version code: `25`
- Artifact: `shared/jssdk/main.zip`
- SHA-256: `b5454bd331f50793d979ee5b4461c1f61239e9075a46cccca03b802785496267`

## Source

- Upstream repository baseline: `da90d3d54c935ea5920c2e85e485200577623d27`
- Upstream Slider fix: `fix(fe,component): align slider behavior with native implementation (#297)`
- Company patch commit: `c74a32aeb882299f0a73a96322ab6393bff4603b`

The Slider implementation is taken directly from the upstream baseline. It is not maintained as a company-specific patch.

The company patch queue contains only capabilities that are still required by the host integration and are not fully available from this upstream baseline:

- page orientation override and render-to-service window resize events;
- fuzzy location and stable location listener registration;
- host map route planning methods;
- host-provided Canvas image URL resolution.

When an equivalent implementation lands upstream, remove the corresponding company patch instead of maintaining two implementations.

## Build

From the repository `fe` directory:

```bash
corepack pnpm install --no-frozen-lockfile
corepack pnpm --filter container... build --mode production
node scripts/generate-sdk.js
```

The generator increments `shared/jssdk/config.json`; the pre-build value was set to `1.0.23 / 24`, producing `1.0.24 / 25`.

## Verification

- Official Slider and PageMeta tests: 20 passed.
- Window resize tests: 3 passed.
- Render runtime tests, including host Canvas resolution: 23 passed.
- Production workspace build: passed.
- Artifact inspection confirmed the Slider root-currentTarget bridge and the orientation, resize, location, map and Canvas symbols are present.
