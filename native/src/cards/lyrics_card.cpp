#include "cards/lyrics_card.h"

#include <windows.h>

#include <thread>

#include "core/http.h"
#include "core/json.h"
#include "platform/log.h"

namespace glance {
namespace {

// 小米以外的接口大多认正常 UA；网易云 additionally 要 Referer。
std::wstring HeaderBlock(bool netease) {
  std::wstring headers =
      L"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      L"(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36\r\n"
      L"Accept: application/json, text/plain, */*\r\n"
      L"Accept-Language: zh-CN,zh;q=0.9,en;q=0.8\r\n";
  if (netease) headers += L"Referer: https://music.163.com/\r\n";
  return headers;
}

// 歌词开头的「作词 : X」名单（设置里可以关）
bool LooksLikeCredit(const std::wstring& text) {
  static const wchar_t* kKeys[] = {
      L"作词", L"作曲", L"编曲", L"制作人", L"monitor", L"录音", L"混音",
      L"母带", L"和声", L"吉他", L"贝斯", L"鼓",   L"键盘",  L"弦乐",
      L"统筹", L"企划", L"出品", L"发行",  L"监制",  L"制作",  L"营销",
      L"策划", L"录音室", L"producer", L"composer", L"lyricist", L"arranger",
      L"mixing", L"mastering"};
  std::wstring lower = text;
  for (wchar_t& c : lower) {
    if (c >= L'A' && c <= L'Z') c = static_cast<wchar_t>(c - L'A' + L'a');
  }
  for (const wchar_t* key : kKeys) {
    const std::wstring needle(key);
    const size_t pos = lower.find(needle);
    if (pos == std::wstring::npos) continue;
    // 形如「作词 : X」——关键词后面跟冒号才算名单行
    size_t i = pos + needle.size();
    while (i < lower.size() && (lower[i] == L' ' || lower[i] == L'\t')) ++i;
    if (i < lower.size() && (lower[i] == L':' || lower[i] == 0xFF1A)) return true;
  }
  return false;
}

std::vector<LrcLine> StripCredits(const std::vector<LrcLine>& input, bool keep) {
  if (keep) return input;
  std::vector<LrcLine> out;
  out.reserve(input.size());
  for (const LrcLine& line : input) {
    if (!LooksLikeCredit(line.s)) out.push_back(line);
  }
  // 整首歌都被当成名单滤空了就原样返回，宁可显示名单也别显示空白
  return out.size() >= 4 ? out : input;
}

// ---- 网易云（非官方接口）----
bool SearchNetease(const std::wstring& query, int limit, JsonValue* out) {
  const std::wstring url =
      L"https://music.163.com/api/search/get?s=" +
      Utf8ToWide(UrlEncode(WideToUtf8(query))) + L"&type=1&limit=" +
      std::to_wstring(limit);
  const HttpResult response = HttpGet(url, HeaderBlock(true), 10000);
  if (!response.ok) return false;
  return ParseJson(response.body, out);
}

bool FetchNeteaseLyrics(int64_t song_id, bool want_trans, bool keep_credits,
                        std::vector<LrcLine>* out) {
  const std::wstring url = L"https://music.163.com/api/song/lyric?id=" +
                           std::to_wstring(song_id) + L"&lv=1&kv=1&tv=-1";
  const HttpResult response = HttpGet(url, HeaderBlock(true), 10000);
  if (!response.ok) return false;

  JsonValue root;
  if (!ParseJson(response.body, &root)) return false;
  const JsonValue* lrc = root.Find("lrc");
  if (lrc == nullptr) return false;
  const JsonValue* lyric = lrc->Find("lyric");
  if (lyric == nullptr) return false;

  std::vector<LrcLine> main =
      StripCredits(Lrc::Parse(lyric->WStringOr(L"")), keep_credits);
  if (main.empty()) return false;

  if (want_trans) {
    if (const JsonValue* tlyric = root.Find("tlyric")) {
      if (const JsonValue* trans = tlyric->Find("lyric")) {
        main = Lrc::Merge(main, Lrc::Parse(trans->WStringOr(L"")));
      }
    }
  }
  *out = std::move(main);
  return true;
}

bool TryNetease(const std::wstring& title, const std::wstring& artist,
                int64_t duration_ms, bool artist_only, bool want_trans,
                bool keep_credits, std::vector<LrcLine>* out) {
  std::wstring query;
  if (artist_only) {
    query = artist;
  } else {
    query = title;
    if (!artist.empty()) query += L" " + artist;
  }
  if (query.empty()) return false;

  JsonValue search;
  if (!SearchNetease(query, artist_only ? 30 : 10, &search)) return false;
  const JsonValue* result = search.Find("result");
  if (result == nullptr) return false;
  const JsonValue* songs = result->Find("songs");
  if (songs == nullptr || !songs->IsArray() || songs->array.empty()) return false;

  std::vector<const JsonValue*> candidates;
  candidates.reserve(songs->array.size());
  for (const JsonValue& song : songs->array) candidates.push_back(&song);

  const int index = Lrc::PickSongIndex(candidates, title, artist, duration_ms);
  if (index < 0) return false;

  const JsonValue* id = candidates[static_cast<size_t>(index)]->Find("id");
  if (id == nullptr) return false;
  return FetchNeteaseLyrics(static_cast<int64_t>(id->NumberOr(0)), want_trans,
                            keep_credits, out);
}

// ---- LRCLIB（有官方 API，歌词是同步的）----
bool FetchLrclibGet(const std::wstring& title, const std::wstring& artist,
                    int64_t duration_ms, bool keep_credits,
                    std::vector<LrcLine>* out) {
  std::wstring url = L"https://lrclib.net/api/get?track_name=" +
                     Utf8ToWide(UrlEncode(WideToUtf8(title))) + L"&artist_name=" +
                     Utf8ToWide(UrlEncode(WideToUtf8(artist)));
  if (duration_ms > 0) {
    url += L"&duration=" + std::to_wstring(duration_ms / 1000);
  }
  const HttpResult response = HttpGet(url, HeaderBlock(false), 12000);
  if (!response.ok) return false;

  JsonValue root;
  if (!ParseJson(response.body, &root)) return false;
  const JsonValue* synced = root.Find("syncedLyrics");
  if (synced == nullptr) return false;
  const std::wstring text = synced->WStringOr(L"");
  if (text.empty()) return false;

  std::vector<LrcLine> lines = StripCredits(Lrc::Parse(text), keep_credits);
  if (lines.empty()) return false;
  *out = std::move(lines);
  return true;
}

bool FetchLrclibSearch(const std::wstring& title, const std::wstring& artist,
                       int64_t duration_ms, bool keep_credits,
                       std::vector<LrcLine>* out) {
  const std::wstring url = L"https://lrclib.net/api/search?track_name=" +
                           Utf8ToWide(UrlEncode(WideToUtf8(title))) +
                           L"&artist_name=" +
                           Utf8ToWide(UrlEncode(WideToUtf8(artist)));
  const HttpResult response = HttpGet(url, HeaderBlock(false), 12000);
  if (!response.ok) return false;

  JsonValue root;
  if (!ParseJson(response.body, &root) || !root.IsArray() || root.array.empty()) {
    return false;
  }

  // 挑第一个带同步歌词的（LRCLIB 的返回已按相关性排序）
  for (const JsonValue& item : root.array) {
    const JsonValue* synced = item.Find("syncedLyrics");
    if (synced == nullptr || synced->type != JsonValue::Type::kString) continue;
    const std::wstring text = synced->WStringOr(L"");
    if (text.empty()) continue;
    std::vector<LrcLine> lines = StripCredits(Lrc::Parse(text), keep_credits);
    if (!lines.empty()) {
      *out = std::move(lines);
      return true;
    }
  }
  (void)duration_ms;
  return false;
}

}  // namespace

LyricsCard::LyricsCard(bool show_trans, bool show_credits, std::string source)
    : show_trans_(show_trans), show_credits_(show_credits),
      source_(std::move(source)) {}

void LyricsCard::OnConfigured() {}

void LyricsCard::StartSmtc() {
  if (smtc_started_) return;
  smtc_started_ = true;
  // Smtc 内部起工作线程轮询 SMTC（详见 platform/smtc.h 的说明：
  // 主线程是 STA，WinRT 的异步 .get() 只能在 MTA 工作线程上调）
  Smtc::Instance().Start();
}

int64_t LyricsCard::PositionMs() const {
  if (!smtc_.available) return 0;
  int64_t position = smtc_.position_ms;
  if (smtc_.status == static_cast<int>(SmtcStatus::kPlaying)) {
    // 播放器隔几秒才推一次进度：补上"读数年龄"和"本地经过时间"，
    // 否则进度条和歌词是一跳一跳走的
    const int64_t local_elapsed =
        static_cast<int64_t>(GetTickCount64()) - smtc_read_at_;
    position += smtc_.position_age_ms + (local_elapsed > 0 ? local_elapsed : 0);
  }
  if (smtc_.duration_ms > 0 && position > smtc_.duration_ms) {
    position = smtc_.duration_ms;
  }
  return position < 0 ? 0 : position;
}

void LyricsCard::MaybeFetchLyrics(const std::wstring& title,
                                  const std::wstring& artist,
                                  int64_t duration_ms) {
  if (!fetch_) fetch_ = std::make_shared<LyricFetch>();
  if (fetch_->running.exchange(true)) return;
  fetch_->finished = false;
  fetch_->error.clear();
  fetch_->lines.clear();
  fetch_->track_key = title + L"|" + artist;

  auto state = fetch_;
  const std::wstring track_key = fetch_->track_key;
  const bool want_trans = show_trans_;
  const bool keep_credits = show_credits_;
  const bool netease_first = (source_ == "auto" || source_ == "netease");
  auto try_fetch = [track_key, title, artist, duration_ms, want_trans,
                    keep_credits, netease_first](std::vector<LrcLine>* out) {
    std::vector<LrcLine> lines;
    if (netease_first) {
      if (TryNetease(title, artist, duration_ms, false, want_trans, keep_credits,
                     &lines) ||
          TryNetease(title, artist, duration_ms, true, want_trans, keep_credits,
                     &lines)) {
        *out = std::move(lines);
        return std::wstring(L"网易云");
      }
      if (FetchLrclibGet(title, artist, duration_ms, keep_credits, &lines)) {
        *out = std::move(lines);
        return std::wstring(L"LRCLIB");
      }
      if (FetchLrclibSearch(title, artist, duration_ms, keep_credits, &lines)) {
        *out = std::move(lines);
        return std::wstring(L"LRCLIB");
      }
    } else {
      if (FetchLrclibGet(title, artist, duration_ms, keep_credits, &lines) ||
          FetchLrclibSearch(title, artist, duration_ms, keep_credits, &lines)) {
        *out = std::move(lines);
        return std::wstring(L"LRCLIB");
      }
      if (TryNetease(title, artist, duration_ms, false, want_trans, keep_credits,
                     &lines)) {
        *out = std::move(lines);
        return std::wstring(L"网易云");
      }
    }
    (void)track_key;
    return std::wstring();
  };

  std::thread([state, try_fetch]() {
    std::vector<LrcLine> lines;
    const std::wstring source = try_fetch(&lines);
    if (source.empty() || lines.empty()) {
      state->error = L"未找到歌词";
    } else {
      Log(L"[lyrics] %zu 行（%s）", lines.size(), source.c_str());
      state->lines = std::move(lines);
    }
    state->running = false;
    state->finished = true;
  }).detach();
}

bool LyricsCard::Update() {
  StartSmtc();
  bool redraw = false;

  // 1) 读快照（带锁拷贝，很便宜；真正轮询在 Smtc 的工作线程里）
  const SmtcSnapshot snapshot = Smtc::Instance().Snapshot();
  smtc_ = snapshot;
  smtc_read_at_ = static_cast<int64_t>(GetTickCount64());

  if (!smtc_logged_) {
    smtc_logged_ = true;
    Log(L"[lyrics] smtc available=%d status=%d app=%s title=%s dur=%lldms",
        snapshot.available ? 1 : 0, snapshot.status,
        Utf8ToWide(snapshot.app).c_str(), Utf8ToWide(snapshot.title).c_str(),
        snapshot.duration_ms);
  }

  const std::wstring title = Utf8ToWide(snapshot.title);
  const std::wstring artist = Utf8ToWide(snapshot.artist);
  const std::wstring key = title + L"|" + artist;
  if (key != track_key_) {
    track_key_ = key;
    lines_.clear();
    fetch_error_.clear();
    last_index_ = -2;
    if (!title.empty() && snapshot.available) {
      MaybeFetchLyrics(title, artist, snapshot.duration_ms);
    }
    redraw = true;
  }

  // 2) 歌词回来了
  if (fetch_ && fetch_->finished.exchange(false)) {
    if (fetch_->track_key == track_key_) {
      lines_ = fetch_->lines;
      fetch_error_ = fetch_->error;
      last_index_ = -2;
    }
    redraw = true;
  }

  // 3) 高亮行变了才重绘
  const int index = Lrc::IndexAt(lines_, PositionMs());
  if (index != last_index_) {
    last_index_ = index;
    redraw = true;
  }
  return redraw;
}

void LyricsCard::Paint(Renderer& renderer, const Theme& theme) {
  const float s = scale;
  renderer.FillRoundRect(rect, theme.card_radius * s, theme.card_bg);

  const float pad = 16.0f * s;
  const float left = rect.left + pad;
  const float right = rect.right - pad;
  float cursor = rect.top + pad;

  const std::wstring title = Utf8ToWide(smtc_.title);
  const std::wstring artist = Utf8ToWide(smtc_.artist);

  // ---- 顶部：歌名 · 歌手 ----
  TextStyle title_style;
  title_style.size = 15.0f * s;
  title_style.weight = DWRITE_FONT_WEIGHT_SEMI_BOLD;
  title_style.family = L"Microsoft YaHei UI";
  title_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  TextStyle meta_style = title_style;
  meta_style.size = 12.0f * s;
  meta_style.weight = DWRITE_FONT_WEIGHT_NORMAL;

  if (title.empty()) {
    renderer.DrawText(L"没有正在播放的音乐", renderer.TextFormat(meta_style),
                      D2D1::RectF(left, cursor, right, cursor + 22.0f * s),
                      theme.fg.WithAlpha(0.45f));
  } else {
    renderer.DrawText(title, renderer.TextFormat(title_style),
                      D2D1::RectF(left, cursor, right * 0.72f + left * 0.28f,
                                  cursor + 22.0f * s),
                      theme.fg);
    if (!artist.empty()) {
      renderer.DrawText(L"· " + artist, renderer.TextFormat(meta_style),
                        D2D1::RectF(rect.left + (rect.right - rect.left) * 0.55f,
                                    cursor, right, cursor + 22.0f * s),
                        theme.fg.WithAlpha(0.5f));
    }
  }
  cursor += 26.0f * s;

  // ---- 歌词区 ----
  const float progress_area = 26.0f * s;
  const float lyric_bottom = rect.bottom - pad - progress_area;
  const float lyric_h = lyric_bottom - cursor;

  if (lines_.empty()) {
    const std::wstring hint =
        fetch_error_.empty() && !title.empty() ? L"正在找歌词…" : fetch_error_;
    if (!hint.empty()) {
      TextStyle hint_style = meta_style;
      hint_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
      hint_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
      renderer.DrawText(hint, renderer.TextFormat(hint_style),
                        D2D1::RectF(left, cursor, right, lyric_bottom),
                        theme.fg.WithAlpha(0.4f));
    }
  } else {
    const int index = Lrc::IndexAt(lines_, PositionMs());
    // 三行窗口：上一行、当前行、下一行（前奏时把开头几行显示出来）
    const int first = index < 0 ? 0 : (index > 0 ? index - 1 : 0);
    const int last = std::min(static_cast<int>(lines_.size()) - 1,
                              (index < 0 ? 2 : index + 1));

    TextStyle current_style;
    current_style.size = 17.0f * s;
    current_style.weight = DWRITE_FONT_WEIGHT_SEMI_BOLD;
    current_style.family = L"Microsoft YaHei UI";
    current_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
    current_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
    TextStyle other_style = current_style;
    other_style.size = 13.0f * s;
    other_style.weight = DWRITE_FONT_WEIGHT_NORMAL;

    const int count = last - first + 1;
    const float row_h = lyric_h / static_cast<float>(count > 0 ? count : 1);
    for (int i = first; i <= last; ++i) {
      const LrcLine& line = lines_[static_cast<size_t>(i)];
      const bool is_current = (i == index);
      const float row_top = cursor + row_h * static_cast<float>(i - first);
      const D2D1_RECT_F row_rect =
          D2D1::RectF(left, row_top, right, row_top + row_h);
      renderer.DrawText(line.s,
                        renderer.TextFormat(is_current ? current_style : other_style),
                        row_rect,
                        theme.fg.WithAlpha(is_current ? 1.0f : 0.38f));
      if (!line.tr.empty()) {
        TextStyle trans_style = other_style;
        trans_style.size = 12.0f * s;
        renderer.DrawText(line.tr, renderer.TextFormat(trans_style),
                          D2D1::RectF(left, row_top + row_h * 0.62f, right,
                                      row_top + row_h * 0.62f + 16.0f * s),
                          theme.fg.WithAlpha(is_current ? 0.7f : 0.28f));
      }
    }
  }

  // ---- 底部：进度条 + 时间 ----
  const int64_t position = PositionMs();
  const int64_t duration = smtc_.duration_ms;
  const float bar_y = rect.bottom - pad - 6.0f * s;

  TextStyle time_style = meta_style;
  time_style.size = 10.5f * s;
  time_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  renderer.DrawText(Lrc::Format(position), renderer.TextFormat(time_style),
                    D2D1::RectF(left, bar_y - 12.0f * s, left + 60.0f * s,
                                bar_y + 2.0f * s),
                    theme.fg.WithAlpha(0.45f));

  const float bar_left = left + 46.0f * s;
  const float bar_right = right - 46.0f * s;
  renderer.FillRoundRect(D2D1::RectF(bar_left, bar_y - 1.5f * s, bar_right,
                                     bar_y + 1.5f * s),
                         1.5f * s, theme.fg.WithAlpha(0.16f));
  if (duration > 0) {
    const float ratio = std::min(1.0f, static_cast<float>(position) /
                                            static_cast<float>(duration));
    if (ratio > 0.001f) {
      renderer.FillRoundRect(
          D2D1::RectF(bar_left, bar_y - 1.5f * s,
                      bar_left + (bar_right - bar_left) * ratio, bar_y + 1.5f * s),
          1.5f * s, theme.fg.WithAlpha(0.85f));
    }
  }
  renderer.DrawText(Lrc::Format(duration), renderer.TextFormat(time_style),
                    D2D1::RectF(right - 60.0f * s, bar_y - 12.0f * s, right,
                                bar_y + 2.0f * s),
                    theme.fg.WithAlpha(0.45f));
}

}  // namespace glance
