// Ported from Lyricify.Lyrics.Helper/Providers/Web/SodaMusic/Response.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../../json_utils.dart';


List<String>? _strList(dynamic v) =>
    v is List ? [for (final e in v) asStr(e)] : null;

Map<String, LyricTranslation>? _translationMap(dynamic v) {
  if (v is! Map) return null;
  final result = <String, LyricTranslation>{};
  v.forEach((key, value) {
    result['$key'] = LyricTranslation.fromJson(asObj(value));
  });
  return result;
}

Map<String, QualityDetailWrap>? _qualityMap(dynamic v) {
  if (v is! Map) return null;
  final result = <String, QualityDetailWrap>{};
  v.forEach((key, value) {
    result['$key'] = QualityDetailWrap.fromJson(asObj(value));
  });
  return result;
}

class SearchResult {
  SearchResult({
    required this.statusCode,
    required this.statusInfo,
    required this.resultGroups,
    required this.extra,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        statusCode: asIntOrNull(j['status_code']),
        statusInfo: j['status_info'] == null
            ? null
            : StatusInfo.fromJson(asObj(j['status_info'])),
        resultGroups: j['result_groups'] is List
            ? [
                for (final e in asArr(j['result_groups']))
                  ResultGroup.fromJson(asObj(e))
              ]
            : null,
        extra: j['extra'] == null
            ? null
            : Extra.fromJson(asObj(j['extra'])),
      );

  int? statusCode;

  StatusInfo? statusInfo;

  List<ResultGroup>? resultGroups;

  Extra? extra;
}

class StatusInfo {
  StatusInfo({required this.logId, required this.statusMsg, required this.now, required this.nowTsMs});

  factory StatusInfo.fromJson(Map<String, dynamic> j) => StatusInfo(
        logId: asStr(j['log_id']),
        statusMsg: asStr(j['status_msg']),
        now: asInt(j['now']),
        nowTsMs: asInt(j['now_ts_ms']),
      );

  String logId;

  String statusMsg;

  int now;

  int nowTsMs;
}

class Extra {
  Extra({required this.logExtra});

  factory Extra.fromJson(Map<String, dynamic> j) =>
      Extra(logExtra: asStr(j['log_extra']));

  String logExtra;
}

class ResultGroup {
  ResultGroup({
    required this.id,
    required this.nextCursor,
    required this.hasMore,
    required this.data,
    required this.displayViewAll,
    required this.displayTitle,
    required this.description,
  });

  factory ResultGroup.fromJson(Map<String, dynamic> j) => ResultGroup(
        id: asStr(j['id']),
        nextCursor: asStr(j['next_cursor']),
        hasMore: asBool(j['has_more']),
        data: j['data'] is List
            ? [for (final e in asArr(j['data'])) ResultGroupItem.fromJson(asObj(e))]
            : null,
        displayViewAll: j['display_view_all'] == null
            ? null
            : asBool(j['display_view_all']),
        displayTitle: asStr(j['display_title']),
        description: asStr(j['description']),
      );

  String id;

  String nextCursor;

  bool hasMore;

  List<ResultGroupItem>? data;

  bool? displayViewAll;

  String displayTitle;

  String description;
}

class ResultGroupItem {
  ResultGroupItem({required this.meta, required this.entity});

  factory ResultGroupItem.fromJson(Map<String, dynamic> j) => ResultGroupItem(
        meta: j['meta'] == null ? null : Meta.fromJson(asObj(j['meta'])),
        entity: j['entity'] == null ? null : Entity.fromJson(asObj(j['entity'])),
      );

  Meta? meta;

  Entity? entity;
}

class Meta {
  Meta({required this.itemType});

  factory Meta.fromJson(Map<String, dynamic> j) =>
      Meta(itemType: asStr(j['item_type']));

  String itemType;
}

class Entity {
  Entity({required this.track});

  factory Entity.fromJson(Map<String, dynamic> j) => Entity(
        track: j['track'] == null
            ? null
            : TrackContainer.fromJson(asObj(j['track'])),
      );

