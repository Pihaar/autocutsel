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

// libinput callbacks for opening/closing device files
static int open_restricted(const char *path, int flags, void *user_data)
{
  int fd = open(path, flags);
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

static _Atomic(int) li_thread_running = 1;
static pthread_t li_thread_id;
static Atom utf8_atom;
static int mouse_pipe[2] = {-1, -1};

// Check pipe for mouse release signal from libinput thread (non-blocking)
static int drain_mouse_pipe(void)
{
  if (mouse_pipe[0] < 0)
    return 0;
  char buf;
  int got = 0;
  while (read(mouse_pipe[0], &buf, 1) > 0)
    got = 1;
  return got;
}

// Dedicated thread for libinput event processing
static void *libinput_thread(void *arg)
{
  struct libinput *li = (struct libinput *)arg;
  struct pollfd pfd = { .fd = libinput_get_fd(li), .events = POLLIN };

  while (atomic_load(&li_thread_running)) {
    if (poll(&pfd, 1, 500) < 0)
      continue;
    libinput_dispatch(li);
    struct libinput_event *ev;
    while ((ev = libinput_get_event(li)) != NULL) {
      if (libinput_event_get_type(ev) == LIBINPUT_EVENT_POINTER_BUTTON) {
        struct libinput_event_pointer *pev = libinput_event_get_pointer_event(ev);
        if (libinput_event_pointer_get_button(pev) == BTN_LEFT &&
            libinput_event_pointer_get_button_state(pev) == LIBINPUT_BUTTON_STATE_RELEASED) {
          // Signal the Xt main loop via pipe for immediate processing
          if (mouse_pipe[1] >= 0) {
            char c = 'r';
            (void)write(mouse_pipe[1], &c, 1);
          }
        }
      }
      libinput_event_destroy(ev);
    }
  }
  return NULL;
}

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

int Syntax(char *call)
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

static void CloseStdFds()
{
  int fd = open("/dev/null", O_RDWR);
  if (fd >= 0) {
    dup2(fd, 0);
    dup2(fd, 1);
    dup2(fd, 2);
    if (fd > 2)
      close(fd);
  }
}

static void CleanupLibinput(void)
{
  if (options.li) {
    atomic_store(&li_thread_running, 0);
    if (li_thread_id)
      pthread_join(li_thread_id, NULL);
    libinput_unref(options.li);
    options.li = NULL;
    if (mouse_pipe[0] >= 0) { close(mouse_pipe[0]); mouse_pipe[0] = -1; }
    if (mouse_pipe[1] >= 0) { close(mouse_pipe[1]); mouse_pipe[1] = -1; }
  }
}

static void Terminate(int caught)
{
  (void)caught;
  atomic_store(&li_thread_running, 0);
  _exit(0);
}

static void TrapSignals()
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

// Returns true if value (or length) is different
// than current ones.
static int ValueDiffers(char *value, int length)
{
  return (!options.value ||
    length != options.length ||
    memcmp(options.value, value, length));
}

// Update the current value
static void ChangeValue(char *value, int length)
{
  char *new_value = XtMalloc(length);
  if (!new_value) {
    printf("WARNING: Unable to allocate memory to store the new value\n");
    return;
  }

  if (options.value)
    XtFree(options.value);

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

    if (XtOwnSelection(box, options.selection,
        0, //XtLastTimestampProcessed(dpy),
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
static void CheckBuffer()
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
    printf("  differs: %d\n", (length > 0 && value) ? ValueDiffers(value, length) : -1);
  }

  if (*type != 0 && *type != XT_CONVERT_FAIL) {
    // In mouseonly mode, a valid response means we captured the selection
    // (whether changed or not). Stop further grace reads to avoid catching
    // subsequent keyboard selections.
    if (options.mouseonly)
      atomic_store(&options.mouse_grace_ticks, 0);

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
        } else {
          printf("WARNING: Unable to own target selection!\n");
        }
      } else {
        if (options.debug)
          printf("Updating buffer\n");
        XStoreBuffer(XtDisplay(w),
               (char*)options.value,
               (int)(options.length),
               buffer );
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

void timeout(XtPointer p, XtIntervalId* i)
{
  if (options.own_selection && !options.wayland)
    CheckBuffer();
  else if (options.mouseonly) {
    // mouseonly: check pipe for mouse button release signal from libinput thread
    if (drain_mouse_pipe()) {
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
  } else {
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
  }

  // mouseonly uses a shorter interval since it only checks a local pipe
  unsigned long interval = options.mouseonly ? 50 : options.pause;
  XtAppAddTimeOut(context, interval, timeout, 0);
}

int main(int argc, char* argv[])
{
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

  // Auto-detect Wayland session (cutbuffer does not work under XWayland)
  options.wayland = (getenv("WAYLAND_DISPLAY") != NULL) ? 1 : 0;
  if (options.wayland && (options.debug || options.verbose))
    printf("Wayland detected, using direct selection sync (no cutbuffer)\n");

  atomic_init(&options.mouse_grace_ticks, 0);

  if (strcmp(options.fork_option, "on") == 0) {
    options.fork = 1;
    options.verbose = 0;
    options.debug = 0;
  }
  else
    options.fork = 0;

  if (options.fork) {
    if (getppid () != 1) {
#ifdef SETPGRP_VOID
      setpgrp();
#else
      setpgrp(0, 0);
#endif
      switch (fork()) {
      case -1:
        fprintf (stderr, "could not fork, exiting\n");
        return errno;
      case 0:
        sleep(3); /* Wait for parent to exit */
        chdir("/");
        TrapSignals();
        CloseStdFds();
        break;
      default:
        return 0;
      }
    }
  }

  options.value = NULL;
  options.length = 0;

  options.own_selection = 0;
  options.own_target = 0;

  box = XtCreateManagedWidget("box", boxWidgetClass, top, NULL, 0);
  dpy = XtDisplay(top);
  utf8_atom = XInternAtom(dpy, "UTF8_STRING", False);

  sel_atom = XInternAtom(dpy, options.selection_name, 0);
  if (sel_atom == None) {
    fprintf(stderr, "autocutsel: could not intern atom for selection %s\n",
            options.selection_name);
    return 1;
  }
  options.selection = sel_atom;
  options.target = XInternAtom(dpy, "CLIPBOARD", 0);
  if (options.target == None) {
    fprintf(stderr, "autocutsel: could not intern CLIPBOARD atom\n");
    return 1;
  }

  // On Wayland without mouseonly: if monitoring CLIPBOARD, sync to PRIMARY
  if (options.wayland && !options.mouseonly && sel_atom == options.target) {
    options.target = XInternAtom(dpy, "PRIMARY", 0);
    if (options.target == None) {
      fprintf(stderr, "autocutsel: could not intern PRIMARY atom\n");
      return 1;
    }
  }

  if (options.debug && (options.mouseonly || options.wayland)) {
    char *target_name = XGetAtomName(dpy, options.target);
    printf("Target selection: %s\n", target_name);
    XFree(target_name);
  }

  buffer = 0;

  if (!options.wayland)
    options.value = XFetchBuffer(dpy, &options.length, buffer);

  {
    unsigned long interval = options.mouseonly ? 50 : options.pause;
    XtAppAddTimeOut(context, interval, timeout, 0);
  }
  XtRealizeWidget(top);
  XUnmapWindow(XtDisplay(top), XtWindow(top));

  // Single-instance check: use a lock selection per monitored selection name
  {
    char lock_name[256];
    snprintf(lock_name, sizeof(lock_name), "_AUTOCUTSEL_LOCK_%s",
             options.selection_name);
    Atom lock_atom = XInternAtom(dpy, lock_name, 0);

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

  // Set up libinput for mouseonly mode: listen for pointer button events
  options.li = NULL;
  if (options.mouseonly) {
    struct udev *udev = udev_new();
    if (udev) {
      options.li = libinput_udev_create_context(&li_interface, NULL, udev);
      if (options.li) {
        if (libinput_udev_assign_seat(options.li, "seat0") == 0) {
          // Create pipe for cross-thread signaling before starting thread
          if (pipe2(mouse_pipe, O_CLOEXEC) < 0) {
            fprintf(stderr, "WARNING: could not create mouse pipe\n");
            libinput_unref(options.li);
            options.li = NULL;
            options.mouseonly = 0;
          } else {
            fcntl(mouse_pipe[0], F_SETFL, O_NONBLOCK);  // non-blocking read end
            fcntl(mouse_pipe[1], F_SETFL, O_NONBLOCK);  // non-blocking write end
            // Start dedicated thread for libinput event processing
            pthread_t li_thread;
            if (pthread_create(&li_thread, NULL, libinput_thread, options.li) == 0) {
              li_thread_id = li_thread;
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

  atexit(CleanupLibinput);

  /* Set up window properties so that the PID of the relevant autocutsel
   * process is known and autocutsel windows can be identified as such when
   * debugging. */
  const int _NET_WM_NAME = 0;
  const int UTF8_STRING = 1;
  const int WM_NAME = 2;
  const int STRING = 3;
  const int _NET_WM_PID = 4;
  const int CARDINAL = 5;

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
  pid_t pid = getpid();

  XChangeProperty(dpy, XtWindow(top), atoms[_NET_WM_NAME], atoms[UTF8_STRING], 8, PropModeReplace, (const unsigned char*)window_name, strlen(window_name));
  XChangeProperty(dpy, XtWindow(top), atoms[WM_NAME], atoms[STRING], 8, PropModeReplace, (const unsigned char*)window_name, strlen(window_name));
  XChangeProperty(dpy, XtWindow(top), atoms[_NET_WM_PID], atoms[CARDINAL], 32, PropModeReplace, (const unsigned char*)&pid, 1);

  XtAppMainLoop(context);

  return 0;
}
