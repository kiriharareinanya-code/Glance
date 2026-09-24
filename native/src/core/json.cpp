#include "core/json.h"

#include <windows.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>

namespace glance {
namespace {

// 递归下降解析器：JSON 文法就这么点，一个 index 走到底。
class Parser {
 public:
  explicit Parser(const std::string& text) : text_(text) {}

  bool Parse(JsonValue* out) {
    SkipWhitespace();
    if (!ParseValue(out)) return false;
    SkipWhitespace();
    return pos_ >= text_.size();  // 尾部不许有多余内容
  }

 private:
  bool ParseValue(JsonValue* out) {
    if (pos_ >= text_.size()) return false;
    switch (text_[pos_]) {
      case '{': return ParseObject(out);
      case '[': return ParseArray(out);
      case '"':
        out->type = JsonValue::Type::kString;
        return ParseString(&out->string_value);
      case 't':
        if (text_.compare(pos_, 4, "true") != 0) return false;
        pos_ += 4;
        out->type = JsonValue::Type::kBool;
        out->bool_value = true;
        return true;
      case 'f':
        if (text_.compare(pos_, 5, "false") != 0) return false;
        pos_ += 5;
        out->type = JsonValue::Type::kBool;
        out->bool_value = false;
        return true;
      case 'n':
        if (text_.compare(pos_, 4, "null") != 0) return false;
        pos_ += 4;
        out->type = JsonValue::Type::kNull;
        return true;
      default: return ParseNumber(out);
    }
  }

