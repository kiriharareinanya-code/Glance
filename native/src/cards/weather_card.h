// 天气卡片：小米天气 v3 数据 + 5 日预报。
//
// 数据链路（与 Flutter 版一致）：手填城市名 → 中国天气网 toy1 拿城市码 +
// open-meteo geocoding 拿经纬度 → 小米 v3 接口拿实况与预报。
// 与 Flutter 版共享 plugindata/weather.json 缓存：启动先用缓存画出来，
// 再后台拉新（有缓存时直接用缓存里的城市码，跳过 toy1——那条链路不稳）。
//
// 线程模型：网络请求在后台线程做，通过 shared_ptr<FetchState> 把结果交回
// 主线程（Update 里轮询 finished）。线程只碰 FetchState、不碰 this，
// 卡片销毁时线程还活着也不会踩野指针。
#ifndef GLANCE_NATIVE_CARDS_WEATHER_CARD_H_
#define GLANCE_NATIVE_CARDS_WEATHER_CARD_H_

#include <atomic>
#include <memory>
#include <string>
#include <vector>

#include "cards/card.h"

namespace glance {

class WeatherCard : public Card {
 public:
  struct DayForecast {
    int code = 99;
    int temp_min = 0;
    int temp_max = 0;
  };
  struct WeatherData {
    bool valid = false;
    std::wstring city;
    int temperature = 0;
    int code = 99;
    std::vector<DayForecast> days;  // 含今天，最多 5 天
  };

  WeatherCard(std::string city_setting, int refresh_min);

  bool Update() override;
  void Paint(Renderer& renderer, const Theme& theme) override;
  // 读 plugindata 缓存要按卡片 id 找，必须等工厂把 id 填好（见 card.h）
  void OnConfigured() override;

  // --capture 用：等首帧数据就绪（网络没回就返回 false，调用方超时兜底）
  bool HasData() const { return data_.valid; }
  bool ReadyForCapture() const override { return data_.valid; }

 private:
  struct Loc {
    bool valid = false;
    std::wstring name;
    std::wstring city_id;  // 中国天气网城市码（小米 locationKey 用）
    double lat = 0.0;
    double lon = 0.0;
  };

  struct FetchState {
    std::atomic<bool> running{false};
    std::atomic<bool> finished{false};
    WeatherData data;
    Loc loc;
    std::wstring error;
  };

  void LoadCached();
  bool NeedsRefresh() const;
  void StartFetch();

  std::string city_setting_;
  int refresh_min_ = 30;
  WeatherData data_;
  Loc loc_;
  std::wstring status_;  // 加载中/错误提示（数据就绪后清空）
  std::shared_ptr<FetchState> fetch_;
  unsigned long long last_fetch_ms_ = 0;
};

}  // namespace glance

#endif  // GLANCE_NATIVE_CARDS_WEATHER_CARD_H_
