# AGENTS.md — phpvm-runtimes maintainer checklist

## Before publishing a catalog

- [ ] phpvm supports manifest v2.1 or v3.0 `artifacts` (per-platform download URLs)
- [ ] All **8** tarballs built and smoke-tested (`bin/php -v`, `bin/composer -V`, `php -m`)
- [ ] `builds/common/extensions.json` "catalog" lists all common extensions (so they appear in the manifest "dev" profile and pass profile validation in verify-manifest)
- [ ] Extension lists in `manifest.json` match every platform build (and the catalog)
- [ ] `scripts/verify-manifest.sh --strict` passes
- [ ] `scripts/verify-manifest-assets.sh dist` passes (tarball checksums match manifest)
- [ ] `catalog_tag` and `published_at` set in `manifest.json`

## Build one runtime (local)

Linux x86_64 runtimes are built locally (this machine):

```bash
scripts/build-runtime-local.sh 8.3.31
```

Apple Silicon runtimes are built via GitHub Actions (see table below). Use the reusable workflows so both platforms produce static SPC binaries.

## Prepare catalog from built assets

```bash
scripts/prepare-catalog.sh --catalog-tag catalog-2026-06-15
```

For patch-only rotation, place the new tarballs in `dist/` and reuse unchanged tarballs from the previous catalog asset set:

```bash
scripts/prepare-catalog.sh \
  --catalog-tag catalog-2026-06-15 \
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
| `validate.yml` | PR/push: script syntax, manifest schema, recipe drift |
| `build-runtime.yml` | Manual: build one PHP version × one target (static via SPC) |
| `build-catalog.yml` | Manual: build all 8 catalog tarballs (static via SPC for both platforms) |
| `publish-catalog.yml` | Manual: attach artifacts + `manifest.json` to a catalog release |

**Build split:** Linux x86_64 tarballs are built locally on this machine. Apple Silicon tarballs are produced by the GitHub Actions `build-*` workflows (the reusable job now uses the static `spc-macos-aarch64` path for `aarch64-apple-darwin`). Legacy dynamic build scripts and `build-apple-dynamic.yml` have been removed.

## Catalog rotation

When PHP `8.3.32` replaces `8.3.31`:

1. Add/update `builds/8.3.32/`, remove old recipe dir when done.
2. Build the Linux tarball locally with `scripts/build-runtime-local.sh`; trigger a GitHub Actions run (via `build-catalog.yml` or `build-runtime.yml`) to obtain the matching Apple Silicon tarball. (Reuse the previous Apple tarball if only Linux changed.)
3. Replace the `8.3.31` row in `manifest.json` (one row per minor line).
4. Publish new `catalog-YYYY-MM-DD` release; prune old assets when convenient.

## Do not

- Commit `.tar.gz` binaries to git
- Mix phpvm CLI assets into phpvm-runtimes releases
- Publish per-profile tarballs (one full binary per PHP version)
