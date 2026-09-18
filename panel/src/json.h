// 极简 JSON：够用就好，够用是指"能把面板协议说清楚"。
//
// 为什么不用 nlohmann：这台机器上 github 拉不动，而为了一个网络问题去引
// 第三方依赖不值当。协议里只有对象/数组/字符串/数字/布尔/null 六种东西，
// 自己实现一两百行完全可控，也不用担心许可与版本。
//
// 关于对象：**保留插入顺序**（用 vector<pair>）。面板要把 schema 原样转发
// 或拼请求体，顺序稳定读日志时省事。
#pragma once

#include <cmath>
#include <cstdint>
#include <map>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace panel {

class Json {
 public:
  enum class Type { Null, Bool, Number, String, Array, Object };

  Json() = default;
  Json(std::nullptr_t) {}
  Json(bool b) : type_(Type::Bool), bool_(b) {}
  Json(double d) : type_(Type::Number), num_(d) {}
  Json(int i) : type_(Type::Number), num_(static_cast<double>(i)) {}
  Json(int64_t i) : type_(Type::Number), num_(static_cast<double>(i)) {}
  Json(const char* s) : type_(Type::String), str_(s ? s : "") {}
  Json(std::string s) : type_(Type::String), str_(std::move(s)) {}

  static Json Object() {
    Json j;
    j.type_ = Type::Object;
    return j;
  }
  static Json Array() {
    Json j;
    j.type_ = Type::Array;
    return j;
  }

  Type type() const { return type_; }
  bool is_null() const { return type_ == Type::Null; }
  bool is_bool() const { return type_ == Type::Bool; }
  bool is_number() const { return type_ == Type::Number; }
  bool is_string() const { return type_ == Type::String; }
  bool is_array() const { return type_ == Type::Array; }
  bool is_object() const { return type_ == Type::Object; }

  bool as_bool(bool fallback = false) const {
    return type_ == Type::Bool ? bool_ : fallback;
  }
  double as_double(double fallback = 0) const {
    return type_ == Type::Number ? num_ : fallback;
  }
  int as_int(int fallback = 0) const {
    return type_ == Type::Number ? static_cast<int>(std::llround(num_))
                                 : fallback;
  }
  // 数字在 JSON 里可能是 3 / 3.0 / "3"，面板都当数字用
  double num_or(double fallback) const {
    if (type_ == Type::Number) return num_;
    if (type_ == Type::String) {
      try {
        return std::stod(str_);
      } catch (...) {
      }
    }
    return fallback;
  }
  std::string as_string(const std::string& fallback = {}) const {
    return type_ == Type::String ? str_ : fallback;
  }

  const std::vector<Json>& items() const { return arr_; }
  // 对象用 pairs()：items() 是数组专用（放一起会静默拿到空列表）
  const std::vector<std::pair<std::string, Json>>& pairs() const {
    return obj_;
  }
  size_t size() const {
    return type_ == Type::Array ? arr_.size()
                                : (type_ == Type::Object ? obj_.size() : 0);
  }

  // ---- 取值 ----
  // 找不到返回一个空的（Null）Json，链式调用不会崩
  const Json& operator[](const std::string& key) const {
    static const Json kNull;
    if (type_ != Type::Object) return kNull;
    for (const auto& kv : obj_) {
      if (kv.first == key) return kv.second;
    }
    return kNull;
  }
  const Json& operator[](size_t i) const {
    static const Json kNull;
    return (type_ == Type::Array && i < arr_.size()) ? arr_[i] : kNull;
  }
  bool has(const std::string& key) const {
    if (type_ != Type::Object) return false;
    for (const auto& kv : obj_) {
      if (kv.first == key) return true;
    }
    return false;
  }
  std::string str(const std::string& key, const std::string& fallback = {}) const {
    return (*this)[key].as_string(fallback);
  }
  double num(const std::string& key, double fallback = 0) const {
    return (*this)[key].num_or(fallback);
  }
  bool flag(const std::string& key, bool fallback = false) const {
    const Json& v = (*this)[key];
    return v.is_bool() ? v.as_bool() : fallback;
  }

