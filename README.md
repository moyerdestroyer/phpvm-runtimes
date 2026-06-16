# phpvm-runtimes

Prebuilt **PHP + Composer** runtimes and the catalog consumed by [phpvm](https://github.com/moyerdestroyer/phpvm).

| Repository | What it ships |
|---|---|
| [phpvm](https://github.com/moyerdestroyer/phpvm) | CLI installer and runtime manager |
| **phpvm-runtimes** (this repo) | `manifest.json` + release tarballs |

phpvm installs and switches PHP versions on your machine. This repo builds those binaries, publishes them to GitHub Releases, and maintains the manifest phpvm reads to find the right download for your platform.

---

## Current catalog

| PHP line | Patch | Composer |
|---|---|---|
| 8.1 | 8.1.34 | 2.9.2 |
| 8.2 | 8.2.31 | 2.9.2 |
| 8.3 | 8.3.31 | 2.9.2 |
| 8.4 | 8.4.22 | 2.9.2 |

Each version is built for two target triples:

| Target | Platform | Minimum host |
|---|---|---|
| `x86_64-unknown-linux-gnu` | Linux x86_64 (glibc) | See `metadata/runtime.json` `linux_compatibility.required_glibc` |
| `aarch64-apple-darwin` | macOS Apple Silicon | macOS 12+ |

That is **8 tarballs** per catalog release (4 PHP versions × 2 platforms).

Runtimes are static binaries built with StaticPHP (SPC). Manifest v2.1 `artifacts` provide per-platform URLs. Profiles (`minimal`, `dev`, `debug`) are starter templates for phpvm (the full set of common extensions is compiled in for the `dev` profile). `dev` is the default profile.

**Not in v1:** macOS Intel, Linux ARM64, Windows.

---

## Using with phpvm

Install [phpvm](https://github.com/moyerdestroyer/phpvm), then point it at this catalog until a default URL ships upstream:

```toml
# ~/.phpvm/config.toml
manifest_url = "https://raw.githubusercontent.com/moyerdestroyer/phpvm-runtimes/master/manifest.json"
```

```bash
phpvm install 8.3          # latest 8.3.x patch from the manifest
phpvm run 8.3 php -v
phpvm run 8.3 composer -V
phpvm profile use debug
```

Install specifiers like `8.3`, `8.3.latest`, or an exact patch (e.g. `8.3.31`) resolve against `manifest.json`. Only the latest patch per minor line is hosted; older patches work only if already installed locally.

> **Requirement:** phpvm must support manifest **v2.1 `artifacts`** (per-platform download URLs). Track compatibility in the [phpvm](https://github.com/moyerdestroyer/phpvm) repo.

---

## What you get in a tarball

Each release asset is a gzip tarball with a single top-level directory. Static assets contain:

```text
php-8.3.31-x86_64-unknown-linux-gnu/
└── bin/
    ├── php              # static PHP CLI (common extensions compiled in)
    ├── composer         # wrapper script
    └── composer.phar    # Composer PHAR
```

phpvm uses the manifest profiles to know the `dev` (and other) starter sets, but the binary includes the full catalog.

Asset naming is fixed:

```text
php-{VERSION}-{TARGET}.tar.gz
```

Example: `php-8.3.31-x86_64-unknown-linux-gnu.tar.gz`

---

## How it is built

Runtimes are compiled with [StaticPHP](https://static-php.dev/) (`spc` v3) from craft recipes under `builds/`. Extension lists live in one place:

```text
builds/common/extensions.json   # catalog + spc extension sets (ensure common extensions are in "catalog" for the dev profile)
builds/common/composer-version.txt
builds/common/spc-pin.json      # pinned spc binary checksums
builds/8.3.31/craft.yml        # generated recipe per PHP version
```

`scripts/render-craft.sh` generates `craft.yml` from `extensions.json`. Do not hand-edit craft files — change `extensions.json` and re-render.

Use `scripts/build-runtime-local.sh` (or the CI reusable) for static builds. `scripts/package-runtime.sh` and `verify-extensions.sh` (`php -m` check) are used for static runtimes.

Binaries are **never committed to git**. They attach to GitHub Releases tagged `catalog-YYYY-MM-DD`.

---

## Repository layout

```text
phpvm-runtimes/
├── manifest.json              # catalog source of truth
├── builds/                    # StaticPHP recipes per PHP version
│   └── common/                # shared pins and extension lists
├── scripts/                   # build, verify, package, manifest helpers
├── docs/phpvm-runtimes.md     # full publisher guide (schema, rotation, policy)
├── AGENTS.md                  # maintainer checklist
└── .github/workflows/         # CI validate, build, publish
```

---

## Building locally

**Prerequisites:** `jq`, `curl`, build toolchain for StaticPHP (see [builds/common/notes.md](builds/common/notes.md)). On Linux, run `scripts/setup-linux-build-deps.sh` or use GitHub Actions when local `spc doctor` cannot install musl-wrapper.

Build and package one static runtime for the **current host only** (no cross-compilation):

```bash
scripts/build-runtime-local.sh 8.3.31
# → dist/php-8.3.31-<host-target>.tar.gz
```

Both Linux and macOS Apple Silicon catalog builds are produced via StaticPHP. Use the GitHub Actions `build-catalog.yml` (or `build-runtime.yml`) for the official matrix. Local Linux builds use `scripts/setup-linux-build-deps.sh` + the build script; macOS uses Homebrew build tools + the same.

---

## Publishing a catalog (maintainers)

Typical rotation flow:

1. **Build** changed tarballs — locally or via `build-catalog.yml` in Actions.
2. **Stage** all 8 tarballs in `dist/` (reuse unchanged ones from a previous release when only one PHP line changed).
3. **Prepare** the manifest:
   ```bash
   scripts/prepare-catalog.sh --catalog-tag catalog-2026-06-13
   ```
4. **Commit** the updated `manifest.json` to the default branch.
5. **Publish** — dispatch `publish-catalog.yml` with the **same** `catalog_tag` and the `build-catalog` run ID. The workflow verifies tarball checksums match the manifest before creating a draft release.
6. **Review** the draft on GitHub, then publish it.

Patch-only rotation with reused tarballs:

```bash
scripts/prepare-catalog.sh \
  --catalog-tag catalog-2026-06-13 \
  --reuse-dir previous-catalog-assets/
```

Verification commands:

```bash
scripts/verify-manifest.sh                    # schema (allows placeholders)
scripts/verify-manifest.sh --strict           # pre-release gate
scripts/verify-manifest-assets.sh dist        # tarball bytes vs manifest sha256
```

See [AGENTS.md](AGENTS.md) for the full checklist and [docs/phpvm-runtimes.md](docs/phpvm-runtimes.md) for manifest schema, rotation examples, and release policy.

---

## GitHub Actions

| Workflow | Trigger | Purpose |
|---|---|---|
| `validate.yml` | push / PR | Script syntax, manifest schema, recipe drift |
| `build-runtime.yml` | manual | Build one static runtime (any target) |
| `build-catalog.yml` | manual | Build all 8 catalog tarballs (static) |
| `publish-catalog.yml` | manual | Validate manifest + tarballs, create draft release |

---

## Documentation

| Doc | Audience |
|---|---|
| [docs/phpvm-runtimes.md](docs/phpvm-runtimes.md) | Manifest schema, release naming, rotation policy |
| [AGENTS.md](AGENTS.md) | Pre-publish checklist and quick commands |
| [builds/common/notes.md](builds/common/notes.md) | StaticPHP tooling, platform floors, local deps |

---

## Design constraints

- One runtime archive per PHP version and target — not per profile.
- Profiles (`minimal`/`dev`/`debug`) are documented in the manifest for phpvm; the static binary includes the common extensions for `dev`.
- One runtime row per **minor line** in the manifest (latest patch only).
- Do not mix phpvm CLI releases with phpvm-runtimes catalog releases.
- Do not commit `.tar.gz` binaries to this repository.
