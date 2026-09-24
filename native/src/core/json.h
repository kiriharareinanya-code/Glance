// 极简 JSON 解析器。
//
// 不引第三方库：目标是单 exe、零依赖。需求也很窄——读 state.json 的布局、
// 以及以后解析天气/歌词接口的响应，够用就行。
//
// 设计取舍：
//   - object 用 vector<pair> 而不是 map：键少、查询靠线性扫，还保住了插入序
//     （调试时打印出来和原文件同序，好对）。
//   - 字符串统一存 UTF-8（std::string），需要给 Windows API 用时转 UTF-16。
//   - 解析失败返回 false 且不抛异常：配置坏了是要"用默认值继续跑"，
//     不是崩给用户看。
#ifndef GLANCE_NATIVE_CORE_JSON_H_
#define GLANCE_NATIVE_CORE_JSON_H_

#include <string>
#include <utility>
#include <vector>

namespace glance {

class JsonValue {
 public:
  enum class Type { kNull, kBool, kNumber, kString, kArray, kObject };

  Type type = Type::kNull;
  bool bool_value = false;
  double number_value = 0.0;
  std::string string_value;  // UTF-8
  std::vector<JsonValue> array;
  std::vector<std::pair<std::string, JsonValue>> object;

  bool IsObject() const { return type == Type::kObject; }
  bool IsArray() const { return type == Type::kArray; }
  bool IsString() const { return type == Type::kString; }
  bool IsNumber() const { return type == Type::kNumber; }

  // 取成员；不存在返回 nullptr。
  const JsonValue* Find(const std::string& key) const;

  double NumberOr(double fallback) const;
  bool BoolOr(bool fallback) const;
  std::string StringOr(const char* fallback) const;
  // 字符串成员转 UTF-16（给 DirectWrite / Win32 用）
  std::wstring WStringOr(const wchar_t* fallback) const;
};

// 解析 UTF-8 JSON 文本。失败返回 false（out 保持未定义）。
bool ParseJson(const std::string& text, JsonValue* out);

// 读文件为 UTF-8 文本；不存在或读失败返回空串。
std::string ReadFileUtf8(const std::wstring& path);

// UTF-8 → UTF-16
std::wstring Utf8ToWide(const std::string& text);

// UTF-16 → UTF-8（拼查询参数、写日志用）
std::string WideToUtf8(const std::wstring& text);

}  // namespace glance

#endif  // GLANCE_NATIVE_CORE_JSON_H_
