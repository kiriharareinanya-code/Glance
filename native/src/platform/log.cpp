#include "platform/log.h"

#include <windows.h>

#include <cstdarg>
#include <cstdio>

namespace glance {
namespace {

// 用 Win32 API 而不是 CRT 的 FILE 流：本工程的 exe 是静态 CRT + GUI 子系统，
// CRT 的宽字符格式化在这里踩过一次 0xC0000409（栈检查失败）——启动第一步
// 就崩在 fwprintf 上，日志只剩个 BOM。日志是排查入口，不能自己先崩。
void WriteLine(const wchar_t* text) {
  wchar_t path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, path, MAX_PATH) == 0) return;
  wchar_t* slash = wcsrchr(path, L'\\');
  if (!slash) return;
  *(slash + 1) = L'\0';
  wcscat_s(path, L"glance_native.log");

  HANDLE file = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;

  // 写成 UTF-8：UTF-16 的日志用记事本打开没问题，但 grep/命令行工具
  // 全是乱码。BOM 只在文件为空时写一次。
  LARGE_INTEGER size = {};
  GetFileSizeEx(file, &size);

  char utf8[2048] = {};
  int written = WideCharToMultiByte(CP_UTF8, 0, text, -1, utf8,
                                    sizeof(utf8) - 1, nullptr, nullptr);
  if (written > 1) {
    DWORD ignored = 0;
    if (size.QuadPart == 0) {
      const unsigned char bom[3] = {0xEF, 0xBB, 0xBF};
      WriteFile(file, bom, 3, &ignored, nullptr);
    }
    WriteFile(file, utf8, static_cast<DWORD>(written - 1), &ignored, nullptr);
    WriteFile(file, "\r\n", 2, &ignored, nullptr);
  }
  CloseHandle(file);
}

}  // namespace

void Log(const wchar_t* format, ...) {
  wchar_t buffer[1536] = {};

  SYSTEMTIME now = {};
  GetLocalTime(&now);
  const int prefix = swprintf_s(buffer, L"%02d:%02d:%02d.%03d ", now.wHour,
                                now.wMinute, now.wSecond, now.wMilliseconds);
  if (prefix < 0) return;

  va_list args;
  va_start(args, format);
  vswprintf_s(buffer + prefix, ARRAYSIZE(buffer) - prefix, format, args);
  va_end(args);

  WriteLine(buffer);
}

}  // namespace glance
