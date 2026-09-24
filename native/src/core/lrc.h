// LRC 歌词解析与选歌（纯逻辑）。
//
// 从 Flutter 版 lib/widgets/builtin/lrc.dart 移植。里面全是边界条件：
// 一行多个时间戳、毫秒 2 位还是 3 位、[ti:]/[ar:] 元信息、时间戳乱序、空行、
// [offset:] 时移。这些错了不会崩，只会让歌词错半拍——很难肉眼发现。
//
// 内部一律用 std::wstring（UTF-16）：繁简表、全角半角、标点过滤都是逐字符
// 操作，在 UTF-8 上做要处理多字节边界，用宽字符一个字符一个 wchar_t 直接完事。
#ifndef GLANCE_NATIVE_CORE_LRC_H_
#define GLANCE_NATIVE_CORE_LRC_H_

#include <cstdint>
#include <string>
#include <vector>

#include "core/json.h"

namespace glance {

struct LrcLine {
  int64_t t = 0;       // 毫秒
  std::wstring s;      // 原文
  std::wstring tr;     // 翻译（merge 之后才有）
};

class Lrc {
 public:
  // 解析成按时间升序的数组
  static std::vector<LrcLine> Parse(const std::wstring& text);

  // pos_ms 时刻该高亮第几行；-1 = 还没到第一句（前奏）。二分查找。
  static int IndexAt(const std::vector<LrcLine>& lines, int64_t pos_ms);

  // 原文与翻译合并：按时间戳对齐，对不上的翻译直接丢（宁可不显示也别错位）
  static std::vector<LrcLine> Merge(const std::vector<LrcLine>& main,
                                    const std::vector<LrcLine>& trans);

  // 毫秒 → "m:ss"（超过一小时才带小时位）
  static std::wstring Format(int64_t ms);

  // 归一化：忽略大小写/空格/标点/括号内容/全角半角/简繁差异
  static std::wstring Norm(const std::wstring& text);

  // 二元组 Dice 相似度 0~1
  static double Sim(const std::wstring& a, const std::wstring& b);

  // 标题的查询变体（去括号版、括号内、简体版、纯拉丁、纯中文…）
  static std::vector<std::wstring> TitleVariants(const std::wstring& title);

  // 从搜索结果里挑最匹配的一首，返回下标；-1 = 没过门槛（60 分）
  // songs 每项是对象，读 name / artists[].name / duration
  static int PickSongIndex(const std::vector<const JsonValue*>& songs,
                           const std::wstring& title, const std::wstring& artist,
                           int64_t duration_ms);
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CORE_LRC_H_
