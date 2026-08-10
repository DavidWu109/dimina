# JSSDK Build Source

This document records the provenance of the bundled JSSDK artifact.

## Release

- JSSDK version: `1.0.25`
- Version code: `26`
- Artifact: `shared/jssdk/main.zip`
- SHA-256: `92e9f4d3af21818da25810e1dcdde8bafbff24001226b70323d70b05996004bf`

## Source

- Upstream repository baseline: `da90d3d54c935ea5920c2e85e485200577623d27`
- Upstream Slider fix: `fix(fe,component): align slider behavior with native implementation (#297)`
- Company patch commit: `68e67065524045746b4b60d4cdde620604536cd1`

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

The generator increments `shared/jssdk/config.json`; the pre-build value was `1.0.24 / 25`, producing `1.0.25 / 26`.

## Verification

- PageMeta orientation tests: 3 passed.
- Window resize tests: 4 passed.
- Render runtime tests, including viewport resize coalescing: 24 passed.
- Production workspace build: passed.
- Artifact inspection confirmed the Slider root-currentTarget bridge and the orientation, resize, location, map and Canvas symbols are present.