  bool ParseObject(JsonValue* out) {
    ++pos_;  // '{'
    out->type = JsonValue::Type::kObject;
    SkipWhitespace();
    if (pos_ < text_.size() && text_[pos_] == '}') {
      ++pos_;
      return true;
    }
    while (pos_ < text_.size()) {
      SkipWhitespace();
      std::string key;
      if (!ParseString(&key)) return false;
      SkipWhitespace();
      if (pos_ >= text_.size() || text_[pos_] != ':') return false;
      ++pos_;
      SkipWhitespace();
      JsonValue value;
      if (!ParseValue(&value)) return false;
      out->object.emplace_back(std::move(key), std::move(value));
      SkipWhitespace();
      if (pos_ >= text_.size()) return false;
      if (text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (text_[pos_] == '}') {
        ++pos_;
        return true;
      }
      return false;
    }
    return false;
  }

  bool ParseArray(JsonValue* out) {
    ++pos_;  // '['
    out->type = JsonValue::Type::kArray;
    SkipWhitespace();
    if (pos_ < text_.size() && text_[pos_] == ']') {
      ++pos_;
      return true;
    }
    while (pos_ < text_.size()) {
      SkipWhitespace();
      JsonValue value;
      if (!ParseValue(&value)) return false;
      out->array.push_back(std::move(value));
      SkipWhitespace();
      if (pos_ >= text_.size()) return false;
      if (text_[pos_] == ',') {
        ++pos_;
        continue;
      }
      if (text_[pos_] == ']') {
        ++pos_;
        return true;
      }
      return false;
    }
    return false;
  }

  bool ParseString(std::string* out) {
    if (pos_ >= text_.size() || text_[pos_] != '"') return false;
    ++pos_;
    out->clear();
    while (pos_ < text_.size()) {
      const char c = text_[pos_++];
      if (c == '"') return true;
      if (c != '\\') {
        out->push_back(c);
        continue;
      }
      if (pos_ >= text_.size()) return false;
      const char esc = text_[pos_++];
      switch (esc) {
        case '"': out->push_back('"'); break;
        case '\\': out->push_back('\\'); break;
        case '/': out->push_back('/'); break;
        case 'b': out->push_back('\b'); break;
        case 'f': out->push_back('\f'); break;
        case 'n': out->push_back('\n'); break;
        case 'r': out->push_back('\r'); break;
        case 't': out->push_back('\t'); break;
        case 'u': {
          // \uXXXX → UTF-8（含代理对：两个 \u 拼一个码点）
          unsigned int code = 0;
          if (!ParseHex4(&code)) return false;
          if (code >= 0xD800 && code <= 0xDBFF) {
            if (pos_ + 1 < text_.size() && text_[pos_] == '\\' &&
                text_[pos_ + 1] == 'u') {
              pos_ += 2;
              unsigned int low = 0;
              if (!ParseHex4(&low)) return false;
              code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
            }
          }
          AppendUtf8(code, out);
          break;
        }
        default: return false;
      }
    }
    return false;
  }

  bool ParseHex4(unsigned int* out) {
    if (pos_ + 4 > text_.size()) return false;
    unsigned int value = 0;
    for (int i = 0; i < 4; ++i) {
      const char c = text_[pos_++];
      value <<= 4;
      if (c >= '0' && c <= '9') value |= static_cast<unsigned>(c - '0');
      else if (c >= 'a' && c <= 'f') value |= static_cast<unsigned>(c - 'a' + 10);
      else if (c >= 'A' && c <= 'F') value |= static_cast<unsigned>(c - 'A' + 10);
      else return false;
    }
    *out = value;
    return true;
  }

  static void AppendUtf8(unsigned int code, std::string* out) {
    if (code < 0x80) {
      out->push_back(static_cast<char>(code));
    } else if (code < 0x800) {
      out->push_back(static_cast<char>(0xC0 | (code >> 6)));
      out->push_back(static_cast<char>(0x80 | (code & 0x3F)));
    } else if (code < 0x10000) {
      out->push_back(static_cast<char>(0xE0 | (code >> 12)));
      out->push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
      out->push_back(static_cast<char>(0x80 | (code & 0x3F)));
    } else {
      out->push_back(static_cast<char>(0xF0 | (code >> 18)));
      out->push_back(static_cast<char>(0x80 | ((code >> 12) & 0x3F)));
      out->push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
      out->push_back(static_cast<char>(0x80 | (code & 0x3F)));
    }
  }

  bool ParseNumber(JsonValue* out) {
    const size_t start = pos_;
    if (pos_ < text_.size() && (text_[pos_] == '-' || text_[pos_] == '+')) ++pos_;
    while (pos_ < text_.size() &&
           (isdigit(static_cast<unsigned char>(text_[pos_])) ||
            text_[pos_] == '.' || text_[pos_] == 'e' || text_[pos_] == 'E' ||
            text_[pos_] == '-' || text_[pos_] == '+')) {
      ++pos_;
    }
    if (pos_ == start) return false;
    const std::string token = text_.substr(start, pos_ - start);
    out->type = JsonValue::Type::kNumber;
    out->number_value = strtod(token.c_str(), nullptr);
    return true;
  }

  void SkipWhitespace() {
    while (pos_ < text_.size() &&
           (text_[pos_] == ' ' || text_[pos_] == '\t' || text_[pos_] == '\n' ||
            text_[pos_] == '\r')) {
      ++pos_;
    }
  }

  const std::string& text_;
  size_t pos_ = 0;
};

}  // namespace

const JsonValue* JsonValue::Find(const std::string& key) const {
  if (type != Type::kObject) return nullptr;
  for (const auto& [k, v] : object) {
    if (k == key) return &v;
  }
  return nullptr;
}

JsonValue* JsonValue::Find(const std::string& key) {
  if (type != Type::kObject) return nullptr;
  for (auto& [k, v] : object) {
    if (k == key) return &v;
  }
  return nullptr;
}

double JsonValue::NumberOr(double fallback) const {
  if (type == Type::kNumber) return number_value;
  if (type == Type::kBool) return bool_value ? 1.0 : 0.0;
  // 字符串形式的数字也要认：小米天气接口把温度和天气码都当字符串给
  // （"value": "27"），只认 number 的话温度会静默变 0。
  if (type == Type::kString && !string_value.empty()) {
    try {
      return std::stod(string_value);
    } catch (...) {
      return fallback;
    }
  }
  return fallback;
}

bool JsonValue::BoolOr(bool fallback) const {
  if (type == Type::kBool) return bool_value;
  if (type == Type::kNumber) return number_value != 0.0;
  return fallback;
}

std::string JsonValue::StringOr(const char* fallback) const {
  return type == Type::kString ? string_value : fallback;
}

std::wstring JsonValue::WStringOr(const wchar_t* fallback) const {
  if (type != Type::kString) return fallback;
  return Utf8ToWide(string_value);
}

bool ParseJson(const std::string& text, JsonValue* out) {
  if (out == nullptr) return false;
  // UTF-8 BOM：某些工具写出来的文件带，跳过更稳
  const size_t start = text.size() >= 3 &&
                               static_cast<unsigned char>(text[0]) == 0xEF &&
                               static_cast<unsigned char>(text[1]) == 0xBB &&
                               static_cast<unsigned char>(text[2]) == 0xBF
                           ? 3
                           : 0;
  const std::string body = text.substr(start);
  Parser parser(body);
  return parser.Parse(out);
}

std::string ReadFileUtf8(const std::wstring& path) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return {};

