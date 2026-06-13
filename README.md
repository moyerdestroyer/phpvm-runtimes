# phpvm-runtimes

Prebuilt PHP + Composer runtimes and the [manifest v2.1](docs/phpvm-runtimes.md) catalog for [phpvm](https://github.com/moyerdestroyer/phpvm).

| Repo | Ships |
|---|---|
| [phpvm](https://github.com/moyerdestroyer/phpvm) | CLI binary, `install.sh` |
| **phpvm-runtimes** (this repo) | PHP tarballs + `manifest.json` |

## Catalog policy

- **4** PHP minor lines (currently 8.1–8.4), latest patch each
- **2** platforms per version: Linux x86_64, macOS Apple Silicon
- **8** release tarballs per catalog publish

See [docs/phpvm-runtimes.md](docs/phpvm-runtimes.md) for the full publisher guide.

## Platform requirements

| Target | Host requirement |
|---|---|
| `x86_64-unknown-linux-gnu` | glibc 2.35+ (Ubuntu 22.04 class) |
| `aarch64-apple-darwin` | macOS 12+ |

macOS Intel, Linux ARM64, and Windows are not in the v1 catalog.

## Consumer setup

Until phpvm ships a default catalog URL, point at this repo's manifest:

```toml
# ~/.phpvm/config.toml
manifest_url = "https://raw.githubusercontent.com/moyerdestroyer/phpvm-runtimes/master/manifest.json"
```

```bash
phpvm install 8.3
phpvm run 8.3 php -v
```

> **Note:** phpvm must support manifest **v2.1 `artifacts`** before this catalog is installable. Track progress in the [phpvm](https://github.com/moyerdestroyer/phpvm) repo.

## Repository layout

```text
manifest.json          # catalog source of truth
builds/                # StaticPHP craft recipes per PHP version
scripts/               # package, verify, manifest update helpers
.github/workflows/     # CI build + catalog publish
```

Binaries are **not** committed — they attach to GitHub Releases (`catalog-YYYY-MM-DD` tags).

## Publishing (maintainers)

Build one local host runtime:

```bash
scripts/build-runtime-local.sh 8.3.31
```

Prepare a full catalog from `dist/`:

```bash
scripts/prepare-catalog.sh --catalog-tag catalog-2026-06-13
```

For patch-only rotation, put the newly rebuilt tarballs in `dist/` and copy unchanged tarballs from a previous asset directory:

```bash
scripts/prepare-catalog.sh \
  --catalog-tag catalog-2026-06-13 \
  --reuse-dir previous-catalog-assets/
```

Then dispatch **Publish catalog** with the `build-catalog` run ID, or create the release manually, and commit updated `manifest.json` to `master`.

Details: [AGENTS.md](AGENTS.md).
