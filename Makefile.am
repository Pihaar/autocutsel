ACLOCAL_AMFLAGS = -I m4

bin_PROGRAMS = autocutsel cutsel

autocutsel_SOURCES = autocutsel.c common.c
cutsel_SOURCES = cutsel.c common.c

noinst_HEADERS = common.h

man1_MANS = autocutsel.1

systemduserunitdir = $(prefix)/lib/systemd/user
systemduserunit_DATA = contrib/systemd/autocutsel@.service

autocutselargsdir = $(docdir)/examples
autocutselargs_DATA = contrib/systemd/mouseonly.args \
	contrib/systemd/clipboard.args \
	contrib/systemd/primary.args

EXTRA_DIST = AUTHORS COPYING ChangeLog INSTALL README TODO test_autocutsel.rb autocutsel.1 \
	contrib/systemd/autocutsel@.service \
	contrib/systemd/mouseonly.args \
	contrib/systemd/clipboard.args \
	contrib/systemd/primary.args \
	PKGBUILD \
	debian/control \
	debian/rules \
	debian/changelog \
	debian/compat \
	debian/source/format \
	debian/autocutsel.install
