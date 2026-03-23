# autocutsel

X11/Wayland clipboard synchronization tool. Keeps the cutbuffer, CLIPBOARD, and PRIMARY selections in sync.

> This is an actively maintained fork of [sigmike/autocutsel](https://github.com/sigmike/autocutsel).

[![Build](https://github.com/Pihaar/autocutsel/actions/workflows/build.yml/badge.svg)](https://github.com/Pihaar/autocutsel/actions/workflows/build.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

[![OBS stable](https://img.shields.io/badge/Build%20status%20for-stable-blue)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel) [![build status](https://build.opensuse.org/projects/home:Pihaar:autocutsel/packages/autocutsel/badge.svg?type=default)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel) <br>
[![OBS nightly](https://img.shields.io/badge/Build%20status%20for-nightly-blue)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel-nightly) [![build status](https://build.opensuse.org/projects/home:Pihaar:autocutsel/packages/autocutsel-nightly/badge.svg?type=default)](https://build.opensuse.org/package/show/home:Pihaar:autocutsel/autocutsel-nightly)

## Installation

Pre-built packages are available via the [openSUSE Build Service](https://build.opensuse.org/project/show/home:Pihaar:autocutsel).

### openSUSE Tumbleweed

```sh
sudo zypper addrepo https://download.opensuse.org/repositories/home:Pihaar:autocutsel/openSUSE_Tumbleweed/home:Pihaar:autocutsel.repo
sudo zypper refresh
sudo zypper install autocutsel
```

### openSUSE Leap 15.6

```sh
sudo zypper addrepo https://download.opensuse.org/repositories/home:Pihaar:autocutsel/15.6/home:Pihaar:autocutsel.repo
sudo zypper refresh
sudo zypper install autocutsel
```

### Fedora 43

```sh
sudo dnf config-manager --add-repo https://download.opensuse.org/repositories/home:Pihaar:autocutsel/Fedora_43/home:Pihaar:autocutsel.repo
sudo dnf install autocutsel
```

### RHEL 9

RHEL is not available on OBS due to licensing. Use the binary-compatible RockyLinux 9 repository instead:

```sh
sudo dnf config-manager --add-repo https://download.opensuse.org/repositories/home:Pihaar:autocutsel/RockyLinux_9/home:Pihaar:autocutsel.repo
sudo dnf install autocutsel
```

### Debian 13

```sh
echo 'deb [signed-by=/etc/apt/keyrings/home_Pihaar_autocutsel.gpg] https://download.opensuse.org/repositories/home:/Pihaar:/autocutsel/Debian_13/ /' | sudo tee /etc/apt/sources.list.d/home_Pihaar_autocutsel.list
curl -fsSL https://download.opensuse.org/repositories/home:/Pihaar:/autocutsel/Debian_13/Release.key | gpg --dearmor | sudo tee /etc/apt/keyrings/home_Pihaar_autocutsel.gpg > /dev/null
sudo apt update
sudo apt install autocutsel
```

Packages for additional distributions (Arch, CentOS Stream, RockyLinux, SUSE SLFO, and more) are listed on the [OBS project page](https://build.opensuse.org/project/show/home:Pihaar:autocutsel).

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

### Classic setup

The traditional approach uses two instances to keep CLIPBOARD, PRIMARY, and the cutbuffer in sync:

```sh
autocutsel &                        # CLIPBOARD ↔ cutbuffer
autocutsel -selection PRIMARY &     # PRIMARY ↔ cutbuffer
```

Add `-fork` to daemonize, or use the [systemd service](#systemd-user-service) for automatic startup.

On Wayland (detected automatically via `WAYLAND_DISPLAY`), the cutbuffer is not available and selections are synced directly. A single instance is sufficient:

```sh
autocutsel -selection PRIMARY &
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-selection NAME` | X selection to operate on (`CLIPBOARD`, `PRIMARY`) | `CLIPBOARD` |
| `-cutbuffer N` | Cutbuffer number (0–7), not used on Wayland | `0` |
| `-pause MS` | Polling interval in milliseconds | `500` |
| `-buttonup` | Only sync when mouse button is released (helps with LibreOffice and similar) | off |
| `-fork` | Daemonize (run in background) | off |
| `-mouseonly` | Sync PRIMARY→CLIPBOARD on mouse selection only (requires `-selection PRIMARY`, libinput, `input` group) | off |
| `-encoding CHARSET` | Convert between UTF-8 and the given charset (e.g. `WINDOWS-1252` for VNC) | off |
| `-debug` | Print debug output | off |
| `-verbose` | Report version and sync events | off |

### Mouse-only mode

With `-mouseonly`, only mouse-based text selection is synced from PRIMARY to CLIPBOARD — keyboard selections (Shift+Arrow etc.) are ignored. This requires access to input devices via libinput:

```sh
sudo usermod -aG input $USER   # re-login required
autocutsel -selection PRIMARY -mouseonly
```

Only a single instance is needed (unlike the classic two-instance setup).

### cutsel utility

`cutsel` is a companion tool for inspecting and manipulating selections and cutbuffers:

```sh
cutsel cut                    # print cutbuffer content
cutsel cut "text"             # set cutbuffer content
cutsel sel                    # print CLIPBOARD content
cutsel sel -selection PRIMARY # print PRIMARY content
cutsel targets                # list selection targets offered by the owner
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
