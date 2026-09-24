#include "core/json.h"

#include <windows.h>

#include <cstdlib>

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

double JsonValue::NumberOr(double fallback) const {
  if (type == Type::kNumber) return number_value;
  if (type == Type::kBool) return bool_value ? 1.0 : 0.0;
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

}  // namespace glance
