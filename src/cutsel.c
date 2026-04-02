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


#include "common.h"

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
};

static void __attribute__((noreturn)) Syntax(char *call)
{
  fprintf (stderr,
    "usage:  %s [-selection <name>] [-cutbuffer <number>] [-debug] [-verbose] cut|sel [<value>]\n",
    call);
  fprintf (stderr,
    "        %s [-selection <name>] [-cutbuffer <number>] [-debug] [-verbose] targets\n",
    call);
  fprintf (stderr,
    "        %s [-selection <name>] [-cutbuffer <number>] [-debug] [-verbose] length\n",
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
};

#undef Offset

// Called when we no longer own the selection
static void LoseSelection(Widget w, Atom *selection)
{
  if (options.debug)
    printf("Selection lost\n");
  exit(0);
}

static void PrintSelection(Widget w, XtPointer client_data, Atom *selection,
                           Atom *type, XtPointer value,
                           unsigned long *received_length, int *format)
{
  Display* d = XtDisplay(w);
  Atom utf8_string = XInternAtom(d, "UTF8_STRING", False);

  if (*type == 0) {
    printf("Nobody owns the selection\n");
  } else if (*type == utf8_string || *type == XA_STRING) {
    fwrite((char*)value, 1, *received_length, stdout);
    putchar('\n');
  } else if (client_data == SEL_TRY_UTF8) {
    // UTF8_STRING not supported, fall back to XA_STRING
    XtFree(value);
    XtGetSelectionValue(w, *selection, XA_STRING,
      PrintSelection, SEL_FALLBACK_STR, CurrentTime);
    return;
  } else {
    char *name = XGetAtomName(d, *type);
    printf("Invalid type received: %s\n", name ? name : "?");
    if (name) XFree(name);
  }

  XtFree(value);
  exit(0);
}

static void TargetsReceived(Widget w, XtPointer client_data, Atom *selection,
                           Atom *type, XtPointer value,
                           unsigned long *length, int *format)
{
  Display* d = XtDisplay(w);
  unsigned long i;
  Atom *atoms;

  if (*type == 0)
    printf("No target received\n");
  else if (*type == XA_ATOM) {
    atoms = (Atom*)value;
    printf("%lu targets (%i bits each):\n", *length, *format);
    for (i=0; i<*length; i++) {
      char *name = XGetAtomName(d, atoms[i]);
      printf("%s\n", name ? name : "?");
      if (name) XFree(name);
    }
  } else {
    char *name = XGetAtomName(d, *type);
    printf("Invalid type received: %s\n", name ? name : "?");
    if (name) XFree(name);
  }

  XtFree(value);
  exit(0);
}

static void LengthReceived(Widget w, XtPointer client_data, Atom *selection,
                           Atom *type, XtPointer value,
                           unsigned long *received_length, int *format)
{
  Display* d = XtDisplay(w);

  if (*type == 0)
    printf("No length received\n");
  else if (*type == XA_INTEGER) {
      printf("Length is %" PRIu32 "\n", (uint32_t)*(CARD32*)value);
  } else {
      char *name = XGetAtomName(d, *type);
      printf("Invalid type received: %s\n", name ? name : "?");
      if (name) XFree(name);
  }

  XtFree(value);
  exit(0);
}

static void OwnSelection(XtPointer p, XtIntervalId* i)
{
  if (XtOwnSelection(box, options.selection, CurrentTime,
                     ConvertSelection, LoseSelection, NULL) == True) {
    if (options.debug)
      printf("Selection owned\n");
  } else
    printf("WARNING: Unable to own selection!\n");
}

static void GetSelection(XtPointer p, XtIntervalId* i)
{
  Display* d = XtDisplay(box);
  Atom utf8_string = XInternAtom(d, "UTF8_STRING", False);
  XtGetSelectionValue(box, sel_atom, utf8_string,
    PrintSelection, SEL_TRY_UTF8,
    CurrentTime);
}

static void GetTargets(XtPointer p, XtIntervalId* i)
{
  Display* d = XtDisplay(box);
  XtGetSelectionValue(box, sel_atom, XA_TARGETS(d),
    TargetsReceived, NULL,
    CurrentTime);
}

static void GetLength(XtPointer p, XtIntervalId* i)
{
  Display* d = XtDisplay(box);
  XtGetSelectionValue(box, sel_atom, XA_LENGTH(d),
    LengthReceived, NULL,
    CurrentTime);
}

static void Exit(XtPointer p, XtIntervalId* i)
{
  exit(0);
}

int main(int argc, char* argv[])
{
  setlinebuf(stdout);

  // Pre-scan for --help/--version before Xt opens the X connection
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-help") == 0) {
      printf("usage:  %s [-selection <name>] [-cutbuffer <number>]"
        " [-debug] [-verbose] cut|sel [<value>]\n", argv[0]);
      printf("        %s [-selection <name>] [-cutbuffer <number>]"
        " [-debug] [-verbose] targets\n", argv[0]);
      printf("        %s [-selection <name>] [-cutbuffer <number>]"
        " [-debug] [-verbose] length\n", argv[0]);
      return 0;
    }
    if (strcmp(argv[i], "--version") == 0 || strcmp(argv[i], "-version") == 0) {
      printf("cutsel v%s\n", VERSION);
      return 0;
    }
  }

  Widget top;
  top = XtVaAppInitialize(&context, "CutSel",
        optionDesc, XtNumber(optionDesc), &argc, argv, NULL,
        XtNoverrideRedirect, True,
        XtNgeometry, "-10-10",
        NULL);

  if (argc < 2) Syntax(argv[0]);

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
    printf("cutsel v%s\n", VERSION);

  options.value = NULL;
  options.length = 0;

  box = XtCreateManagedWidget("box", boxWidgetClass, top, NULL, 0);
  dpy = XtDisplay(top);

  sel_atom = XInternAtom(dpy, options.selection_name, False);
  if (sel_atom == None) {
    fprintf(stderr, "cutsel: could not intern atom for selection %s\n",
            options.selection_name);
    return 1;
  }
  options.selection = sel_atom;

  buffer = options.buffer;
  if (buffer < 0 || buffer > 7) {
    fprintf(stderr, "cutsel: cutbuffer number must be 0-7\n");
    return 1;
  }

  if (strcmp(argv[1], "cut") == 0) {
    if (argc > 2) {
      XStoreBuffer(dpy,
       argv[2],
       strlen(argv[2]),
       buffer);
      XtAppAddTimeOut(context, 10, Exit, 0);
    } else {
      options.value = XFetchBuffer(dpy, &options.length, buffer);
      if (options.value && options.length > 0) {
        fwrite(options.value, 1, options.length, stdout);
        putchar('\n');
      }
      XFree(options.value);
      exit(0);
    }
  } else if (strcmp(argv[1], "sel") == 0) {
    if (argc > 2) {
      options.value = argv[2];
      options.length = strlen(argv[2]);
      XtAppAddTimeOut(context, 10, OwnSelection, 0);
    } else {
      XtAppAddTimeOut(context, 10, GetSelection, 0);
    }
  } else if (strcmp(argv[1], "targets") == 0) {
    XtAppAddTimeOut(context, 10, GetTargets, 0);
  } else if (strcmp(argv[1], "length") == 0) {
    XtAppAddTimeOut(context, 10, GetLength, 0);
  } else {
    Syntax(argv[0]);
  }

  XtRealizeWidget(top);
  XtAppMainLoop(context);
  return 0;
}
