#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

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

#endif  // RUNNER_UTILS_H_
