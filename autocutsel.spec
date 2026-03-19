Name:           autocutsel
Version:        0.10.1
Release:        2%{?dist}
Summary:        Synchronize X selections and cutbuffer with mouse-only support
License:        GPL-2.0-or-later
URL:            https://github.com/Pihaar/autocutsel
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  autoconf
BuildRequires:  automake
BuildRequires:  libtool

BuildRequires:  pkgconfig(x11)
BuildRequires:  pkgconfig(xt)
BuildRequires:  pkgconfig(xmu)
BuildRequires:  pkgconfig(xext)
BuildRequires:  pkgconfig(libinput)
BuildRequires:  pkgconfig(libudev)
BuildRequires:  libXaw-devel

%description
autocutsel tracks changes in the server's cutbuffer and clipboard selection,
keeping them synchronized.

This fork adds the -mouseonly option which synchronizes PRIMARY to CLIPBOARD
only when text is selected with the mouse. Keyboard-based selections (e.g.
Shift+Arrow) are ignored, preventing accidental clipboard overwrites in
editors like VSCode.

%prep
%autosetup

%build
./bootstrap
%configure
%make_build

%install
%make_install

%files
%license COPYING
%doc README AUTHORS ChangeLog TODO
%{_bindir}/autocutsel
%{_bindir}/cutsel
%{_mandir}/man1/autocutsel.1*
