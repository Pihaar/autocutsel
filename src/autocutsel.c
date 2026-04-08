/*
 * autocutsel by Michael Witrant <mike @ lepton . fr>
 * Synchronizes the cutbuffer and the selection
 * Copyright (c) 2001-2021 Michael Witrant.
 *
 * Most code taken from:
 * * clear-cut-buffers.c by "E. Jay Berkenbilt" <ejb @ ql . org>
 *   in these messages:
 *     http://boudicca.tux.org/mhonarc/ma-linux/2001-Feb/msg00824.html
 *
 * * xcutsel.c by Ralph Swick, DEC/Project Athena
 *   from the XFree86 project: http://www.xfree86.org/
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

#include "common.h"

#ifdef HAVE_XFIXES
#include <X11/extensions/Xfixes.h>
#endif

#ifdef USE_LIBINPUT
// libinput callbacks for opening/closing device files
static int open_restricted(const char *path, int flags, void *user_data)
{
  int fd = open(path, flags | O_CLOEXEC);
  return fd < 0 ? -errno : fd;
}

static void close_restricted(int fd, void *user_data)
{
  close(fd);
}

static const struct libinput_interface li_interface = {
  .open_restricted = open_restricted,
  .close_restricted = close_restricted,
};

static atomic_int li_thread_running = 1;
static pthread_t li_thread_id;
static int li_thread_created = 0;
static int mouse_pipe[2] = {-1, -1};

// Dedicated thread for libinput event processing
static void *libinput_thread(void *arg)
{
  struct libinput *li = (struct libinput *)arg;
  struct pollfd pfd = { .fd = libinput_get_fd(li), .events = POLLIN };

  while (atomic_load(&li_thread_running)) {
    if (poll(&pfd, 1, 500) < 0) {
      if (errno != EINTR)
        usleep(100000);
      continue;
    }
    libinput_dispatch(li);
    struct libinput_event *ev;
    while ((ev = libinput_get_event(li)) != NULL) {
      if (libinput_event_get_type(ev) == LIBINPUT_EVENT_POINTER_BUTTON) {
        struct libinput_event_pointer *pev = libinput_event_get_pointer_event(ev);
        if (libinput_event_pointer_get_button(pev) == BTN_LEFT &&
            libinput_event_pointer_get_button_state(pev) == LIBINPUT_BUTTON_STATE_RELEASED) {
          if (mouse_pipe[1] >= 0) {
            char c = 'r';
            if (write(mouse_pipe[1], &c, 1) < 0 && errno != EAGAIN)
              perror("mouse_pipe write");
          }
        }
      }
      libinput_event_destroy(ev);
    }
  }
  return NULL;
}
#endif /* USE_LIBINPUT */

static Atom utf8_atom;
static Atom primary_atom;

#ifdef HAVE_XFIXES
static int xfixes_event_base = 0;
static int xfixes_error_base = 0;
static int have_xfixes = 0;
#endif

static XrmOptionDescRec optionDesc[] = {
  {"-selection", "selection", XrmoptionSepArg, NULL},
  {"-select",    "selection", XrmoptionSepArg, NULL},
  {"-sel",       "selection", XrmoptionSepArg, NULL},
  {"-s",         "selection", XrmoptionSepArg, NULL},
  {"-cutbuffer", "cutBuffer", XrmoptionSepArg, NULL},
  {"-cut",       "cutBuffer", XrmoptionSepArg, NULL},
  {"-c",         "cutBuffer", XrmoptionSepArg, NULL},
  {"-debug",     "debug",     XrmoptionNoArg,  "on"},
  {"-d",         "debug",     XrmoptionNoArg,  "on"},
  {"-verbose",   "verbose",   XrmoptionNoArg,  "on"},
  {"-v",         "verbose",   XrmoptionNoArg,  "on"},
  {"-fork",      "fork",      XrmoptionNoArg,  "on"},
  {"-f",         "fork",      XrmoptionNoArg,  "on"},
  {"-pause",     "pause",     XrmoptionSepArg, NULL},
  {"-p",         "pause",     XrmoptionSepArg, NULL},
  {"-buttonup",  "buttonup",  XrmoptionNoArg,  "on"},
  {"-mouseonly", "mouseonly", XrmoptionNoArg,  "on"},
  {"-encoding",  "encoding",  XrmoptionSepArg, NULL},
  {"-e",         "encoding",  XrmoptionSepArg, NULL},
};

static void __attribute__((noreturn)) Syntax(char *call)
{
  fprintf (stderr,
    "usage:  %s [-selection <name>] [-cutbuffer <number>]"
    " [-pause <milliseconds>] [-debug] [-verbose] [-fork] [-buttonup]"
    " [-mouseonly] [-encoding <charset>]\n",
    call);
  exit (1);
}

