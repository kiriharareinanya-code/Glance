#include "core/lrc.h"

#include <algorithm>
#include <cmath>
#include <map>

#include "core/date_util.h"  // 只为编译单元一致性（无实际用途）

namespace glance {
namespace {

bool IsDigit(wchar_t c) { return c >= L'0' && c <= L'9'; }

bool IsSpace(wchar_t c) {
  return c == L' ' || c == L'\t' || c == L'\r' || c == L'\n' || c == 0x3000;
}

// [mm:ss]、[mm:ss.xx]、[mm:ss:xx]（少数源用冒号分隔毫秒）
struct Stamp {
  size_t begin = 0;
  size_t end = 0;  // 指向 ']' 之后
  int64_t ms = 0;
};

bool ParseStampAt(const std::wstring& line, size_t pos, Stamp* out) {
  if (pos >= line.size() || line[pos] != L'[') return false;
  size_t i = pos + 1;
  size_t digits_begin = i;
  while (i < line.size() && IsDigit(line[i])) ++i;
  const size_t min_len = i - digits_begin;
  if (min_len < 1 || min_len > 3) return false;
  if (i >= line.size() || line[i] != L':') return false;
  const int minutes = std::stoi(line.substr(digits_begin, min_len));

  ++i;
  digits_begin = i;
  while (i < line.size() && IsDigit(line[i])) ++i;
  const size_t sec_len = i - digits_begin;
  if (sec_len < 1 || sec_len > 2) return false;
  const int seconds = std::stoi(line.substr(digits_begin, sec_len));

  int milliseconds = 0;
  if (i < line.size() && (line[i] == L'.' || line[i] == L':')) {
    ++i;
    digits_begin = i;
    while (i < line.size() && IsDigit(line[i])) ++i;
    const size_t frac_len = i - digits_begin;
    if (frac_len >= 1 && frac_len <= 3) {
      const int value = std::stoi(line.substr(digits_begin, frac_len));
      // "5" → 500ms、"50" → 500ms、"500" → 500ms（两位是百分秒）
      milliseconds = frac_len == 1 ? value * 100 : (frac_len == 2 ? value * 10 : value);
    }
  }
  if (i >= line.size() || line[i] != L']') return false;

  out->begin = pos;
  out->end = i + 1;
  out->ms = static_cast<int64_t>(minutes) * 60000 + seconds * 1000 + milliseconds;
  return true;
}

// 元信息行：[ti:…] [ar:…] [al:…] [by:…]
bool LooksLikeMeta(const std::wstring& text) {
  if (text.size() < 3 || text[0] != L'[') return false;
  size_t i = 1;
  while (i < text.size() && ((text[i] >= L'a' && text[i] <= L'z') ||
                             (text[i] >= L'A' && text[i] <= L'Z'))) {
    ++i;
  }
  return i > 1 && i < text.size() && text[i] == L':';
}

// 繁 → 简（限标题/歌手归一化与查询用；表外字符原样返回）
const wchar_t* const kT2S =
    L"東东專专愛爱陽阳無无樂乐語语聲声雲云電电畫画見见貝贝頁页門门問问間间聞闻閱阅書书寫写學学覺觉覽览優优傷伤價价眾众會会傳传偉伟側侧兒儿蘭兰興兴養养內内關关務务動动勢势華华協协單单賣卖衛卫廠厂歷历壓压縣县參参雙双變变葉叶号号嘆叹員员團团園园圍围國国圖图圓圆場场壞坏塊块堅坚壇坛處处備备復复夠够頭头夾夹奪夺奮奋婦妇媽妈娛娱孫孙寧宁寶宝實实寵宠審审層层歲岁豈岂崗岗島岛嶺岭峽峡幣币帥帅師师帳帐簾帘帶带幫帮寬宽慶庆庫库應应廢废棄弃彌弥彎弯歸归當当錄录徹彻從从憶忆憂忧懷怀態态憐怜總总戀恋懇恳惡恶惱恼懸悬驚惊懼惧慘惨慣惯願愿戰战撲扑執执擴扩掃扫揚扬擔担擬拟攏拢擇择掛挂摯挚擋挡掙挣揮挥損损換换據据擲掷攬揽擱搁擺摆搖摇攤摊撐撑敵敌敗败賬账貨货質质販贩貪贪貧贫貫贯費费賀贺賊贼賈贾資资賞赏賜赐賠赔賺赚賽赛讚赞贈赠贏赢趕赶趨趋躍跃踐践輪轮軟软軸轴輕轻載载較较輔辅輛辆輸输達达遷迁過过運运還还這这進进遠远違违連连遲迟點点臨临緊紧髒脏髮发麗丽舉举舊旧藝艺藥药蘇苏補补裝装裡里視视計计訊讯記记許许論论設设訪访證证評评詞词話话該该詳详誤误説说調调談谈請请諸诸讀读識识議议讓让財财賢贤購购軍军車车極极機机權权殺杀毀毁氣气汉汉決决淨净準准濕湿满满滨滨滾滚潜潜潔洁烏乌為为爾尔猶犹獄狱獎奖獨独獲获瑪玛瓊琼瘋疯盜盗盡尽监监盘盘矿矿碼码確确禮礼種种穩稳窮穷竊窃豎竖競竞筆笔簡简級级純纯紙纸細细紹绍經经維维網网綜综錯错難难響响顆颗飛飞飯饭馆馆馬马體体魚鱼鳥鸟麦麦麼么檔档檢检灣湾營营櫻樱狀状獅狮藍蓝製制規规覓觅註注認认護护豐丰賓宾蹟迹邊边適适選选鄉乡鄭郑針针韓韩頂顶頻频顧顾風风馳驰驅驱雞鸡";

const std::map<wchar_t, wchar_t>& TraditionalToSimplified() {
  static const std::map<wchar_t, wchar_t> table = [] {
    std::map<wchar_t, wchar_t> map;
    for (size_t i = 0; kT2S[i] != L'\0' && kT2S[i + 1] != L'\0'; i += 2) {
      map[kT2S[i]] = kT2S[i + 1];
    }
    return map;
  }();
  return table;
}

bool IsCjk(wchar_t c) {
  return (c >= 0x3400 && c <= 0x4DBF) || (c >= 0x4E00 && c <= 0x9FFF) ||
         (c >= 0xF900 && c <= 0xFAFF);
}

bool IsFullwidth(wchar_t c) { return c >= 0xFF01 && c <= 0xFF5E; }

// 全角 → 半角（含全角空格）
wchar_t FoldFullwidth(wchar_t c) {
  if (c == 0x3000) return L' ';
  if (IsFullwidth(c)) return static_cast<wchar_t>(c - 0xFEE0);
  return c;
}

// norm 里要丢掉的标点/符号
bool IsPunct(wchar_t c) {
  switch (c) {
    case L'-': case L'_': case L'\xB7':  // ·
    case L',': case L'.': case L'!': case L'?':
    case 0x3002:  // 。
    case 0xFF0C:  // ，
    case 0xFF01:  // ！
    case 0xFF1F:  // ？
    case L'\'': case L'"':
    case 0x201C: case 0x201D:  // “ ”
    case 0x2018: case 0x2019:  // ‘ ’
      return true;
    default:
      return false;
  }
}

// 括号内容：（…）(…) […]
std::wstring StripBrackets(const std::wstring& text) {
  std::wstring out;
  int depth = 0;
  for (const wchar_t c : text) {
    if (c == L'(' || c == L'[' || c == 0xFF08) {
      ++depth;
    } else if (c == L')' || c == L']' || c == 0xFF09) {
      if (depth > 0) --depth;
    } else if (depth == 0) {
      out.push_back(c);
    }
  }
  return out;
}

// 「伴奏/remix/live…」这类版本标记
bool HasJunk(const std::wstring& normalized) {
  static const wchar_t* kJunk[] = {L"伴奏", L"instrumental", L"remix", L"dj版",
                                   L"纯享", L"翻自",        L"cover", L"live",
                                   L"现场", L"demo",        L"加速",  L"减速",
                                   L"钢琴版", L"吉他版"};
  for (const wchar_t* junk : kJunk) {
    if (normalized.find(junk) != std::wstring::npos) return true;
  }
  return false;
}

std::wstring ToLowerAscii(const std::wstring& text) {
  std::wstring out;
  out.reserve(text.size());
  for (wchar_t c : text) {
    out.push_back(c >= L'A' && c <= L'Z' ? static_cast<wchar_t>(c - L'A' + L'a') : c);
  }
  return out;
}

std::vector<std::wstring> SplitLines(const std::wstring& text) {
  std::vector<std::wstring> lines;
  std::wstring current;
  for (const wchar_t c : text) {
    if (c == L'\n') {
      lines.push_back(current);
      current.clear();
    } else if (c != L'\r') {
      current.push_back(c);
    }
  }
  lines.push_back(current);
  return lines;
}

}  // namespace

std::vector<LrcLine> Lrc::Parse(const std::wstring& text) {
  std::vector<LrcLine> out;
  if (text.empty()) return out;

  int64_t offset = 0;
  for (const std::wstring& line : SplitLines(text)) {
    if (line.empty()) continue;

    // [offset:-500]：整体时移，正数表示歌词提前
    if (line.size() > 9 && line[0] == L'[' && ToLowerAscii(line).rfind(L"[offset:", 0) == 0) {
      const size_t close = line.find(L']');
      if (close != std::wstring::npos) {
        try {
          offset = std::stoll(line.substr(8, close - 8));
        } catch (...) {
          offset = 0;
        }
      }
      continue;
    }

    std::vector<Stamp> stamps;
    std::wstring body;
    size_t pos = 0;
    size_t last_end = 0;
    while (pos < line.size()) {
      Stamp stamp;
      if (line[pos] == L'[' && ParseStampAt(line, pos, &stamp)) {
        body += line.substr(last_end, pos - last_end);
        stamps.push_back(stamp);
        pos = stamp.end;
        last_end = pos;
      } else {
        ++pos;
      }
    }
    body += line.substr(last_end);

    if (stamps.empty()) continue;

    // 去掉时间戳后的正文；元信息行跳过
    std::wstring text_part = body;
    while (!text_part.empty() && IsSpace(text_part.front())) text_part.erase(text_part.begin());
    while (!text_part.empty() && IsSpace(text_part.back())) text_part.pop_back();
    if (LooksLikeMeta(text_part)) continue;

    for (const Stamp& stamp : stamps) {
      LrcLine item;
      item.t = stamp.ms - offset;
      item.s = text_part;
      out.push_back(std::move(item));
    }
  }

  // 源文件不保证有序（一行多时间戳就必然乱序）
  std::stable_sort(out.begin(), out.end(),
                   [](const LrcLine& a, const LrcLine& b) { return a.t < b.t; });
  return out;
}

int Lrc::IndexAt(const std::vector<LrcLine>& lines, int64_t pos_ms) {
  if (lines.empty()) return -1;
  if (pos_ms < lines.front().t) return -1;
  int lo = 0;
  int hi = static_cast<int>(lines.size()) - 1;
  int answer = 0;
  while (lo <= hi) {
    const int mid = (lo + hi) >> 1;
    if (lines[static_cast<size_t>(mid)].t <= pos_ms) {
      answer = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return answer;
}

std::vector<LrcLine> Lrc::Merge(const std::vector<LrcLine>& main,
                                const std::vector<LrcLine>& trans) {
  if (trans.empty()) return main;
  std::map<int64_t, std::wstring> map;
  for (const LrcLine& line : trans) map[line.t] = line.s;

  std::vector<LrcLine> out;
  out.reserve(main.size());
  for (const LrcLine& line : main) {
    LrcLine merged = line;
    const auto it = map.find(line.t);
    if (it != map.end() && it->second != line.s) merged.tr = it->second;
    out.push_back(std::move(merged));
  }
  return out;
}

std::wstring Lrc::Format(int64_t ms) {
  if (ms < 0) ms = 0;
  const int64_t total = ms / 1000;
  const int64_t s = total % 60;
  const int64_t m = (total / 60) % 60;
  const int64_t h = total / 3600;
  wchar_t buffer[32] = {};
  if (h > 0) {
    swprintf_s(buffer, L"%lld:%02lld:%02lld", h, m, s);
  } else {
    swprintf_s(buffer, L"%lld:%02lld", m, s);
  }
  return buffer;
}

std::wstring Lrc::Norm(const std::wstring& text) {
  // 1) 繁→简 2) 全角→半角 3) 小写 4) 去括号内容 5) 去标点与空格
  const auto& table = TraditionalToSimplified();
  std::wstring step1;
  step1.reserve(text.size());
  for (const wchar_t c : text) {
    const auto it = table.find(c);
    step1.push_back(it != table.end() ? it->second : c);
  }

  std::wstring step2;
  step2.reserve(step1.size());
  for (const wchar_t c : step1) step2.push_back(FoldFullwidth(c));

  const std::wstring step3 = ToLowerAscii(step2);
  const std::wstring step4 = StripBrackets(step3);

  std::wstring out;
  out.reserve(step4.size());
  for (const wchar_t c : step4) {
    if (IsSpace(c) || IsPunct(c)) continue;
    out.push_back(c);
  }
  return out;
}

double Lrc::Sim(const std::wstring& a_raw, const std::wstring& b_raw) {
  const std::wstring a = Norm(a_raw);
  const std::wstring b = Norm(b_raw);
  if (a.empty() || b.empty()) return 0.0;
  if (a == b) return 1.0;
  if (a.size() < 2 || b.size() < 2) return 0.0;

  std::map<std::wstring, int> grams;
  int na = 0;
  for (size_t i = 0; i + 1 < a.size(); ++i) {
    grams[a.substr(i, 2)]++;
    ++na;
  }
  int nb = 0;
  int inter = 0;
  for (size_t i = 0; i + 1 < b.size(); ++i) {
    ++nb;
    const std::wstring gram = b.substr(i, 2);
    const auto it = grams.find(gram);
    if (it != grams.end() && it->second > 0) {
      ++inter;
      it->second--;
    }
  }
  return (na + nb) == 0 ? 0.0 : (2.0 * inter) / static_cast<double>(na + nb);
}

std::vector<std::wstring> Lrc::TitleVariants(const std::wstring& title_raw) {
  std::vector<std::wstring> out;
  std::vector<std::wstring> seen;

  const auto push = [&](std::wstring value) {
    // 去重键用原始串（norm 会剥掉括号内容，「X (Y)」和「X」是不同的查询）
    while (!value.empty() && IsSpace(value.front())) value.erase(value.begin());
    while (!value.empty() && IsSpace(value.back())) value.pop_back();
    if (value.empty()) return;
    if (std::find(seen.begin(), seen.end(), value) != seen.end()) return;
    if (Norm(value).empty()) return;
    seen.push_back(value);
    out.push_back(std::move(value));
  };

  std::wstring title = title_raw;
  if (title.empty()) return out;
  push(title);
  push(StripBrackets(title));

  // 括号里的内容单独当一次查询：「歌名 (动画版)」→ 试「动画版」
  const size_t open = title.find_first_of(L"(（[");
  if (open != std::wstring::npos) {
    const size_t close = title.find_first_of(L")）]", open + 1);
    if (close != std::wstring::npos && close > open + 3) {
      push(title.substr(open + 1, close - open - 1));
    }
  }

  // 纯拉丁 / 纯 CJK 两个变体
  std::wstring latin;
  std::wstring cjk;
  for (const wchar_t c : title) {
    if (c >= 0x20 && c <= 0x7E) latin.push_back(c);
    if (IsCjk(c)) cjk.push_back(c);
  }
  if (!latin.empty() && latin != title) push(latin);
  if (!cjk.empty() && cjk != title) push(cjk);
  return out;
}

int Lrc::PickSongIndex(const std::vector<const JsonValue*>& songs,
                       const std::wstring& title, const std::wstring& artist,
                       int64_t duration_ms) {
  if (songs.empty()) return -1;
  const std::wstring nt = Norm(title);
  const std::wstring na = Norm(artist);

  int best = -1;
  double best_score = -1e9;

  for (size_t i = 0; i < songs.size(); ++i) {
    const JsonValue* song = songs[i];
    if (song == nullptr) continue;

    std::wstring artists_text;
    if (const JsonValue* artists = song->Find("artists");
        artists != nullptr && artists->IsArray()) {
      for (const JsonValue& item : artists->array) {
        if (const JsonValue* name = item.Find("name")) {
          if (!artists_text.empty()) artists_text += L"/";
          artists_text += name->WStringOr(L"");
        }
      }
    }
    const std::wstring an = Norm(artists_text);
    const std::wstring sn = Norm(song->Find("name") != nullptr
                                     ? song->Find("name")->WStringOr(L"")
                                     : L"");

    double score = 0.0;
    // 歌手是最硬的信号
    if (!na.empty() && !an.empty()) {
      if (an.find(na) != std::wstring::npos || na.find(an) != std::wstring::npos) {
        score += 60;
      } else {
        score -= 40;
      }
    }
    // 时长：3 秒内视为一致
    const int64_t dur = static_cast<int64_t>(
        song->Find("duration") != nullptr ? song->Find("duration")->NumberOr(0.0) : 0.0);
    if (duration_ms > 0 && dur > 0) {
      const int64_t diff = std::llabs(dur - duration_ms);
      if (diff <= 3000) {
        score += 50;
      } else {
        score -= std::min<double>(50.0, (diff - 3000) / 1000.0 * 3.0);
      }
    }
    // 标题只加分不重扣（繁简、异体字、译名会让字面对不上）
    if (!nt.empty() && !sn.empty()) {
      if (sn == nt) {
        score += 40;
      } else if (sn.find(nt) != std::wstring::npos ||
                 nt.find(sn) != std::wstring::npos) {
        score += 25;
      } else {
        const double similarity = Sim(sn, nt);
        if (similarity >= 0.3) score += std::round(similarity * 30.0);
      }
    }
    // 原曲名里本来就写着 Live/Remix 时不该扣
    if (HasJunk(sn) && !HasJunk(Norm(title))) score -= 70;
    // 搜索排序本身是信息，靠前的略加分
    score += std::max(0.0, 10.0 - static_cast<double>(i) * 2.0);

    if (score > best_score) {
      best_score = score;
      best = static_cast<int>(i);
    }
  }
  return best_score >= 60 ? best : -1;
}

}  // namespace glance
