// 开机自启：写当前用户的 Run 键。
//
// 用 HKCU 而不是 HKLM（不需要管理员、不污染其他用户），也不用计划任务
// （桌面组件没那个必要）。键名固定，卸载时自己删得掉。
#ifndef GLANCE_NATIVE_PLATFORM_AUTOSTART_H_
#define GLANCE_NATIVE_PLATFORM_AUTOSTART_H_

#include <string>

namespace glance {

// 当前 exe 的完整路径（带引号，路径里有空格时注册表里必须带引号）
std::wstring QuotedExecutablePath();

// 是否已经设了开机自启
bool IsAutostartEnabled();

// 开关开机自启。返回是否成功。
bool SetAutostartEnabled(bool enabled);

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_AUTOSTART_H_
