/*
 * RohomieoBrokerService.cpp — LocalSystem elevated broker (official service pattern).
 *
 * Installed once with UAC via install-broker.ps1. Listens on \\.\pipe\RohomieoBroker
 * and performs firewall / Defender / process start-stop on behalf of the interactive user.
 *
 * Build (WSL MinGW):  make -C native/rohomieo-broker
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <winsvc.h>
#include <wtsapi32.h>
#include <userenv.h>
#include <sddl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#include "protocol.h"

#pragma comment(lib, "advapi32")
#pragma comment(lib, "wtsapi32")
#pragma comment(lib, "userenv")

static SERVICE_STATUS_HANDLE g_status_handle = NULL;
static SERVICE_STATUS g_status;
static HANDLE g_stop_event = NULL;
static HANDLE g_pipe_thread = NULL;
static volatile LONG g_running = 0;

static char g_log_path[MAX_PATH] = {0};

static void log_line(const char *msg) {
  SYSTEMTIME st;
  GetLocalTime(&st);
  char line[1024];
  _snprintf(line, sizeof(line), "%04d-%02d-%02dT%02d:%02d:%02d %s\r\n",
            st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, msg);
  HANDLE h = CreateFileA(g_log_path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
                         OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (h != INVALID_HANDLE_VALUE) {
    DWORD w = 0;
    WriteFile(h, line, (DWORD)strlen(line), &w, NULL);
    CloseHandle(h);
  }
}

static void set_status(DWORD state, DWORD exit_code, DWORD wait_hint) {
  g_status.dwCurrentState = state;
  g_status.dwWin32ExitCode = exit_code;
  g_status.dwWaitHint = wait_hint;
  g_status.dwControlsAccepted =
      (state == SERVICE_START_PENDING) ? 0 : (SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN);
  if (state == SERVICE_RUNNING || state == SERVICE_STOPPED)
    g_status.dwCheckPoint = 0;
  else
    g_status.dwCheckPoint++;
  SetServiceStatus(g_status_handle, &g_status);
}

static DWORD WINAPI ctrl_handler(DWORD ctrl, DWORD ev, LPVOID data, LPVOID ctx) {
  (void)ev;
  (void)data;
  (void)ctx;
  if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
    set_status(SERVICE_STOP_PENDING, NO_ERROR, 5000);
    InterlockedExchange(&g_running, 0);
    if (g_stop_event) SetEvent(g_stop_event);
    return NO_ERROR;
  }
  return ERROR_CALL_NOT_IMPLEMENTED;
}

/* --- helpers --- */

static int run_hidden(const char *app, const char *cmdline) {
  STARTUPINFOA si;
  PROCESS_INFORMATION pi;
  char *cmd = _strdup(cmdline);
  if (!cmd) return 0;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  si.dwFlags = STARTF_USESHOWWINDOW;
  si.wShowWindow = SW_HIDE;
  ZeroMemory(&pi, sizeof(pi));
  BOOL ok = CreateProcessA(app, cmd, NULL, NULL, FALSE,
                           CREATE_NO_WINDOW, NULL, NULL, &si, &pi);
  free(cmd);
  if (!ok) return 0;
  WaitForSingleObject(pi.hProcess, 60000);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return code == 0;
}

static int path_is_under_run_dir(const char *path) {
  char local[MAX_PATH];
  char allowed[MAX_PATH];
  char full[MAX_PATH];
  DWORD n = GetEnvironmentVariableA("LOCALAPPDATA", local, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    /* Service has empty LOCALAPPDATA — resolve via active user profile. */
    DWORD sid = WTSGetActiveConsoleSessionId();
    HANDLE tok = NULL;
    if (sid == 0xFFFFFFFF || !WTSQueryUserToken(sid, &tok)) return 0;
    char *env = NULL;
    if (!CreateEnvironmentBlock((LPVOID *)&env, tok, FALSE)) {
      CloseHandle(tok);
      return 0;
    }
    local[0] = 0;
    for (char *p = env; *p; p += strlen(p) + 1) {
      if (_strnicmp(p, "LOCALAPPDATA=", 13) == 0) {
        strncpy(local, p + 13, MAX_PATH - 1);
        local[MAX_PATH - 1] = 0;
        break;
      }
    }
    DestroyEnvironmentBlock(env);
    CloseHandle(tok);
    if (!local[0]) return 0;
  }
  _snprintf(allowed, sizeof(allowed), "%s\\rohomieo-run", local);
  if (!GetFullPathNameA(path, MAX_PATH, full, NULL)) return 0;
  size_t alen = strlen(allowed);
  if (_strnicmp(full, allowed, alen) != 0) return 0;
  if (full[alen] != '\\' && full[alen] != '\0') return 0;
  return 1;
}

