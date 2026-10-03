// Ported from Lyricify.Lyrics.Helper/Providers/Web/Kugou/Response.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
/// `songname` / `album_name` / `songname_original` / `singername` / `filename` / `hash` /
/// `product_from` / `accesskey` / `can_score` / `krctype` / `content_format` / `trans_id` …
library;

import '../../../json_utils.dart';

class SearchSongResponse {
  SearchSongResponse({
    required this.status,
    required this.error,
    required this.data,
    required this.errorCode,
  });

  final int status;

  final String error;

  final DataItem? data;

  /// `[JsonProperty("errcode")]`
  final int errorCode;

  factory SearchSongResponse.fromJson(Map<String, dynamic> j) => SearchSongResponse(
        status: asInt(j['status']),
        error: asStr(j['error']),
        data: j['data'] == null ? null : DataItem.fromJson(asObj(j['data'])),
        errorCode: asInt(j['errcode']),
      );
}

class DataItem {
  DataItem({
    required this.timestamp,
    required this.total,
    required this.info,
  });

  final int timestamp;

  final int total;

  final List<DataItemInfoItem> info;

  factory DataItem.fromJson(Map<String, dynamic> j) => DataItem(
        timestamp: asInt(j['timestamp']),
        total: asInt(j['total']),
        info: [for (final e in asArr(j['info'])) DataItemInfoItem.fromJson(asObj(e))],
      );
}

class DataItemInfoItem {
  DataItemInfoItem({
    required this.hash,
    required this.songName,
    required this.albumName,
    required this.songNameOriginal,
    required this.singerName,
    required this.duration,
    required this.filename,
    required this.group,
  });

  final String hash;

  /// `[JsonProperty("songname")]`
  final String songName;

  /// `[JsonProperty("album_name")]`
  final String albumName;

  /// `[JsonProperty("songname_original")]`
  final String songNameOriginal;

  /// `[JsonProperty("singername")]`
  final String singerName;

  final int duration;

  /// `[JsonProperty("filename")]`
  final String filename;

  final List<DataItemInfoItem> group;

  factory DataItemInfoItem.fromJson(Map<String, dynamic> j) => DataItemInfoItem(
        hash: asStr(j['hash']),
        songName: asStr(j['songname']),
        albumName: asStr(j['album_name']),
        songNameOriginal: asStr(j['songname_original']),
        singerName: asStr(j['singername']),
        duration: asInt(j['duration']),
        filename: asStr(j['filename']),
        group: [
          for (final e in asArr(j['group'])) DataItemInfoItem.fromJson(asObj(e))
        ],
      );
}

typedef InfoItem = DataItemInfoItem;

class SearchLyricsResponse {
  SearchLyricsResponse({
    required this.status,
    required this.info,
    required this.errorCode,
    required this.errorMessage,
    required this.keyword,
    required this.proposal,
    required this.hasCompleteRight,
    required this.ugc,
    required this.ugcCount,
    required this.expire,
    required this.candidates,
  });

  final int status;

  final String info;

  /// `[JsonProperty("errcode")]`
  final int errorCode;

  /// `[JsonProperty("errmsg")]`
  final String errorMessage;

  final String keyword;

  final String proposal;

  /// `[JsonProperty("has_complete_right")]`
  final int hasCompleteRight;

  final int ugc;

  /// `[JsonProperty("ugccount")]`
  final int ugcCount;

  final int expire;

  final List<Candidate> candidates;

  factory SearchLyricsResponse.fromJson(Map<String, dynamic> j) => SearchLyricsResponse(
        status: asInt(j['status']),
        info: asStr(j['info']),
        errorCode: asInt(j['errcode']),
        errorMessage: asStr(j['errmsg']),
        keyword: asStr(j['keyword']),
        proposal: asStr(j['proposal']),
        hasCompleteRight: asInt(j['has_complete_right']),
        ugc: asInt(j['ugc']),
        ugcCount: asInt(j['ugccount']),
        expire: asInt(j['expire']),
        candidates: [
          for (final e in asArr(j['candidates'])) Candidate.fromJson(asObj(e))
        ],
      );
}

class Candidate {
  Candidate({
    required this.id,
    required this.productFrom,
    required this.accessKey,
    required this.canScore,
    required this.singer,
    required this.song,
    required this.duration,
    required this.uid,
    required this.nickname,
    required this.origiuid,
    required this.originame,
    required this.transuid,
    required this.transname,
    required this.sounduid,
    required this.soundname,
    required this.language,
    required this.krcType,
    required this.hitlayer,
    required this.hitcasemask,
    required this.adjust,
    required this.score,
    required this.contentType,
    required this.contentFormat,
    required this.transId,
  });

  final String? id;

  /// `[JsonProperty("product_from")]`
  final String productFrom;

  /// `[JsonProperty("accesskey")]`
  final String? accessKey;

  /// `[JsonProperty("can_score")]`
  final bool canScore;

  final String? singer;

  final String? song;

  final int? duration;

  final String uid;

  final String nickname;

  final String origiuid;

  final String originame;

  final String transuid;

  final String transname;

  final String sounduid;

  final String soundname;

  final String language;

  /// `[JsonProperty("krctype")]`
  final int krcType;

  final int hitlayer;

  final int hitcasemask;

  final int adjust;

  final int score;

  /// `[JsonProperty("contenttype")]`
  final int contentType;

  /// `[JsonProperty("content_format")]`
  final int contentFormat;

  final String transId;

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        id: j['id'] == null ? null : asStr(j['id']),
        productFrom: asStr(j['product_from']),
        accessKey: j['accesskey'] == null ? null : asStr(j['accesskey']),
        canScore: asBool(j['can_score']),
        singer: j['singer'] == null ? null : asStr(j['singer']),
        song: j['song'] == null ? null : asStr(j['song']),
        duration: asIntOrNull(j['duration']),
        uid: asStr(j['uid']),
        nickname: asStr(j['nickname']),
        origiuid: asStr(j['origiuid']),
        originame: asStr(j['originame']),
        transuid: asStr(j['transuid']),
        transname: asStr(j['transname']),
        sounduid: asStr(j['sounduid']),
        soundname: asStr(j['soundname']),
        language: asStr(j['language']),
        krcType: asInt(j['krctype']),
        hitlayer: asInt(j['hitlayer']),
        hitcasemask: asInt(j['hitcasemask']),
        adjust: asInt(j['adjust']),
        score: asInt(j['score']),
        contentType: asInt(j['contenttype']),
        contentFormat: asInt(j['content_format']),
        transId: asStr(j['download_id']),
      );
}