  // ---- 构造 ----
  Json& set(const std::string& key, Json value) {
    if (type_ != Type::Object) {
      type_ = Type::Object;
      obj_.clear();
    }
    for (auto& kv : obj_) {
      if (kv.first == key) {
        kv.second = std::move(value);
        return *this;
      }
    }
    obj_.emplace_back(key, std::move(value));
    return *this;
  }
  void push(Json value) {
    if (type_ != Type::Array) {
      type_ = Type::Array;
      arr_.clear();
    }
    arr_.push_back(std::move(value));
  }

  // ---- 序列化 ----
  std::string dump() const {
    std::string out;
    write(out);
    return out;
  }

  // ---- 解析。失败返回 Null 并填 error ----
  static Json Parse(const std::string& text, std::string* error = nullptr) {
    Parser p{text};
    Json j = p.ParseValue();
    if (p.bad) {
      if (error) *error = p.error;
      return Json();
    }
    p.SkipWs();
    if (!p.AtEnd()) {
      if (error) *error = "末尾有多余内容";
      return Json();
    }
    return j;
  }

 private:
  Type type_ = Type::Null;
  bool bool_ = false;
  double num_ = 0;
  std::string str_;
  std::vector<Json> arr_;
  std::vector<std::pair<std::string, Json>> obj_;