#define Offset(field) XtOffsetOf(OptionsRec, field)

static XtResource resources[] = {
  {"selection", "Selection", XtRString, sizeof(String),
    Offset(selection_name), XtRString, "CLIPBOARD"},
  {"cutBuffer", "CutBuffer", XtRInt, sizeof(int),
    Offset(buffer), XtRImmediate, (XtPointer)0},
  {"debug", "Debug", XtRString, sizeof(String),
    Offset(debug_option), XtRString, "off"},
  {"verbose", "Verbose", XtRString, sizeof(String),
    Offset(verbose_option), XtRString, "off"},
  {"fork", "Fork", XtRString, sizeof(String),
    Offset(fork_option), XtRString, "off"},
  {"pause", "Pause", XtRInt, sizeof(int),
    Offset(pause), XtRImmediate, (XtPointer)500},
  {"buttonup", "ButtonUp", XtRString, sizeof(String),
    Offset(buttonup_option), XtRString, "off"},
  {"mouseonly", "MouseOnly", XtRString, sizeof(String),
    Offset(mouseonly_option), XtRString, "off"},
  {"encoding", "Encoding", XtRString, sizeof(String),
    Offset(encoding), XtRString, NULL},
};

#undef Offset

static void CloseStdFds(void)
{
  int fd = open("/dev/null", O_RDWR);
  if (fd >= 0) {
    if (dup2(fd, 0) < 0) perror("dup2 stdin");
    if (dup2(fd, 1) < 0) perror("dup2 stdout");
    if (dup2(fd, 2) < 0) perror("dup2 stderr");
    if (fd > 2)
      close(fd);
  }
}

#ifdef USE_LIBINPUT
static void CleanupLibinput(void)
{
  if (options.li) {
    atomic_store(&li_thread_running, 0);
    if (li_thread_created)
      pthread_join(li_thread_id, NULL);
    libinput_unref(options.li);
    options.li = NULL;
    if (mouse_pipe[0] >= 0) { close(mouse_pipe[0]); mouse_pipe[0] = -1; }
    if (mouse_pipe[1] >= 0) { close(mouse_pipe[1]); mouse_pipe[1] = -1; }
  }
}
#endif

static void Terminate(int caught)
{
  (void)caught;
#ifdef USE_LIBINPUT
  atomic_store(&li_thread_running, 0);
#endif
  _exit(0);
}

static void TrapSignals(void)
{
  struct sigaction action;
  sigemptyset (&action.sa_mask);
  action.sa_flags = 0;
  action.sa_handler = Terminate;

  sigaction(SIGTERM, &action, NULL);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGHUP, &action, NULL);
}

// Called when we no longer own the selection
static void LoseSelection(Widget w, Atom *selection)
{
  if (options.debug)
    printf("Selection lost\n");
  options.own_selection = 0;
}

// Called when we lose target selection ownership (mouseonly/Wayland mode)
static void LoseTarget(Widget w, Atom *selection)
{
  if (options.debug)
    printf("Target selection ownership lost\n");
  options.own_target = 0;
}

// No-op callback for temporary PRIMARY ownership used to clear stale holders
static void LosePrimaryTemp(Widget w, Atom *selection)
{
  (void)w;
  (void)selection;
}

// Returns true if value (or length) is different
// than current ones.
// Update the current value
static void ChangeValue(char *value, int length)
{
  /* XtMalloc calls XtErrorMsg on failure which typically exits; the NULL
     check is unreachable in standard Xt but retained as defense-in-depth. */
  char *new_value = XtMalloc(length);
  if (!new_value) {
    fprintf(stderr, "WARNING: Unable to allocate memory to store the new value\n");
    return;
  }

  if (options.value) {
    secure_zero(options.value, options.length);
    XtFree(options.value);
  }

  options.length = length;
  options.value = new_value;
  memcpy(options.value, value, options.length);

  if (options.debug) {
    printf("New value saved: ");
    PrintValue(options.value, options.length);
    printf("\n");
  }
}

