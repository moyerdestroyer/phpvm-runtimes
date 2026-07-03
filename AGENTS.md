# AGENTS.md — phpvm-runtimes maintainer checklist

## Before publishing a catalog

- [ ] phpvm supports manifest v2.1 `artifacts` (per-platform download URLs)
- [ ] All catalog tarballs built and smoke-tested (`bin/php -v`, `bin/composer -V`, `php -m`) — currently **8** tarballs for 4 PHP lines × 2 targets
- [ ] `builds/common/extensions.json` is the single source of truth: `catalog` lists all extensions compiled into every binary; `dev_profile` and `minimal_profile` define the profile subsets; `debug` profile = full catalog; profiles must pass validation in verify-manifest
- [ ] Extension lists in `manifest.json` match every platform build (and the catalog) — `update-manifest.py` derives them from `extensions.json`
- [ ] `scripts/verify-manifest.sh --strict` passes
- [ ] `scripts/verify-manifest-assets.sh dist` passes (tarball checksums match manifest)
- [ ] Only extensions buildable statically by SPC for the project's musl static target are in the "catalog" (see SPC extension notes; xdebug is deliberately omitted as it only supports shared builds)
- [ ] `catalog_tag` and `published_at` set in `manifest.json`

## Build one runtime

Linux x86_64 runtimes can be built locally on this machine:

```bash
scripts/build-runtime-local.sh 8.3.31
```

Official catalog automation builds both Linux x86_64 and Apple Silicon runtimes via GitHub Actions using the reusable static SPC workflow. Linux runtimes are fully static (musl) and have no glibc dependency.

## Automatic catalog rotation

`auto-catalog-rotation.yml` runs every two days and can also be dispatched manually. It:

1. Plans the desired catalog from php.net release metadata.
2. Keeps a fixed catalog size by adding new PHP minor lines and dropping the oldest line.
3. Builds every planned runtime for both targets in GitHub Actions.
4. Updates `builds/<version>/` recipes and `manifest.json` in an automated PR.
5. Creates or updates a draft `catalog-YYYY-MM-DD` release with the built assets.

Publishing the draft release remains a manual review step.

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
| `auto-catalog-rotation.yml` | Every 2 days/manual: plan PHP updates, build assets, open PR, create draft release |
| `check-php-updates.yml` | Every 2 days: detect planned PHP catalog changes, open issue if found |
| `build-runtime.yml` | Manual: build one PHP version × one target (static via SPC) |
| `build-catalog.yml` | Manual: build the planned catalog tarballs (static via SPC for both platforms) |
| `publish-catalog.yml` | Manual: attach artifacts + `manifest.json` to a catalog release |

**Build split:** Local Linux builds remain supported, but scheduled catalog automation builds Linux x86_64 and Apple Silicon tarballs in GitHub Actions. The reusable job uses `spc-linux-x86_64` for Linux and `spc-macos-aarch64` for `aarch64-apple-darwin`.

## Catalog rotation

When PHP `8.3.32` replaces `8.3.31`, automation should handle the rotation. Manual fallback:

1. Add/update `builds/8.3.32/`, remove old recipe dir when done.
2. Build tarballs locally or with GitHub Actions (`build-catalog.yml` or `build-runtime.yml`).
3. Replace the `8.3.31` row in `manifest.json` (one row per minor line).
4. Publish new `catalog-YYYY-MM-DD` release; prune old assets when convenient.

## Do not

- Commit `.tar.gz` binaries to git
- Mix phpvm CLI assets into phpvm-runtimes releases
- Publish per-profile tarballs (one full binary per PHP version)
