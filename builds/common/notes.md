# Shared build notes

## Tooling

Runtimes are built with [StaticPHP](https://static-php.dev/) (`spc` v3). Each version directory contains a `craft.yml` recipe.

## Extension catalog

`extensions.json` lists:

- **`catalog`** — all extensions compiled into the static binary and published in `manifest.json` (must match `php -m` on every platform build). This is the full set; the `debug` profile enables all of them.
- **`dev_profile`** — subset auto-enabled in the `dev` profile (the default). Curated for common web development: MySQL, Redis, GD, image handling, process control, sodium, etc.
- **`minimal_profile`** — bare essentials (`openssl`, `phar`, `mbstring`).
- **`spc`** — superset passed to StaticPHP (includes hidden dependencies such as `mysqlnd`, `ctype`, `filter`, `pdo`).

Extensions present in `catalog` but not in `dev_profile` (e.g. `bz2`, `ffi`, `gettext`, `gmp`, `iconv`, `imagick`, `ldap`, `memcached`, `opcache`, `pdo_pgsql`, `pgsql`, `soap`, `xsl`, `yaml`) are compiled in and always available via `php -m` but are not part of the default `dev` profile. Enable them with `phpvm ext enable <name>` or `-d extension=<name>`.

## Local Linux build deps

StaticPHP doctor requires **flex**, **gperf**, and **musl-wrapper**. On Linux without sudo:

- `brew install flex gperf` (Linuxbrew) covers the parser tools
- `musl-wrapper` installs via `sudo make install` inside spc doctor — use **GitHub Actions** (`build-runtime.yml`) when local doctor cannot auto-fix

## Platform floors

| Target | Built on | Notes |
|---|---|---|
| `x86_64-unknown-linux-gnu` | `ubuntu-22.04` | Static musl binary — no glibc dependency on the host |
| `aarch64-apple-darwin` | `macos-14` or later | macOS 12+ (set via `MACOSX_DEPLOYMENT_TARGET`) |

Linux runtimes are fully static (musl) and have **no glibc requirement**. macOS runtimes target macOS 12+.

## Composer

Version pinned in `composer-version.txt`. Builds download the official PHAR and install a `bin/composer` wrapper next to `bin/php`.
