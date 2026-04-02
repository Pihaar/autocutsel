/*
 * autocutsel by Michael Witrant <mike @ lepton . fr>
 * Manipulates the cutbuffer and the selection
 * Copyright (c) 2001-2021 Michael Witrant.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 * This program is distributed under the terms
 * of the GNU General Public License (read the COPYING file)
 *
 */

#include "config.h"

#include <X11/Xmu/Atoms.h>
#include <X11/Xmu/StdSel.h>

#include <X11/Intrinsic.h>
#include <X11/StringDefs.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Shell.h>
#include <X11/Xutil.h>
#include <X11/Xaw/Box.h>
#include <X11/Xaw/Cardinals.h>
#include <X11/Xmd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <iconv.h>

#ifdef USE_LIBINPUT
#include <stdatomic.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input-event-codes.h>
#endif


/*
 * Thread safety: The libinput thread only accesses mouse_grace_ticks (via
 * atomics). All other fields (value, length, etc.) are only accessed from the
 * Xt main loop thread, so no additional synchronization is needed.
 */
typedef struct {
  String  selection_name;
  int     buffer;
  String  debug_option;
  String  verbose_option;
  String  fork_option;
  String  buttonup_option;
  int     pause;
  int     debug;
  int     verbose;
  int     fork;
  Atom    selection;
  char*   value;
  int     length;
  int     own_selection;
  int     buttonup;
  String  mouseonly_option;
  int     mouseonly;
#ifdef USE_LIBINPUT
  atomic_int mouse_grace_ticks;
  struct libinput *li;
#endif
  Atom    target;
  int     own_target;
  int     wayland;
  String  encoding;
  // Reverse-direction tracking: last known value of the target selection,
  // used in mouseonly/Wayland mode to detect external CLIPBOARD changes.
  char*   reverse_value;
  int     reverse_length;
} OptionsRec;

extern Widget box;
extern Display* dpy;
extern XtAppContext context;
extern Atom sel_atom;
extern int buffer;
extern OptionsRec options;

// client_data flags for UTF8_STRING / XA_STRING fallback
#define SEL_TRY_UTF8     ((XtPointer)(long)0)
#define SEL_FALLBACK_STR ((XtPointer)(long)1)

void PrintValue(char *value, int length);
char *ConvertEncoding(const char *from_enc, const char *to_enc,
                      const char *input, int in_len, int *out_len);
Boolean ConvertSelection(Widget w, Atom *selection, Atom *target,
                                Atom *type, XtPointer *value,
                                unsigned long *length, int *format);
