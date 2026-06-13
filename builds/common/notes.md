# Shared build notes

## Tooling

Runtimes are built with [StaticPHP](https://static-php.dev/) (`spc` v3). Each version directory contains a `craft.yml` recipe.

## Extension catalog

`extensions.json` lists:

- **`catalog`** — extensions published in `manifest.json` (must match `php -m` on every platform build).
- **`spc`** — superset passed to StaticPHP (includes dependencies such as `mysqlnd`, `pdo`, `zlib`).

## Local Linux build deps

StaticPHP doctor requires **flex**, **gperf**, and **musl-wrapper**. On Linux without sudo:

- `brew install flex gperf` (Linuxbrew) covers the parser tools
- `musl-wrapper` installs via `sudo make install` inside spc doctor — use **GitHub Actions** (`build-runtime.yml`) when local doctor cannot auto-fix

## Platform floors

| Target | Built on | Minimum host |
|---|---|---|
| `x86_64-unknown-linux-gnu` | `ubuntu-22.04` | glibc 2.35+ (Ubuntu 22.04 class) |
| `aarch64-apple-darwin` | `macos-latest` | macOS 12+ |

## Composer

Version pinned in `composer-version.txt`. Builds download the official PHAR and install a `bin/composer` wrapper next to `bin/php`.