// Called just before owning the selection, to ensure we don't
// do it if the selection already has the same value
static void OwnSelectionIfDiffers(Widget w, XtPointer client_data,
                                  Atom *selection, Atom *type, XtPointer value,
                                  unsigned long *received_length, int *format)
{
  int length = (*received_length > INT_MAX) ? INT_MAX : (int)*received_length;
  if (*received_length > INT_MAX && options.debug)
    printf("WARNING: selection truncated from %lu to %d bytes\n",
           *received_length, length);

  if ((*type == 0 || *type == XT_CONVERT_FAIL) && client_data == SEL_TRY_UTF8) {
    // UTF8_STRING not supported, retry with XA_STRING before owning
    if (options.debug)
      printf("OwnSelectionIfDiffers: UTF8_STRING failed, retrying with XA_STRING\n");
    XtFree(value);
    XtGetSelectionValue(w, *selection, XA_STRING,
      OwnSelectionIfDiffers, SEL_FALLBACK_STR,
      CurrentTime);
    return;
  }

  // When the selection conversion failed entirely (no owner, or owner cannot
  // convert), only own the selection if we have a stored value to serve.
  // Without this guard, we could enter a ping-pong loop with another client
  // that also cannot provide a conversion.
  if ((*type == 0 || *type == XT_CONVERT_FAIL || length == 0 || !value) &&
      (!options.value || options.length <= 0)) {
    XtFree(value);
    return;
  }

  if (*type == 0 ||
      *type == XT_CONVERT_FAIL ||
      length == 0 ||
      !value ||
      ValueDiffers(value, length)) {
    if (options.debug)
      printf("Selection is out of date. Owning it\n");

    if (options.verbose)
    {
      printf("cut -> sel: ");
      PrintValue(options.value, options.length);
      printf("\n");
    }

    // CurrentTime is used because autocutsel is timer-driven with no triggering
    // user event. XtLastTimestampProcessed could be stale and cause the X server
    // to reject the ownership claim (ICCCM §2.1).
    if (XtOwnSelection(box, options.selection, CurrentTime,
        ConvertSelection, LoseSelection, NULL) == True) {
      if (options.debug)
        printf("Selection owned\n");
      options.own_selection = 1;
    }
    else
      printf("WARNING: Unable to own selection!\n");
  }
  XtFree(value);
}

// Look for change in the buffer, and update the selection if necessary
static void CheckBuffer(void)
{
  char *value;
  int length;

  value = XFetchBuffer(dpy, &length, buffer);

  if (length > 0 && ValueDiffers(value, length)) {
    if (options.debug) {
      printf("Buffer changed: ");
      PrintValue(value, length);
      printf("\n");
    }

    ChangeValue(value, length);
    XtGetSelectionValue(box, sel_atom, utf8_atom,
      OwnSelectionIfDiffers, SEL_TRY_UTF8,
      CurrentTime);
  }

  XFree(value);
}

