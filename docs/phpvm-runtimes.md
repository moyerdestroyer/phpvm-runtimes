# phpvm-runtimes — Publisher Guide

This document defines the **phpvm-runtimes** companion repository: how to lay out builds, name release assets, and publish `manifest.json` so the [phpvm](https://github.com/moyerdestroyer/phpvm) CLI can install PHP on **Linux x86_64** and **macOS Apple Silicon**.

Runtimes are static PHP+Composer binaries (manifest v2.1 `artifacts`). The `dev` profile in the manifest (and top-level profiles) must include common extensions so that phpvm's default experience is rich.

The **phpvm** repo ships the CLI. **phpvm-runtimes** ships PHP+Composer trees and the manifest. Do not mix the two in one GitHub Release.

---

## Catalog policy

| Rule | Value |
|---|---|
| PHP minor lines published | **4** (e.g. 8.1, 8.2, 8.3, 8.4 — adjust over time) |
| Patches per minor | **Latest only** (one exact version per line, e.g. `8.3.23`) |
| Platforms per version | **2** target triples (see below) |
| Total remote tarballs | **8** (4 versions × 2 platforms) |
| Older patches | **Not hosted**; remain usable only if already installed under `~/.phpvm/runtimes/<version>/` |

When PHP `8.3.24` replaces `8.3.23`, update the manifest entry and replace the two `8.3.24` assets. Delete or expire `8.3.23` assets to save space.

Users install with specifiers like `8.3`, `8.3.latest`, or the exact patch `8.3.23`. Exact patches not in the manifest fail fresh install by design.

---

## Supported target triples

Must match phpvm’s installer and runtime resolution (same strings as `install.sh` / Rust targets):

| Target | OS / CPU |
|---|---|
| `x86_64-unknown-linux-gnu` | Linux x86_64 (glibc; required glibc is recorded per artifact) |
| `aarch64-apple-darwin` | macOS Apple Silicon |

**Not in v1 catalog:** macOS Intel (`x86_64-apple-darwin`), Linux ARM64 (`aarch64-unknown-linux-gnu`), Windows.

---

## Repository layout

```text
phpvm-runtimes/
├── README.md
├── manifest.json                 # Source of truth (also attached to releases)
├── AGENTS.md                     # Optional: your build/publish checklist
│
├── builds/                       # Build recipes (not the binaries themselves)
│   ├── common/
│   │   ├── extensions.json       # Shared extension list for “full” builds
│   │   └── composer-version.txt  # e.g. 2.9.2
│   ├── 8.3.31/
│   │   ├── craft.yml             # Generated StaticPHP recipe
│   │   └── notes.md              # Release notes and known quirks
│   └── …
│
├── scripts/
│   ├── build-runtime-local.sh    # Build/package one host runtime end-to-end (static via SPC)
│   ├── prepare-catalog.sh        # Update manifest from a complete asset set
│   ├── package-runtime.sh        # Validate tree → tar.gz + sha256 (static)
│   ├── update-manifest.py        # Inject urls/checksums into manifest.json
│   ├── verify-manifest.sh        # Schema + HTTPS + 64-char sha256
│   ├── verify-extensions.sh      # Smoke-test static build (php -m catalog match)
│   └── verify-manifest-assets.sh # Tarball bytes vs manifest sha256
│
└── .github/
    └── workflows/
        ├── validate.yml            # PR/push: script + manifest checks
        ├── build-runtime.yml       # Manual: 1 version x 1 target
        ├── build-catalog.yml       # Manual: all 8 catalog tarballs
        └── publish-catalog.yml     # Validate manifest, create draft release
```

**Do not commit** multi-hundred-MB tarballs to git. Binaries live only on **GitHub Releases** (or object storage later).

---

## Runtime tarball layout

Each archive is a **gzip tarball** with a **single top-level directory** (stripped on extract by phpvm). Static archives contain:

```text
php-8.3.23-x86_64-unknown-linux-gnu/    # top-level dir (any single segment name is fine)
└── bin/
    ├── php                             # static executable (common extensions compiled in)
    ├── composer                        # executable wrapper
    └── composer.phar                   # Composer PHAR used by the wrapper
```

The manifest profiles document the expected `dev` set (see "ensure common extensions wind up in the dev profile"). No `ext/`, `lib/`, or runtime `etc/` tree is required in the tarball for static.

### Packaging rules

- Format: `.tar.gz`
- Root contains `bin/php`, `bin/composer`, `bin/composer.phar`
- No symlinks pointing outside the archive (phpvm rejects unsafe tar entries)
- Run `package-runtime.sh` to produce **sidecar checksum**:

```text
php-8.3.23-x86_64-unknown-linux-gnu.tar.gz
php-8.3.23-x86_64-unknown-linux-gnu.tar.gz.sha256   # optional for humans; manifest carries sha256
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
php-8.3.23-x86_64-unknown-linux-gnu.tar.gz
php-8.3.23-aarch64-apple-darwin.tar.gz
```

### GitHub Releases strategy (recommended)

Use a **catalog release** per publish (not one release per PHP patch forever):

| Approach | Tag example | Assets |
|---|---|---|
| **Rolling catalog** (simplest) | `catalog` or `catalog-2025-06-12` | All 8 tarballs + `manifest.json` |
| Per PHP version | `php-8.3.23` | 2 tarballs for that version only |

**Recommended for v1:** tag `catalog-YYYY-MM-DD`, attach **all current tarballs + `manifest.json`**, set manifest URLs to:

```text
https://github.com/<org>/phpvm-runtimes/releases/download/catalog-2025-06-12/php-8.3.23-x86_64-unknown-linux-gnu.tar.gz
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

Manifest v2.1 uses an **`artifacts`** map keyed by target triple for multi-platform catalogs. Static catalogs use simple string arrays for `extensions` (matching the `catalog` list from `builds/common/extensions.json`, which must include all common extensions referenced by the `dev` profile).

### Top-level shape

```json
{
  "schema": "2.1",
  "published_at": "2025-06-12T00:00:00Z",
  "catalog_tag": "catalog-2025-06-12",
  "default_profile": "dev",
  "profiles": [ … ],
  "runtimes": [ … ]
}
```

- **`profiles`** — starter templates (`minimal`, `dev`, `debug`). The `dev` profile must list common extensions.
- **`runtimes`** — **exactly four entries**, one per supported minor line (latest patch). `extensions` is a simple array of names (or minimal objects for zend exts like xdebug to satisfy profile validation).

### Runtime entry (static)

```json
{
  "php": "8.3.23",
  "composer": "2.9.2",
  "extensions": [
    "curl", "dom", "fileinfo", "gd", "intl", "mbstring", "mysqli", "openssl",
    "pdo", "pdo_mysql", "pdo_sqlite", "phar", "session", "simplexml", "sockets",
    "sqlite3", "tokenizer", "xml", "xmlreader", "xmlwriter", "zip", "zlib",
    { "name": "xdebug", "type": "zend_extension", "bundled": true, "default": false }
  ],
  "artifacts": {
    "x86_64-unknown-linux-gnu": { "url": "...", "sha256": "..." },
    "aarch64-apple-darwin": { "url": "...", "sha256": "..." }
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `php` | yes | Exact semver `MAJOR.MINOR.PATCH` |
| `composer` | yes | Bundled Composer version string |
| `extensions` | yes | Full catalog compiled into the static build (must match `builds/common/extensions.json` "catalog"; profiles reference these) |
| `artifacts` | yes | Map of target triple → `{ url, sha256 }` |

## Legacy dynamic notes (v3.0)

(The project has returned to static v2.1 binaries and simple manifest entries. Dynamic v3.0 support and examples were for an earlier experiment with loadable extensions and are no longer used for the catalog. `update-manifest.py` will emit schema 2.1 + `runtime_type: "static"` for static builds.)

Previous dynamic experiments used per-extension objects and `runtime_type: "dynamic"`. Do not use for new catalogs.
          "type": "extension",
          "bundled": true,
          "default": true,
          "file": "ext/curl.so"
        },
        {
          "name": "opcache",
          "type": "zend_extension",
          "bundled": true,
          "default": false,
          "file": "ext/opcache.so"
        }
      ],
      "artifacts": {
        "x86_64-unknown-linux-gnu": { "url": "...", "sha256": "..." }
      }
    }
  ]
}
```

Rules:

- `runtime_type` must be `dynamic`.
- `default_profile` must be `dev`.
- `extensions[].type` is `extension` or `zend_extension`.
- `extensions[].file` is relative to the runtime root.
- Profile extension names must exist in `extensions[].name`.
- `minimal`, `dev`, and `debug` must exist in `profiles`; `debug` enables Xdebug as a Zend extension.
- Linux dynamic runtimes record the build glibc and the highest required `GLIBC_*` symbol so phpvm can warn on older hosts.
- Extension files are bundled but enabled only when a profile or `phpvm ext enable` writes a snippet. `default: true` means the extension is part of the default `dev` profile.

### phpvm consumer behavior (contract)

On `phpvm install <spec>`:

1. Resolve specifier against manifest `runtimes[].php` (e.g. `8.3.latest` → `8.3.23`).
2. Detect host target triple (same logic as `install.sh`).
3. Select `artifacts[target]`.
4. Download, verify `sha256`, extract, apply the requested profile or `default_profile` (`dev`).

If the host triple is missing from `artifacts`, fail with a clear error (e.g. Linux ARM not published).

> **Note:** phpvm `master` still reads legacy single `url`/`sha256`. Implement v2.1 `artifacts` support in phpvm before publishing this catalog (tracked in phpvm repo).

### Example full manifest (minimal)

```json
{
  "schema": "2.1",
  "published_at": "2025-06-12T00:00:00Z",
  "catalog_tag": "catalog-2025-06-12",
  "default_profile": "dev",
  "profiles": [
    {
      "name": "minimal",
      "extensions": ["openssl", "phar", "mbstring"]
    },
    {
      "name": "dev",
      "extensions": ["openssl", "phar", "mbstring", "curl", "dom", "fileinfo", "gd", "intl", "mysqli", "pdo", "pdo_mysql", "pdo_sqlite", "session", "simplexml", "sockets", "sqlite3", "tokenizer", "xml", "xmlreader", "xmlwriter", "zip", "zlib"]
    },
    {
      "name": "debug",
      "extensions": ["openssl", "phar", "mbstring", "curl", "dom", "fileinfo", "gd", "intl", "mysqli", "pdo", "pdo_mysql", "pdo_sqlite", "session", "simplexml", "sockets", "sqlite3", "tokenizer", "xml", "xmlreader", "xmlwriter", "zip", "zlib"],
      "zend_extensions": ["xdebug"]
    }
  ],
  "runtimes": [
    {
      "php": "8.1.33",
      "composer": "2.8.9",
      "extensions": ["curl", "mbstring", "openssl", "xml", "zip"],
      "artifacts": {
        "x86_64-unknown-linux-gnu": { "url": "…", "sha256": "…" },
        "aarch64-apple-darwin": { "url": "…", "sha256": "…" }
      }
    },
    {
      "php": "8.2.29",
      "composer": "2.9.2",
      "extensions": ["…"],
      "artifacts": { "…": { "url": "…", "sha256": "…" } }
    },
    {
      "php": "8.3.23",
      "composer": "2.9.2",
      "extensions": ["…"],
      "artifacts": { "…": { "url": "…", "sha256": "…" } }
    },
    {
      "php": "8.4.8",
      "composer": "2.9.2",
      "extensions": ["…"],
      "artifacts": { "…": { "url": "…", "sha256": "…" } }
    }
  ]
}
```

Extension lists should match what you actually compile into the static build for every platform build of that PHP version.

---

## Build matrix (what to produce)

For each catalog publish, build **8 artifacts**:

| PHP | Linux x86_64 | macOS ARM |
|---|---|---|
| 8.1.x (latest) | ✓ | ✓ |
| 8.2.x (latest) | ✓ | ✓ |
| 8.3.x (latest) | ✓ | ✓ |
| 8.4.x (latest) | ✓ | ✓ |

Suggested tooling: [static-php-cli](https://github.com/crazywhalecc/static-php-cli) (SPC) via the `craft.yml` recipes. The `catalog` list in `extensions.json` (used for both verification and the `dev` profile) must be comprehensive.

| Target | Where to build |
|---|---|
| `x86_64-unknown-linux-gnu` | Local (with setup-linux-build-deps.sh) or GitHub Actions ubuntu runner |
| `aarch64-apple-darwin` | GitHub Actions `macos-26` runner (via the reusable workflow) |

Document minimums in README. Static builds aim for broad glibc / macOS compatibility via SPC's vendored approach.

---

## Publish checklist

1. **Build** changed tarballs (Linux locally via `build-runtime-local.sh` + deps setup, or use `build-catalog.yml` / `build-runtime.yml` Actions for the matrix). All use the static SPC path now.
2. **Verify** each tarball: `bin/php -v`, `bin/composer -V`, `php -m` matches the catalog in `extensions.json` (via `verify-extensions.sh` inside packaging).
3. **Stage** a complete 8-tarball asset set in `dist/`, reusing unchanged tarballs from the previous catalog when only one PHP line changed.
4. **Run** `scripts/prepare-catalog.sh --catalog-tag catalog-YYYY-MM-DD` (it re-renders craft files and lets `update-manifest.py` produce schema 2.1 + static metadata + the rich profiles).
5. **Confirm** `scripts/verify-manifest.sh --strict` and `scripts/verify-manifest-assets.sh dist` pass. (Profiles will be checked against the now-comprehensive catalog.)
6. **Commit** `manifest.json` to the default branch (`master`) on phpvm-runtimes.
7. **Create** GitHub Release `catalog-YYYY-MM-DD` with `publish-catalog.yml` (use the **same** `catalog_tag` as step 4) or upload manually; the workflow verifies tarball checksums match the committed manifest.
8. **Smoke test** on each OS:
   ```bash
   phpvm install 8.3
   phpvm run 8.3 php -v
   phpvm profile use debug
   phpvm doctor
   ```
9. **Prune** previous catalog release assets if you need GitHub storage headroom (optional; old local installs unaffected).

---

## Rotation example

**Before:** manifest lists `8.3.23` with two artifacts.

**After PHP 8.3.24 ships:**

1. Build two new `8.3.24` tarballs.
2. Replace the single `runtimes[]` row: `php` `8.3.23` → `8.3.24`, new urls/checksums.
3. Publish new catalog release; remove `8.3.23` assets when convenient.
4. Users with `~/.phpvm/runtimes/8.3.23/` keep working; `phpvm install 8.3.23` on a new machine fails unless they use a custom manifest mirror.

---

## Validation rules (enforced by phpvm)

These match phpvm’s manifest parser today and planned v2.1 support:

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

---

## Next steps

1. Create empty `phpvm-runtimes` repo with this layout.
2. Implement manifest **v2.1 `artifacts`** parsing in phpvm (`src/manifest.rs` + `static_php` download path).
3. Build **one** version end-to-end (e.g. `8.3.23` × Linux only) as a smoke test, then fill the 8-artifact matrix.
4. Set `manifest_url` in docs/examples; later point `DEFAULT_MANIFEST_URL` at the raw GitHub URL or `phpvm.com`.

See also: [manifest-v2.md](./manifest-v2.md) (profile presets and installed runtime layout).
