# AGENTS.md — phpvm-runtimes maintainer checklist

## Before publishing a catalog

- [ ] phpvm supports manifest v2.1 `artifacts` (per-platform download URLs)
- [ ] All **12** tarballs built and smoke-tested (`bin/php -v`, `bin/composer -V`, `php -m`)
- [ ] Extension lists in `manifest.json` match every platform build
- [ ] `scripts/verify-manifest.sh --strict` passes
- [ ] `catalog_tag` and `published_at` set in `manifest.json`

## Build one runtime (local)

```bash
PHP_VERSION=8.3.31
TARGET=x86_64-unknown-linux-gnu   # or x86_64-apple-darwin / aarch64-apple-darwin

cd "builds/${PHP_VERSION}"
# download spc for host — see https://static-php.dev
../../scripts/build-static-php.sh   # or run spc craft manually
```

Stage `bin/php` + `bin/composer`, then:

```bash
scripts/package-runtime.sh dist/staging "${PHP_VERSION}" "${TARGET}"
```

## Update manifest from built assets

```bash
python3 scripts/update-manifest.py \
  --catalog-tag catalog-2026-06-13 \
  --assets-dir dist/ \
  --github-repo moyerdestroyer/phpvm-runtimes
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
| `publish-catalog.yml` | Manual: attach artifacts + `manifest.json` to a catalog release |

## Catalog rotation

When PHP `8.3.32` replaces `8.3.31`:

1. Add/update `builds/8.3.32/`, remove old recipe dir when done.
2. Build three new tarballs.
3. Replace the `8.3.31` row in `manifest.json` (one row per minor line).
4. Publish new `catalog-YYYY-MM-DD` release; prune old assets when convenient.

## Do not

- Commit `.tar.gz` binaries to git
- Mix phpvm CLI assets into phpvm-runtimes releases
- Publish per-profile tarballs (one full binary per PHP version)