  static void write_string(std::string& out, const std::string& s) {
    out.push_back('"');
    for (unsigned char c : s) {
      switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        default:
          if (c < 0x20) {
            char buf[8];
            std::snprintf(buf, sizeof(buf), "\\u%04x", c);
            out += buf;
          } else {
            // UTF-8 原样透出：协议两侧都是 UTF-8，别做转换
            out.push_back(static_cast<char>(c));
          }
      }
    }
    out.push_back('"');
  }

  void write(std::string& out) const {
    switch (type_) {
      case Type::Null: out += "null"; break;
      case Type::Bool: out += bool_ ? "true" : "false"; break;
      case Type::Number: {
        // 整数不要写成 1.000000：Dart 侧收到 1.0 也认，但日志难看
        if (std::isfinite(num_) && num_ == std::floor(num_) &&
            std::fabs(num_) < 1e15) {
          out += std::to_string(static_cast<int64_t>(num_));
        } else {
          char buf[40];
          std::snprintf(buf, sizeof(buf), "%.10g", num_);
          out += buf;
        }
        break;
      }
      case Type::String: write_string(out, str_); break;
      case Type::Array: {
        out.push_back('[');
        bool first = true;
        for (const auto& v : arr_) {
          if (!first) out.push_back(',');
          first = false;
          v.write(out);
        }
        out.push_back(']');
        break;
      }
      case Type::Object: {
        out.push_back('{');
        bool first = true;
        for (const auto& kv : obj_) {
          if (!first) out.push_back(',');
          first = false;
          write_string(out, kv.first);
          out.push_back(':');
          kv.second.write(out);
        }
        out.push_back('}');
        break;
      }
    }
  }

  struct Parser {
    const std::string& s;
    size_t i = 0;
    bool bad = false;
    std::string error;

    bool AtEnd() const { return i >= s.size(); }
    char Peek() const { return AtEnd() ? '\0' : s[i]; }

    void Fail(const std::string& why) {
      if (!bad) {
        bad = true;
        error = why + "（位置 " + std::to_string(i) + "）";
      }
    }

    void SkipWs() {
      while (!AtEnd()) {
        const char c = s[i];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
          ++i;
        } else {
          break;
        }
      }
    }

    bool Literal(const char* lit) {
      const size_t n = std::char_traits<char>::length(lit);
      if (s.compare(i, n, lit) != 0) return false;
      i += n;
      return true;
    }

    Json ParseValue() {
      SkipWs();
      if (AtEnd()) {
        Fail("空内容");
        return Json();
      }
      const char c = Peek();
      switch (c) {
        case '{': return ParseObject();
        case '[': return ParseArray();
        case '"': return Json(ParseString());
        case 't':
          if (Literal("true")) return Json(true);
          Fail("期望 true");
          return Json();
        case 'f':
          if (Literal("false")) return Json(false);
          Fail("期望 false");
          return Json();
        case 'n':
          if (Literal("null")) return Json();
          Fail("期望 null");
          return Json();
        default: return ParseNumber();
      }
    }

    Json ParseObject() {
      ++i;  // {
      Json j = Json::Object();
      SkipWs();
      if (Peek() == '}') {
        ++i;
        return j;
      }
      while (true) {
        SkipWs();
        if (Peek() != '"') {
          Fail("对象的键必须是字符串");
          return Json();
        }
        std::string key = ParseString();
        SkipWs();
        if (Peek() != ':') {
          Fail("键后缺冒号");
          return Json();
        }
        ++i;
        j.set(key, ParseValue());
        SkipWs();
        if (Peek() == ',') {
          ++i;
          continue;
        }
        if (Peek() == '}') {
          ++i;
          return j;
        }
        Fail("对象里期望 , 或 }");
        return Json();
      }
    }

    Json ParseArray() {
      ++i;  // [
      Json j = Json::Array();
      SkipWs();
      if (Peek() == ']') {
        ++i;
        return j;
      }
      while (true) {
        j.push(ParseValue());
        SkipWs();
        if (Peek() == ',') {
          ++i;
          continue;
        }
        if (Peek() == ']') {
          ++i;
          return j;
        }
        Fail("数组里期望 , 或 ]");
        return Json();
      }
    }

    // 把码点按 UTF-8 写进 out（中文/emoji 都得对）
    static void AppendUtf8(std::string& out, uint32_t cp) {
      if (cp < 0x80) {
        out.push_back(static_cast<char>(cp));
      } else if (cp < 0x800) {
        out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
      } else if (cp < 0x10000) {
        out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
      } else {
        out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
        out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
      }
    }

    uint32_t ParseHex4() {
      uint32_t v = 0;
      for (int k = 0; k < 4; ++k) {
        if (AtEnd()) {
          Fail("\\u 转义不完整");
          return 0;
        }
        const char c = s[i++];
        v <<= 4;
        if (c >= '0' && c <= '9') {
          v |= static_cast<uint32_t>(c - '0');
        } else if (c >= 'a' && c <= 'f') {
          v |= static_cast<uint32_t>(c - 'a' + 10);
        } else if (c >= 'A' && c <= 'F') {
          v |= static_cast<uint32_t>(c - 'A' + 10);
        } else {
          Fail("\\u 后面不是十六进制");
          return 0;
        }
      }
      return v;
    }

    std::string ParseString() {
      ++i;  // 开引号
      std::string out;
      while (true) {
        if (AtEnd()) {
          Fail("字符串没有收尾引号");
          return out;
        }
        const unsigned char c = static_cast<unsigned char>(s[i++]);
        if (c == '"') return out;
        if (c != '\\') {
          out.push_back(static_cast<char>(c));
          continue;
        }
        if (AtEnd()) {
          Fail("转义没写完");
          return out;
        }
        const char e = s[i++];
        switch (e) {
          case '"': out.push_back('"'); break;
          case '\\': out.push_back('\\'); break;
          case '/': out.push_back('/'); break;
          case 'n': out.push_back('\n'); break;
          case 't': out.push_back('\t'); break;
          case 'r': out.push_back('\r'); break;
          case 'b': out.push_back('\b'); break;
          case 'f': out.push_back('\f'); break;
          case 'u': {
            uint32_t cp = ParseHex4();
            // 代理对：高位 + 低位要合成一个码点
            if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < s.size() &&
                s[i] == '\\' && s[i + 1] == 'u') {
              i += 2;
              const uint32_t lo = ParseHex4();
              if (lo >= 0xDC00 && lo <= 0xDFFF) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
              }
            }
            AppendUtf8(out, cp);
            break;
          }
          default:
            Fail("不认识的转义");
            return out;
        }
      }
    }

    Json ParseNumber() {
      const size_t start = i;
      if (Peek() == '-' || Peek() == '+') ++i;
      while (!AtEnd()) {
        const char c = Peek();
        if ((c >= '0' && c <= '9') || c == '.' || c == 'e' || c == 'E' ||
            c == '+' || c == '-') {
          ++i;
        } else {
          break;
        }
      }
      if (i == start) {
        Fail("不是合法的值");
        return Json();
      }
      try {
        return Json(std::stod(s.substr(start, i - start)));
      } catch (...) {
        Fail("数字解析失败");
        return Json();
      }
    }
  };
};

}  // namespace panel