// Called when the requested selection value is available
static void SelectionReceived(Widget w, XtPointer client_data, Atom *selection,
                              Atom *type, XtPointer value,
                              unsigned long *received_length, int *format)
{
  int length = (*received_length > INT_MAX) ? INT_MAX : (int)*received_length;
  if (*received_length > INT_MAX && options.debug)
    printf("WARNING: selection truncated from %lu to %d bytes\n",
           *received_length, length);

  if (options.debug) {
    printf("SelectionReceived: type=%lu length=%d format=%d\n",
           (unsigned long)*type, length, *format);
    if (length > 0 && value)  {
      printf("  value: ");
      PrintValue((char*)value, length > 80 ? 80 : length);
      printf("\n");
    }
    if (options.value) {
      printf("  cached: ");
      PrintValue(options.value, options.length > 80 ? 80 : options.length);
      printf("\n");
    }
  }

  if (*type != 0 && *type != XT_CONVERT_FAIL) {
    // In mouseonly mode, a valid response means we captured the selection
    // (whether changed or not). Stop further grace reads to avoid catching
    // subsequent keyboard selections.
#ifdef USE_LIBINPUT
    if (options.mouseonly)
      atomic_store(&options.mouse_grace_ticks, 0);
#endif

    char *store_value = (char*)value;
    int store_length = length;
    char *conv = NULL;

    // If -encoding is set, convert received UTF-8 to VNC encoding for storage
    if (options.encoding && length > 0) {
      int conv_len;
      conv = ConvertEncoding("UTF-8", options.encoding,
                             (char*)value, length, &conv_len);
      if (conv) {
        store_value = conv;
        store_length = conv_len;
      }
    }

    if (options.debug)
      printf("  differs: %d\n", ValueDiffers(store_value, store_length));

    if (store_length > 0 && ValueDiffers(store_value, store_length)) {
      if (options.debug) {
        printf("Selection changed: ");
        PrintValue(store_value, store_length);
        printf("\n");
      }

      ChangeValue(store_value, store_length);
      if (options.verbose) {
        printf("sel -> cut: ");
        PrintValue(options.value, options.length);
        printf("\n");
      }

      if (options.mouseonly || options.wayland) {
        // Directly own target selection - force XWayland to notice the change
        // by disowning first, then re-claiming ownership
        if (options.debug)
          printf("Owning target selection directly\n");
        if (options.own_target) {
          // Disown first to force a new SelectionNotify to XWayland
          XtDisownSelection(box, options.target, CurrentTime);
          options.own_target = 0;
        }
        if (XtOwnSelection(box, options.target, CurrentTime,
            ConvertSelection, LoseTarget, NULL) == True) {
          options.own_target = 1;
          // Update reverse tracking with the raw UTF-8 value (pre-encoding),
          // NOT options.value (which may be VNC-encoded). ReverseReceived
          // compares against raw UTF-8 from the target selection.
          if (options.reverse_value) {
            secure_zero(options.reverse_value, options.reverse_length);
            XtFree(options.reverse_value);
          }
          options.reverse_value = XtMalloc(length);
          memcpy(options.reverse_value, (char*)value, length);
          options.reverse_length = length;
        } else {
          printf("WARNING: Unable to own target selection!\n");
        }
      } else {
        if (options.debug)
          printf("Updating buffer\n");
        XStoreBuffer(XtDisplay(w),
               (char*)options.value,
               options.length,
               buffer );

        // Clear stale PRIMARY holders (e.g. xterm visual selection)
        // so middle-click pastes the new cutbuffer content instead
        // of the old PRIMARY value.
        if (sel_atom != primary_atom) {
          if (XtOwnSelection(box, primary_atom, CurrentTime,
              ConvertSelection, LosePrimaryTemp, NULL) == True) {
            if (options.debug)
              printf("Clearing stale PRIMARY selection\n");
            XtDisownSelection(box, primary_atom, CurrentTime);
          }
        }
      }

      XtFree(value);
      if (conv) XtFree(conv);
      return;
    }
    if (conv) XtFree(conv);
  } else if (client_data == SEL_TRY_UTF8) {
    // UTF8_STRING not supported by selection owner, fall back to XA_STRING
    if (options.debug)
      printf("UTF8_STRING failed, retrying with XA_STRING\n");
    XtFree(value);
    XtGetSelectionValue(w, *selection, XA_STRING,
      SelectionReceived, SEL_FALLBACK_STR,
      CurrentTime);
    return;
  }
  XtFree(value);

  // Unless a new selection value is found, check the buffer value
  // (skip in mouseonly/Wayland modes - we use direct selection sync)
  if (!options.mouseonly && !options.wayland)
    CheckBuffer();
}

// Reverse direction: check if the target selection (e.g. CLIPBOARD) changed
// externally (e.g. browser Clipboard API).  If so, own the monitored selection
// (e.g. PRIMARY) with the new value.  This makes mouseonly/Wayland mode
// truly bidirectional without requiring a second instance.
static void ReverseReceived(Widget w, XtPointer client_data, Atom *selection,
                            Atom *type, XtPointer value,
                            unsigned long *received_length, int *format)
{
  int length = (*received_length > INT_MAX) ? INT_MAX : (int)*received_length;
  if (*received_length > INT_MAX && options.debug)
    printf("WARNING: reverse selection truncated from %lu to %d bytes\n",
           *received_length, length);

  if (*type == 0 || *type == XT_CONVERT_FAIL) {
    if (client_data == SEL_TRY_UTF8) {
      XtFree(value);
      XtGetSelectionValue(w, *selection, XA_STRING,
        ReverseReceived, SEL_FALLBACK_STR, CurrentTime);
      return;
    }
    XtFree(value);
    return;
  }

  // Skip if we own the target and the value matches what we last synced
  // (compare against reverse_value which tracks raw UTF-8 from the target,
  // not options.value which may be encoding-converted)
  if (options.own_target && options.reverse_value &&
      length == options.reverse_length &&
      memcmp(options.reverse_value, value, length) == 0) {
    XtFree(value);
    return;
  }

  // Check if this is genuinely new compared to last reverse poll
  int differs = (!options.reverse_value ||
                 length != options.reverse_length ||
                 memcmp(options.reverse_value, value, length));

  if (length > 0 && differs) {
    if (options.debug) {
      printf("Reverse: target selection changed: ");
      PrintValue((char*)value, length > 80 ? 80 : length);
      printf("\n");
    }
    if (options.verbose) {
      printf("reverse: ");
      PrintValue((char*)value, length);
      printf("\n");
    }

    // Update reverse tracking (zero old buffer before freeing to avoid
    // leaving sensitive clipboard data as heap residue)
    char *new_rv = XtMalloc(length);
    if (!new_rv) { XtFree(value); return; }  // defense-in-depth (XtMalloc exits)
    memcpy(new_rv, value, length);
    if (options.reverse_value) {
      secure_zero(options.reverse_value, options.reverse_length);
      XtFree(options.reverse_value);
    }
    options.reverse_value = new_rv;
    options.reverse_length = length;

    // Convert encoding if needed (same as forward path in SelectionReceived)
    char *store_value = (char*)value;
    int store_length = length;
    char *conv = NULL;
    if (options.encoding && length > 0) {
      int conv_len;
      conv = ConvertEncoding("UTF-8", options.encoding,
                             (char*)value, length, &conv_len);
      if (conv) {
        store_value = conv;
        store_length = conv_len;
      }
    }

    // Also update main value so we don't re-sync it back
    if (store_length > 0) {
      ChangeValue(store_value, store_length);

      // Own the monitored selection (e.g. PRIMARY) with this value
      if (XtOwnSelection(box, options.selection, CurrentTime,
          ConvertSelection, LoseSelection, NULL) == True) {
        options.own_selection = 1;
        if (options.debug)
          printf("Reverse: owned monitored selection\n");
      }
    }
    if (conv) XtFree(conv);
  }

  XtFree(value);
}

