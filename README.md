# Tailscale — Android CLI (HugoCirca fork)

https://tailscale.com

Private WireGuard® networks made easy — **Android `tailscaled`/`tailscale` CLI for Termux/shell with `--ssh`**

> **Fork notice:** This is a modified fork of https://github.com/tailscale/tailscale, maintained by [HugoCirca](https://github.com/HugoCirca/tailscale) for Android CLI use. Not affiliated with or endorsed by Tailscale Inc. Original code is Copyright (c) 2020 Tailscale Inc & contributors, licensed under [BSD 3-Clause](LICENSE). This fork retains the original license and adds Android-specific build changes.

## Android Quick Start (Termux)

One-liner installer (downloads `tailscale`/`tailscaled` for your arch and starts `tailscaled` with userspace networking):

```bash
# shortest (same script):
curl -fsSL tinyurl.com/28cmqfk4 | bash
# full URL:
curl -fsSL https://raw.githubusercontent.com/HugoCirca/tailscale/1.102.3-android-dev/termux.sh | bash
# with authkey:
bash termux.sh --authkey tskey-auth-... --ssh --hostname my-phone
# interactive device login (no authkey):
bash termux.sh
# -> To authenticate, visit: https://login.tailscale.com/a/...
```

Hostname defaults to your phone model (`ro.product.model`, e.g. `vivo-v2204`) — `--hostname` overrides it.

After install:
```bash
tailscale --socket=/data/data/com.termux/files/usr/var/run/tailscale/tailscaled.sock status
tailscale --socket=$PREFIX/var/run/tailscale/tailscaled.sock ip -4
cat $PREFIX/tmp/tailscaled.log
```

Restart Termux once after install — the runit service (`tailscaled`) only `sv-enable`s on next shell start (`runsvdir` must be running), then `sv status tailscaled`. Flags: `--no-sv` skips service setup, `--sv-now` tries enabling immediately.

`termux.sh` details: installs to `$PREFIX/bin`, state in `$PREFIX/var/lib/tailscale`, socket in `$PREFIX/var/run/tailscale/tailscaled.sock`, uses `tailscale up --ssh` by default, supports `--authkey`, `--no-ssh`, `--hostname`, `--no-sv`, `--sv-now`.

Releases: https://github.com/HugoCirca/tailscale/releases — tags are plain `v1.102.3` to match upstream `tailscale/tailscale` (legacy `v1.102.3-android` still supported). Assets are `tailscale_1.102.3_arm64.tgz` / `tailscale_1.102.3_arm.tgz` (`VERSION_SHORT`).

## Building for Android

Requires Go 1.26 and Android NDK r27c (handled by workflow). Local:

```bash
# check
./scripts/android.sh check arm64
# build
./scripts/android.sh build --upx arm64
./scripts/android.sh build --upx arm
# outputs: dist/tailscaled.arm64, dist/tailscaled.arm
# versioning
./build_dist.sh shellvars  # -> VERSION_SHORT, VERSION_LONG
tar -czf dist/tailscale_${VERSION_SHORT}_arm64.tgz -C dist --transform='s/tailscaled.arm64/tailscaled/' tailscaled.arm64
```

Workflow `.github/workflows/build_android.yml` builds on tag `v*` (and legacy `v*-android`), uploads `tailscale_${VERSION_SHORT}_*.tgz` and creates GitHub Release.

## Overview (upstream)

This repository contains the majority of Tailscale's open source code.
Notably, it includes the `tailscaled` daemon and
the `tailscale` CLI tool. The `tailscaled` daemon runs on Linux, Windows,
[macOS](https://tailscale.com/kb/1065/macos-variants/), and to varying degrees
on FreeBSD and OpenBSD. The Tailscale iOS and Android apps use this repo's
code, but this repo doesn't contain the mobile GUI code.

Other [Tailscale repos](https://github.com/orgs/tailscale/repositories) of note:

* the Android app is at https://github.com/tailscale/tailscale-android
* the Synology package is at https://github.com/tailscale/tailscale-synology
* the QNAP package is at https://github.com/tailscale/tailscale-qpkg
* the Chocolatey packaging is at https://github.com/tailscale/tailscale-chocolatey

For background on which parts of Tailscale are open source and why,
see [https://tailscale.com/opensource/](https://tailscale.com/opensource/).

## Using

We serve packages for a variety of distros and platforms at
[https://pkgs.tailscale.com](https://pkgs.tailscale.com/).

## Other clients

The [macOS, iOS, and Windows clients](https://tailscale.com/download)
use the code in this repository but additionally include small GUI
wrappers. The GUI wrappers on non-open source platforms are themselves
not open source.

## Building (generic)

We always require the latest Go release, currently Go 1.26. (While we build
releases with our [Go fork](https://github.com/tailscale/go/), its use is not
required.)

```
go install tailscale.com/cmd/tailscale{,d}
```

If you're packaging Tailscale for distribution, use `build_dist.sh`
instead, to burn commit IDs and version info into the binaries:

```
./build_dist.sh tailscale.com/cmd/tailscale
./build_dist.sh tailscale.com/cmd/tailscaled
```

If your distro has conventions that preclude the use of
`build_dist.sh`, please do the equivalent of what it does in your
distro's way, so that bug reports contain useful version information.

## Bugs

Please file any issues about this fork on [HugoCirca/tailscale issues](https://github.com/HugoCirca/tailscale/issues). Upstream issues at [tailscale/tailscale issues](https://github.com/tailscale/tailscale/issues).

## Contributing

PRs welcome! But please file bugs. Commit messages should [reference
bugs](https://docs.github.com/en/github/writing-on-github/autolinked-references-and-urls).

We require [Developer Certificate of
Origin](https://en.wikipedia.org/wiki/Developer_Certificate_of_Origin)
`Signed-off-by` lines in commits.

See [commit-messages.md](docs/commit-messages.md) (or skim `git log`) for our commit message style.

## About Us

[Tailscale](https://tailscale.com/) is primarily developed by the
people at https://github.com/orgs/tailscale/people. For other contributors,
see:

* https://github.com/tailscale/tailscale/graphs/contributors
* https://github.com/tailscale/tailscale-android/graphs/contributors

Fork maintained by [Synac](https://github.com/SynacNipo) / HugoCirca.

## Legal

WireGuard is a registered trademark of Jason A. Donenfeld.

Original code Copyright (c) 2020 Tailscale Inc & contributors, BSD 3-Clause - see [LICENSE](LICENSE).