  LARGE_INTEGER size = {};
  if (!GetFileSizeEx(file, &size) || size.QuadPart <= 0 ||
      size.QuadPart > 32 * 1024 * 1024) {
    CloseHandle(file);
    return {};
  }
  std::string buffer(static_cast<size_t>(size.QuadPart), '\0');
  DWORD read = 0;
  const bool ok = ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()),
                           &read, nullptr) != FALSE;
  CloseHandle(file);
  if (!ok) return {};
  buffer.resize(read);
  return buffer;
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) return {};
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      wide.data(), length);
  return wide;
}

namespace {

void EscapeJsonString(const std::string& text, std::string* out) {
  out->push_back('"');
  for (const char c : text) {
    switch (c) {
      case '"':
        out->append("\\\"");
        break;
      case '\\':
        out->push_back('\\');
        out->push_back('\\');
        break;
      case '\n':
        out->append("\\n");
        break;
      case '\r':
        out->append("\\r");
        break;
      case '\t':
        out->append("\\t");
        break;
      default:
        out->push_back(c);
        break;
    }
  }
  out->push_back('"');
}

void StringifyTo(const JsonValue& value, int level, std::string* out) {
  const std::string pad(static_cast<size_t>(level) * 2, ' ');
  const std::string pad_inner(static_cast<size_t>(level + 1) * 2, ' ');
  switch (value.type) {
    case JsonValue::Type::kNull:
      *out += "null";
      break;
    case JsonValue::Type::kBool:
      *out += value.bool_value ? "true" : "false";
      break;
    case JsonValue::Type::kNumber: {
      char buffer[48] = {};
      // 整数值别写成 104.0：state.json 里 gridCell 就是整数，写成浮点
      // 会让 Flutter 版读到同样的值但文件 diff 全是噪音
      if (value.number_value == std::floor(value.number_value) &&
          std::fabs(value.number_value) < 1e15) {
        snprintf(buffer, sizeof(buffer), "%lld",
                 static_cast<long long>(value.number_value));
      } else {
        // %.15g：能往返 double 的精度。用 %.10g 会把 752.6666666666667 改写成
        // 752.6666667，用户没动过的卡片坐标也跟着变，diff 全是噪音。
        snprintf(buffer, sizeof(buffer), "%.15g", value.number_value);
      }
      *out += buffer;
      break;
    }
    case JsonValue::Type::kString:
      EscapeJsonString(value.string_value, out);
      break;
    case JsonValue::Type::kArray: {
      if (value.array.empty()) {
        *out += "[]";
        break;
      }
      out->push_back('[');
      out->push_back('\n');
      for (size_t i = 0; i < value.array.size(); ++i) {
        *out += pad_inner;
        StringifyTo(value.array[i], level + 1, out);
        if (i + 1 < value.array.size()) *out += ',';
        out->push_back('\n');
      }
      *out += pad;
      *out += ']';
      break;
    }
    case JsonValue::Type::kObject: {
      if (value.object.empty()) {
        *out += "{}";
        break;
      }
      out->push_back('{');
      out->push_back('\n');
      for (size_t i = 0; i < value.object.size(); ++i) {
        *out += pad_inner;
        EscapeJsonString(value.object[i].first, out);
        *out += ": ";
        StringifyTo(value.object[i].second, level + 1, out);
        if (i + 1 < value.object.size()) *out += ',';
        out->push_back('\n');
      }
      *out += pad;
      *out += '}';
      break;
    }
  }
}

}  // namespace

std::string StringifyJson(const JsonValue& value) {
  std::string out;
  StringifyTo(value, 0, &out);
  out.push_back('\n');  // 末尾补一个换行：工具改这个文件时 diff 干净些
  return out;
}

bool WriteFileUtf8(const std::wstring& path, const std::string& text) {
  const std::wstring temp = path + L".tmp";
  {
    HANDLE file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    const bool ok = WriteFile(file, text.data(), static_cast<DWORD>(text.size()),
                              &written, nullptr) != FALSE;
    CloseHandle(file);
    if (!ok || written != text.size()) {
      DeleteFileW(temp.c_str());
      return false;
    }
  }
  // 原子替换：MoveFileEx 带 REPLACE_EXISTING 在同一个卷上是原子的
  return MoveFileExW(temp.c_str(), path.c_str(),
                     MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != FALSE;
}

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.c_str(),
                                         static_cast<int>(text.size()), nullptr, 0,
                                         nullptr, nullptr);
  if (length <= 0) return {};
  std::string utf8(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      utf8.data(), length, nullptr, nullptr);
  return utf8;
}

}  // namespace glance
