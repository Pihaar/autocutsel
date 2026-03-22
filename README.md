# autocutsel

X11/Wayland clipboard synchronization tool. Keeps the cutbuffer, CLIPBOARD, and PRIMARY selections in sync.

> This is an actively maintained fork of [sigmike/autocutsel](https://github.com/sigmike/autocutsel).

[![Build](https://github.com/Pihaar/autocutsel/actions/workflows/build.yml/badge.svg)](https://github.com/Pihaar/autocutsel/actions/workflows/build.yml)
[![OBS stable](https://img.shields.io/badge/Build%20status%20for-stable%20package:-blue)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel) [![](https://build.opensuse.org/projects/home:Pihaar:autocutsel/packages/autocutsel/badge.svg?type=default)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel)
[![OBS nightly](https://img.shields.io/badge/Build%20status%20for-nightly%20package:-blue)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel-nightly) [![](https://build.opensuse.org/projects/home:Pihaar:autocutsel/packages/autocutsel-nightly/badge.svg?type=default)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel-nightly)
[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

## Pre-built packages

RPM and DEB packages for many distributions are available via the [openSUSE Build Service](https://build.opensuse.org/project/show/home:Pihaar:autocutsel):

openSUSE, Fedora, Debian, Arch Linux, CentOS, SUSE SLFO.

## Features (beyond upstream)

- **`-mouseonly`** — sync PRIMARY to CLIPBOARD only on mouse selection (ignores keyboard selections)
- **Wayland auto-detection** — direct selection sync when cutbuffer is unavailable
- **`-encoding`** — charset conversion for VNC clients with legacy encodings
- **Systemd user service** — template unit with sandboxing and per-instance configuration
- **Single-instance lock** — prevents duplicate processes per selection
- **PRIMARY clear** — clears stale PRIMARY holders (e.g. xterm highlighting) after CLIPBOARD sync

## Building from source

### Dependencies

Fedora/RHEL/CentOS:

```sh
sudo dnf install gcc make autoconf automake libtool pkg-config \
  libX11-devel libXt-devel libXmu-devel libXaw-devel libXext-devel \
  libinput-devel systemd-devel
```

Ubuntu/Debian:

```sh
sudo apt-get install gcc make autoconf automake libtool pkg-config \
  libx11-dev libxt-dev libxmu-dev libxaw7-dev libxext-dev \
  libinput-dev libudev-dev
```

openSUSE:

```sh
sudo zypper install gcc make autoconf automake libtool pkg-config \
  libX11-devel libXt-devel libXmu-devel libXaw-devel libXext-devel \
  libinput-devel systemd-devel
```

### Build & install

```sh
./bootstrap
./configure
make
make check        # run tests
sudo make install
```

## Usage

Basic usage (sync CLIPBOARD with cutbuffer):

```sh
autocutsel
```

Mouse-only mode (sync PRIMARY to CLIPBOARD on mouse selection only):

```sh
autocutsel -selection PRIMARY -mouseonly
```

Requires membership in the `input` group for libinput access:

```sh
sudo usermod -aG input $USER   # re-login required
```

Other options:

```sh
autocutsel -selection PRIMARY     # sync PRIMARY instead of CLIPBOARD
autocutsel -buttonup              # only sync when mouse button is released
autocutsel -encoding WINDOWS-1252 # charset conversion for VNC
autocutsel -debug                 # verbose debug output
autocutsel -fork                  # daemonize
```

### Wayland

Wayland is detected automatically via `WAYLAND_DISPLAY`. The cutbuffer is not used; selections are synced directly. Recommended:

```sh
autocutsel -selection PRIMARY
```

## Systemd user service

autocutsel ships a template unit `autocutsel@.service` with example argument files.

```sh
# Create config directory and copy example
mkdir -p ~/.config/autocutsel
cp /usr/share/doc/autocutsel/examples/mouseonly.args ~/.config/autocutsel/

# Enable and start
systemctl --user daemon-reload
systemctl --user enable --now autocutsel@mouseonly

# View logs
journalctl --user -u 'autocutsel@*'
```

Available configurations in `examples/`:

| File | Description |
|------|-------------|
| `mouseonly.args` | Sync PRIMARY to CLIPBOARD on mouse selection only |
| `clipboard.args` | Sync CLIPBOARD with cutbuffer (traditional, pair with primary) |
| `primary.args` | Sync PRIMARY with cutbuffer (traditional, pair with clipboard) |

## Acknowledgments

autocutsel was originally created by [Michael Witrant](https://github.com/sigmike) (sigmike).
Original project: https://www.nongnu.org/autocutsel/

## License

GNU General Public License v2.0 or later — see [COPYING](COPYING).
