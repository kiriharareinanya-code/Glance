// 极简日志：写 exe 同目录的 glance_native.log。
//
// 原生版没有 Flutter 那套日志设施，而 GUI 子系统没有控制台，
// 启动失败时不然就是"双击了什么都没发生"。这个文件就是排查入口。
#ifndef GLANCE_NATIVE_PLATFORM_LOG_H_
#define GLANCE_NATIVE_PLATFORM_LOG_H_

namespace glance {

void Log(const wchar_t* format, ...);

}  // namespace glance

#endif  // GLANCE_NATIVE_PLATFORM_LOG_H_