// Separate timer for reverse direction polling (CLIPBOARD→PRIMARY).
#ifdef HAVE_XFIXES
// XFixes event handler: fires when selection ownership changes.
// Replaces forward polling for instant detection of selection changes.
static void XFixesSelectionHandler(Widget w, XtPointer client_data,
                                   XEvent *event, Boolean *cont)
{
  if (event->type != xfixes_event_base + XFixesSelectionNotify)
    return;

  XFixesSelectionNotifyEvent *sev = (XFixesSelectionNotifyEvent *)event;

  if (sev->selection != sel_atom)
    return;

  if (sev->owner == XtWindow(box) || sev->owner == None)
    return;

  if (options.debug) {
    char *sel_name = XGetAtomName(dpy, sev->selection);
    printf("XFixes: selection %s owner changed (subtype %d)\n",
           sel_name ? sel_name : "?", sev->subtype);
    if (sel_name) XFree(sel_name);
  }

  XtGetSelectionValue(box, sel_atom, utf8_atom,
    SelectionReceived, SEL_TRY_UTF8, CurrentTime);
}
#endif

// Separate timer for reverse direction polling (CLIPBOARD->PRIMARY).
// Fires every 500ms independently of the forward poll timer.
// Used in both mouseonly and Wayland modes.
static void reverse_timeout(XtPointer p, XtIntervalId* i)
{
  if (!options.own_target) {
    XtGetSelectionValue(box, options.target, utf8_atom,
      ReverseReceived, SEL_TRY_UTF8, CurrentTime);
  }
  XtAppAddTimeOut(context, 500, reverse_timeout, 0);
}

static void timeout(XtPointer p, XtIntervalId* i)
{
  if (options.mouseonly) {
#ifdef USE_LIBINPUT
    // mouseonly: check pipe for mouse button release signal from libinput thread
    if (drain_pipe(mouse_pipe[0])) {
      if (options.debug)
        printf("mouseonly: mouse release detected, reading selection\n");
      atomic_store(&options.mouse_grace_ticks, 1);
      XtGetSelectionValue(box, sel_atom, utf8_atom,
        SelectionReceived, SEL_TRY_UTF8,
        CurrentTime);
    } else if (atomic_load(&options.mouse_grace_ticks) > 0) {
      // Previous pipe-triggered read failed; retry once
      atomic_fetch_sub(&options.mouse_grace_ticks, 1);
      if (options.debug)
        printf("mouseonly: retry read (%d remaining)\n",
               atomic_load(&options.mouse_grace_ticks));
      XtGetSelectionValue(box, sel_atom, utf8_atom,
        SelectionReceived, SEL_TRY_UTF8,
        CurrentTime);
    }
#endif
  } else if (options.own_selection && !options.wayland) {
    // We own the selection — check if the cutbuffer changed
    CheckBuffer();
  } else {
#ifdef HAVE_XFIXES
    // When XFixes is active, selection ownership changes are event-driven
    // (via XFixesSelectionHandler). No need to poll here.
    if (!have_xfixes) {
#endif
    int get_value = 1;

    if (options.buttonup) {
      int screen_num = DefaultScreen(dpy);
      int root_x, root_y, win_x, win_y;
      unsigned int mask;
      Window root_wnd, child_wnd;
      XQueryPointer(dpy, RootWindow(dpy,screen_num), &root_wnd, &child_wnd,
        &root_x, &root_y, &win_x, &win_y, &mask);
      if (mask & (ShiftMask | Button1Mask))
        get_value = 0;
    }

    if (get_value)
      XtGetSelectionValue(box, sel_atom, utf8_atom,
        SelectionReceived, SEL_TRY_UTF8,
        CurrentTime);
#ifdef HAVE_XFIXES
    }
#endif
  }

  // mouseonly uses a shorter interval since it only checks a local pipe
  unsigned long interval = options.mouseonly ? 50 : options.pause;
  XtAppAddTimeOut(context, interval, timeout, 0);
}

