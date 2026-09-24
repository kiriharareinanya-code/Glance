#include "cards/weather_card.h"

#include <windows.h>

#include <thread>

#include "cards/weather_icon.h"
#include "core/app_state.h"
#include "core/http.h"
#include "core/json.h"
#include "core/date_util.h"
#include "platform/log.h"

namespace glance {
namespace {

constexpr const wchar_t* kBrowserUserAgent =
    L"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    L"(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

std::wstring HeaderBlock(const wchar_t* referer) {
  std::wstring headers =
      L"User-Agent: ";
  headers += kBrowserUserAgent;
  headers += L"\r\nAccept: application/json, text/plain, */*\r\n"
             L"Accept-Language: zh-CN,zh;q=0.9,en;q=0.8\r\n";
  if (referer != nullptr) {
    headers += L"Referer: ";
    headers += referer;
    headers += L"\r\n";
  }
  return headers;
}

int CodeFromValue(const JsonValue* node) {
  if (node == nullptr) return 99;
  return static_cast<int>(node->NumberOr(99.0));
}

}  // namespace

WeatherCard::WeatherCard(std::string city_setting, int refresh_min)
    : city_setting_(std::move(city_setting)), refresh_min_(refresh_min) {
  if (refresh_min_ < 5) refresh_min_ = 5;
  // 缓存读取放在 OnConfigured（那时才拿得到卡片 id），见 card.h 的说明
}

void WeatherCard::OnConfigured() {
  LoadCached();
  if (!data_.valid) status_ = L"正在获取天气…";
}

bool WeatherCard::Update() {
  bool redraw = false;

  // 后台结果回来了：接过来
  if (fetch_ && fetch_->finished.exchange(false)) {
    if (fetch_->data.valid) {
      data_ = fetch_->data;
      loc_ = fetch_->loc;
      status_.clear();
    } else {
      // 有旧数据就留着旧数据，只在没有数据时把错误显示出来
      status_ = fetch_->error.empty() ? L"天气不可用" : fetch_->error;
      if (data_.valid) status_.clear();
    }
    redraw = true;
  }

  if (NeedsRefresh()) StartFetch();
  return redraw;
}

bool WeatherCard::NeedsRefresh() const {
  if (fetch_ && fetch_->running.load()) return false;
  if (last_fetch_ms_ == 0) return true;  // 首次
  const unsigned long long now = GetTickCount64();
  return (now - last_fetch_ms_) >=
         static_cast<unsigned long long>(refresh_min_) * 60ull * 1000ull;
}

void WeatherCard::StartFetch() {
  if (!fetch_) fetch_ = std::make_shared<FetchState>();
  if (fetch_->running.exchange(true)) return;  // 已在跑
  fetch_->finished = false;
  fetch_->error.clear();
  fetch_->data = WeatherData{};
  fetch_->loc = Loc{};

  last_fetch_ms_ = GetTickCount64();

  const std::string city_setting = city_setting_;
  const Loc cached_loc = loc_;  // 有缓存 loc 就用它，省掉不稳的 toy1 那一步
  auto state = fetch_;

  // 分离线程：完成即退出。只捕获 state（shared_ptr），不碰 this。
  std::thread([state, city_setting, cached_loc]() {
    state->running = true;

    Loc loc = cached_loc;
    if (!loc.valid && !city_setting.empty()) {
      // 1) toy1 拿城市码。返回是 JSONP：([{"ref":"101250309~天元~..."}])
      const std::string encoded = UrlEncode(city_setting);
      const std::wstring toy1 =
          L"https://toy1.weather.com.cn/search?cityname=" +
          Utf8ToWide(encoded);
      const HttpResult search =
          HttpGet(toy1, HeaderBlock(L"https://www.weather.com.cn/"), 10000);
      if (!search.ok) {
        state->error = L"城市查询失败（" + Utf8ToWide(search.error) + L"）";
        state->running = false;
        state->finished = true;
        return;
      }
      // 剥 JSONP 外壳
      const size_t begin = search.body.find('[');
      const size_t end = search.body.rfind(']');
      if (begin == std::string::npos || end == std::string::npos || end <= begin) {
        state->error = L"没找到城市「" + Utf8ToWide(city_setting) + L"」";
        state->running = false;
        state->finished = true;
        return;
      }
      JsonValue hits;
      if (!ParseJson(search.body.substr(begin, end - begin + 1), &hits) ||
          !hits.IsArray() || hits.array.empty()) {
        state->error = L"没找到城市「" + Utf8ToWide(city_setting) + L"」";
        state->running = false;
        state->finished = true;
        return;
      }
      const JsonValue* ref = hits.array.front().Find("ref");
      const std::string ref_text = ref != nullptr ? ref->StringOr("") : "";
      const size_t tilde = ref_text.find('~');
      if (ref_text.empty() || tilde == std::string::npos) {
        state->error = L"城市码解析失败";
        state->running = false;
        state->finished = true;
        return;
      }
      loc.city_id = Utf8ToWide(ref_text.substr(0, tilde));
      // ref 的后续字段是拼音/编码混排（实测"株洲"那条第二段是 "hunan"），
      // 拿它当显示名会显示成拼音。显示名留给 geocoding 的中文结果，
      // 兜底用手填的城市名。

      // 2) geocoding 拿坐标（小米 v3 要求经纬度）
      const std::wstring geo =
          L"https://geocoding-api.open-meteo.com/v1/search?name=" +
          Utf8ToWide(encoded) + L"&count=1&language=zh&format=json";
      const HttpResult geo_result = HttpGet(geo, HeaderBlock(nullptr), 10000);
      if (geo_result.ok) {
        JsonValue geo_json;
        if (ParseJson(geo_result.body, &geo_json)) {
          if (const JsonValue* results = geo_json.Find("results");
              results != nullptr && results->IsArray() && !results->array.empty()) {
            const JsonValue& first = results->array.front();
            if (const JsonValue* lat = first.Find("latitude")) {
              loc.lat = lat->NumberOr(0.0);
            }
            if (const JsonValue* lon = first.Find("longitude")) {
              loc.lon = lon->NumberOr(0.0);
            }
            // geocoding 给的是标准中文地名（"株洲"），用它当显示名
            if (const JsonValue* name = first.Find("name")) {
              loc.name = name->WStringOr(L"");
            }
          }
        }
      }
      loc.valid = !loc.city_id.empty();
      if (!loc.valid) {
        state->error = L"城市「" + Utf8ToWide(city_setting) + L"」解析失败";
        state->running = false;
        state->finished = true;
        return;
      }
      // 兜底：geocoding 没给名字就用手填的城市名（比拼音强）
      if (loc.name.empty()) loc.name = Utf8ToWide(city_setting);
    } else if (!loc.valid) {
      // 既没有设置也没有缓存：自动定位这一版还没做，先如实报错
      state->error = L"没有可用城市（请在设置里填城市）";
      state->running = false;
      state->finished = true;
      return;
    }

    // 3) 小米 v3 主接口
    wchar_t coord[96] = {};
    swprintf_s(coord, L"%.4f", loc.lat);
    std::wstring url =
        L"https://weatherapi.market.xiaomi.com/wtr-v3/weather/all?latitude=";
    url += coord;
    url += L"&longitude=";
    swprintf_s(coord, L"%.4f", loc.lon);
    url += coord;
    url += L"&locationKey=weathercn%3A";
    url += loc.city_id;
    url += L"&days=5&appKey=weather20151024&sign=zUFJoAR2ZVrDy1vF3D07"
           L"&isGlobal=false&locale=zh_cn";

    const HttpResult response = HttpGet(url, HeaderBlock(nullptr), 15000);
    if (!response.ok) {
      state->error = L"获取天气失败（" + Utf8ToWide(response.error) + L"）";
      state->running = false;
      state->finished = true;
      return;
    }

    JsonValue root;
    if (!ParseJson(response.body, &root)) {
      state->error = L"天气数据解析失败";
      state->running = false;
      state->finished = true;
      return;
    }

    WeatherData parsed;
    const JsonValue* current = root.Find("current");
    const JsonValue* daily = root.Find("forecastDaily");
    if (current == nullptr || daily == nullptr) {
      state->error = L"天气数据不完整";
      state->running = false;
      state->finished = true;
      return;
    }

    if (const JsonValue* temp = current->Find("temperature")) {
      parsed.temperature = static_cast<int>(temp->Find("value") != nullptr
                                                ? temp->Find("value")->NumberOr(0.0)
                                                : 0.0);
    }
    parsed.code = CodeFromValue(current->Find("weather"));

    // forecastDaily.temperature.value = [{"from": 最高, "to": 最低}, ...]
    // forecastDaily.weather.value      = [{"from": 白天码, "to": 夜间码}, ...]
    const JsonValue* temps = daily->Find("temperature");
    const JsonValue* codes = daily->Find("weather");
    const JsonValue* temp_values = temps != nullptr ? temps->Find("value") : nullptr;
    const JsonValue* code_values = codes != nullptr ? codes->Find("value") : nullptr;
    if (temp_values != nullptr && temp_values->IsArray()) {
      for (size_t i = 0; i < temp_values->array.size() && i < 5; ++i) {
        DayForecast day;
        const JsonValue& item = temp_values->array[i];
        if (const JsonValue* from = item.Find("from")) {
          day.temp_max = static_cast<int>(from->NumberOr(0.0));
        }
        if (const JsonValue* to = item.Find("to")) {
          day.temp_min = static_cast<int>(to->NumberOr(0.0));
        }
        if (code_values != nullptr && code_values->IsArray() &&
            i < code_values->array.size()) {
          day.code = CodeFromValue(code_values->array[i].Find("from"));
        }
        parsed.days.push_back(day);
      }
    }

    parsed.city = loc.name;
    parsed.valid = !parsed.days.empty();
    if (!parsed.valid) {
      state->error = L"天气数据不完整";
    } else {
      Log(L"[weather] ok: %s %d℃ %s (%zu 天预报)", parsed.city.c_str(),
          parsed.temperature, DescriptionForCode(parsed.code),
          parsed.days.size());
    }

    state->data = std::move(parsed);
    state->loc = loc;
    state->running = false;
    state->finished = true;
  }).detach();
}

void WeatherCard::LoadCached() {
  // 缓存结构（与 Flutter 版共享）：{"@inst:<cardId>:cache": {"data": {...}, "loc": {...}}}
  const std::wstring path = FindUserDataFile(L"plugindata\\weather.json");
  if (path.empty()) return;
  JsonValue root;
  if (!ParseJson(ReadFileUtf8(path), &root)) return;

  const std::string key = "@inst:" + id + ":cache";
  const JsonValue* entry = root.Find(key);
  if (entry == nullptr) return;

  if (const JsonValue* loc = entry->Find("loc")) {
    if (const JsonValue* city_id = loc->Find("cityId")) {
      loc_.city_id = city_id->WStringOr(L"");
    }
    if (const JsonValue* name = loc->Find("name")) {
      loc_.name = name->WStringOr(L"");
    }
    if (const JsonValue* lat = loc->Find("lat")) loc_.lat = lat->NumberOr(0.0);
    if (const JsonValue* lon = loc->Find("lon")) loc_.lon = lon->NumberOr(0.0);
    loc_.valid = !loc_.city_id.empty();
  }

  const JsonValue* data = entry->Find("data");
  if (data == nullptr) return;
  if (const JsonValue* current = data->Find("current")) {
    if (const JsonValue* temp = current->Find("temperature")) {
      data_.temperature = static_cast<int>(
          temp->Find("value") != nullptr ? temp->Find("value")->NumberOr(0.0) : 0.0);
    }
    data_.code = CodeFromValue(current->Find("weather"));
  }
  if (const JsonValue* daily = data->Find("forecastDaily")) {
    const JsonValue* temps = daily->Find("temperature");
    const JsonValue* codes = daily->Find("weather");
    const JsonValue* temp_values = temps != nullptr ? temps->Find("value") : nullptr;
    const JsonValue* code_values = codes != nullptr ? codes->Find("value") : nullptr;
    if (temp_values != nullptr && temp_values->IsArray()) {
      for (size_t i = 0; i < temp_values->array.size() && i < 5; ++i) {
        DayForecast day;
        const JsonValue& item = temp_values->array[i];
        if (const JsonValue* from = item.Find("from")) {
          day.temp_max = static_cast<int>(from->NumberOr(0.0));
        }
        if (const JsonValue* to = item.Find("to")) {
          day.temp_min = static_cast<int>(to->NumberOr(0.0));
        }
        if (code_values != nullptr && code_values->IsArray() &&
            i < code_values->array.size()) {
          day.code = CodeFromValue(code_values->array[i].Find("from"));
        }
        data_.days.push_back(day);
      }
    }
  }

  data_.city = loc_.name;
  data_.valid = !data_.days.empty();
  if (data_.valid) {
    Log(L"[weather] cache hit: %s %d℃ (%zu 天)", data_.city.c_str(),
        data_.temperature, data_.days.size());
  }
}

void WeatherCard::Paint(Renderer& renderer, const Theme& theme) {
  const float s = scale;
  renderer.FillCardBackground(rect, theme.card_radius * s, theme.card_bg,
                              theme.CardTintAlpha());

  const float pad_x = 18.0f * s;
  const float pad_y = 16.0f * s;
  const float left = rect.left + pad_x;
  const float right = rect.right - pad_x;
  float cursor = rect.top + pad_y;

  if (!data_.valid) {
    // 无数据：居中显示状态（"正在获取天气…" 或错误原因）
    TextStyle hint;
    hint.size = 13.0f * s;
    hint.family = L"Microsoft YaHei UI";
    hint.align = DWRITE_TEXT_ALIGNMENT_CENTER;
    hint.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
    renderer.DrawText(status_, renderer.TextFormat(hint),
                      D2D1::RectF(left, rect.top, right, rect.bottom),
                      theme.fg.WithAlpha(0.55f));
    return;
  }

  // ---- 城市名（前缀一个语义色小圆点，与 Flutter 版一致）----
  const wchar_t* cur_kind = IconKindForCode(data_.code);
  const Color accent = ColorForIconKind(cur_kind);

  renderer.FillCircle(left + 2.0f * s, cursor + 7.0f * s, 2.0f * s, accent);
  TextStyle city_style;
  city_style.size = 13.0f * s;
  city_style.family = L"Microsoft YaHei UI";
  city_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  renderer.DrawText(data_.city, renderer.TextFormat(city_style),
                    D2D1::RectF(left + 10.0f * s, cursor, right, cursor + 18.0f * s),
                    theme.fg.WithAlpha(0.55f));
  cursor += 26.0f * s;

  // ---- 大字温度 + 图标 + 描述 ----
  const float big = 44.0f * s;
  TextStyle temp_style;
  temp_style.size = big;
  temp_style.weight = DWRITE_FONT_WEIGHT_BOLD;
  temp_style.family = L"Segoe UI";
  temp_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  const std::wstring temp_text =
      std::to_wstring(data_.temperature) + L"\u00B0";
  const float temp_h = big * 1.25f;
  renderer.DrawText(temp_text, renderer.TextFormat(temp_style),
                    D2D1::RectF(left, cursor, left + 150.0f * s, cursor + temp_h),
                    theme.fg);

  // 图标在右侧，描述在图标下面
  const float icon_size = 40.0f * s;
  const float icon_cx = right - icon_size * 0.5f - 2.0f * s;
  const float icon_cy = cursor + temp_h * 0.42f;
  DrawWeatherIcon(renderer, cur_kind, icon_cx, icon_cy, icon_size, accent);

  TextStyle desc_style;
  desc_style.size = 13.0f * s;
  desc_style.family = L"Microsoft YaHei UI";
  desc_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  desc_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;
  renderer.DrawText(DescriptionForCode(data_.code),
                    renderer.TextFormat(desc_style),
                    D2D1::RectF(icon_cx - 60.0f * s, icon_cy + icon_size * 0.55f,
                                icon_cx + 60.0f * s,
                                icon_cy + icon_size * 0.55f + 18.0f * s),
                    theme.fg.WithAlpha(0.72f));
  cursor += temp_h + 6.0f * s;

  // ---- 5 日预报 ----
  const int day_count = static_cast<int>(data_.days.size());
  if (day_count == 0) return;
  const float col_w = (right - left) / static_cast<float>(day_count);
  const float row_h = rect.bottom - pad_y - cursor;
  if (row_h <= 10.0f * s) return;

  static const wchar_t* kWeekdays[] = {L"周日", L"周一", L"周二", L"周三",
                                       L"周四", L"周五", L"周六"};
  SYSTEMTIME now = {};
  GetLocalTime(&now);
  const int64_t today_days = DaysFromCivil(now.wYear, now.wMonth, now.wDay);

  TextStyle label_style;
  label_style.size = 11.0f * s;
  label_style.family = L"Microsoft YaHei UI";
  label_style.align = DWRITE_TEXT_ALIGNMENT_CENTER;
  label_style.valign = DWRITE_PARAGRAPH_ALIGNMENT_CENTER;

  for (int i = 0; i < day_count; ++i) {
    const DayForecast& day = data_.days[static_cast<size_t>(i)];
    const float cx = left + col_w * (static_cast<float>(i) + 0.5f);

    // 第 0 天是今天、第 1 天明天，其余按日期算周几
    int y = 0, m = 0, d = 0;
    CivilFromDays(today_days + i, &y, &m, &d);
    const std::wstring label =
        i == 0 ? L"今天"
               : (i == 1 ? L"明天" : kWeekdays[WeekdayFromDays(today_days + i)]);

    float cy = cursor;
    renderer.DrawText(label, renderer.TextFormat(label_style),
                      D2D1::RectF(cx - col_w * 0.5f, cy, cx + col_w * 0.5f,
                                  cy + 16.0f * s),
                      theme.fg.WithAlpha(i == 0 ? 0.9f : 0.6f));
    cy += 18.0f * s;

    const wchar_t* kind = IconKindForCode(day.code);
    const float small_icon = 22.0f * s;
    DrawWeatherIcon(renderer, kind, cx, cy + small_icon * 0.5f, small_icon,
                    ColorForIconKind(kind));
    cy += small_icon + 4.0f * s;

    const std::wstring range =
        std::to_wstring(day.temp_max) + L"/" + std::to_wstring(day.temp_min);
    renderer.DrawText(range, renderer.TextFormat(label_style),
                      D2D1::RectF(cx - col_w * 0.5f, cy, cx + col_w * 0.5f,
                                  cy + 16.0f * s),
                      theme.fg.WithAlpha(0.82f));
  }
}

}  // namespace glance
