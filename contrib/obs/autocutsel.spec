# libtool rewrites source paths during compilation, causing find-debuginfo
# to produce an empty debugsourcefiles.list.  Keep debuginfo, skip debugsource.
%global _debugsource_packages 0

Name:           autocutsel
Version:        0
Release:        0
Summary:        Synchronize X selections and cutbuffer with mouse-only support
License:        GPL-2.0-or-later
Group:          System/X11/Utilities
URL:            https://github.com/Pihaar/autocutsel
Source0:        %{name}-%{version}.tar.gz
Conflicts:      autocutsel-nightly

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
BuildRequires:  systemd-rpm-macros

%description
autocutsel tracks changes in the server's cutbuffer and clipboard selection,
keeping them synchronized.

This fork adds the -mouseonly option which synchronizes PRIMARY to CLIPBOARD
only when text is selected with the mouse. Keyboard-based selections (e.g.
Shift+Arrow) are ignored, preventing accidental clipboard overwrites in
text editors.

%prep
%autosetup

%build
./bootstrap
%configure --docdir=%{_docdir}/%{name}
%make_build

%install
%make_install

%check
%make_build check

%files
%license COPYING
%doc README AUTHORS ChangeLog
%dir %{_docdir}/%{name}/examples
%{_docdir}/%{name}/examples/mouseonly.args
%{_docdir}/%{name}/examples/clipboard.args
%{_docdir}/%{name}/examples/primary.args
%{_bindir}/autocutsel
%{_bindir}/cutsel
%{_mandir}/man1/autocutsel.1*
%{_mandir}/man1/cutsel.1*
%{_prefix}/lib/systemd/user/autocutsel@.service

%changelog