  TrackContainer? track;
}

class TrackContainer {
  TrackContainer({
    required this.id,
    required this.album,
    required this.artists,
    required this.duration,
    required this.name,
    required this.preview,
    required this.state,
    required this.stats,
    required this.vid,
    required this.labelInfo,
    required this.simId,
    required this.bitRates,
    required this.auditionInfo,
    required this.songMakerTeam,
    required this.mediaType,
    required this.explicit,
    required this.chorus,
    required this.colors,
    required this.limitedFreeInfo,
    required this.vocal,
    required this.langCodes,
    required this.firstVocal,
    required this.sharablePlatforms,
    required this.playableRange,
    required this.plugStatus,
    required this.tags,
    required this.fragments,
  });

  factory TrackContainer.fromJson(Map<String, dynamic> j) => TrackContainer(
        id: asStr(j['id']),
        album: j['album'] == null ? null : Album.fromJson(asObj(j['album'])),
        artists: j['artists'] is List
            ? [for (final e in asArr(j['artists'])) Artist.fromJson(asObj(e))]
            : null,
        duration: asInt(j['duration']),
        name: asStr(j['name']),
        preview:
            j['preview'] == null ? null : Preview.fromJson(asObj(j['preview'])),
        state: j['state'] == null ? null : State.fromJson(asObj(j['state'])),
        stats: j['stats'] == null ? null : Stats.fromJson(asObj(j['stats'])),
        vid: asStr(j['vid']),
        labelInfo: j['label_info'] == null
            ? null
            : LabelInfo.fromJson(asObj(j['label_info'])),
        simId: asIntOrNull(j['sim_id']),
        bitRates: j['bit_rates'] is List
            ? [for (final e in asArr(j['bit_rates'])) BitRateItem.fromJson(asObj(e))]
            : null,
        auditionInfo: j['audition_info'] == null
            ? null
            : AuditionInfo.fromJson(asObj(j['audition_info'])),
        songMakerTeam: j['song_maker_team'] == null
            ? null
            : SongMakerTeam.fromJson(asObj(j['song_maker_team'])),
        mediaType: asStr(j['media_type']),
        explicit: j['explicit'] == null ? null : asBool(j['explicit']),
        chorus: j['chorus'] == null ? null : Chorus.fromJson(asObj(j['chorus'])),
        colors: j['colors'] == null ? null : Colors.fromJson(asObj(j['colors'])),
        limitedFreeInfo: j['limited_free_info'],
        vocal: asIntOrNull(j['vocal']),
        langCodes: _strList(j['lang_codes']),
        firstVocal: j['first_vocal'] == null
            ? null
            : Range.fromJson(asObj(j['first_vocal'])),
        sharablePlatforms: _strList(j['sharable_platforms']),
        playableRange: j['playable_range'] == null
            ? null
            : Range.fromJson(asObj(j['playable_range'])),
        plugStatus: j['plug_status'] == null
            ? null
            : PlugStatus.fromJson(asObj(j['plug_status'])),
        tags: j['tags'] is List
            ? [for (final e in asArr(j['tags'])) TagWrapper.fromJson(asObj(e))]
            : null,
        fragments: j['fragments'] is List
            ? [for (final e in asArr(j['fragments'])) Fragment.fromJson(asObj(e))]
            : null,
      );

  String id;

  Album? album;

  List<Artist>? artists;

  int duration;

  String name;

  Preview? preview;

  State? state;

  Stats? stats;

  String vid;

  LabelInfo? labelInfo;

  int? simId;

  List<BitRateItem>? bitRates;

  AuditionInfo? auditionInfo;

  SongMakerTeam? songMakerTeam;

  String mediaType;

  bool? explicit;

  Chorus? chorus;

  Colors? colors;

  Object? limitedFreeInfo;

  int? vocal;

  List<String>? langCodes;

  Range? firstVocal;

  List<String>? sharablePlatforms;

  Range? playableRange;

  PlugStatus? plugStatus;

  List<TagWrapper>? tags;

