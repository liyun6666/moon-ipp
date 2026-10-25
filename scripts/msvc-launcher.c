/* A Unicode-preserving launcher. All compiler-adapter logic is in msvc-cl.mbtx. */
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#ifdef MOON_IPP_ARCHIVER
#define DRIVER_ROLE L"--archiver"
#else
#define DRIVER_ROLE L"--compiler"
#endif

int wmain(void) {
  wchar_t moon[32768], script[32768];
  DWORD n = GetEnvironmentVariableW(L"MOON_IPP_MOON", moon, 32768);
  if (n == 0 || n >= 32768) return 2;
  n = GetEnvironmentVariableW(L"MOON_IPP_CL_SCRIPT", script, 32768);
  if (n == 0 || n >= 32768) return 2;

  /* Keep the original argument tail verbatim, including Windows quoting. */
  const wchar_t *tail = GetCommandLineW();
  int quoted = 0;
  while (*tail && (quoted || (*tail != L' ' && *tail != L'\t'))) {
    if (*tail == L'"') quoted = !quoted;
    ++tail;
  }
  while (*tail == L' ' || *tail == L'\t') ++tail;
  size_t capacity = wcslen(moon) + wcslen(script) + wcslen(tail) + 64;
  if (capacity > 32767) return 2;
  wchar_t *command = (wchar_t *)calloc(capacity, sizeof(wchar_t));
  if (!command) return 2;
  if (swprintf_s(command, capacity,
      L"\"%ls\" run --quiet --deny-warn \"%ls\" %ls %ls", moon, script, DRIVER_ROLE, tail) < 0) {
    free(command);
    return 2;
  }

  STARTUPINFOW startup;
  PROCESS_INFORMATION process;
  ZeroMemory(&startup, sizeof(startup));
  ZeroMemory(&process, sizeof(process));
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
  startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
  startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
  if (!CreateProcessW(moon, command, NULL, NULL, TRUE, CREATE_NO_WINDOW,
      NULL, NULL, &startup, &process)) {
    free(command);
    return 2;
  }
  free(command);
  DWORD status = 1;
  if (WaitForSingleObject(process.hProcess, INFINITE) != WAIT_OBJECT_0 ||
      !GetExitCodeProcess(process.hProcess, &status)) status = 1;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return (int)status;
}
