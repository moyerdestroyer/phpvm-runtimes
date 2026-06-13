# phpvm-runtimes

Prebuilt PHP + Composer runtimes and the [manifest v2.1](docs/phpvm-runtimes.md) catalog for [phpvm](https://github.com/moyerdestroyer/phpvm).

| Repo | Ships |
|---|---|
| [phpvm](https://github.com/moyerdestroyer/phpvm) | CLI binary, `install.sh` |
| **phpvm-runtimes** (this repo) | PHP tarballs + `manifest.json` |

## Catalog policy

- **4** PHP minor lines (currently 8.1–8.4), latest patch each
- **3** platforms per version: Linux x86_64, macOS Intel, macOS Apple Silicon
- **12** release tarballs per catalog publish

See [docs/phpvm-runtimes.md](docs/phpvm-runtimes.md) for the full publisher guide.

## Platform requirements

| Target | Host requirement |
|---|---|
| `x86_64-unknown-linux-gnu` | glibc 2.35+ (Ubuntu 22.04 class) |
| `x86_64-apple-darwin` | macOS 12+ |
| `aarch64-apple-darwin` | macOS 12+ |

Linux ARM64 and Windows are not in the v1 catalog.

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

1. Dispatch **Build runtime** for each version × platform (or build all 12 locally).
2. Run `scripts/update-manifest.py` with the built tarballs and catalog tag.
3. Run `scripts/verify-manifest.sh --strict`.
4. Dispatch **Publish catalog** (or create the release manually).
5. Commit updated `manifest.json` to `master`.

Details: [AGENTS.md](AGENTS.md).