  List<Fragment>? fragments;
}

class Album {
  Album({
    required this.id,
    required this.name,
    required this.releaseDate,
    required this.urlCover,
    required this.urlPlayerBg,
    required this.coverGradientEffectColor,
    required this.playingWaveColor,
    required this.pausedWaveColor,
  });

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: asStr(j['id']),
        name: asStr(j['name']),
        releaseDate: asInt(j['release_date']),
        urlCover: j['url_cover'] == null
            ? null
            : UrlWithTemplate.fromJson(asObj(j['url_cover'])),
        urlPlayerBg: j['url_player_bg'] == null
            ? null
            : UrlWithTemplate.fromJson(asObj(j['url_player_bg'])),
        coverGradientEffectColor: j['cover_gradient_effect_color'] is List
            ? [
                for (final e in asArr(j['cover_gradient_effect_color']))
                  RgbColor.fromJson(asObj(e))
              ]
            : null,
        playingWaveColor: j['playing_wave_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['playing_wave_color'])),
        pausedWaveColor: j['paused_wave_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['paused_wave_color'])),
      );

  String id;

  String name;

  int releaseDate;

  UrlWithTemplate? urlCover;

  UrlWithTemplate? urlPlayerBg;

  List<RgbColor>? coverGradientEffectColor;

  RgbaColor? playingWaveColor;

  RgbaColor? pausedWaveColor;
}

class UrlWithTemplate {
  UrlWithTemplate({required this.uri, required this.urls, required this.template, required this.templatePrefix});

  factory UrlWithTemplate.fromJson(Map<String, dynamic> j) => UrlWithTemplate(
        uri: asStr(j['uri']),
        urls: _strList(j['urls']),
        template: asStr(j['template']),
        templatePrefix: asStr(j['template_prefix']),
      );

  String uri;

  List<String>? urls;

  String template;

  String templatePrefix;
}

class Artist {
  Artist({
    required this.id,
    required this.name,
    required this.urlAvatar,
    required this.state,
    required this.userInfo,
    required this.simpleDisplayName,
    required this.userArtistType,
  });

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        id: asStr(j['id']),
        name: asStr(j['name']),
        urlAvatar: j['url_avatar'] == null
            ? null
            : UrlWithTemplate.fromJson(asObj(j['url_avatar'])),
        state: j['state'] == null ? null : State.fromJson(asObj(j['state'])),
        userInfo: j['user_info'] == null
            ? null
            : ArtistUserInfo.fromJson(asObj(j['user_info'])),
        simpleDisplayName: asStr(j['simple_display_name']),
        userArtistType: asIntOrNull(j['user_artist_type']),
      );

  String id;

  String name;

  UrlWithTemplate? urlAvatar;

  State? state;

  ArtistUserInfo? userInfo;

  String simpleDisplayName;

  int? userArtistType;
}

class ArtistUserInfo {
  ArtistUserInfo({
    required this.id,
    required this.nickname,
    required this.mediumAvatarUrl,
    required this.thumbAvatarUrl,
    required this.artistId,
    required this.secret,
    required this.testTag,
    required this.vipStage,
    required this.isVip,
  });

  factory ArtistUserInfo.fromJson(Map<String, dynamic> j) => ArtistUserInfo(
        id: asStr(j['id']),
        nickname: asStr(j['nickname']),
        mediumAvatarUrl: j['medium_avatar_url'] == null
            ? null
            : UrlsOnly.fromJson(asObj(j['medium_avatar_url'])),
        thumbAvatarUrl: j['thumb_avatar_url'] == null
            ? null
            : UrlsOnly.fromJson(asObj(j['thumb_avatar_url'])),
        artistId: asStr(j['artist_id']),
        secret: j['secret'] == null ? null : asBool(j['secret']),
        testTag: asIntOrNull(j['test_tag']),
        vipStage: asStr(j['vip_stage']),
        isVip: j['is_vip'] == null ? null : asBool(j['is_vip']),
      );

  String id;

  String nickname;

  UrlsOnly? mediumAvatarUrl;

  UrlsOnly? thumbAvatarUrl;

  String artistId;

  bool? secret;

  int? testTag;

  String vipStage;

  bool? isVip;
}

class UrlsOnly {
  UrlsOnly({required this.urls, required this.needCompleteUrl});

