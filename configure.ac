dnl Process this file with autoconf to produce a configure script.
AC_INIT([autocutsel],[0.11.4],[https://github.com/Pihaar/autocutsel/issues])
AC_CONFIG_SRCDIR([src/autocutsel.c])
AM_INIT_AUTOMAKE([foreign subdir-objects serial-tests])

AC_CONFIG_MACRO_DIRS([m4])

AC_CONFIG_HEADERS(config.h)

dnl Checks for programs.
AC_PROG_CC
LT_INIT
AC_PATH_XTRA
if test "$no_x" = "yes"
then
  AC_MSG_ERROR([Unable to find X libraries])
fi
AC_CHECK_LIB(Xext, main, LIBS="$LIBS -lXext", [], $X_PRE_LIB $X_LIBS $LIBS -lX11 $X_EXTRA_LIBS)

LIBS="$X_PRE_LIBS $X_LIBS $LIBS -lX11 $X_EXTRA_LIBS"

AC_CHECK_LIB(Xaw, main,
  LIBS="$LIBS -lXaw",
  AC_MSG_ERROR(Unable to find Xaw library),
  $LIBS)

AC_CHECK_LIB(Xt, XtDisplay,
  LIBS="$LIBS -lXt",
  AC_MSG_ERROR(Unable to find Xt library),
  $LIBS)

AC_CHECK_LIB(Xmu, XmuGetHostname,
  LIBS="$LIBS -lXmu",
  AC_MSG_ERROR(Unable to find Xmu library),
  $LIBS)

PKG_CHECK_MODULES([LIBINPUT], [libinput],
  [CFLAGS="$CFLAGS $LIBINPUT_CFLAGS"
   AC_DEFINE([USE_LIBINPUT], [1], [Define if libinput is available])],
  AC_MSG_ERROR(Unable to find libinput))

PKG_CHECK_MODULES([LIBUDEV], [libudev],
  [CFLAGS="$CFLAGS $LIBUDEV_CFLAGS"],
  AC_MSG_ERROR(Unable to find libudev))

AUTOCUTSEL_LIBS="$LIBINPUT_LIBS $LIBUDEV_LIBS -lpthread"
AC_SUBST([AUTOCUTSEL_LIBS])

dnl Checks for library functions.
AC_FUNC_SETPGRP
AC_CHECK_FUNCS([explicit_bzero])

dnl Warnings
AC_MSG_CHECKING([whether to enable -Wall])
if test -n "$GCC"; then
  AC_MSG_RESULT(adding -Wall to CFLAGS.)
  CFLAGS="$CFLAGS -Wall -Wno-unused-parameter"
else
  AC_MSG_RESULT(no)
fi

dnl Hardening flags (checked individually for compiler/linker support)
if test -n "$GCC"; then
  for hflag in -fstack-protector-strong -fPIE; do
    AC_MSG_CHECKING([whether $CC supports $hflag])
    saved_CFLAGS="$CFLAGS"
    CFLAGS="$CFLAGS $hflag"
    AC_COMPILE_IFELSE([AC_LANG_PROGRAM()],
      [AC_MSG_RESULT([yes])],
      [AC_MSG_RESULT([no]); CFLAGS="$saved_CFLAGS"])
  done

  AC_MSG_CHECKING([whether _FORTIFY_SOURCE=2 works])
  saved_CFLAGS="$CFLAGS"
  CFLAGS="$CFLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -Werror"
  AC_COMPILE_IFELSE([AC_LANG_PROGRAM()],
    [AC_MSG_RESULT([yes]); CFLAGS="$saved_CFLAGS -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2"],
    [AC_MSG_RESULT([no]); CFLAGS="$saved_CFLAGS"])

  for hflag in -pie -Wl,-z,relro -Wl,-z,now; do
    AC_MSG_CHECKING([whether $CC supports $hflag])
    saved_LDFLAGS="$LDFLAGS"
    LDFLAGS="$LDFLAGS $hflag"
    AC_LINK_IFELSE([AC_LANG_PROGRAM()],
      [AC_MSG_RESULT([yes])],
      [AC_MSG_RESULT([no]); LDFLAGS="$saved_LDFLAGS"])
  done
fi

AC_CONFIG_FILES([Makefile autocutsel.1 cutsel.1])
AC_OUTPUT