int main(int argc, char* argv[])
{
  // Line-buffer stdout so output reaches the journal when running under systemd
  setlinebuf(stdout);

  // Ignore SIGPIPE so a pipe write in the libinput thread does not
  // kill the process if the read end is closed unexpectedly.
#ifdef USE_LIBINPUT
  signal(SIGPIPE, SIG_IGN);
#endif

  // Pre-scan for --help/--version before Xt opens the X connection
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-help") == 0) {
      printf("usage:  %s [-selection <name>] [-cutbuffer <number>]"
        " [-pause <milliseconds>] [-debug] [-verbose] [-fork] [-buttonup]"
        " [-mouseonly] [-encoding <charset>]\n", argv[0]);
      return 0;
    }
    if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-version") == 0) {
      printf("autocutsel v%s\n", VERSION);
      return 0;
    }
  }

  Widget top;
  top = XtVaAppInitialize(&context, "AutoCutSel",
        optionDesc, XtNumber(optionDesc), &argc, argv, NULL,
        XtNoverrideRedirect, True,
        XtNgeometry, "-10-10",
        NULL);

  if (argc != 1) Syntax(argv[0]);

  XtGetApplicationResources(top, (XtPointer)&options,
          resources, XtNumber(resources),
          NULL, ZERO );

  if (strcmp(options.debug_option, "on") == 0)
    options.debug = 1;
  else
    options.debug = 0;

  if (strcmp(options.verbose_option, "on") == 0)
    options.verbose = 1;
  else
    options.verbose = 0;

  if (options.debug || options.verbose)
    printf("autocutsel v%s\n", VERSION);

  if (options.encoding && options.debug)
    printf("Encoding conversion: %s <-> UTF-8\n", options.encoding);

  if (strcmp(options.buttonup_option, "on") == 0)
    options.buttonup = 1;
  else
    options.buttonup = 0;

  if (strcmp(options.mouseonly_option, "on") == 0)
    options.mouseonly = 1;
  else
    options.mouseonly = 0;

  // Validate pause interval (negative int → huge unsigned long timeout)
  if (options.pause < 1)
    options.pause = 500;

#ifndef USE_LIBINPUT
  // Without libinput, -mouseonly cannot distinguish mouse from keyboard selections
  if (options.mouseonly) {
    fprintf(stderr, "autocutsel: -mouseonly requires libinput (not available in this build)\n");
    return 1;
  }
#endif

  // Auto-detect Wayland session (cutbuffer does not work under XWayland)
  options.wayland = (getenv("WAYLAND_DISPLAY") != NULL) ? 1 : 0;
  if (options.wayland && (options.debug || options.verbose))
    printf("Wayland detected, using direct selection sync (no cutbuffer)\n");

#ifdef USE_LIBINPUT
  atomic_init(&options.mouse_grace_ticks, 0);