static int basename_ok(const char *path, const char *expect) {
  const char *base = strrchr(path, '\\');
  base = base ? base + 1 : path;
  return _stricmp(base, expect) == 0;
}

static void kill_image(const char *exe_name) {
  char cmd[512];
  _snprintf(cmd, sizeof(cmd),
            "C:\\Windows\\System32\\cmd.exe /c "
            "C:\\Windows\\System32\\taskkill.exe /F /IM %s /T >nul 2>&1",
            exe_name);
  run_hidden("C:\\Windows\\System32\\cmd.exe", cmd);
}

/* Launch in the interactive user's session (MSDN: WTSQueryUserToken). */
static int start_in_user_session(const char *exe, char *cmdline) {
  DWORD session = WTSGetActiveConsoleSessionId();
  if (session == 0xFFFFFFFF) {
    log_line("ERR no active console session");
    return 0;
  }
  HANDLE user_token = NULL;
  if (!WTSQueryUserToken(session, &user_token)) {
    log_line("ERR WTSQueryUserToken failed");
    return 0;
  }
  HANDLE primary = NULL;
  if (!DuplicateTokenEx(user_token, MAXIMUM_ALLOWED, NULL, SecurityIdentification,
                        TokenPrimary, &primary)) {
    CloseHandle(user_token);
    log_line("ERR DuplicateTokenEx failed");
    return 0;
  }
  CloseHandle(user_token);

  LPVOID env = NULL;
  if (!CreateEnvironmentBlock(&env, primary, FALSE)) {
    CloseHandle(primary);
    log_line("ERR CreateEnvironmentBlock failed");
    return 0;
  }

  wchar_t wexe[MAX_PATH];
  wchar_t wcmd[ROHOMIEO_BROKER_PIPE_BUF];
  MultiByteToWideChar(CP_ACP, 0, exe, -1, wexe, MAX_PATH);
  MultiByteToWideChar(CP_ACP, 0, cmdline, -1, wcmd, ROHOMIEO_BROKER_PIPE_BUF);

  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  ZeroMemory(&si, sizeof(si));
  si.cb = sizeof(si);
  si.lpDesktop = (LPWSTR)L"winsta0\\default";
  ZeroMemory(&pi, sizeof(pi));

  BOOL ok = CreateProcessAsUserW(
      primary, wexe, wcmd, NULL, NULL, FALSE,
      CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE, env, NULL, &si, &pi);

  DestroyEnvironmentBlock(env);
  CloseHandle(primary);

  if (!ok) {
    char buf[128];
    _snprintf(buf, sizeof(buf), "ERR CreateProcessAsUser %lu", GetLastError());
    log_line(buf);
    return 0;
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return 1;
}

static int path_is_rohomieo_run_target(const char *path) {
  char full[MAX_PATH];
  if (!GetFullPathNameA(path, MAX_PATH, full, NULL)) return 0;
  if (path_is_under_run_dir(full)) return 1;
  /* Exact directory ...\rohomieo-run */
  size_t n = strlen(full);
  const char *suf = "rohomieo-run";
  size_t s = strlen(suf);
  if (n >= s && _stricmp(full + n - s, suf) == 0) {
    if (n == s || full[n - s - 1] == '\\') return 1;
  }
  return 0;
}

static int firewall_add(void) {
  char cmd[512];
  const char *netsh = "C:\\Windows\\System32\\netsh.exe";
  _snprintf(cmd, sizeof(cmd),
            "%s advfirewall firewall delete rule name=\"%s\"", netsh,
            ROHOMIEO_FIREWALL_RULE_NAME);
  run_hidden(netsh, cmd);
  _snprintf(cmd, sizeof(cmd),
            "%s advfirewall firewall add rule name=\"%s\" dir=in action=allow "
            "protocol=TCP localport=%s profile=any",
            netsh, ROHOMIEO_FIREWALL_RULE_NAME, ROHOMIEO_FIREWALL_PORT);
  return run_hidden(netsh, cmd);
}

static int firewall_remove(void) {
  char cmd[512];
  const char *netsh = "C:\\Windows\\System32\\netsh.exe";
  _snprintf(cmd, sizeof(cmd),
            "%s advfirewall firewall delete rule name=\"%s\"", netsh,
            ROHOMIEO_FIREWALL_RULE_NAME);
  run_hidden(netsh, cmd);
  return 1;
}

static int defender_exclude(const char *path, int add) {
  if (add && !path_is_rohomieo_run_target(path)) return 0;
  if (!add && !path_is_rohomieo_run_target(path)) return 0;

  char cmd[1024];
  const char *ps =
      "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
  if (add) {
    _snprintf(cmd, sizeof(cmd),
              "%s -NoProfile -ExecutionPolicy Bypass -Command "
              "\"Add-MpPreference -ExclusionPath '%s'\"",
              ps, path);
  } else {
    _snprintf(cmd, sizeof(cmd),
              "%s -NoProfile -ExecutionPolicy Bypass -Command "
              "\"Remove-MpPreference -ExclusionPath '%s'\"",
              ps, path);
  }
  return run_hidden(ps, cmd);
}

static void reply(HANDLE pipe, const char *msg) {
  DWORD w = 0;
  WriteFile(pipe, msg, (DWORD)strlen(msg), &w, NULL);
}

static void handle_line(HANDLE pipe, char *line) {
  /* trim CR */
  size_t n = strlen(line);
  while (n && (line[n - 1] == '\r' || line[n - 1] == '\n')) line[--n] = 0;
  if (!n) {
    reply(pipe, "ERR empty\n");
    return;
  }

  char logbuf[512];
  _snprintf(logbuf, sizeof(logbuf), "cmd: %s", line);
  log_line(logbuf);

  if (_stricmp(line, "PING") == 0) {
    reply(pipe, "OK\n");
    return;
  }
  if (_stricmp(line, "FIREWALL_ADD") == 0) {
    reply(pipe, firewall_add() ? "OK\n" : "ERR firewall add failed\n");
    return;
  }
  if (_stricmp(line, "FIREWALL_REMOVE") == 0) {
    reply(pipe, firewall_remove() ? "OK\n" : "ERR firewall remove failed\n");
    return;
  }
  if (_stricmp(line, "STOP_HOST") == 0) {
    kill_image("rohomieo-host.exe");
    reply(pipe, "OK\n");
    return;
  }
  if (_stricmp(line, "STOP_SIGNALING") == 0) {
    kill_image("rohomieo-signaling.exe");
    reply(pipe, "OK\n");
    return;
  }
  if (_stricmp(line, "KILL_ALL") == 0) {
    kill_image("rohomieo-host.exe");
    kill_image("rohomieo-signaling.exe");
    reply(pipe, "OK\n");
    return;
  }

  if (_strnicmp(line, "DEFENDER_ADD ", 13) == 0) {
    const char *p = line + 13;
    while (*p == ' ') p++;
    reply(pipe, defender_exclude(p, 1) ? "OK\n" : "ERR defender add rejected/failed\n");
    return;
  }
  if (_strnicmp(line, "DEFENDER_REMOVE ", 16) == 0) {
    const char *p = line + 16;
    while (*p == ' ') p++;
    reply(pipe, defender_exclude(p, 0) ? "OK\n" : "ERR defender remove failed\n");
    return;
  }

  int is_host = _strnicmp(line, "START_HOST ", 11) == 0;
  int is_sig = _strnicmp(line, "START_SIGNALING ", 16) == 0;
  if (is_host || is_sig) {
    char *rest = line + (is_host ? 11 : 16);
    while (*rest == ' ') rest++;
    char exe[MAX_PATH];
    char *sp = strchr(rest, ' ');
    if (sp) {
      size_t el = (size_t)(sp - rest);
      if (el >= MAX_PATH) {
        reply(pipe, "ERR path too long\n");
        return;
      }
      memcpy(exe, rest, el);
      exe[el] = 0;
    } else {
      strncpy(exe, rest, MAX_PATH - 1);
      exe[MAX_PATH - 1] = 0;
      sp = rest + strlen(rest);
    }
    const char *expect = is_host ? "rohomieo-host.exe" : "rohomieo-signaling.exe";
    if (!path_is_under_run_dir(exe) || !basename_ok(exe, expect)) {
      reply(pipe, "ERR path not allowed (must be under %%LOCALAPPDATA%%\\rohomieo-run)\n");
      return;
    }
    /* Build: "exe" args... */
    char cmdline[ROHOMIEO_BROKER_PIPE_BUF];
    if (*sp) {
      _snprintf(cmdline, sizeof(cmdline), "\"%s\"%s", exe, sp);
    } else {
      _snprintf(cmdline, sizeof(cmdline), "\"%s\"", exe);
    }
    reply(pipe, start_in_user_session(exe, cmdline) ? "OK\n" : "ERR start failed\n");
    return;
  }

  reply(pipe, "ERR unknown command\n");
}

static DWORD WINAPI pipe_server(LPVOID param) {
  (void)param;
  /* SYSTEM + Interactive Users can connect. No world-writable. */
  PSECURITY_DESCRIPTOR sd = NULL;
  if (!ConvertStringSecurityDescriptorToSecurityDescriptorA(
          "D:(A;;GA;;;SY)(A;;GRGW;;;IU)(A;;GRGW;;;BA)",
          SDDL_REVISION_1, &sd, NULL)) {
    log_line("ERR SDDL convert failed");
    return 1;
  }
  SECURITY_ATTRIBUTES sa;
  sa.nLength = sizeof(sa);
  sa.lpSecurityDescriptor = sd;
  sa.bInheritHandle = FALSE;

  while (InterlockedCompareExchange(&g_running, 1, 1)) {
    HANDLE pipe = CreateNamedPipeA(
        ROHOMIEO_BROKER_PIPE_NAME, PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
        1, ROHOMIEO_BROKER_PIPE_BUF, ROHOMIEO_BROKER_PIPE_BUF, 0, &sa);
    if (pipe == INVALID_HANDLE_VALUE) {
      Sleep(500);
      continue;
    }
    /* Overlap stop with ConnectNamedPipe via wait on stop event in another
       thread is complex; poll by using a short connect timeout pattern —
       ConnectNamedPipe blocks, so also watch stop via APC-free approach:
       cancel by closing from stop handler is hard. Use PIPE wait + check. */
    BOOL connected = ConnectNamedPipe(pipe, NULL)
                         ? TRUE
                         : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (!InterlockedCompareExchange(&g_running, 1, 1)) {
      CloseHandle(pipe);
      break;
    }
    if (connected) {
      char buf[ROHOMIEO_BROKER_PIPE_BUF];
      DWORD rd = 0;
      if (ReadFile(pipe, buf, sizeof(buf) - 1, &rd, NULL) && rd > 0) {
        buf[rd] = 0;
        handle_line(pipe, buf);
      } else {
        reply(pipe, "ERR read failed\n");
      }
      FlushFileBuffers(pipe);
      DisconnectNamedPipe(pipe);
    }
    CloseHandle(pipe);
  }

  LocalFree(sd);
  return 0;
}

static void WINAPI service_main(DWORD argc, LPSTR *argv) {
  (void)argc;
  (void)argv;
  g_status_handle =
      RegisterServiceCtrlHandlerExA(ROHOMIEO_BROKER_SERVICE_NAME, ctrl_handler, NULL);
  if (!g_status_handle) return;

  ZeroMemory(&g_status, sizeof(g_status));
  g_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  set_status(SERVICE_START_PENDING, NO_ERROR, 3000);

  char progdata[MAX_PATH];
  if (GetEnvironmentVariableA("PROGRAMDATA", progdata, MAX_PATH) == 0)
    strcpy(progdata, "C:\\ProgramData");
  char dir[MAX_PATH];
  _snprintf(dir, sizeof(dir), "%s\\Rohomieo", progdata);
  CreateDirectoryA(dir, NULL);
  _snprintf(g_log_path, sizeof(g_log_path), "%s\\broker.log", dir);

  g_stop_event = CreateEventA(NULL, TRUE, FALSE, NULL);
  InterlockedExchange(&g_running, 1);
  g_pipe_thread = CreateThread(NULL, 0, pipe_server, NULL, 0, NULL);

  log_line("service running");
  set_status(SERVICE_RUNNING, NO_ERROR, 0);

  WaitForSingleObject(g_stop_event, INFINITE);

  InterlockedExchange(&g_running, 0);
  /* Unblock ConnectNamedPipe by connecting once as client. */
  HANDLE wake = CreateFileA(ROHOMIEO_BROKER_PIPE_NAME, GENERIC_READ | GENERIC_WRITE, 0,
                            NULL, OPEN_EXISTING, 0, NULL);
  if (wake != INVALID_HANDLE_VALUE) CloseHandle(wake);
  if (g_pipe_thread) {
    WaitForSingleObject(g_pipe_thread, 5000);
    CloseHandle(g_pipe_thread);
  }
  if (g_stop_event) CloseHandle(g_stop_event);
  log_line("service stopped");
  set_status(SERVICE_STOPPED, NO_ERROR, 0);
}

int main(int argc, char **argv) {
  (void)argc;
  (void)argv;
  SERVICE_TABLE_ENTRYA table[] = {
      {(LPSTR)ROHOMIEO_BROKER_SERVICE_NAME, service_main},
      {NULL, NULL},
  };
  if (!StartServiceCtrlDispatcherA(table)) {
    /* Not started by SCM — print brief help for operators. */
    fprintf(stderr,
            "RohomieoBroker: install with scripts/windows/install-broker.ps1 (Admin).\n"
            "This binary is a Windows service; do not run it interactively.\n");
    return 1;
  }
  return 0;
}
