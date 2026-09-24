#include "platform/autostart.h"

#include <windows.h>

#include "platform/log.h"

namespace glance {
namespace {

constexpr const wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kValueName[] = L"Glance";

}  // namespace

std::wstring QuotedExecutablePath() {
  wchar_t path[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, path, MAX_PATH) == 0) return {};
  std::wstring result = L"\"";
  result += path;
  result += L"\"";
  return result;
}

bool IsAutostartEnabled() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_QUERY_VALUE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  wchar_t value[MAX_PATH * 2] = {};
  DWORD size = sizeof(value);
  DWORD type = 0;
  const LONG status =
      RegQueryValueExW(key, kValueName, nullptr, &type,
                       reinterpret_cast<LPBYTE>(value), &size);
  RegCloseKey(key);
  if (status != ERROR_SUCCESS || type != REG_SZ) return false;

  // 值存在就算开——但路径可能指向旧的 exe（换过目录），这时顺手纠一下
  const std::wstring expected = QuotedExecutablePath();
  const std::wstring actual(value, size / sizeof(wchar_t));
  if (!expected.empty() && actual.find(expected) == std::wstring::npos) {
    Log(L"[autostart] 注册表里的路径与当前 exe 不一致，已重写");
    SetAutostartEnabled(true);
  }
  return true;
}

bool SetAutostartEnabled(bool enabled) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }

  bool ok = false;
  if (enabled) {
    const std::wstring command = QuotedExecutablePath();
    if (!command.empty()) {
      const DWORD bytes = static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t));
      ok = RegSetValueExW(key, kValueName, 0, REG_SZ,
                          reinterpret_cast<const BYTE*>(command.c_str()),
                          bytes) == ERROR_SUCCESS;
    }
  } else {
    const LONG status = RegDeleteValueW(key, kValueName);
    ok = (status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND);
  }
  RegCloseKey(key);
  Log(L"[autostart] set %d -> %d", enabled ? 1 : 0, ok ? 1 : 0);
  return ok;
}

}  // namespace glance
