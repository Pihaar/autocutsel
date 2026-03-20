ACLOCAL_AMFLAGS = -I m4

bin_PROGRAMS = autocutsel cutsel

autocutsel_SOURCES = src/autocutsel.c src/common.c
cutsel_SOURCES = src/cutsel.c src/common.c

noinst_HEADERS = src/common.h

man1_MANS = autocutsel.1

TESTS = tests/test-no-display.sh \
	tests/test-cli.sh \
	tests/test-modes.sh \
	tests/test-wayland.sh \
	tests/test-instance.sh \
	tests/test-cutsel.sh

TEST_EXTENSIONS = .sh
SH_LOG_COMPILER = $(SHELL)

# Pass binary paths to tests so they find the just-built binaries
TESTS_ENVIRONMENT = \
	AUTOCUTSEL="$(abs_builddir)/autocutsel"; export AUTOCUTSEL; \
	CUTSEL="$(abs_builddir)/cutsel"; export CUTSEL;

systemduserunitdir = $(prefix)/lib/systemd/user
systemduserunit_DATA = contrib/systemd/autocutsel@.service

autocutselargsdir = $(docdir)/examples
autocutselargs_DATA = contrib/systemd/mouseonly.args \
	contrib/systemd/clipboard.args \
	contrib/systemd/primary.args

EXTRA_DIST = AUTHORS COPYING ChangeLog README autocutsel.1.in \
	bootstrap \
	tests/helpers.sh \
	tests/test-no-display.sh \
	tests/test-cli.sh \
	tests/test-modes.sh \
	tests/test-wayland.sh \
	tests/test-instance.sh \
	tests/test-cutsel.sh \
	contrib/systemd/autocutsel@.service \
	contrib/systemd/mouseonly.args \
	contrib/systemd/clipboard.args \
	contrib/systemd/primary.args \
	contrib/rpm/autocutsel.spec \
	contrib/arch/PKGBUILD \
	debian/control \
	debian/rules \
	debian/changelog \
	debian/source/format \
	debian/autocutsel.install
