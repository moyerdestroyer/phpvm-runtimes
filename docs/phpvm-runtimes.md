# phpvm-runtimes — Publisher Guide

This document defines the **phpvm-runtimes** companion repository: how to lay out builds, name release assets, and publish `manifest.json` so the [phpvm](https://github.com/moyerdestroyer/phpvm) CLI can install PHP on **Linux x86_64** and **macOS Apple Silicon**.

Runtimes are static PHP+Composer binaries (manifest v2.1 `artifacts`). The `dev` profile in the manifest is derived from `builds/common/extensions.json` so that phpvm's default experience is rich. The `debug` profile enables every catalog extension.

The **phpvm** repo ships the CLI. **phpvm-runtimes** ships PHP+Composer trees and the manifest. Do not mix the two in one GitHub Release.

---

## Catalog policy

| Rule | Value |
|---|---|
| PHP minor lines published | **4** (e.g. 8.1, 8.2, 8.3, 8.4 — adjust over time) |
| Patches per minor | **Latest only** (one exact version per line, e.g. `8.3.31`) |
| Platforms per version | **2** target triples (see below) |
| Total remote tarballs | **8** (4 versions × 2 platforms) |
| Older patches | **Not hosted**; remain usable only if already installed under `~/.phpvm/runtimes/<version>/` |

When PHP `8.3.32` replaces `8.3.31`, update the manifest entry and replace the two `8.3.32` assets. Delete or expire `8.3.31` assets to save space.

When php.net publishes a new supported minor line, the catalog keeps a fixed size: add the new minor line and remove the oldest published minor line.

Users install with specifiers like `8.3`, `8.3.latest`, or the exact patch `8.3.31`. Exact patches not in the manifest fail fresh install by design.

---

## Supported target triples

Must match phpvm's installer and runtime resolution (same strings as `install.sh` / Rust targets):

| Target | OS / CPU | Runtime model |
|---|---|---|
| `x86_64-unknown-linux-gnu` | Linux x86_64 | Static (musl) — no glibc dependency |
| `aarch64-apple-darwin` | macOS Apple Silicon | Static — macOS 12+ |

**Not in v1 catalog:** macOS Intel (`x86_64-apple-darwin`), Linux ARM64 (`aarch64-unknown-linux-gnu`), Windows.

---

## Repository layout

```text
phpvm-runtimes/
├── README.md
├── manifest.json                 # Source of truth (also attached to releases)
├── AGENTS.md                     # Build/publish checklist
│
├── builds/                       # Build recipes (not the binaries themselves)
│   ├── common/
│   │   ├── extensions.json       # Single source: catalog + profiles + spc set
│   │   ├── composer-version.txt  # e.g. 2.9.2
│   │   └── spc-pin.json          # pinned spc binary checksums
│   ├── 8.3.31/
│   │   ├── craft.yml             # Generated StaticPHP recipe
│   │   └── notes.md              # Release notes and known quirks
│   └── …
│
├── scripts/
│   ├── build-runtime-local.sh    # Build/package one host runtime end-to-end
│   ├── plan-catalog-update.py    # Plan latest supported PHP catalog from php.net
│   ├── apply-catalog-plan.py     # Apply planned runtime rows to manifest.json
│   ├── sync-runtime-recipes.sh   # Sync builds/<version>/ dirs from a plan
│   ├── prepare-catalog.sh        # Update manifest from a complete asset set
│   ├── package-runtime.sh        # Validate tree → tar.gz + sha256
│   ├── update-manifest.py        # Inject urls/checksums, derive profiles from extensions.json
│   ├── verify-manifest.sh        # Schema + HTTPS + 64-char sha256
│   ├── verify-extensions.sh      # Smoke-test static build (php -m catalog match)
│   └── verify-manifest-assets.sh # Tarball bytes vs manifest sha256
│
└── .github/
    └── workflows/
        ├── validate.yml            # PR/push: script + manifest checks
        ├── auto-catalog-rotation.yml # Weekly/manual: build PR + draft release
        ├── check-php-updates.yml   # Weekly: detect planned catalog changes
        ├── build-runtime.yml       # Manual: 1 version x 1 target
        ├── build-catalog.yml       # Manual: planned catalog tarballs
        └── publish-catalog.yml     # Validate manifest, create draft release
```

**Do not commit** multi-hundred-MB tarballs to git. Binaries live only on **GitHub Releases**.

---

## Runtime tarball layout

Each archive is a **gzip tarball** with a **single top-level directory** (stripped on extract by phpvm). Static archives contain:

```text
php-8.3.31-x86_64-unknown-linux-gnu/    # top-level dir
└── bin/
    ├── php                             # static executable (all catalog extensions compiled in)
    ├── composer                        # executable wrapper
    └── composer.phar                   # Composer PHAR used by the wrapper
```

No `ext/`, `lib/`, or runtime `etc/` tree is required in the tarball for static builds — all extensions are compiled into the single `php` binary.

### Packaging rules

- Format: `.tar.gz`
- Root contains `bin/php`, `bin/composer`, `bin/composer.phar`
- No symlinks pointing outside the archive (phpvm rejects unsafe tar entries)
- Run `package-runtime.sh` to produce **sidecar checksum**:

```text
php-8.3.31-x86_64-unknown-linux-gnu.tar.gz
php-8.3.31-x86_64-unknown-linux-gnu.tar.gz.sha256   # optional for humans; manifest carries sha256
```

Checksum in manifest: **lowercase hex, 64 characters**, of the `.tar.gz` file bytes.

---

## Release asset naming

**Required pattern** (phpvm resolves downloads from manifest URLs; names must be stable and predictable):

```text
php-{PHP_VERSION}-{TARGET}.tar.gz
```

Examples:

```text
php-8.3.31-x86_64-unknown-linux-gnu.tar.gz
php-8.3.31-aarch64-apple-darwin.tar.gz
```

### GitHub Releases strategy (recommended)

Use a **catalog release** per publish (not one release per PHP patch forever):

| Approach | Tag example | Assets |
|---|---|---|
| **Rolling catalog** (simplest) | `catalog` or `catalog-2026-06-16` | All current tarballs + `manifest.json` |
| Per PHP version | `php-8.3.31` | 2 tarballs for that version only |

**Recommended for v1:** tag `catalog-YYYY-MM-DD`, attach **all current tarballs + `manifest.json`**, set manifest URLs to:

```text
https://github.com/<org>/phpvm-runtimes/releases/download/catalog-2026-06-16/php-8.3.31-x86_64-unknown-linux-gnu.tar.gz
```

Manifest is also served from the repo for review/diff:

```text
https://raw.githubusercontent.com/<org>/phpvm-runtimes/master/manifest.json
```

Point phpvm at it via global/project config until `DEFAULT_MANIFEST_URL` is updated:

```toml
manifest_url = "https://raw.githubusercontent.com/<org>/phpvm-runtimes/master/manifest.json"
```

---

## Manifest schema (v2.1 — per-platform artifacts)

Manifest v2.1 uses an **`artifacts`** map keyed by target triple for multi-platform catalogs. Runtime `extensions` is a simple array of names matching the `catalog` list from `builds/common/extensions.json`.

### Top-level shape

```json
{
  "schema": "2.1",
  "published_at": "2026-06-16T00:00:00Z",
  "catalog_tag": "catalog-2026-06-16",
  "default_profile": "dev",
  "profiles": [ … ],
  "runtimes": [ … ]
}
```

- **`profiles`** — three profiles, all derived from `extensions.json`:
  - `minimal` — bare essentials (`openssl`, `phar`, `mbstring`).
  - `dev` — common web development extensions (the default). MySQL, Redis, GD, bcmath, sodium, pcntl, and more.
  - `debug` — **every** catalog extension enabled (maximal).
- **`runtimes`** — **exactly four entries**, one per supported minor line (latest patch). `extensions` is an array of names matching the full `catalog` from `extensions.json`.

### Runtime entry (static)

```json
{
  "php": "8.3.31",
  "composer": "2.9.2",
  "extensions": [
    "bcmath", "bz2", "curl", "dom", "exif", "ffi", "fileinfo", "ftp",
    "gd", "gettext", "gmp", "iconv", "imagick", "intl", "ldap",
    "mbstring", "memcached", "mysqli", "opcache", "openssl", "pcntl",
    "pdo", "pdo_mysql", "pdo_pgsql", "pdo_sqlite", "pgsql", "phar",
    "posix", "redis", "session", "simplexml", "soap", "sockets",
    "sodium", "sqlite3", "tokenizer", "xml", "xmlreader", "xmlwriter",
    "xsl", "yaml", "zip", "zlib"
  ],
  "artifacts": {
    "x86_64-unknown-linux-gnu": { "url": "...", "sha256": "..." },
    "aarch64-apple-darwin": { "url": "...", "sha256": "..." }
  },
  "runtime_type": "static",
  "thread_safety": "nts",
  "default_profile": "dev"
}
```

| Field | Required | Notes |
|---|---|---|
| `php` | yes | Exact semver `MAJOR.MINOR.PATCH` |
| `composer` | yes | Bundled Composer version string |
| `extensions` | yes | Full catalog compiled into the static build (must match `builds/common/extensions.json` `catalog`) |
| `artifacts` | yes | Map of target triple → `{ url, sha256 }` |
| `runtime_type` | yes | Always `static` |
| `thread_safety` | yes | Always `nts` |
| `default_profile` | yes | Always `dev` |

Linux runtimes are fully static (musl) and carry **no glibc requirement**. There is no `linux_compatibility` field in the v2.1 static schema.

### phpvm consumer behavior (contract)

On `phpvm install <spec>`:

1. Resolve specifier against manifest `runtimes[].php` (e.g. `8.3.latest` → `8.3.31`).
2. Detect host target triple (same logic as `install.sh`).
3. Select `artifacts[target]`.
4. Download, verify `sha256`, extract, apply the requested profile or `default_profile` (`dev`).

If the host triple is missing from `artifacts`, fail with a clear error (e.g. Linux ARM not published).

---

## Build matrix (what to produce)

For each catalog publish, build **8 artifacts**:

| PHP | Linux x86_64 | macOS ARM |
|---|---|---|
| 8.1.x (latest) | ✓ | ✓ |
| 8.2.x (latest) | ✓ | ✓ |
| 8.3.x (latest) | ✓ | ✓ |
| 8.4.x (latest) | ✓ | ✓ |

Suggested tooling: [static-php-cli](https://github.com/crazywhalecc/static-php-cli) (SPC) via the `craft.yml` recipes. The `catalog` list in `extensions.json` must be comprehensive and match `php -m` on every platform build.

| Target | Where to build |
|---|---|
| `x86_64-unknown-linux-gnu` | Local (with setup-linux-build-deps.sh) or GitHub Actions ubuntu runner |
| `aarch64-apple-darwin` | GitHub Actions macOS runner (via the reusable workflow) |

---

## Publish checklist

1. **Prefer automation**: run or wait for `auto-catalog-rotation.yml`; it plans php.net patch/new-minor changes, builds both targets, opens the manifest/recipe PR, and creates a draft release.
2. **Build manually if needed** (Linux locally via `build-runtime-local.sh` + deps setup, or use `build-catalog.yml` / `build-runtime.yml` Actions for the matrix).
3. **Verify** each tarball: `bin/php -v`, `bin/composer -V`, `php -m` matches the catalog in `extensions.json` (via `verify-extensions.sh` inside packaging).
4. **Stage** a complete catalog asset set in `dist/`, reusing unchanged tarballs from the previous catalog when only one PHP line changed.
5. **Run** `scripts/prepare-catalog.sh --catalog-tag catalog-YYYY-MM-DD` (it re-renders craft files and lets `update-manifest.py` produce schema 2.1 + static metadata + profiles derived from extensions.json).
6. **Confirm** `scripts/verify-manifest.sh --strict` and `scripts/verify-manifest-assets.sh dist` pass.
7. **Commit** `manifest.json` and changed `builds/<version>/` recipe dirs to the default branch (`master`) on phpvm-runtimes.
8. **Create** GitHub Release `catalog-YYYY-MM-DD` with `publish-catalog.yml` (use the **same** `catalog_tag` as step 5) or upload manually; the workflow verifies tarball checksums match the committed manifest.
9. **Smoke test** on each OS:
   ```bash
   phpvm install 8.3
   phpvm run 8.3 php -v
   phpvm profile use debug
   phpvm doctor
   ```
10. **Prune** previous catalog release assets if you need GitHub storage headroom (optional; old local installs unaffected).

---

## Rotation example

**Before:** manifest lists `8.3.31` with two artifacts.

**After PHP 8.3.32 ships:**

1. Build two new `8.3.32` tarballs.
2. Replace the single `runtimes[]` row: `php` `8.3.31` → `8.3.32`, new urls/checksums.
3. Publish new catalog release; remove `8.3.31` assets when convenient.
4. Users with `~/.phpvm/runtimes/8.3.31/` keep working; `phpvm install 8.3.31` on a new machine fails unless they use a custom manifest mirror.

---

## Validation rules (enforced by phpvm)

These match phpvm's manifest parser:

- `url` must be `https://`
- `sha256` must be 64 hex characters (case-insensitive at verify time)
- Exactly **one** runtime row per `php` version string
- No conflicting URLs for the same `php` + target
- `extensions` must reflect the built binary (doctor/profile switching depends on catalog truth)

---

## Relationship to phpvm CLI releases

| Repo | Ships | Release trigger |
|---|---|---|
| `phpvm` | `phpvm` binary, `install.sh` | Tag `v0.1.0` |
| `phpvm-runtimes` | PHP runtimes + `manifest.json` | Tag `catalog-…` or manual release |

End-user flow:

```bash
# 1. Install CLI (once)
curl -fsSL https://raw.githubusercontent.com/.../phpvm/master/install.sh | bash

# 2. Point at catalog (until default URL is live)
phpvm install 8.3   # uses manifest_url + host target to pick artifact
```
