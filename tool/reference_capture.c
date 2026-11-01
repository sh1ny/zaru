#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "jq.h"
#include "jv.h"

/* Developer-only, linked to the pinned libjq. No query source is rewritten. */
typedef struct {
  char *data;
  size_t length;
  size_t capacity;
} buffer;

typedef struct {
  jv value;
  int phase;
  int index;
  int iterator;
  int length;
} wire_frame;

typedef struct {
  jv messages;
} diagnostic_capture;

static void fatal(const char *message) {
  fprintf(stderr, "reference_capture_incomplete: %s\n", message);
  exit(70);
}

static void append_bytes(buffer *out, const char *bytes, size_t length) {
  if (length > SIZE_MAX - out->length - 1) fatal("wire size overflow");
  size_t required = out->length + length + 1;
  if (required > out->capacity) {
    size_t capacity = out->capacity ? out->capacity : 256;
    while (capacity < required) {
      if (capacity > SIZE_MAX / 2) {
        capacity = required;
        break;
      }
      capacity *= 2;
    }
    char *grown = realloc(out->data, capacity);
    if (!grown) fatal("wire allocation failed");
    out->data = grown;
    out->capacity = capacity;
  }
  memcpy(out->data + out->length, bytes, length);
  out->length += length;
  out->data[out->length] = '\0';
}

static void append_text(buffer *out, const char *text) {
  append_bytes(out, text, strlen(text));
}

static void append_json(buffer *out, jv value) {
  jv encoded = jv_dump_string(value, 0);
  append_bytes(out, jv_string_value(encoded),
               (size_t)jv_string_length_bytes(jv_copy(encoded)));
  jv_free(encoded);
}

static const char *number_kind(jv value) {
  if (jv_get_kind(value) != JV_KIND_NUMBER) return NULL;
  /* A finite decimal literal can convert to binary64 infinity. */
  if (jv_number_get_literal(value) != NULL) return "literal";
  double number = jv_number_value(value);
  if (isnan(number)) return "nan";
  if (isinf(number)) return signbit(number) ? "negativeInfinity" : "positiveInfinity";
  return "computed";
}

static void push_frame(wire_frame **frames, size_t *count, size_t *capacity,
                       jv value) {
  if (*count == *capacity) {
    size_t next = *capacity ? *capacity * 2 : 32;
    if (next < *capacity || next > SIZE_MAX / sizeof(**frames)) {
      fatal("wire frame overflow");
    }
    wire_frame *grown = realloc(*frames, next * sizeof(**frames));
    if (!grown) fatal("wire frame allocation failed");
    *frames = grown;
    *capacity = next;
  }
  (*frames)[(*count)++] = (wire_frame){value, 0, 0, 0, 0};
}

/* Store wire as JSON text, so jq's own printer depth does not truncate it. */
static jv lossless_wire(jv value) {
  buffer out = {0};
  wire_frame *frames = NULL;
  size_t count = 0, capacity = 0;
  push_frame(&frames, &count, &capacity, value);
  while (count) {
    wire_frame *frame = &frames[count - 1];
    jv_kind kind = jv_get_kind(frame->value);
    if (frame->phase == 0) {
      if (kind == JV_KIND_ARRAY) {
        append_text(&out, "[\"array\",[");
        frame->length = jv_array_length(jv_copy(frame->value));
        frame->phase = 1;
        continue;
      }
      if (kind == JV_KIND_OBJECT) {
        append_text(&out, "[\"object\",[");
        frame->iterator = jv_object_iter(frame->value);
        frame->phase = 1;
        continue;
      }
      switch (kind) {
        case JV_KIND_NULL:
          append_text(&out, "[\"null\"]");
          break;
        case JV_KIND_FALSE:
        case JV_KIND_TRUE:
          append_text(&out, "[\"boolean\",");
          append_json(&out, jv_copy(frame->value));
          append_text(&out, "]");
          break;
        case JV_KIND_STRING:
          append_text(&out, "[\"string\",");
          append_json(&out, jv_copy(frame->value));
          append_text(&out, "]");
          break;
        case JV_KIND_NUMBER: {
          const char *classification = number_kind(frame->value);
          append_text(&out, "[\"number\",");
          if (!strcmp(classification, "literal") ||
              !strcmp(classification, "computed")) {
            append_json(&out, jv_string(classification));
            append_text(&out, ",");
            jv printed = jv_dump_string(jv_copy(frame->value), 0);
            append_json(&out, printed);
          } else {
            append_json(&out, jv_string(classification));
          }
          append_text(&out, "]");
          break;
        }
        default:
          fatal("invalid value in lossless wire");
      }
      jv_free(frame->value);
      count--;
      continue;
    }
    if (kind == JV_KIND_ARRAY) {
      if (frame->index == frame->length) {
        append_text(&out, "]]");
        jv_free(frame->value);
        count--;
        continue;
      }
      if (frame->index) append_text(&out, ",");
      jv child = jv_array_get(jv_copy(frame->value), frame->index++);
      push_frame(&frames, &count, &capacity, child);
      continue;
    }
    if (frame->phase == 2) {
      append_text(&out, "]");
      frame->phase = 1;
      continue;
    }
    if (!jv_object_iter_valid(frame->value, frame->iterator)) {
      append_text(&out, "]]");
      jv_free(frame->value);
      count--;
      continue;
    }
    if (frame->index++) append_text(&out, ",");
    append_text(&out, "[");
    append_json(&out, jv_object_iter_key(frame->value, frame->iterator));
    append_text(&out, ",");
    jv child = jv_object_iter_value(frame->value, frame->iterator);
    frame->iterator = jv_object_iter_next(frame->value, frame->iterator);
    frame->phase = 2;
    push_frame(&frames, &count, &capacity, child);
  }
  free(frames);
  if (out.length > INT_MAX) fatal("wire exceeds jq string capacity");
  jv result = jv_string_sized(out.data, (int)out.length);
  free(out.data);
  return result;
}