  factory UrlsOnly.fromJson(Map<String, dynamic> j) => UrlsOnly(
        urls: _strList(j['urls']),
        needCompleteUrl: j['need_complete_url'] == null
            ? null
            : asBool(j['need_complete_url']),
      );

  List<String>? urls;

  bool? needCompleteUrl;
}

class State {
  State({required this.blockedByMe});

  factory State.fromJson(Map<String, dynamic> j) =>
      State(blockedByMe: j['blocked_by_me'] == null ? null : asBool(j['blocked_by_me']));

  bool? blockedByMe;
}

class Preview {
  Preview({required this.duration, required this.start, required this.vid, required this.bitRates});

  factory Preview.fromJson(Map<String, dynamic> j) => Preview(
        duration: asIntOrNull(j['duration']),
        start: asIntOrNull(j['start']),
        vid: asStr(j['vid']),
        bitRates: j['bit_rates'] is List
            ? [for (final e in asArr(j['bit_rates'])) BitRateItem.fromJson(asObj(e))]
            : null,
      );

  int? duration;

  int? start;

  String vid;

  List<BitRateItem>? bitRates;
}

class BitRateItem {
  BitRateItem({required this.br, required this.size, required this.quality});

  factory BitRateItem.fromJson(Map<String, dynamic> j) => BitRateItem(
        br: asInt(j['br']),
        size: asInt(j['size']),
        quality: asStr(j['quality']),
      );

  int br;

  int size;

  String quality;
}

class Stats {
  Stats({required this.countCollected, required this.countComment, required this.countShared});

  factory Stats.fromJson(Map<String, dynamic> j) => Stats(
        countCollected: asIntOrNull(j['count_collected']),
        countComment: asIntOrNull(j['count_comment']),
        countShared: asIntOrNull(j['count_shared']),
      );

  int? countCollected;

  int? countComment;

  int? countShared;
}

class LabelInfo {
  LabelInfo({
    required this.onlyVipDownload,
    required this.onlyVipPlayable,
    required this.qualityOnlyVipCanDownload,
    required this.qualityOnlyVipCanPlay,
    required this.isOriginal,
    required this.qualityMap,
  });

  factory LabelInfo.fromJson(Map<String, dynamic> j) => LabelInfo(
        onlyVipDownload:
            j['only_vip_download'] == null ? null : asBool(j['only_vip_download']),
        onlyVipPlayable:
            j['only_vip_playable'] == null ? null : asBool(j['only_vip_playable']),
        qualityOnlyVipCanDownload: _strList(j['quality_only_vip_can_download']),
        qualityOnlyVipCanPlay: _strList(j['quality_only_vip_can_play']),
        isOriginal: j['is_original'] == null ? null : asBool(j['is_original']),
        qualityMap: _qualityMap(j['quality_map']),
      );

  bool? onlyVipDownload;

  bool? onlyVipPlayable;

  List<String>? qualityOnlyVipCanDownload;

  List<String>? qualityOnlyVipCanPlay;

  bool? isOriginal;

  Map<String, QualityDetailWrap>? qualityMap;
}

class QualityDetailWrap {
  QualityDetailWrap({required this.playDetail, required this.downloadDetail});

  factory QualityDetailWrap.fromJson(Map<String, dynamic> j) =>
      QualityDetailWrap(
        playDetail: j['play_detail'] == null
            ? null
            : QualityDetail.fromJson(asObj(j['play_detail'])),
        downloadDetail: j['download_detail'] == null
            ? null
            : QualityDetail.fromJson(asObj(j['download_detail'])),
      );

  QualityDetail? playDetail;

  QualityDetail? downloadDetail;
}

class QualityDetail {
  QualityDetail({required this.condition, required this.needVip, required this.needPurchase});

  factory QualityDetail.fromJson(Map<String, dynamic> j) => QualityDetail(
        condition: asStr(j['condition']),
        needVip: j['need_vip'] == null ? null : asBool(j['need_vip']),
        needPurchase: j['need_purchase'] == null ? null : asBool(j['need_purchase']),
      );

  String condition;

