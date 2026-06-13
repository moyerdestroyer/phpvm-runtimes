# AGENTS.md — phpvm-runtimes maintainer checklist

## Before publishing a catalog

- [ ] phpvm supports manifest v2.1 `artifacts` (per-platform download URLs)
- [ ] All **8** tarballs built and smoke-tested (`bin/php -v`, `bin/composer -V`, `php -m`)
- [ ] Extension lists in `manifest.json` match every platform build
- [ ] `scripts/verify-manifest.sh --strict` passes
- [ ] `catalog_tag` and `published_at` set in `manifest.json`

## Build one runtime (local)

```bash
scripts/build-runtime-local.sh 8.3.31
```

## Prepare catalog from built assets

```bash
scripts/prepare-catalog.sh --catalog-tag catalog-2026-06-13
```

For patch-only rotation, place the new tarballs in `dist/` and reuse unchanged tarballs from the previous catalog asset set:

```bash
scripts/prepare-catalog.sh \
  --catalog-tag catalog-2026-06-13 \
  --reuse-dir previous-catalog-assets/
```

## Verify manifest

```bash
# Schema only (allows unpublished placeholders)
scripts/verify-manifest.sh

# Pre-release gate (rejects PLACEHOLDER urls and zero checksums)
scripts/verify-manifest.sh --strict
```

## GitHub Actions

| Workflow | Purpose |
|---|---|
| `build-runtime.yml` | Manual: build one PHP version × one target |
| `build-catalog.yml` | Manual: build all 8 catalog tarballs |
| `publish-catalog.yml` | Manual: attach artifacts + `manifest.json` to a catalog release |

## Catalog rotation

When PHP `8.3.32` replaces `8.3.31`:

1. Add/update `builds/8.3.32/`, remove old recipe dir when done.
2. Build two new tarballs.
3. Replace the `8.3.31` row in `manifest.json` (one row per minor line).
4. Publish new `catalog-YYYY-MM-DD` release; prune old assets when convenient.

## Do not

- Commit `.tar.gz` binaries to git
- Mix phpvm CLI assets into phpvm-runtimes releases
- Publish per-profile tarballs (one full binary per PHP version)
