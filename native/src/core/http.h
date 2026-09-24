// 极简 HTTP 客户端（WinHTTP）。
//
// 用系统自带的 WinHTTP 而不是 libcurl：单 exe 的底线是零依赖，而 WinHTTP
// 走系统代理设置、支持 TLS、随 Windows 更新——桌面组件只需要 GET 一个
// JSON，够用。
//
// 注意：本模块是**阻塞**的（同步收发）。调用方负责放到后台线程，
// 别在 UI 线程上调（第一个天气请求的延迟能到秒级，会把窗口卡住）。
#ifndef GLANCE_NATIVE_CORE_HTTP_H_
#define GLANCE_NATIVE_CORE_HTTP_H_

#include <string>
#include <vector>

namespace glance {

struct HttpResult {
  bool ok = false;
  int status = 0;           // HTTP 状态码（ok=false 时也可能是 200 之外的码）
  std::string body;         // UTF-8 响应体
  std::string error;        // 失败原因（给日志和界面用）
};

// 同步 GET。headers 是 "名称: 值" 形式的多行字符串（WinHTTP 的格式）。
// timeout_ms 覆盖连接与接收两段。
HttpResult HttpGet(const std::wstring& url, const std::wstring& headers,
                   int timeout_ms);

// URL 编码（UTF-8 百分号编码），用于拼接查询参数里的中文
std::string UrlEncode(const std::string& utf8_text);

}  // namespace glance

#endif  // GLANCE_NATIVE_CORE_HTTP_H_
