#include "log.h"

#include <cstdio>
#include <ctime>
#include <mutex>
#include <vector>

#include "text.h"

namespace panel {
namespace {

std::mutex g_mutex;
bool g_resolved = false;
std::wstring g_path;

std::wstring ExeDir() {
  wchar_t buf[MAX_PATH]{};
  const DWORD n = ::GetModuleFileNameW(nullptr, buf, MAX_PATH);
  std::wstring path(buf, n);
  const size_t slash = path.find_last_of(L'\\');
  return slash == std::wstring::npos ? L"." : path.substr(0, slash);
}

std::wstring TempDir() {
  wchar_t buf[MAX_PATH]{};
  const DWORD n = ::GetTempPathW(MAX_PATH, buf);
  return std::wstring(buf, n);
}

bool CanWrite(const std::wstring& path) {
  HANDLE h = ::CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                           nullptr);
  if (h == INVALID_HANDLE_VALUE) return false;
  ::CloseHandle(h);
  return true;
}

std::string Now() {
  std::time_t t = std::time(nullptr);
  std::tm tm{};
  localtime_s(&tm, &t);
  char buf[32];
  std::snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d",
                tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour,
                tm.tm_min, tm.tm_sec);
  return buf;
}

}  // namespace

const std::wstring& LogPath() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (!g_resolved) {
    g_resolved = true;
    // 优先写 exe 同目录（好找）；目录只读之类就退到临时目录
    const std::wstring near_exe = ExeDir() + L"\\panel.log";
    g_path = CanWrite(near_exe) ? near_exe : TempDir() + L"glance-panel.log";
  }
  return g_path;
}

void LogLine(const std::string& text) {
  const std::wstring path = LogPath();
  const std::string line = Now() + " " + text + "\r\n";

  std::lock_guard<std::mutex> lock(g_mutex);
  HANDLE h = ::CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                           nullptr);
  if (h == INVALID_HANDLE_VALUE) return;
  DWORD written = 0;
  // 直接写 UTF-8 字节：核心的日志也是这套编码，两边看着一致
  ::WriteFile(h, line.data(), static_cast<DWORD>(line.size()), &written,
              nullptr);
  ::CloseHandle(h);
}

void LogException(const char* where, const std::exception& e) {
  LogLine(std::string("E [") + where + "] 异常：" + e.what());
}

void LogUnknownException(const char* where) {
  LogLine(std::string("E [") + where + "] 未知异常");
}

void LogHresult(const char* where, const winrt::hresult_error& e) {
  char code[32];
  std::snprintf(code, sizeof(code), "0x%08X",
                static_cast<unsigned>(e.code().value));
  LogLine(std::string("E [") + where + "] HRESULT " + code + "：" +
          Utf8FromWide(e.message().c_str()));
}

}  // namespace panel
