#include "core/http.h"

#include <windows.h>
#include <winhttp.h>

#include <cstdio>

#include "platform/log.h"

namespace glance {
namespace {

std::wstring StatusText(DWORD error) {
  wchar_t buffer[256] = {};
  swprintf_s(buffer, L"WinHTTP error %lu", error);
  return buffer;
}

}  // namespace

std::string UrlEncode(const std::string& utf8_text) {
  static const char* kHex = "0123456789ABCDEF";
  std::string out;
  out.reserve(utf8_text.size() * 3);
  for (const unsigned char c : utf8_text) {
    // 保留未保留字符：字母数字与 -_.~
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
      out.push_back(static_cast<char>(c));
    } else {
      out.push_back('%');
      out.push_back(kHex[c >> 4]);
      out.push_back(kHex[c & 0x0F]);
    }
  }
  return out;
}

HttpResult HttpGet(const std::wstring& url, const std::wstring& headers,
                   int timeout_ms) {
  HttpResult result;

  // 解析 URL（WinHttpCrackUrl 要求可写缓冲）
  std::vector<wchar_t> url_buffer(url.begin(), url.end());
  url_buffer.push_back(L'\0');
  URL_COMPONENTS parts = {};
  parts.dwStructSize = sizeof(parts);
  parts.dwSchemeLength = static_cast<DWORD>(-1);
  parts.dwHostNameLength = static_cast<DWORD>(-1);
  parts.dwUrlPathLength = static_cast<DWORD>(-1);
  parts.dwExtraInfoLength = static_cast<DWORD>(-1);
  if (!WinHttpCrackUrl(url_buffer.data(), 0, 0, &parts)) {
    result.error = "URL 解析失败";
    return result;
  }

  const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  std::wstring path(parts.lpszUrlPath, parts.dwUrlPathLength);
  if (parts.dwExtraInfoLength > 0) {
    path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
  }
  const bool https = parts.nScheme == INTERNET_SCHEME_HTTPS;

  HINTERNET session = WinHttpOpen(
      L"Glance/0.2.127 (Windows; native)", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (session == nullptr) {
    result.error = "WinHttpOpen 失败";
    return result;
  }
  WinHttpSetTimeouts(session, timeout_ms, timeout_ms, timeout_ms, timeout_ms);

  HINTERNET connect =
      WinHttpConnect(session, host.c_str(), parts.nPort, 0);
  if (connect == nullptr) {
    result.error = "连接失败";
    WinHttpCloseHandle(session);
    return result;
  }

  HINTERNET request = WinHttpOpenRequest(
      connect, L"GET", path.c_str(), nullptr, WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES, https ? WINHTTP_FLAG_SECURE : 0);
  if (request == nullptr) {
    result.error = "创建请求失败";
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    return result;
  }

  const wchar_t* header_ptr =
      headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.c_str();
  const DWORD header_len = headers.empty() ? 0 : static_cast<DWORD>(headers.size());

  BOOL sent = WinHttpSendRequest(request, header_ptr, header_len,
                                 WINHTTP_NO_REQUEST_DATA, 0, 0, 0);
  if (sent) sent = WinHttpReceiveResponse(request, nullptr);
  if (!sent) {
    result.error = "请求失败（超时或网络不可达）";
  } else {
    DWORD status = 0;
    DWORD status_size = sizeof(status);
    WinHttpQueryHeaders(request,
                        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                        WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
                        WINHTTP_NO_HEADER_INDEX);
    result.status = static_cast<int>(status);

    std::string body;
    DWORD available = 0;
    do {
      available = 0;
      if (!WinHttpQueryDataAvailable(request, &available)) break;
      if (available == 0) break;
      // 单次响应上限 4MB：天气/歌词 JSON 都很小，防的是异常服务端把内存打满
      if (body.size() + available > 4 * 1024 * 1024) break;
      std::string chunk(available, '\0');
      DWORD read = 0;
      if (!WinHttpReadData(request, chunk.data(), available, &read)) break;
      chunk.resize(read);
      body += chunk;
    } while (available > 0);

    result.body = std::move(body);
    result.ok = (status == 200) && !result.body.empty();
    if (status != 200) {
      result.error = "HTTP " + std::to_string(status);
    }
  }

  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);
  return result;
}

}  // namespace glance
