#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <windows.h>

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// 没有控制台可用时，把标准流接到 NUL，保证 0/1/2 三个句柄始终有效。
// 双击启动（无父控制台、也没有调试器）时句柄会指向无效值，Dart 侧往
// stdout/stderr 写就会抛 "句柄无效"（OS Error 6）。
void NeutralizeStandardStreams();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// 返回当前承载桌面图标层（SHELLDLL_DefView）的顶层窗口。绝大多数时候是
// Progman；装了动态壁纸类软件后图标层可能被挪进某个 WorkerW。磁贴要"贴着
// 桌面走"，认的就是这个窗口。找不到图标层时退回 Progman（可能为 nullptr）。
HWND FindDesktopBand();

#endif  // RUNNER_UTILS_H_
