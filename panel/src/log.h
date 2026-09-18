// 面板的日志。
//
// GUI 子系统没有控制台，出问题就成了黑盒——一次例外就是"窗口一闪没了"，
// 现场什么都不留。所以面板自己写文件：exe 同目录下的 panel.log，
// 写不进去就退到 %TEMP%。同时把所有 UI 回调包在 try/catch 里，
// 让"崩了"变成"日志里有那一行"。
#pragma once

#include <windows.h>

#include <winrt/base.h>

#include <exception>
#include <string>

namespace panel {

// 日志文件路径（第一次调用时确定下来）
const std::wstring& LogPath();

void LogLine(const std::string& text);

// 把异常变成一行日志。异常类型不定，所以这里什么都接。
void LogException(const char* where, const std::exception& e);
void LogUnknownException(const char* where);
void LogHresult(const char* where, const winrt::hresult_error& e);

// 在 UI 回调里用的护栏：出了事记日志，绝不让它掀掉整个进程
template <typename Fn>
void Guard(const char* where, Fn&& fn) {
  try {
    fn();
  } catch (const winrt::hresult_error& e) {
    LogHresult(where, e);
  } catch (const std::exception& e) {
    LogException(where, e);
  } catch (...) {
    LogUnknownException(where);
  }
}

}  // namespace panel
