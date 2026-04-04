ACLOCAL_AMFLAGS = -I m4

bin_PROGRAMS = autocutsel cutsel

autocutsel_SOURCES = src/autocutsel.c src/common.c
autocutsel_LDADD = @AUTOCUTSEL_LIBS@
cutsel_SOURCES = src/cutsel.c src/common.c

noinst_HEADERS = src/common.h

check_PROGRAMS = tests/test-unit
tests_test_unit_SOURCES = tests/test-unit.c src/common.c
tests_test_unit_CPPFLAGS = -I$(srcdir)/src

man1_MANS = autocutsel.1 cutsel.1

TESTS = tests/test-unit \
	tests/test-no-display.sh \
	tests/test-cli.sh \
	tests/test-modes.sh \
	tests/test-wayland.sh \
	tests/test-instance.sh \
	tests/test-cutsel.sh \
	tests/test-sync.sh \
	tests/test-robustness.sh

TEST_EXTENSIONS = .sh
SH_LOG_COMPILER = $(SHELL)

# Pass binary paths to tests so they find the just-built binaries.
# Unset WAYLAND_DISPLAY to prevent host Wayland session from affecting tests.
TESTS_ENVIRONMENT = \
	AUTOCUTSEL="$(abs_builddir)/autocutsel"; export AUTOCUTSEL; \
	CUTSEL="$(abs_builddir)/cutsel"; export CUTSEL; \
	unset WAYLAND_DISPLAY;

systemduserunitdir = $(prefix)/lib/systemd/user
systemduserunit_DATA = contrib/systemd/autocutsel@.service

autocutselargsdir = $(docdir)/examples
autocutselargs_DATA = contrib/systemd/mouseonly.args \
	contrib/systemd/clipboard.args \
	contrib/systemd/primary.args

EXTRA_DIST = AUTHORS COPYING ChangeLog README.md autocutsel.1.in cutsel.1.in \
	bootstrap \
	tests/helpers.sh \
	tests/test-unit.c \
	tests/test-no-display.sh \
	tests/test-cli.sh \
	tests/test-modes.sh \
	tests/test-wayland.sh \
	tests/test-instance.sh \
	tests/test-cutsel.sh \
	tests/test-sync.sh \
	tests/test-robustness.sh \
	contrib/systemd/autocutsel@.service \
	contrib/systemd/mouseonly.args \
	contrib/systemd/clipboard.args \
	contrib/systemd/primary.args \
	contrib/rpm/autocutsel.spec \
	contrib/obs/autocutsel.spec \
	contrib/arch/PKGBUILD \
	.obs/workflows.yml \
	debian/control \
	debian/rules \
	debian/changelog \
	debian/source/format \
	debian/autocutsel.install