static jv read_stream(FILE *stream) {
  buffer out = {0};
  char chunk[8192];
  if (fflush(stream) || fseek(stream, 0, SEEK_SET)) fatal("temporary stream rewind failed");
  size_t length;
  while ((length = fread(chunk, 1, sizeof(chunk), stream))) {
    append_bytes(&out, chunk, length);
  }
  if (ferror(stream)) fatal("temporary stream read failed");
  if (out.length > INT_MAX) fatal("capture exceeds jq string capacity");
  jv result = jv_string_sized(out.data ? out.data : "", (int)out.length);
  free(out.data);
  return result;
}

static jv capture_cli(const char *executable, const char *modules,
                      const char *program, const char *input) {
  FILE *in = tmpfile(), *out = tmpfile(), *err = tmpfile();
  if (!in || !out || !err) fatal("cannot create independent CLI capture files");
  size_t input_length = strlen(input);
  if (fwrite(input, 1, input_length, in) != input_length ||
      fputc('\n', in) == EOF || fflush(in) || fseek(in, 0, SEEK_SET)) {
    fatal("cannot prepare independent CLI input");
  }
  pid_t child = fork();
  if (child < 0) fatal("cannot fork independent CLI");
  if (child == 0) {
    if (dup2(fileno(in), STDIN_FILENO) < 0 ||
        dup2(fileno(out), STDOUT_FILENO) < 0 ||
        dup2(fileno(err), STDERR_FILENO) < 0) _exit(126);
    fclose(in);
    fclose(out);
    fclose(err);
    char *const arguments[] = {
      (char *)executable, "-c", "-M", "-L", (char *)modules, "--",
      (char *)program, NULL,
    };
    execv(executable, arguments);
    perror("reference CLI exec");
    _exit(127);
  }
  int status;
  while (waitpid(child, &status, 0) < 0) {
    if (errno != EINTR) fatal("independent CLI wait failed");
  }
  if (!WIFEXITED(status)) fatal("independent CLI crashed or was signalled");
  jv result = jv_object();
  result = jv_object_set(result, jv_string("cliExitCode"),
                         jv_number(WEXITSTATUS(status)));
  result = jv_object_set(result, jv_string("cliStdout"), read_stream(out));
  result = jv_object_set(result, jv_string("cliStderr"), read_stream(err));
  fclose(in);
  fclose(out);
  fclose(err);
  return result;
}

static void record_diagnostic(void *data, jv message) {
  diagnostic_capture *capture = data;
  if (jv_get_kind(message) != JV_KIND_STRING) {
    message = jv_dump_string(message, JV_PRINT_INVALID);
  }
  capture->messages = jv_array_append(capture->messages, message);
}

static jv failure(const char *message) {
  return JV_OBJECT(jv_string("ok"), jv_false(),
                   jv_string("error"), jv_string(message));
}

