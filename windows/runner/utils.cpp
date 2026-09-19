#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

void NeutralizeStandardStreams() {
  // 双击启动时既没有父控制台（AttachConsole 失败），通常也没有调试器，
  // 于是 libc 的标准句柄保持启动时的无效值。Dart 的 stdout/stderr 写入
  // 会以 "writeFrom failed (OS Error: 句柄无效。, errno = 6)" 的形式抛出来，
  // 冒到 runZonedGuarded 里，每次启动都在日志留下一条假错误。
  //
  // 接到 NUL 设备即可：写进去是空操作，句柄本身有效，不会再报错。
  // 已经有可用句柄时（控制台/管道/重定向）不动，保持原有输出。
  FILE *streams[3] = {stdin, stdout, stderr};
  for (int fd = 0; fd <= 2; ++fd) {
    const intptr_t h = _get_osfhandle(fd);
    if (h != -1 && h != 0) continue;
    // freopen_s 失败也没什么可做的：日志写失败不该反过来影响启动。
    FILE *unused = nullptr;
    freopen_s(&unused, "NUL", (fd == 0) ? "r" : "w", streams[fd]);
  }
}

std::vector<std::string> GetCommandLineArguments() {  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  // First, find the length of the string with a safe upper bound (CWE-126).
  // UNICODE_STRING_MAX_CHARS (32767) is the maximum length of a UNICODE_STRING.
  int input_length = static_cast<int>(wcsnlen(utf16_string, UNICODE_STRING_MAX_CHARS));
  // Now use that bounded length to determine the required buffer size.
  // When an explicit length is passed, WideCharToMultiByte does not include
  // the null terminator in its returned size.
  int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, nullptr, 0, nullptr, nullptr);
  std::string utf8_string;
  if (target_length == 0 || static_cast<size_t>(target_length) > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

HWND FindDesktopBand() {
  // 桌面图标层（SHELLDLL_DefView）绝大多数时候挂在 Progman 下；装了
  // Wallpaper Engine 这类动态壁纸软件后，shell 会把图标层挪进一个 WorkerW。
  // 磁贴要"贴着桌面走"，认的就是承载图标层的这个顶层窗口。
  const HWND progman = ::FindWindowW(L"Progman", nullptr);
  if (progman && ::FindWindowExW(progman, nullptr, L"SHELLDLL_DefView", nullptr)) {
    return progman;
  }
  HWND worker = nullptr;
  while (true) {
    worker = ::FindWindowExW(nullptr, worker, L"WorkerW", nullptr);
    if (!worker) break;
    if (::FindWindowExW(worker, nullptr, L"SHELLDLL_DefView", nullptr)) {
      return worker;
    }
  }
  // 兜底：没找到图标层就认 Progman（壁纸总画在它身上）；它也可能是 nullptr，
  // 调用方自行跳过这一拍。
  return progman;
}
