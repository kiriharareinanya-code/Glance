#include "ipc.h"

#include <winsock2.h>  // 顺序要紧：afunix.h 依赖 winsock2 的声明
#include <ws2tcpip.h>

#include <afunix.h>

#include <cstring>

#include "text.h"

namespace panel {
namespace {

constexpr size_t kSunPathMax = sizeof(sockaddr_un::sun_path) - 1;

bool EnsureWinsock() {
  static const bool ok = [] {
    WSADATA data{};
    return ::WSAStartup(MAKEWORD(2, 2), &data) == 0;
  }();
  return ok;
}

}  // namespace

PanelClient::~PanelClient() { Close(); }

bool PanelClient::Connect(const std::string& socket_path,
                          const std::string& token, std::string* error) {
  auto fail = [&](const std::string& why) {
    if (error) *error = why;
    Close();
    return false;
  };

  if (!EnsureWinsock()) return fail("Winsock 初始化失败");

  const std::string ansi = AnsiFromWide(WideFromUtf8(socket_path));
  if (ansi.size() > kSunPathMax) {
    return fail("socket 路径太长（AF_UNIX 上限 108 字节）");
  }

  SOCKET s = ::socket(AF_UNIX, SOCK_STREAM, 0);
  if (s == INVALID_SOCKET) return fail("建 socket 失败 err=" + std::to_string(::WSAGetLastError()));

  sockaddr_un addr{};
  addr.sun_family = AF_UNIX;
  std::memcpy(addr.sun_path, ansi.c_str(), ansi.size());

  if (::connect(s, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) ==
      SOCKET_ERROR) {
    const int err = ::WSAGetLastError();
    ::closesocket(s);
    return fail("连不上核心 err=" + std::to_string(err) +
                "（核心在跑吗？它启动时会把端点写进 userdata\\panel-ipc.json）");
  }

  sock_ = static_cast<intptr_t>(s);
  running_.store(true);
  reader_ = std::thread([this] { ReaderLoop(); });

  // ---- 握手 ----
  // 用同步等待：握手不成功后面全白搭，而且它必须在第一条消息位置。
  std::mutex mu;
  std::condition_variable cv;
  bool done = false;
  PanelResult result;

  Json params = Json::Object();
  params.set("protocol", Json(kProtocolVersion));
  params.set("token", Json(token));
  Call(kMethodHello, std::move(params), [&](const PanelResult& r) {
    {
      std::lock_guard<std::mutex> lock(mu);
      result = r;
      done = true;
    }
    cv.notify_one();
  });

  {
    std::unique_lock<std::mutex> lock(mu);
    if (!cv.wait_for(lock, std::chrono::seconds(5), [&] { return done; })) {
      return fail("握手超时（核心没回应 hello）");
    }
  }
  if (!result.ok) {
    std::string why = "握手被拒：" + result.error_code;
    if (!result.error_msg.empty()) why += " —— " + result.error_msg;
    return fail(why);
  }

  core_version_ = result.value.str("core", "");
  if (result.value["core"].is_object()) {
    core_version_ = result.value["core"].str("version");
    core_display_version_ = result.value["core"].str("displayVersion");
  }
  return true;
}

void PanelClient::Close() {
  if (!running_.exchange(false)) {
    if (sock_ != -1) {
      ::closesocket(static_cast<SOCKET>(sock_));
      sock_ = -1;
    }
    return;
  }
  if (sock_ != -1) {
    ::shutdown(static_cast<SOCKET>(sock_), SD_BOTH);
    ::closesocket(static_cast<SOCKET>(sock_));
    sock_ = -1;
  }
  if (reader_.joinable()) reader_.join();

  // 还挂着的请求全部以"核心走了"收尾，UI 才不会卡在加载中
  std::map<int, Callback> pending;
  {
    std::lock_guard<std::mutex> lock(pending_mu_);
    pending.swap(pending_);
  }
  PanelResult gone;
  gone.error_code = "core_gone";
  gone.error_msg = "与核心的连接已断开";
  for (auto& kv : pending) {
    if (kv.second) kv.second(gone);
  }
}

void PanelClient::Call(const std::string& method, Json params, Callback cb) {
  if (!running_.load() || sock_ == -1) {
    if (cb) {
      PanelResult r;
      r.error_code = "core_gone";
      r.error_msg = "还没连上核心";
      cb(r);
    }
    return;
  }

  int id = 0;
  {
    std::lock_guard<std::mutex> lock(pending_mu_);
    id = ++seq_;
    pending_[id] = std::move(cb);
  }

  Json msg = Json::Object();
  msg.set("id", Json(id));
  msg.set("m", Json(method));
  msg.set("p", std::move(params));
  const std::string line = msg.dump() + "\n";

  std::lock_guard<std::mutex> lock(write_mu_);
  const char* p = line.data();
  size_t left = line.size();
  while (left > 0) {
    const int n = ::send(static_cast<SOCKET>(sock_), p, static_cast<int>(left), 0);
    if (n <= 0) {
      running_.store(false);
      return;
    }
    p += n;
    left -= static_cast<size_t>(n);
  }
}

void PanelClient::ReaderLoop() {
  std::string tail;
  char buf[8192];

  while (running_.load()) {
    const int n = ::recv(static_cast<SOCKET>(sock_), buf, sizeof(buf), 0);
    if (n <= 0) break;  // 0 = 对端关闭
    tail.append(buf, static_cast<size_t>(n));

    size_t pos = 0;
    while (true) {
      const size_t nl = tail.find('\n', pos);
      if (nl == std::string::npos) break;
      const std::string line = tail.substr(pos, nl - pos);
      pos = nl + 1;

      if (line.empty()) continue;
      std::string err;
      Json msg = Json::Parse(line, &err);
      if (!msg.is_object()) continue;  // 认不出的行直接跳过，别把连接搞死

      // 事件：没有 id，有 e
      if (msg.has("e")) {
        const std::string name = msg.str("e");
        EventHandler h;
        h = on_event_;
        if (h) h(name, msg["p"]);
        continue;
      }

      const int id = msg["id"].as_int(-1);
      Callback cb;
      {
        std::lock_guard<std::mutex> lock(pending_mu_);
        auto it = pending_.find(id);
        if (it != pending_.end()) {
          cb = std::move(it->second);
          pending_.erase(it);
        }
      }
      if (!cb) continue;

      PanelResult r;
      r.ok = msg.flag("ok");
      if (r.ok) {
        r.value = msg["r"];
      } else {
        r.error_code = msg["err"].str("code", "internal");
        r.error_msg = msg["err"].str("msg");
      }
      cb(r);
    }
    if (pos > 0) tail.erase(0, pos);
  }

  running_.store(false);
}

}  // namespace panel