#endif

  if (strcmp(options.fork_option, "on") == 0) {
    options.fork = 1;
    options.verbose = 0;
    options.debug = 0;
  }
  else
    options.fork = 0;

  // Install signal handlers for clean shutdown in all modes (not just fork).
  // This ensures li_thread_running is set to 0 on SIGTERM/SIGINT/SIGHUP.
  TrapSignals();

  if (options.fork) {
    switch (fork()) {
    case -1:
      fprintf (stderr, "could not fork, exiting\n");
      return EXIT_FAILURE;
    case 0:
      if (setsid() < 0)
        perror("setsid");
      if (chdir("/") < 0)
        perror("chdir");
      CloseStdFds();
      break;
    default:
      return 0;
    }
  }

  options.value = NULL;
  options.length = 0;
  options.reverse_value = NULL;
  options.reverse_length = 0;

  options.own_selection = 0;
  options.own_target = 0;

  box = XtCreateManagedWidget("box", boxWidgetClass, top, NULL, 0);
  dpy = XtDisplay(top);
  utf8_atom = XInternAtom(dpy, "UTF8_STRING", False);
  primary_atom = XInternAtom(dpy, "PRIMARY", False);

  sel_atom = XInternAtom(dpy, options.selection_name, False);
  if (sel_atom == None) {
    fprintf(stderr, "autocutsel: could not intern atom for selection %s\n",
            options.selection_name);
    return 1;
  }
  options.selection = sel_atom;
  options.target = XInternAtom(dpy, "CLIPBOARD", False);
  if (options.target == None) {
    fprintf(stderr, "autocutsel: could not intern CLIPBOARD atom\n");
    return 1;
  }

  // On Wayland: remap so we read from one selection and write to the other.
  // - Default (no mouseonly): monitor CLIPBOARD, sync to PRIMARY
  // - Mouseonly: monitor PRIMARY (where mouse selections go), sync to CLIPBOARD
  if (options.wayland && sel_atom == options.target) {
    if (options.mouseonly) {
      // Read from PRIMARY (mouse selections), write to CLIPBOARD (already set)
      sel_atom = primary_atom;
      options.selection = sel_atom;
    } else {
      // Read from CLIPBOARD, write to PRIMARY
      options.target = primary_atom;
    }
  }

  if (options.debug && (options.mouseonly || options.wayland)) {
    char *sel_name = XGetAtomName(dpy, sel_atom);
    char *target_name = XGetAtomName(dpy, options.target);
    printf("Monitoring: %s -> Target: %s\n",
           sel_name ? sel_name : "?", target_name ? target_name : "?");
    if (sel_name) XFree(sel_name);
    if (target_name) XFree(target_name);
  }

  buffer = options.buffer;
  if (buffer < 0 || buffer > 7) {
    fprintf(stderr, "autocutsel: cutbuffer number must be 0-7\n");
    return 1;
  }

  if (!options.wayland) {
    char *xbuf = XFetchBuffer(dpy, &options.length, buffer);
    if (xbuf && options.length > 0) {
      options.value = XtMalloc(options.length);
      memcpy(options.value, xbuf, options.length);
    }
    XFree(xbuf);
  }

  XtRealizeWidget(top);
  XUnmapWindow(XtDisplay(top), XtWindow(top));

#ifdef HAVE_XFIXES
  // Probe for XFixes extension: enables event-driven selection monitoring
  if (XFixesQueryExtension(dpy, &xfixes_event_base, &xfixes_error_base)) {
    int xfixes_major = 0, xfixes_minor = 0;
    XFixesQueryVersion(dpy, &xfixes_major, &xfixes_minor);
    if (xfixes_major >= 1) {
      have_xfixes = 1;
      if (options.debug || options.verbose)
        printf("XFixes %d.%d: using event-driven selection monitoring\n",
               xfixes_major, xfixes_minor);
      XFixesSelectSelectionInput(dpy, XtWindow(top), sel_atom,
        XFixesSetSelectionOwnerNotifyMask |
        XFixesSelectionWindowDestroyNotifyMask |
        XFixesSelectionClientCloseNotifyMask);
      XtAddRawEventHandler(top, 0, True, XFixesSelectionHandler, NULL);
    } else if (options.debug) {
      printf("XFixes %d.%d too old (need 1.0+), using polling\n",
             xfixes_major, xfixes_minor);
    }
  } else if (options.debug) {
    printf("XFixes extension not available, using polling\n");
  }
#endif

  // Single-instance check: use a lock selection per monitored selection name
  {
    char lock_name[256];
    int n = snprintf(lock_name, sizeof(lock_name), "_AUTOCUTSEL_LOCK_%s",
             options.selection_name);
    if (n >= (int)sizeof(lock_name)) {
      fprintf(stderr, "autocutsel: selection name too long for lock atom\n");
      return 1;
    }
    Atom lock_atom = XInternAtom(dpy, lock_name, False);

    // Note: TOCTOU race between check and XSetSelectionOwner is inherent to X11.
    // The confirming XGetSelectionOwner below mitigates but does not eliminate it.

    if (XGetSelectionOwner(dpy, lock_atom) != None) {
      fprintf(stderr, "autocutsel: another instance is already running"
                      " for selection %s\n", options.selection_name);
      return 0;
    }

    XSetSelectionOwner(dpy, lock_atom, XtWindow(top), CurrentTime);
    if (XGetSelectionOwner(dpy, lock_atom) != XtWindow(top)) {
      fprintf(stderr, "autocutsel: could not acquire instance lock"
                      " for selection %s\n", options.selection_name);
      return 1;
    }
  }

