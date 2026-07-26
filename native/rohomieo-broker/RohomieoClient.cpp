/*
 * RohomieoClient.cpp — unprivileged pipe client for RohomieoBroker service.
 *
 * Usage:
 *   rohomieo-broker-ctl.exe PING
 *   rohomieo-broker-ctl.exe FIREWALL_ADD
 *   rohomieo-broker-ctl.exe FIREWALL_REMOVE
 *   rohomieo-broker-ctl.exe DEFENDER_ADD <path>
 *   rohomieo-broker-ctl.exe DEFENDER_REMOVE <path>
 *   rohomieo-broker-ctl.exe START_HOST <exe> [args...]
 *   rohomieo-broker-ctl.exe START_SIGNALING <exe> [args...]
 *   rohomieo-broker-ctl.exe STOP_HOST
 *   rohomieo-broker-ctl.exe STOP_SIGNALING
 *   rohomieo-broker-ctl.exe KILL_ALL
 *
 * Exit 0 on OK, 1 on ERR / pipe unavailable.
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "protocol.h"

static int broker_transact(const char *request, char *response, DWORD response_cap) {
  HANDLE pipe = INVALID_HANDLE_VALUE;
  for (int i = 0; i < 50; i++) {
    pipe = CreateFileA(ROHOMIEO_BROKER_PIPE_NAME, GENERIC_READ | GENERIC_WRITE, 0,
                       NULL, OPEN_EXISTING, 0, NULL);
    if (pipe != INVALID_HANDLE_VALUE) break;
    if (GetLastError() != ERROR_PIPE_BUSY) {
      fprintf(stderr, "broker unavailable (is RohomieoBroker service running?)\n");
      return 0;
    }
    WaitNamedPipeA(ROHOMIEO_BROKER_PIPE_NAME, 1000);
  }
  if (pipe == INVALID_HANDLE_VALUE) {
    fprintf(stderr, "broker busy timeout\n");
    return 0;
  }

  DWORD mode = PIPE_READMODE_MESSAGE;
  SetNamedPipeHandleState(pipe, &mode, NULL, NULL);

  char req[ROHOMIEO_BROKER_PIPE_BUF];
  _snprintf(req, sizeof(req), "%s\n", request);
  DWORD w = 0;
  if (!WriteFile(pipe, req, (DWORD)strlen(req), &w, NULL)) {
    fprintf(stderr, "WriteFile failed: %lu\n", GetLastError());
    CloseHandle(pipe);
    return 0;
  }

  DWORD rd = 0;
  if (!ReadFile(pipe, response, response_cap - 1, &rd, NULL)) {
    fprintf(stderr, "ReadFile failed: %lu\n", GetLastError());
    CloseHandle(pipe);
    return 0;
  }
  response[rd] = 0;
  CloseHandle(pipe);
  return 1;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr,
            "Usage: %s <COMMAND> [args...]\n"
            "Commands: PING FIREWALL_ADD FIREWALL_REMOVE DEFENDER_ADD DEFENDER_REMOVE\n"
            "          START_HOST START_SIGNALING STOP_HOST STOP_SIGNALING KILL_ALL\n",
            argv[0]);
    return 1;
  }

  char request[ROHOMIEO_BROKER_PIPE_BUF];
  request[0] = 0;

  if (argc == 2) {
    strncpy(request, argv[1], sizeof(request) - 1);
  } else {
    size_t off = 0;
    for (int i = 1; i < argc; i++) {
      size_t need = strlen(argv[i]) + (i > 1 ? 1 : 0);
      if (off + need >= sizeof(request)) {
        fprintf(stderr, "command too long\n");
        return 1;
      }
      if (i > 1) request[off++] = ' ';
      memcpy(request + off, argv[i], strlen(argv[i]));
      off += strlen(argv[i]);
      request[off] = 0;
    }
  }

  char response[ROHOMIEO_BROKER_PIPE_BUF];
  if (!broker_transact(request, response, sizeof(response))) return 1;

  fputs(response, stdout);
  if (_strnicmp(response, "OK", 2) == 0) return 0;
  return 1;
}