  bool? needVip;

  bool? needPurchase;
}

class AuditionInfo {
  AuditionInfo({required this.vid, required this.startTimeMs, required this.durationMs});

  factory AuditionInfo.fromJson(Map<String, dynamic> j) => AuditionInfo(
        vid: asStr(j['vid']),
        startTimeMs: asIntOrNull(j['start_time_ms']),
        durationMs: asIntOrNull(j['duration_ms']),
      );

  String vid;

  int? startTimeMs;

  int? durationMs;
}

class SongMakerTeam {
  SongMakerTeam({required this.composers, required this.lyricists});

  factory SongMakerTeam.fromJson(Map<String, dynamic> j) => SongMakerTeam(
        composers: j['composers'] is List
            ? [for (final e in asArr(j['composers'])) NameOnly.fromJson(asObj(e))]
            : null,
        lyricists: j['lyricists'] is List
            ? [for (final e in asArr(j['lyricists'])) NameOnly.fromJson(asObj(e))]
            : null,
      );

  List<NameOnly>? composers;

  List<NameOnly>? lyricists;
}

class NameOnly {
  NameOnly({required this.name});

  factory NameOnly.fromJson(Map<String, dynamic> j) => NameOnly(name: asStr(j['name']));

  String name;
}

class Chorus {
  Chorus({required this.start, required this.duration});

  factory Chorus.fromJson(Map<String, dynamic> j) => Chorus(
        start: asIntOrNull(j['start']),
        duration: asIntOrNull(j['duration']),
      );

  int? start;

  int? duration;
}

class Colors {
  Colors({
    required this.coverGradientEffectColor,
    required this.normalLyricColor,
    required this.playingLyricColor,
    required this.recommendReasonBackgroundColor,
    required this.featuredCommentTagColor,
    required this.backgroundColor,
    required this.playingWaveColor,
    required this.pausedWaveColor,
    required this.commentShareAdditionalColor,
    required this.baseColors,
    required this.nonInteractiveAnchorBackground,
  });

