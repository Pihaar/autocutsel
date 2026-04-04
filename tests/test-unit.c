/*
 * Unit tests for autocutsel internal functions.
 * Does NOT require an X display — tests pure logic only.
 */

#include "config.h"
#include "common.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/time.h>

static int passes = 0;
static int failures = 0;

#define ASSERT_EQ(a, b) do { \
  long _a = (long)(a), _b = (long)(b); \
  if (_a != _b) { \
    fprintf(stderr, "  FAIL %s:%d: %s=%ld, expected %s=%ld\n", \
            __FILE__, __LINE__, #a, _a, #b, _b); \
    failures++; \
  } else { passes++; } \
} while(0)

#define ASSERT_STR_EQ(a, b) do { \
  const char *_a = (a), *_b = (b); \
  if (strcmp(_a, _b) != 0) { \
    fprintf(stderr, "  FAIL %s:%d: %s=\"%s\", expected \"%s\"\n", \
            __FILE__, __LINE__, #a, _a, _b); \
    failures++; \
  } else { passes++; } \
} while(0)

#define ASSERT_NULL(a) do { \
  if ((a) != NULL) { \
    fprintf(stderr, "  FAIL %s:%d: %s is not NULL\n", \
            __FILE__, __LINE__, #a); \
    failures++; \
  } else { passes++; } \
} while(0)

#define ASSERT_NOT_NULL(a) do { \
  if ((a) == NULL) { \
    fprintf(stderr, "  FAIL %s:%d: %s is NULL\n", \
            __FILE__, __LINE__, #a); \
    failures++; \
  } else { passes++; } \
} while(0)

/* --- PrintValue stdout capture helper --- */

static char captured[4096];
static int captured_len;

static void capture_print_value(char *value, int length)
{
  int pipefd[2];
  if (pipe(pipefd) < 0) { perror("pipe"); return; }
  fflush(stdout);
  int saved = dup(STDOUT_FILENO);
  dup2(pipefd[1], STDOUT_FILENO);
  close(pipefd[1]);

  PrintValue(value, length);
  fflush(stdout);

  dup2(saved, STDOUT_FILENO);
  close(saved);

  captured_len = (int)read(pipefd[0], captured, sizeof(captured) - 1);
  if (captured_len < 0) captured_len = 0;
  captured[captured_len] = '\0';
  close(pipefd[0]);
}

/* --- ConvertEncoding tests --- */

static void test_convert_encoding(void)
{
  int out_len;
  char *result;

  /* ASCII round-trip through ISO-8859-1 */
  result = ConvertEncoding("UTF-8", "ISO-8859-1", "hello", 5, &out_len);
  ASSERT_NOT_NULL(result);
  if (result) {
    ASSERT_EQ(out_len, 5);
    ASSERT_EQ(memcmp(result, "hello", 5), 0);
    XtFree(result);
  }

  /* UTF-8 umlaut ä -> ISO-8859-1 0xE4 */
  result = ConvertEncoding("UTF-8", "ISO-8859-1", "\xC3\xA4", 2, &out_len);
  ASSERT_NOT_NULL(result);
  if (result) {
    ASSERT_EQ(out_len, 1);
    ASSERT_EQ((unsigned char)result[0], 0xE4);
    XtFree(result);
  }

  /* CJK to ISO-8859-1: lossy, must return NULL */
  result = ConvertEncoding("UTF-8", "ISO-8859-1",
    "\xE3\x83\x86\xE3\x82\xB9\xE3\x83\x88", 9, &out_len);
  ASSERT_NULL(result);

  /* Empty input (in_len=0) -> NULL */
  result = ConvertEncoding("UTF-8", "ISO-8859-1", "x", 0, &out_len);
  ASSERT_NULL(result);

  /* Negative in_len -> NULL */
  result = ConvertEncoding("UTF-8", "ISO-8859-1", "x", -1, &out_len);
  ASSERT_NULL(result);

  /* Invalid encoding name -> NULL */
  result = ConvertEncoding("NONEXISTENT_XYZ", "ISO-8859-1", "hello", 5, &out_len);
  ASSERT_NULL(result);

  /* NULL input with in_len=0 -> NULL */
  result = ConvertEncoding("UTF-8", "ISO-8859-1", NULL, 0, &out_len);
  ASSERT_NULL(result);
}

/* --- PrintValue tests --- */

