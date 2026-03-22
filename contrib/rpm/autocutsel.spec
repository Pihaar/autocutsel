# libtool rewrites source paths during compilation, causing find-debuginfo
# to produce an empty debugsourcefiles.list.  Keep debuginfo, skip debugsource.
%global _debugsource_packages 0

Name:           autocutsel
Version:        0.11.2
Release:        1%{?dist}
Summary:        Synchronize X selections and cutbuffer with mouse-only support
License:        GPL-2.0-or-later
URL:            https://github.com/Pihaar/autocutsel
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
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
%doc README.md AUTHORS ChangeLog
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
* Sat Mar 21 2026 Pihaar <pihaar@users.noreply.github.com> - 0.11.2-1
- Fix -mouseonly on Wayland: read from PRIMARY instead of CLIPBOARD
- Fix cutsel UTF-8 support (UTF8_STRING with XA_STRING fallback)
- Fix debug output to show post-encoding-conversion comparison
- Add line-buffered stdout for systemd journal logging
- Expand test suite to 124 assertions with functional sync tests

* Sat Mar 21 2026 Pihaar <pihaar@users.noreply.github.com> - 0.11.1-1
- Fix XChangeProperty PID type for 64-bit correctness
- Fix allocator mismatch (XFetchBuffer/XtFree)
- Add cutsel.1 man page
- Split library linkage: cutsel no longer depends on libinput
- Guard libinput headers behind USE_LIBINPUT
- Add sanitizer CI job (ASan + UBSan)
- Add make check to all CI build jobs and RPM check sections

* Fri Mar 20 2026 Pihaar <pihaar@users.noreply.github.com> - 0.11.0-2
- Reorganize directory structure (src/, contrib/rpm/, contrib/arch/)
- Fix CI portability: replace pipe2() with pipe()+fcntl()
- Fix openSUSE docdir path mismatch

* Thu Mar 19 2026 Pihaar <pihaar@users.noreply.github.com> - 0.11.0-1
- Wayland auto-detection with direct selection sync
- Pipe-based mouseonly mouse release detection
- Encoding conversion support (-encoding option)
- Instance management (prevent duplicate processes)
- Systemd user service with hardening options