#ifdef USE_LIBINPUT
  // Set up libinput for mouseonly mode: listen for pointer button events
  options.li = NULL;
  if (options.mouseonly) {
    struct udev *udev = udev_new();
    if (udev) {
      options.li = libinput_udev_create_context(&li_interface, NULL, udev);
      if (options.li) {
        if (libinput_udev_assign_seat(options.li, "seat0") == 0) {
          // Create pipe for cross-thread signaling before starting thread
          if (pipe(mouse_pipe) < 0) {
            fprintf(stderr, "WARNING: could not create mouse pipe\n");
            libinput_unref(options.li);
            options.li = NULL;
            options.mouseonly = 0;
          } else {
            if (fcntl(mouse_pipe[0], F_SETFD, FD_CLOEXEC) < 0 ||
                fcntl(mouse_pipe[1], F_SETFD, FD_CLOEXEC) < 0 ||
                fcntl(mouse_pipe[0], F_SETFL, O_NONBLOCK) < 0 ||
                fcntl(mouse_pipe[1], F_SETFL, O_NONBLOCK) < 0) {
              perror("fcntl mouse_pipe");
              close(mouse_pipe[0]); close(mouse_pipe[1]);
              mouse_pipe[0] = mouse_pipe[1] = -1;
              libinput_unref(options.li);
              options.li = NULL;
              options.mouseonly = 0;
            } else {
              // Start dedicated thread for libinput event processing
              pthread_t li_thread;
              if (pthread_create(&li_thread, NULL, libinput_thread, options.li) == 0) {
                li_thread_id = li_thread;
                li_thread_created = 1;
                if (options.debug)
                  printf("libinput mouseonly mode enabled (threaded)\n");
              } else {
                fprintf(stderr, "WARNING: could not create libinput thread\n");
                close(mouse_pipe[0]); close(mouse_pipe[1]);
                mouse_pipe[0] = mouse_pipe[1] = -1;
                libinput_unref(options.li);
                options.li = NULL;
                options.mouseonly = 0;
              }
            }
          }
        } else {
          fprintf(stderr, "WARNING: libinput could not assign seat, -mouseonly will not work\n");
          libinput_unref(options.li);
          options.li = NULL;
          options.mouseonly = 0;
        }
      } else {
        fprintf(stderr, "WARNING: could not create libinput context, -mouseonly will not work\n");
        options.mouseonly = 0;
      }
      udev_unref(udev);
    } else {
      fprintf(stderr, "WARNING: could not create udev context, -mouseonly will not work\n");
      options.mouseonly = 0;
    }
  }

  // Note: atexit handlers are only called by exit(), not _exit().
  // Since Terminate() uses _exit() (async-signal-safe), this handler only
  // runs if XtAppMainLoop somehow returns (which it normally does not).
  atexit(CleanupLibinput);
#endif /* USE_LIBINPUT */

  // Register timers AFTER libinput setup (mouseonly may have been disabled
  // if libinput init failed, affecting which timers are needed).
  {
    unsigned long interval = options.mouseonly ? 50 : options.pause;
    XtAppAddTimeOut(context, interval, timeout, 0);
  }
  if (options.mouseonly || options.wayland) {
    XtAppAddTimeOut(context, 500, reverse_timeout, 0);
  }

  /* Set up window properties so that the PID of the relevant autocutsel
   * process is known and autocutsel windows can be identified as such when
   * debugging. */
  const int IDX_NET_WM_NAME = 0;
  const int IDX_UTF8_STRING = 1;
  const int IDX_WM_NAME = 2;
  const int IDX_STRING = 3;
  const int IDX_NET_WM_PID = 4;
  const int IDX_CARDINAL = 5;

  Atom atoms[6];
  char *names[6] = {
      "_NET_WM_NAME",
      "UTF8_STRING",
      "WM_NAME",
      "STRING",
      "_NET_WM_PID",
      "CARDINAL",
  };
  XInternAtoms(dpy, names, 6, 0, atoms);

  const char *window_name = "autocutsel";
  long pid = (long)getpid();

  XChangeProperty(dpy, XtWindow(top), atoms[IDX_NET_WM_NAME], atoms[IDX_UTF8_STRING], 8, PropModeReplace, (const unsigned char*)window_name, (int)strlen(window_name));
  XChangeProperty(dpy, XtWindow(top), atoms[IDX_WM_NAME], atoms[IDX_STRING], 8, PropModeReplace, (const unsigned char*)window_name, (int)strlen(window_name));
  XChangeProperty(dpy, XtWindow(top), atoms[IDX_NET_WM_PID], atoms[IDX_CARDINAL], 32, PropModeReplace, (const unsigned char*)&pid, 1);

  XtAppMainLoop(context);

  return 0;
}