static void test_print_value(void)
{
  /* Normal ASCII */
  capture_print_value("hello", 5);
  ASSERT_STR_EQ(captured, "\"hello\"");

  /* Newline escaped */
  capture_print_value("a\nb", 3);
  ASSERT_STR_EQ(captured, "\"a\\nb\"");

  /* Carriage return escaped */
  capture_print_value("a\rb", 3);
  ASSERT_STR_EQ(captured, "\"a\\rb\"");

  /* Tab escaped */
  capture_print_value("a\tb", 3);
  ASSERT_STR_EQ(captured, "\"a\\tb\"");

  /* Non-printable byte -> \xHH */
  capture_print_value("\x01", 1);
  ASSERT_STR_EQ(captured, "\"\\x01\"");

  /* 47 chars: full output with closing quote */
  {
    char buf[47];
    memset(buf, 'A', 47);
    capture_print_value(buf, 47);
    /* Should be: "AAA...47 A's" (1 + 47 + 1 = 49 chars) */
    ASSERT_EQ(captured[0], '"');
    ASSERT_EQ(captured[48], '"');
    ASSERT_EQ(captured_len, 49);
  }

  /* 48 chars: truncated (printed >= 48 triggers after 48th char) */
  {
    char buf[48];
    memset(buf, 'B', 48);
    capture_print_value(buf, 48);
    /* Output: "BBB...48 B's"... -> quote + 48 chars + "... = 53 chars */
    ASSERT_EQ(captured[0], '"');
    ASSERT_EQ(captured_len, 53);
    /* Ends with "... */
    ASSERT_STR_EQ(captured + 49, "\"...");
  }

  /* Empty (length=0) */
  capture_print_value("", 0);
  ASSERT_STR_EQ(captured, "\"\"");
}

/* --- ValueDiffers tests --- */

static void test_value_differs(void)
{
  /* NULL options.value: always differs */
  options.value = NULL;
  options.length = 0;
  ASSERT_EQ(ValueDiffers("test", 4), 1);

  /* Same value: returns 0 */
  options.value = XtMalloc(5);
  memcpy(options.value, "hello", 5);
  options.length = 5;
  ASSERT_EQ(ValueDiffers("hello", 5), 0);

  /* Different value: returns 1 */
  ASSERT_EQ(ValueDiffers("world", 5), 1);

  /* Same content different length: returns 1 */
  ASSERT_EQ(ValueDiffers("hello", 4), 1);

  /* Both length 0 with non-NULL value: returns 0 */
  XtFree(options.value);
  options.value = XtMalloc(1);
  options.length = 0;
  ASSERT_EQ(ValueDiffers("", 0), 0);

  /* Cleanup */
  XtFree(options.value);
  options.value = NULL;
  options.length = 0;
}

/* --- drain_pipe tests --- */

/* No-op signal handler for EINTR test (SIG_IGN would not cause EINTR) */
static void noop_signal(int sig) { (void)sig; }

static void test_drain_pipe(void)
{
  int pipefd[2];

  /* fd=-1: returns 0 */
  ASSERT_EQ(drain_pipe(-1), 0);

  /* Empty pipe: returns 0 */
  pipe(pipefd);
  fcntl(pipefd[0], F_SETFL, O_NONBLOCK);
  ASSERT_EQ(drain_pipe(pipefd[0]), 0);

  /* Pipe with data: returns 1 */
  write(pipefd[1], "abc", 3);
  ASSERT_EQ(drain_pipe(pipefd[0]), 1);

  /* After drain, empty: returns 0 */
  ASSERT_EQ(drain_pipe(pipefd[0]), 0);

  /* Multiple bytes drained */
  write(pipefd[1], "xyzxyzxyz", 9);
  ASSERT_EQ(drain_pipe(pipefd[0]), 1);

  /* EINTR resilience: schedule a signal with a real handler (not SIG_IGN,
     which silently discards signals without causing EINTR).  Best-effort
     test — the signal may or may not fire during read(). */
  {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = noop_signal;  /* real handler → can cause EINTR */
    sa.sa_flags = 0;              /* no SA_RESTART → read returns EINTR */
    sigaction(SIGALRM, &sa, NULL);

    write(pipefd[1], "eintr", 5);
    struct itimerval itv = { .it_value = { .tv_sec = 0, .tv_usec = 500 } };
    setitimer(ITIMER_REAL, &itv, NULL);
    ASSERT_EQ(drain_pipe(pipefd[0]), 1);
    /* Disarm timer */
    memset(&itv, 0, sizeof(itv));
    setitimer(ITIMER_REAL, &itv, NULL);
  }

  close(pipefd[0]);
  close(pipefd[1]);
}

/* --- Main --- */

int main(int argc, char *argv[])
{
  (void)argc; (void)argv;

  /* Initialize globals for tests */
  memset(&options, 0, sizeof(options));

  printf("=== Unit tests ===\n");

  printf("ConvertEncoding:\n");
  test_convert_encoding();

  printf("PrintValue:\n");
  test_print_value();

  printf("ValueDiffers:\n");
  test_value_differs();

  printf("drain_pipe:\n");
  test_drain_pipe();

  printf("\nResults: %d passed, %d failed\n", passes, failures);
  return failures > 0 ? 1 : 0;
}
