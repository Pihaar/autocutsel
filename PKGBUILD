# Maintainer: Patrick Haar <Pihaar@users.noreply.github.com>
pkgname=autocutsel
pkgver=0.11.0
pkgrel=1
pkgdesc='Keep the X clipboard and the cutbuffer in sync (with -mouseonly support)'
arch=('x86_64')
url='https://github.com/Pihaar/autocutsel'
license=('GPL-2.0-or-later')
depends=('libx11' 'libxt' 'libxmu' 'libxaw' 'libxext' 'libinput' 'systemd-libs')
makedepends=('autoconf' 'automake' 'libtool' 'pkg-config')
source=("$pkgname-$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
  cd "$pkgname-$pkgver"
  ./bootstrap
  ./configure --prefix=/usr
  make
}

package() {
  cd "$pkgname-$pkgver"
  make DESTDIR="$pkgdir" install
}