static jv capture_request(jv request, const char *executable,
                          const char *modules) {
  if (jv_get_kind(request) != JV_KIND_OBJECT) {
    jv_free(request);
    return failure("reference_request_invalid");
  }
  jv program_value = jv_object_get(jv_copy(request), jv_string("program"));
  jv input_value = jv_object_get(jv_copy(request), jv_string("input"));
  jv expected = jv_object_get(jv_copy(request), jv_string("expected"));
  int has_expected = jv_is_valid(expected);
  if (jv_get_kind(program_value) != JV_KIND_STRING ||
      jv_get_kind(input_value) != JV_KIND_STRING ||
      (has_expected && jv_get_kind(expected) != JV_KIND_ARRAY)) {
    jv_free(program_value);
    jv_free(input_value);
    jv_free(expected);
    jv_free(request);
    return failure("reference_request_invalid");
  }
  const char *program = jv_string_value(program_value);
  const char *input_text = jv_string_value(input_value);
  if (strlen(program) != (size_t)jv_string_length_bytes(jv_copy(program_value)) ||
      strlen(input_text) != (size_t)jv_string_length_bytes(jv_copy(input_value))) {
    jv_free(program_value);
    jv_free(input_value);
    jv_free(expected);
    jv_free(request);
    return failure("reference_request_embedded_nul");
  }
  jv input = jv_parse(input_text);
  if (!jv_is_valid(input)) {
    jv_free(input);
    jv_free(program_value);
    jv_free(input_value);
    jv_free(expected);
    jv_free(request);
    return failure("reference_input_invalid");
  }

  /* Separate OS process, same library build: validates the capture protocol. */
  jv record = capture_cli(executable, modules, program, input_text);
  record = jv_object_set(record, jv_string("ok"), jv_true());
  diagnostic_capture diagnostics = {jv_array()};
  jq_state *jq = jq_init();
  if (!jq) fatal("jq_init failed");
  jq_set_attr(jq, jv_string("JQ_LIBRARY_PATH"), JV_ARRAY(jv_string(modules)));
  jq_set_error_cb(jq, record_diagnostic, &diagnostics);
  int compiled = jq_compile(jq, program);
  record = jv_object_set(record, jv_string("compiled"), jv_bool(compiled));
  jv prefix = jv_array(), kinds = jv_array(), numbers = jv_array();
  jv wires = jv_array();
  int seen = 0, matches = 1;
  int expected_length = has_expected ? jv_array_length(jv_copy(expected)) : 0;
  const char *terminal = "compileError";
  if (compiled) {
    jq_start(jq, input, 0);
    input = jv_invalid();
    jv value;
    while (jv_is_valid(value = jq_next(jq))) {
      if (has_expected) {
        if (seen >= expected_length) {
          matches = 0;
        } else {
          jv text = jv_array_get(jv_copy(expected), seen);
          if (jv_get_kind(text) != JV_KIND_STRING) fatal("expected value is not raw JSON text");
          jv wanted = jv_parse(jv_string_value(text));
          jv_free(text);
          if (!jv_is_valid(wanted)) fatal("expected raw JSON cannot be parsed");
          if (!jv_equal(jv_copy(value), wanted)) matches = 0;
        }
      }
      if (seen == INT_MAX) fatal("output count overflow");
      seen++;
      const char *numeric = number_kind(value);
      kinds = jv_array_append(kinds, jv_string(jv_kind_name(jv_get_kind(value))));
      numbers = jv_array_append(numbers, numeric ? jv_string(numeric) : jv_null());
      wires = jv_array_append(wires, lossless_wire(jv_copy(value)));
      prefix = jv_array_append(prefix, jv_dump_string(value, 0));
    }
    if (jq_halted(jq)) {
      record = jv_object_set(record, jv_string("ok"), jv_false());
      record = jv_object_set(record, jv_string("error"),
                             jv_string("reference_unexpected_halt"));
    } else if (jv_invalid_has_msg(jv_copy(value))) {
      terminal = "runtimeError";
      jv error = jv_invalid_get_msg(jv_copy(value));
      const char *numeric = number_kind(error);
      record = jv_object_set(record, jv_string("errorWire"), lossless_wire(jv_copy(error)));
      record = jv_object_set(record, jv_string("errorValueText"), jv_dump_string(jv_copy(error), 0));
      record = jv_object_set(record, jv_string("errorValueKind"),
                             jv_string(jv_kind_name(jv_get_kind(error))));
      record = jv_object_set(record, jv_string("errorValueNumberKind"),
                             numeric ? jv_string(numeric) : jv_null());
      jv_free(error);
    } else {
      terminal = "exhausted";
    }
    jv_free(value);
  }
  if (has_expected) {
    record = jv_object_set(record, jv_string("fixtureOutputsMatch"),
                           jv_bool(matches && seen == expected_length));
  }
  record = jv_object_set(record, jv_string("terminal"), jv_string(terminal));
  record = jv_object_set(record, jv_string("outputPrefix"), prefix);
  record = jv_object_set(record, jv_string("outputKinds"), kinds);
  record = jv_object_set(record, jv_string("outputNumberKinds"), numbers);
  record = jv_object_set(record, jv_string("outputWire"), wires);
  record = jv_object_set(record, jv_string("diagnostics"), diagnostics.messages);
  jq_teardown(&jq);
  jv_free(input);
  jv_free(program_value);
  jv_free(input_value);
  jv_free(expected);
  jv_free(request);
  return record;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: reference_capture JQ MODULES < requests.ndjson\n");
    return 64;
  }
  if (!setlocale(LC_ALL, "C")) fatal("C locale unavailable");
  char *line = NULL;
  size_t capacity = 0;
  ssize_t length;
  while ((length = getline(&line, &capacity, stdin)) >= 0) {
    if (length > INT_MAX) fatal("request exceeds jq parser capacity");
    jv request = jv_parse_sized(line, (int)length);
    if (!jv_is_valid(request)) fatal("invalid request JSON");
    jv record = capture_request(request, argv[1], argv[2]);
    jv encoded = jv_dump_string(record, 0);
    size_t size = (size_t)jv_string_length_bytes(jv_copy(encoded));
    if (fwrite(jv_string_value(encoded), 1, size, stdout) != size ||
        fputc('\n', stdout) == EOF || fflush(stdout)) {
      fatal("cannot write capture record");
    }
    jv_free(encoded);
  }
  free(line);
  if (ferror(stdin)) fatal("request input read failed");
  return 0;
}
