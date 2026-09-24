// 歌词卡片：SMTC 拿"正在放什么" + 网络取歌词。
//
// 两条数据链（与 Flutter 版一致）：
//   播放信息 ← 系统媒体控件（platform/smtc.h，从 runner 原样搬来的实现）
//   歌词     ← 网易云（主）→ LRCLIB（兜底），选歌逻辑在 core/lrc.h
//
// 位置不靠 SMTC 逐帧喂：播放器隔几秒才推一次进度。所以记下读数时刻，
// 播放中按本地经过时间往前外推（SmtcSnapshot.updated_at_ms 就是为此存在）。
//
// 本轮范围：歌曲信息 + 歌词（当前行高亮）+ 进度条。
// 封面图（要 WIC 解码 + 圆角裁剪）与拖动进度归到后续。
#ifndef GLANCE_NATIVE_CARDS_LYRICS_CARD_H_
#define GLANCE_NATIVE_CARDS_LYRICS_CARD_H_

#include <atomic>
#include <memory>
#include <string>
#include <vector>

#include "cards/card.h"
#include "core/lrc.h"
#include "platform/smtc.h"

namespace glance {

class LyricsCard : public Card {
 public:
  LyricsCard(bool show_trans, bool show_credits, std::string source);

  bool Update() override;
  void Paint(Renderer& renderer, const Theme& theme) override;
  void OnConfigured() override;

  // --capture 用：等 SMTC 首轮采样 + 有歌时等歌词回来
  bool ReadyForCapture() const override {
    if (!smtc_logged_) return false;
    const bool waiting_lyrics = smtc_.available && !smtc_.title.empty() &&
                                lines_.empty() && fetch_error_.empty();
    return !waiting_lyrics;
  }

 private:
  struct LyricFetch {
    std::atomic<bool> running{false};
    std::atomic<bool> finished{false};
    std::wstring track_key;  // "标题|歌手"，用于把结果对上当前歌曲
    std::vector<LrcLine> lines;
    std::wstring error;
  };

  // 当前播放位置（毫秒）：SMTC 读数 + 播放中按经过时间外推
  int64_t PositionMs() const;
  void MaybeFetchLyrics(const std::wstring& title, const std::wstring& artist,
                        int64_t duration_ms);
  void StartSmtc();

  bool show_trans_ = true;
  bool show_credits_ = false;
  std::string source_ = "auto";

  SmtcSnapshot smtc_;
  int64_t smtc_read_at_ = 0;  // 读到这份快照的本地时刻（GetTickCount64）
  std::wstring track_key_;
  std::wstring fetch_error_;

  std::vector<LrcLine> lines_;
  std::shared_ptr<LyricFetch> fetch_;
  bool smtc_started_ = false;
  bool smtc_logged_ = false;  // 首次读到快照时打一条日志，确认 SMTC 通路
  // 歌词高亮变化才重绘（100ms 粒度检查）
  int last_index_ = -2;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_LYRICS_CARD_H_
