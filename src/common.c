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

Widget box;
Display* dpy;
XtAppContext context;
Atom sel_atom;
int buffer;
OptionsRec options;

void PrintValue(char *value, int length)
{
  unsigned char c;
  int len = 0;

  putc('"', stdout);
  for (; length > 0; length--, value++) {
    c = (unsigned char)*value;
    switch (c) {
    case '\n':
      printf("\\n");
      break;
    case '\r':
      printf("\\r");
      break;
    case '\t':
      printf("\\t");
      break;
    default:
      if (c < 32 || c > 127)
        printf("\\x%02X", c);
      else
        putc(c, stdout);
    }
    len++;
    if (len >= 48) {
      printf("\"...");
      return;
    }
  }
  putc('"', stdout);
}



// Convert between encodings using iconv.
// Returns a newly XtMalloc'd buffer (caller must XtFree) and sets *out_len.
// Returns NULL on failure.
char *ConvertEncoding(const char *from_enc, const char *to_enc,
                      const char *input, int in_len, int *out_len)
{
  iconv_t cd = iconv_open(to_enc, from_enc);
  if (cd == (iconv_t)-1) {
    if (options.debug)
      printf("iconv_open(%s, %s) failed: %s\n", to_enc, from_enc, strerror(errno));
    return NULL;
  }

  if (in_len <= 0) { iconv_close(cd); return NULL; }

  // Guard against integer overflow: in_len * 4 + 4
  if ((size_t)in_len > (SIZE_MAX - 4) / 4) { iconv_close(cd); return NULL; }
  size_t out_alloc = (size_t)in_len * 4 + 4;
  char *out_buf = XtMalloc(out_alloc);
  if (!out_buf) {
    iconv_close(cd);
    return NULL;
  }

  char *in_ptr = (char *)input;
  size_t in_left = (size_t)in_len;
  char *out_ptr = out_buf;
  size_t out_left = out_alloc;

  size_t ret = iconv(cd, &in_ptr, &in_left, &out_ptr, &out_left);
  iconv_close(cd);

  if (ret == (size_t)-1 || in_left > 0) {
    if (options.debug) {
      if (ret == (size_t)-1)
        printf("iconv conversion failed: %s\n", strerror(errno));
      else
        printf("iconv conversion incomplete: %zu bytes unconverted\n", in_left);
    }
    XtFree(out_buf);
    return NULL;
  }

  *out_len = (int)(out_alloc - out_left);
  return out_buf;
}


// called when someone requests the selection value
Boolean ConvertSelection(Widget w, Atom *selection, Atom *target,
                                Atom *type, XtPointer *value,
                                unsigned long *length, int *format)
{
  Display* d = XtDisplay(w);
  XSelectionRequestEvent* req =
    XtGetSelectionRequest(w, *selection, (XtRequestId)NULL);
  Atom utf8_string = XInternAtom(d, "UTF8_STRING", False);

  if (options.debug) {
    char *target_name = XGetAtomName(d, *target);
    char *sel_name = XGetAtomName(d, *selection);
    printf("Window 0x%lx requested %s of selection %s.\n",
      req->requestor, target_name, sel_name);
    XFree(target_name);
    XFree(sel_name);
  }

  if (*target == XA_TARGETS(d)) {
    Atom *targetP, *atoms;
    XPointer std_targets;
    unsigned long std_length;
    unsigned long i;

    XmuConvertStandardSelection(w, req->time, selection, target, type,
        &std_targets, &std_length, format);
    *value = XtMalloc(sizeof(Atom)*(std_length + 5));
    targetP = *(Atom**)value;
    atoms = targetP;
    *length = std_length + 5;
    *targetP++ = utf8_string;
    *targetP++ = XA_STRING;
    *targetP++ = XA_TEXT(d);
    *targetP++ = XA_LENGTH(d);
    *targetP++ = XA_LIST_LENGTH(d);
    memmove( (char*)targetP, (char*)std_targets, sizeof(Atom)*std_length);
    XtFree((char*)std_targets);
    *type = XA_ATOM;
    *format = 32;

    if (options.debug) {
      printf("Targets are: ");
      for (i=0; i<*length; i++) {
        char *name = XGetAtomName(d, atoms[i]);
        printf("%s ", name);
        XFree(name);
      }
      printf("\n");
    }

    return True;
  }

  if (*target == utf8_string || *target == XA_STRING || *target == XA_TEXT(d)) {
    *type = *target;

    if (options.length <= 0 || !options.value) {
      *value = XtMalloc(1);
      *length = 0;
    } else {
      char *conv = NULL;
      if (options.encoding && *target == utf8_string) {
        // If -encoding is set and UTF8_STRING is requested, convert stored value
        // from the VNC encoding to UTF-8
        int conv_len;
        conv = ConvertEncoding(options.encoding, "UTF-8",
                               options.value, options.length, &conv_len);
        if (conv) {
          *value = (XtPointer)conv;
          *length = conv_len;
        }
      }
      if (!conv) {
        *value = XtMalloc((Cardinal) options.length);
        memmove((char *)*value, options.value, options.length);
        *length = options.length;
      }
    }
    *format = 8;

    if (options.debug) {
      char *name = XGetAtomName(d, *target);
      printf("Returning %s ", name);
      XFree(name);
      PrintValue((char*)*value, *length);
      printf("\n");
    }

    return True;
  }

  if (*target == XA_LIST_LENGTH(d)) {
    CARD32 *temp = (CARD32 *) XtMalloc(sizeof(CARD32));
    *temp = 1L;
    *value = (XtPointer) temp;
    *type = XA_INTEGER;
    *length = 1;
    *format = 32;

    if (options.debug)
      printf("Returning %" PRIx32 "\n", (uint32_t)*temp);

    return True;
  }

  if (*target == XA_LENGTH(d)) {
    CARD32 *temp = (CARD32 *) XtMalloc(sizeof(CARD32));
    *temp = options.length;
    *value = (XtPointer) temp;
    *type = XA_INTEGER;
    *length = 1;
    *format = 32;

    if (options.debug)
      printf("Returning %" PRIx32 "\n", (uint32_t)*temp);

    return True;
  }

  if (XmuConvertStandardSelection(w, req->time, selection, target, type,
          (XPointer *)value, length, format)) {
    printf("Returning conversion of standard selection\n");
    return True;
  }

  /* else */
  if (options.debug)
    printf("Target not supported\n");

  return False;
}