  factory Colors.fromJson(Map<String, dynamic> j) => Colors(
        coverGradientEffectColor: j['cover_gradient_effect_color'] is List
            ? [
                for (final e in asArr(j['cover_gradient_effect_color']))
                  RgbColor.fromJson(asObj(e))
              ]
            : null,
        normalLyricColor: j['normal_lyric_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['normal_lyric_color'])),
        playingLyricColor: j['playing_lyric_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['playing_lyric_color'])),
        recommendReasonBackgroundColor: j['recommend_reason_background_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['recommend_reason_background_color'])),
        featuredCommentTagColor: j['featured_comment_tag_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['featured_comment_tag_color'])),
        backgroundColor: j['background_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['background_color'])),
        playingWaveColor: j['playing_wave_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['playing_wave_color'])),
        pausedWaveColor: j['paused_wave_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['paused_wave_color'])),
        commentShareAdditionalColor: j['comment_share_additional_color'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['comment_share_additional_color'])),
        baseColors: j['base_colors'] is List
            ? [for (final e in asArr(j['base_colors'])) RgbColor.fromJson(asObj(e))]
            : null,
        nonInteractiveAnchorBackground: j['non_interactive_anchor_background'] == null
            ? null
            : RgbaColor.fromJson(asObj(j['non_interactive_anchor_background'])),
      );

  List<RgbColor>? coverGradientEffectColor;

  RgbaColor? normalLyricColor;

  RgbaColor? playingLyricColor;

  RgbaColor? recommendReasonBackgroundColor;

  RgbaColor? featuredCommentTagColor;

  RgbaColor? backgroundColor;

  RgbaColor? playingWaveColor;

  RgbaColor? pausedWaveColor;

  RgbaColor? commentShareAdditionalColor;

  List<RgbColor>? baseColors;

  RgbaColor? nonInteractiveAnchorBackground;
}

class RgbColor {
  RgbColor({required this.rgb});

  factory RgbColor.fromJson(Map<String, dynamic> j) => RgbColor(rgb: asStr(j['rgb']));

  String rgb;
}

class RgbaColor extends RgbColor {
  // ignore: use_super_parameters
  RgbaColor({required String rgb, required this.alpha}) : super(rgb: rgb);

  factory RgbaColor.fromJson(Map<String, dynamic> j) =>
      RgbaColor(rgb: asStr(j['rgb']), alpha: asStr(j['alpha']));

  String alpha;
}

class Range {
  Range({required this.start, required this.duration});

  factory Range.fromJson(Map<String, dynamic> j) => Range(
        start: asIntOrNull(j['start']),
        duration: asIntOrNull(j['duration']),
      );

  int? start;

  int? duration;
}

class PlugStatus {
  PlugStatus({required this.canPlug, required this.isPlugged});

  factory PlugStatus.fromJson(Map<String, dynamic> j) => PlugStatus(
        canPlug: j['can_plug'] == null ? null : asBool(j['can_plug']),
        isPlugged: j['is_plugged'] == null ? null : asBool(j['is_plugged']),
      );

  bool? canPlug;

  bool? isPlugged;
}

class TagWrapper {
  TagWrapper({required this.category, required this.firstLevelTag, required this.secondLevelTag});

  factory TagWrapper.fromJson(Map<String, dynamic> j) => TagWrapper(
        category: j['category'] == null
            ? null
            : TagCategory.fromJson(asObj(j['category'])),
        firstLevelTag: j['first_level_tag'] == null
            ? null
            : Tag.fromJson(asObj(j['first_level_tag'])),
        secondLevelTag: j['second_level_tag'] == null
            ? null
            : Tag.fromJson(asObj(j['second_level_tag'])),
      );

  TagCategory? category;

  Tag? firstLevelTag;

  Tag? secondLevelTag;
}

class TagCategory {
  TagCategory({required this.tagId, required this.tagName});

  factory TagCategory.fromJson(Map<String, dynamic> j) => TagCategory(
        tagId: asInt(j['tag_id']),
        tagName: asStr(j['tag_name']),
      );

  int tagId;

  String tagName;
}

class Tag {
  Tag({required this.tagId, required this.tagName});

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
        tagId: asInt(j['tag_id']),
        tagName: asStr(j['tag_name']),
      );

  int tagId;

  String tagName;
}

class Fragment {
  Fragment({required this.type, required this.startTime, required this.endTime});

  factory Fragment.fromJson(Map<String, dynamic> j) => Fragment(
        type: asStr(j['type']),
        startTime: asIntOrNull(j['start_time']),
        endTime: asIntOrNull(j['end_time']),
      );

  String type;

  int? startTime;

  int? endTime;
}

class TrackDetailResult {
  TrackDetailResult({
    required this.statusCode,
    required this.statusInfo,
    required this.lyric,
    required this.track,
    required this.trackPlayer,
    required this.seoTrack,
    required this.riskResult,
    required this.expireAt,
  });

  factory TrackDetailResult.fromJson(Map<String, dynamic> j) => TrackDetailResult(
        statusCode: asIntOrNull(j['status_code']),
        statusInfo: j['status_info'] == null
            ? null
            : StatusInfo.fromJson(asObj(j['status_info'])),
        lyric: j['lyric'] == null ? null : LyricInfo.fromJson(asObj(j['lyric'])),
        track: j['track'] == null ? null : TrackInfo.fromJson(asObj(j['track'])),
        trackPlayer: j['track_player'] == null
            ? null
            : TrackPlayer.fromJson(asObj(j['track_player'])),
        seoTrack: j['seo_track'] == null
            ? null
            : SeoTrackDetail.fromJson(asObj(j['seo_track'])),
        riskResult: asIntOrNull(j['risk_result']),
        expireAt: asIntOrNull(j['expire_at']),
      );

  int? statusCode;

  StatusInfo? statusInfo;

  LyricInfo? lyric;

  TrackInfo? track;

  TrackPlayer? trackPlayer;

  SeoTrackDetail? seoTrack;

  int? riskResult;

  int? expireAt;
}

class SeoTrackDetail {
  SeoTrackDetail({required this.track, required this.trackPlayer});

  factory SeoTrackDetail.fromJson(Map<String, dynamic> j) => SeoTrackDetail(
        track: j['track'] == null ? null : TrackInfo.fromJson(asObj(j['track'])),
        trackPlayer: j['track_player'] == null
            ? null
            : TrackPlayer.fromJson(asObj(j['track_player'])),
      );

  TrackInfo? track;

  TrackPlayer? trackPlayer;
}

class LyricInfo {
  LyricInfo({
    required this.content,
    required this.lang,
    required this.hideRequestLyrics,
    required this.type,
    required this.lyricContributor,
    required this.id,
    required this.langTranslations,
    required this.translations,
  });

  factory LyricInfo.fromJson(Map<String, dynamic> j) => LyricInfo(
        content: asStr(j['content']),
        lang: asStr(j['lang']),
        hideRequestLyrics: j['hide_request_lyrics'] == null
            ? null
            : asBool(j['hide_request_lyrics']),
        type: asStr(j['type']),
        lyricContributor: j['lyric_contributor'] == null
            ? null
            : LyricContributor.fromJson(asObj(j['lyric_contributor'])),
        id: asStr(j['id']),
        langTranslations: _translationMap(j['lang_translations']),
        translations: j['translations'] == null
            ? null
            : LyricTranslation2.fromJson(asObj(j['translations'])),
      );

  String content;

  String lang;

  bool? hideRequestLyrics;

  String type;

  LyricContributor? lyricContributor;

  String id;

  Map<String, LyricTranslation>? langTranslations;

  LyricTranslation2? translations;
}

class LyricTranslation2 {
  LyricTranslation2({required this.chineseTranslation});

  factory LyricTranslation2.fromJson(Map<String, dynamic> j) =>
      LyricTranslation2(chineseTranslation: asStr(j['cn']));

  String chineseTranslation;
}

class LyricContributor {
  LyricContributor({required this.filterReason});

  factory LyricContributor.fromJson(Map<String, dynamic> j) =>
      LyricContributor(filterReason: asStr(j['filter_reason']));

  String filterReason;
}

class LyricTranslation {
  LyricTranslation({
    required this.content,
    required this.lang,
    required this.hideRequestLyrics,
    required this.type,
    required this.lyricContributor,
    required this.id,
  });

  factory LyricTranslation.fromJson(Map<String, dynamic> j) => LyricTranslation(
        content: asStr(j['content']),
        lang: asStr(j['lang']),
        hideRequestLyrics: j['hide_request_lyrics'] == null
            ? null
            : asBool(j['hide_request_lyrics']),
        type: asStr(j['type']),
        lyricContributor: j['lyric_contributor'] == null
            ? null
            : LyricContributor.fromJson(asObj(j['lyric_contributor'])),
        id: asStr(j['id']),
      );

  String content;

  String lang;

  bool? hideRequestLyrics;

  String type;

  LyricContributor? lyricContributor;

  String id;
}

class TrackInfo {
  TrackInfo({
    required this.id,
    required this.album,
    required this.artists,
    required this.duration,
    required this.name,
    required this.preview,
    required this.state,
    required this.stats,
    required this.vid,
    required this.labelInfo,
    required this.simId,
    required this.bitRates,
    required this.auditionInfo,
    required this.songMakerTeam,
    required this.mediaType,
    required this.chorus,
    required this.colors,
    required this.limitedFreeInfo,
    required this.vocal,
    required this.langCodes,
    required this.firstVocal,
    required this.sharablePlatforms,
    required this.plugStatus,
    required this.tags,
  });

  factory TrackInfo.fromJson(Map<String, dynamic> j) => TrackInfo(
        id: asStr(j['id']),
        album: j['album'] == null ? null : Album.fromJson(asObj(j['album'])),
        artists: j['artists'] is List
            ? [for (final e in asArr(j['artists'])) Artist.fromJson(asObj(e))]
            : null,
        duration: asInt(j['duration']),
        name: asStr(j['name']),
        preview:
            j['preview'] == null ? null : Preview.fromJson(asObj(j['preview'])),
        state: j['state'] == null ? null : State.fromJson(asObj(j['state'])),
        stats: j['stats'] == null ? null : Stats.fromJson(asObj(j['stats'])),
        vid: asStr(j['vid']),
        labelInfo: j['label_info'] == null
            ? null
            : LabelInfo.fromJson(asObj(j['label_info'])),
        simId: asIntOrNull(j['sim_id']),
        bitRates: j['bit_rates'] is List
            ? [for (final e in asArr(j['bit_rates'])) BitRateItem.fromJson(asObj(e))]
            : null,
        auditionInfo: j['audition_info'] == null
            ? null
            : AuditionInfo.fromJson(asObj(j['audition_info'])),
        songMakerTeam: j['song_maker_team'] == null
            ? null
            : SongMakerTeam.fromJson(asObj(j['song_maker_team'])),
        mediaType: asStr(j['media_type']),
        chorus: j['chorus'] == null ? null : Chorus.fromJson(asObj(j['chorus'])),
        colors: j['colors'] == null ? null : Colors.fromJson(asObj(j['colors'])),
        limitedFreeInfo: j['limited_free_info'] == null
            ? null
            : LimitedFreeInfo.fromJson(asObj(j['limited_free_info'])),
        vocal: asIntOrNull(j['vocal']),
        langCodes: _strList(j['lang_codes']),
        firstVocal: j['first_vocal'] == null
            ? null
            : Range.fromJson(asObj(j['first_vocal'])),
        sharablePlatforms: _strList(j['sharable_platforms']),
        plugStatus: j['plug_status'] == null
            ? null
            : PlugStatus.fromJson(asObj(j['plug_status'])),
        tags: j['tags'] is List
            ? [for (final e in asArr(j['tags'])) TagWrapper.fromJson(asObj(e))]
            : null,
      );

  String id;

  Album? album;

  List<Artist>? artists;

  int duration;

  String name;

  Preview? preview;

  State? state;

  Stats? stats;

  String vid;

  LabelInfo? labelInfo;

  int? simId;

  List<BitRateItem>? bitRates;

  AuditionInfo? auditionInfo;

  SongMakerTeam? songMakerTeam;

  String mediaType;

  Chorus? chorus;

  Colors? colors;

  LimitedFreeInfo? limitedFreeInfo;

  int? vocal;

  List<String>? langCodes;

  Range? firstVocal;

  List<String>? sharablePlatforms;

  PlugStatus? plugStatus;

  List<TagWrapper>? tags;
}

class LimitedFreeInfo {
  LimitedFreeInfo({
    required this.queueTypes,
    required this.expireTime,
    required this.sign,
    required this.signVersion,
    required this.limitedFreeType,
    required this.rewindPrevInterceptType,
    required this.interceptType,
  });

  factory LimitedFreeInfo.fromJson(Map<String, dynamic> j) => LimitedFreeInfo(
        queueTypes: _strList(j['queue_types']),
        expireTime: asIntOrNull(j['expire_time']),
        sign: asStr(j['sign']),
        signVersion: asStr(j['sign_version']),
        limitedFreeType: asStr(j['limited_free_type']),
        rewindPrevInterceptType: asStr(j['rewind_prev_intercept_type']),
        interceptType: asStr(j['intercept_type']),
      );

  List<String>? queueTypes;

  int? expireTime;

  String sign;

  String signVersion;

  String limitedFreeType;

  String rewindPrevInterceptType;

  String interceptType;
}

class TrackPlayer {
  TrackPlayer({
    required this.expireAt,
    required this.mediaId,
    required this.urlPlayerInfo,
    required this.videoModel,
    required this.videoModelType,
  });

  factory TrackPlayer.fromJson(Map<String, dynamic> j) => TrackPlayer(
        expireAt: asIntOrNull(j['expire_at']),
        mediaId: asStr(j['media_id']),
        urlPlayerInfo: asStr(j['url_player_info']),
        videoModel: asStr(j['video_model']),
        videoModelType: asIntOrNull(j['video_model_type']),
      );

  int? expireAt;

  String mediaId;

  String urlPlayerInfo;

  String videoModel;

  int? videoModelType;
}
