// Ported from Lyricify.Lyrics.Helper/Providers/Web/QQMusic/Response.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
library;

import 'dart:convert';

import '../../../json_utils.dart';

String _jstr(Map<String, dynamic> j, String key) => asStr(j[key]);
int _jint(Map<String, dynamic> j, String key) => asInt(j[key]);

class MusicFcgApiResult {
  MusicFcgApiResult({
    required this.code,
    required this.ts,
    required this.startTs,
    required this.traceid,
    required this.req,
    required this.req0,
    required this.req1,
  });

  final int code;

  final int ts;

  final int startTs;

  final String traceid;

  final MusicFcgReq? req;

  final MusicFcgReq0? req0;

  final MusicFcgReq1? req1;

  factory MusicFcgApiResult.fromJson(Map<String, dynamic> j) => MusicFcgApiResult(
        code: _jint(j, 'code'),
        ts: _jint(j, 'ts'),
        startTs: j['start_ts'] == null ? 0 : _jint(j, 'start_ts'),
        traceid: _jstr(j, 'traceid'),
        req: j['req'] == null ? null : MusicFcgReq.fromJson(asObj(j['req'])),
        req0: j['req_0'] == null ? null : MusicFcgReq0.fromJson(asObj(j['req_0'])),
        req1: j['req_1'] == null ? null : MusicFcgReq1.fromJson(asObj(j['req_1'])),
      );
}

class MusicFcgReq {
  MusicFcgReq({required this.code, required this.data});

  final int code;

  final MusicFcgReqData? data;

  factory MusicFcgReq.fromJson(Map<String, dynamic> j) => MusicFcgReq(
        code: _jint(j, 'code'),
        data: j['data'] == null ? null : MusicFcgReqData.fromJson(asObj(j['data'])),
      );
}

class MusicFcgReqData {
  MusicFcgReqData({
    required this.sip,
    required this.keepalivefile,
    required this.testfile2g,
    required this.testfilewifi,
  });

  final List<String> sip;

  final String keepalivefile;

  final String testfile2g;

  final String testfilewifi;

  factory MusicFcgReqData.fromJson(Map<String, dynamic> j) => MusicFcgReqData(
        sip: [for (final e in asArr(j['sip'])) asStr(e)],
        keepalivefile: _jstr(j, 'keepalivefile'),
        testfile2g: _jstr(j, 'testfile2g'),
        testfilewifi: _jstr(j, 'testfilewifi'),
      );
}

class MusicFcgReq0 {
  MusicFcgReq0({required this.code, required this.data});

  final int code;

  final MusicFcgReq0Data? data;

  factory MusicFcgReq0.fromJson(Map<String, dynamic> j) => MusicFcgReq0(
        code: _jint(j, 'code'),
        data: j['data'] == null ? null : MusicFcgReq0Data.fromJson(asObj(j['data'])),
      );
}

class MusicFcgReq0Data {
  MusicFcgReq0Data({
    required this.sip,
    required this.testfile2g,
    required this.testfilewifi,
    required this.midurlinfo,
  });

  final List<String> sip;

  final String testfile2g;

  final String testfilewifi;

  final List<MusicFcgReq0DataMidurlinfo> midurlinfo;

  factory MusicFcgReq0Data.fromJson(Map<String, dynamic> j) => MusicFcgReq0Data(
        sip: [for (final e in asArr(j['sip'])) asStr(e)],
        testfile2g: _jstr(j, 'testfile2g'),
        testfilewifi: _jstr(j, 'testfilewifi'),
        midurlinfo: [
          for (final e in asArr(j['midurlinfo']))
            MusicFcgReq0DataMidurlinfo.fromJson(asObj(e))
        ],
      );
}

class MusicFcgReq0DataMidurlinfo {
  MusicFcgReq0DataMidurlinfo({required this.songmid, required this.purl});

  final String songmid;

  final String purl;

  factory MusicFcgReq0DataMidurlinfo.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq0DataMidurlinfo(
        songmid: _jstr(j, 'songmid'),
        purl: _jstr(j, 'purl'),
      );
}

class MusicFcgReq1 {
  MusicFcgReq1({required this.code, required this.data});

  final int code;

  final MusicFcgReq1Data? data;

  factory MusicFcgReq1.fromJson(Map<String, dynamic> j) => MusicFcgReq1(
        code: _jint(j, 'code'),
        data: j['data'] == null ? null : MusicFcgReq1Data.fromJson(asObj(j['data'])),
      );
}

class MusicFcgReq1Data {
  MusicFcgReq1Data({
    required this.code,
    required this.ver,
    required this.body,
    required this.meta,
  });

  final int code;

  final int ver;

  final MusicFcgReq1DataBody? body;

  final MusicFcgReq1DataMeta? meta;

  factory MusicFcgReq1Data.fromJson(Map<String, dynamic> j) => MusicFcgReq1Data(
        code: _jint(j, 'code'),
        ver: _jint(j, 'ver'),
        body:
            j['body'] == null ? null : MusicFcgReq1DataBody.fromJson(asObj(j['body'])),
        meta:
            j['meta'] == null ? null : MusicFcgReq1DataMeta.fromJson(asObj(j['meta'])),
      );
}

class MusicFcgReq1DataBody {
  MusicFcgReq1DataBody({required this.album, required this.song, required this.songlist});

  final MusicFcgReq1DataBodyAlbum? album;

  final MusicFcgReq1DataBodySong? song;

  final MusicFcgReq1DataBodyPlayList? songlist;

  factory MusicFcgReq1DataBody.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataBody(
        album: j['album'] == null
            ? null
            : MusicFcgReq1DataBodyAlbum.fromJson(asObj(j['album'])),
        song: j['song'] == null
            ? null
            : MusicFcgReq1DataBodySong.fromJson(asObj(j['song'])),
        songlist: j['songlist'] == null
            ? null
            : MusicFcgReq1DataBodyPlayList.fromJson(asObj(j['songlist'])),
      );
}

class MusicFcgReq1DataBodyAlbum {
  MusicFcgReq1DataBodyAlbum({required this.list});

  final List<MusicFcgReq1DataBodyAlbumInfo> list;

  factory MusicFcgReq1DataBodyAlbum.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataBodyAlbum(
        list: [
          for (final e in asArr(j['list']))
            MusicFcgReq1DataBodyAlbumInfo.fromJson(asObj(e))
        ],
      );
}

class MusicFcgReq1DataBodyAlbumInfo {
  MusicFcgReq1DataBodyAlbumInfo({
    required this.albumID,
    required this.albumMID,
    required this.albumName,
    required this.songCount,
    required this.publicTime,
    required this.singerList,
  });

  final int albumID;

  final String albumMID;

  final String albumName;

  final int songCount;

  final String publicTime;

  final List<Singer> singerList;

  factory MusicFcgReq1DataBodyAlbumInfo.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataBodyAlbumInfo(
        albumID: _jint(j, 'albumID'),
        albumMID:
            j['albumMid'] == null ? _jstr(j, 'albumMID') : _jstr(j, 'albumMid'),
        albumName: _jstr(j, 'albumName'),
        songCount: _jint(j, 'song_count'),
        publicTime: _jstr(j, 'publicTime'),
        singerList: [
          for (final e in asArr(j['singer_list'])) Singer.fromJson(asObj(e))
        ],
      );
}

class MusicFcgReq1DataBodySong {
  MusicFcgReq1DataBodySong({required this.list});

  final List<BodySong> list;

  factory MusicFcgReq1DataBodySong.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataBodySong(
        list: [for (final e in asArr(j['list'])) BodySong.fromJson(asObj(e))],
      );
}

class BodySong {
  BodySong({
    required this.album,
    required this.id,
    required this.interval,
    required this.mid,
    required this.name,
    required this.desc,
    required this.singer,
    required this.title,
    required this.subtitle,
    required this.timePublic,
    required this.group,
    required this.language,
    required this.genre,
  });

  final Album? album;

  final String id;

  final int interval;

  final String mid;

  final String name;

  final String desc;

  final List<Singer> singer;

  final String title;

  final String subtitle;

  final String timePublic;

  /// `[JsonProperty("grp")]`
  final List<BodySong> group;

  final int language;
  final int genre;

  factory BodySong.fromJson(Map<String, dynamic> j) => BodySong(
        album: j['album'] == null ? null : Album.fromJson(asObj(j['album'])),
        id: _jstr(j, 'id'),
        interval: _jint(j, 'interval'),
        mid: _jstr(j, 'mid'),
        name: _jstr(j, 'name'),
        desc: _jstr(j, 'desc'),
        singer: [for (final e in asArr(j['singer'])) Singer.fromJson(asObj(e))],
        title: _jstr(j, 'title'),
        subtitle: _jstr(j, 'subtitle'),
        timePublic: _jstr(j, 'time_public'),
        group: [for (final e in asArr(j['grp'])) BodySong.fromJson(asObj(e))],
        language: _jint(j, 'language'),
        genre: _jint(j, 'genre'),
      );
}

class MusicFcgReq1DataBodyPlayList {
  MusicFcgReq1DataBodyPlayList({required this.list});

  final List<MusicFcgReq1DataBodyPlayListInfo> list;

  factory MusicFcgReq1DataBodyPlayList.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataBodyPlayList(
        list: [
          for (final e in asArr(j['list']))
            MusicFcgReq1DataBodyPlayListInfo.fromJson(asObj(e))
        ],
      );
}

class MusicFcgReq1DataBodyPlayListInfo {
  MusicFcgReq1DataBodyPlayListInfo({
    required this.dissid,
    required this.dissname,
    required this.imgurl,
    required this.introduction,
    required this.songCount,
    required this.listennum,
    required this.creator,
  });

  final String dissid;

  final String dissname;

  final String imgurl;

  final String introduction;

  final int songCount;

  final int listennum;

  final MusicFcgReq1DataBodyPlayListCreator? creator;

  factory MusicFcgReq1DataBodyPlayListInfo.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataBodyPlayListInfo(
        dissid: _jstr(j, 'dissid'),
        dissname: _jstr(j, 'dissname'),
        imgurl: _jstr(j, 'imgurl'),
        introduction: _jstr(j, 'introduction'),
        songCount: _jint(j, 'song_Count'),
        listennum: _jint(j, 'listennum'),
        creator: j['creator'] == null
            ? null
            : MusicFcgReq1DataBodyPlayListCreator.fromJson(asObj(j['creator'])),
      );
}

class MusicFcgReq1DataBodyPlayListCreator {
  MusicFcgReq1DataBodyPlayListCreator({required this.name, required this.qq});

  final String name;

  final int qq;

  factory MusicFcgReq1DataBodyPlayListCreator.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataBodyPlayListCreator(
        name: _jstr(j, 'name'),
        qq: _jint(j, 'qq'),
      );
}

class MusicFcgReq1DataMeta {
  MusicFcgReq1DataMeta({
    required this.curpage,
    required this.nextpage,
    required this.perpage,
    required this.query,
    required this.sum,
  });

  final int curpage;

  final int nextpage;

  final int perpage;

  final String query;

  final int sum;

  factory MusicFcgReq1DataMeta.fromJson(Map<String, dynamic> j) =>
      MusicFcgReq1DataMeta(
        curpage: _jint(j, 'curpage'),
        nextpage: _jint(j, 'nextpage'),
        perpage: _jint(j, 'perpage'),
        query: _jstr(j, 'query'),
        sum: _jint(j, 'sum'),
      );
}

class MusicFcgApiAlternativeResult {
  MusicFcgApiAlternativeResult({
    required this.code,
    required this.ts,
    required this.startTs,
    required this.traceid,
    required this.search,
  });

  final int code;

  final int ts;

  final int startTs;

  final String traceid;

  /// `[JsonProperty("music.search.SearchCgiService")]`
  final SearchCgiService? search;

  factory MusicFcgApiAlternativeResult.fromJson(Map<String, dynamic> j) =>
      MusicFcgApiAlternativeResult(
        code: _jint(j, 'code'),
        ts: _jint(j, 'ts'),
        startTs: _jint(j, 'start_ts'),
        traceid: _jstr(j, 'traceid'),
        search: j['music.search.SearchCgiService'] == null
            ? null
            : SearchCgiService.fromJson(asObj(j['music.search.SearchCgiService'])),
      );
}

class SearchCgiService {
  SearchCgiService({required this.data});

  final DataBody? data;

  factory SearchCgiService.fromJson(Map<String, dynamic> j) => SearchCgiService(
        data: j['data'] == null ? null : DataBody.fromJson(asObj(j['data'])),
      );
}

class DataBody {
  DataBody({required this.body});

  final SearchData? body;

  factory DataBody.fromJson(Map<String, dynamic> j) => DataBody(
        body: j['body'] == null ? null : SearchData.fromJson(asObj(j['body'])),
      );
}

class SearchData {
  SearchData({required this.song});

  final AlternativeSearchSong? song;

  factory SearchData.fromJson(Map<String, dynamic> j) => SearchData(
        song: j['song'] == null
            ? null
            : AlternativeSearchSong.fromJson(asObj(j['song'])),
      );
}

class AlternativeSearchSong {
  AlternativeSearchSong({required this.list});

  final List<Song> list;

  factory AlternativeSearchSong.fromJson(Map<String, dynamic> j) =>
      AlternativeSearchSong(
        list: [for (final e in asArr(j['list'])) Song.fromJson(asObj(e))],
      );
}

class AlbumResult {
  AlbumResult({required this.code, required this.data, required this.message});

  final int code;

  final AlbumInfo? data;

  final String message;

  factory AlbumResult.fromJson(Map<String, dynamic> j) => AlbumResult(
        code: _jint(j, 'code'),
        data: j['data'] == null ? null : AlbumInfo.fromJson(asObj(j['data'])),
        message: _jstr(j, 'message'),
      );
}

class PlaylistResult {
  PlaylistResult({required this.code, required this.cdlist});

  final int code;

  final List<Playlist> cdlist;

  factory PlaylistResult.fromJson(Map<String, dynamic> j) => PlaylistResult(
        code: _jint(j, 'code'),
        cdlist: [for (final e in asArr(j['cdlist'])) Playlist.fromJson(asObj(e))],
      );
}

class SongResult {
  SongResult({required this.code, required this.data});

  final int code;

  final List<Song> data;

  factory SongResult.fromJson(Map<String, dynamic> j) => SongResult(
        code: _jint(j, 'code'),
        data: [for (final e in asArr(j['data'])) Song.fromJson(asObj(e))],
      );

  bool isIllegal() {
    return code != 0 || data.isEmpty;
  }
}

class LyricResult {
  LyricResult({required this.code, required this.lyric, required this.trans});

  final int code;

  String lyric;

  String trans;

  factory LyricResult.fromJson(Map<String, dynamic> j) => LyricResult(
        code: _jint(j, 'code'),
        lyric: asStr(j['lyric']),
        trans: j['trans'] == null ? '' : asStr(j['trans']),
      );

  LyricResult decode() {
    if (lyric.isNotEmpty) {
      lyric = utf8.decode(base64.decode(lyric));
    }

    if (trans.isNotEmpty) {
      trans = utf8.decode(base64.decode(trans));
    }

    return this;
  }
}

class Playlist {
  Playlist({
    required this.disstid,
    required this.dissname,
    required this.nickname,
    required this.logo,
    required this.desc,
    required this.tags,
    required this.songnum,
    required this.songids,
    required this.songList,
    required this.visitnum,
    required this.cTime,
  });

  final String disstid;

  final String dissname;

  final String nickname;

  final String logo;

  final String desc;

  final List<Tag> tags;

  final int songnum;

  final String songids;

  final List<Song> songList;

  final int visitnum;

  final int cTime;

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        disstid: _jstr(j, 'disstid'),
        dissname: _jstr(j, 'dissname'),
        nickname: _jstr(j, 'nickname'),
        logo: _jstr(j, 'logo'),
        desc: _jstr(j, 'desc'),
        tags: [for (final e in asArr(j['tags'])) Tag.fromJson(asObj(e))],
        songnum: _jint(j, 'songnum'),
        songids: _jstr(j, 'songids'),
        songList: [for (final e in asArr(j['songlist'])) Song.fromJson(asObj(e))],
        visitnum: _jint(j, 'visitnum'),
        cTime: _jint(j, 'ctime'),
      );
}

class Tag {
  Tag({required this.id, required this.name, required this.pid});

  final int id;

  final String name;

  final int pid;

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
        id: _jint(j, 'id'),
        name: _jstr(j, 'name'),
        pid: _jint(j, 'pid'),
      );
}

class Song {
  Song({
    required this.album,
    required this.id,
    required this.interval,
    required this.mid,
    required this.name,
    required this.desc,
    required this.singer,
    required this.title,
    required this.subtitle,
    required this.timePublic,
    required this.group,
    required this.language,
    required this.genre,
  });

  final Album? album;

  final String id;

  final int interval;

  final String mid;

  final String name;

  final String desc;

  final List<Singer> singer;

  final String title;

  final String subtitle;

  final String timePublic;

  /// `[JsonProperty("grp")]`
  final List<Song> group;

  final int language;
  final int genre;

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        album: j['album'] == null ? null : Album.fromJson(asObj(j['album'])),
        id: _jstr(j, 'id'),
        interval: _jint(j, 'interval'),
        mid: _jstr(j, 'mid'),
        name: _jstr(j, 'name'),
        desc: _jstr(j, 'desc'),
        singer: [for (final e in asArr(j['singer'])) Singer.fromJson(asObj(e))],
        title: _jstr(j, 'title'),
        subtitle: _jstr(j, 'subtitle'),
        timePublic: _jstr(j, 'time_public'),
        group: [for (final e in asArr(j['grp'])) Song.fromJson(asObj(e))],
        language: _jint(j, 'language'),
        genre: _jint(j, 'genre'),
      );
}

class AlbumInfo {
  AlbumInfo({
    required this.aDate,
    required this.company,
    required this.desc,
    required this.id,
    required this.mid,
    required this.lan,
    required this.list,
    required this.name,
    required this.singerid,
    required this.singermid,
    required this.singername,
    required this.total,
  });

  final String aDate;

  final String company;

  final String desc;

  final int id;

  final String mid;

  final String lan;

  final List<AlbumSong> list;

  final String name;

  final int singerid;

  final String singermid;

  final String singername;

  final int total;

  factory AlbumInfo.fromJson(Map<String, dynamic> j) => AlbumInfo(
        aDate: _jstr(j, 'aDate'),
        company: _jstr(j, 'company'),
        desc: _jstr(j, 'desc'),
        id: _jint(j, 'id'),
        mid: _jstr(j, 'mid'),
        lan: _jstr(j, 'lan'),
        list: [for (final e in asArr(j['list'])) AlbumSong.fromJson(asObj(e))],
        name: _jstr(j, 'name'),
        singerid: _jint(j, 'singerid'),
        singermid: _jstr(j, 'singermid'),
        singername: _jstr(j, 'singername'),
        total: _jint(j, 'total'),
      );
}

class AlbumSong {
  AlbumSong({
    required this.singer,
    required this.songid,
    required this.songmid,
    required this.songname,
  });

  final List<Singer> singer;

  final int songid;

  final String songmid;

  final String songname;

  factory AlbumSong.fromJson(Map<String, dynamic> j) => AlbumSong(
        singer: [for (final e in asArr(j['singer'])) Singer.fromJson(asObj(e))],
        songid: _jint(j, 'songid'),
        songmid: _jstr(j, 'songmid'),
        songname: _jstr(j, 'songname'),
      );
}

class SingerSongResult {
  SingerSongResult({
    required this.code,
    required this.ts,
    required this.startTs,
    required this.traceid,
    required this.singer,
  });

  final int code;
  final int ts;

  final int startTs;

  final String traceid;
  final SingerData? singer;

  factory SingerSongResult.fromJson(Map<String, dynamic> j) => SingerSongResult(
        code: _jint(j, 'code'),
        ts: _jint(j, 'ts'),
        startTs: _jint(j, 'start_ts'),
        traceid: _jstr(j, 'traceid'),
        singer: j['singer'] == null ? null : SingerData.fromJson(asObj(j['singer'])),
      );
}

class SingerData {
  SingerData({required this.code, required this.data});

  final int code;
  final SingerInfo? data;

  factory SingerData.fromJson(Map<String, dynamic> j) => SingerData(
        code: _jint(j, 'code'),
        data: j['data'] == null ? null : SingerInfo.fromJson(asObj(j['data'])),
      );
}

class SingerInfo {
  SingerInfo({
    required this.songlist,
    required this.singerBrief,
    required this.musicGrp,
    required this.totalAlbum,
    required this.totalMv,
    required this.totalSong,
    required this.yinyueren,
    required this.showSingerDesc,
  });

  final List<SongInfo> songlist;

  final String singerBrief;

  final List<dynamic> musicGrp;

  final int totalAlbum;

  final int totalMv;

  final int totalSong;

  final String yinyueren;

  final bool showSingerDesc;

  factory SingerInfo.fromJson(Map<String, dynamic> j) => SingerInfo(
        songlist: [for (final e in asArr(j['songlist'])) SongInfo.fromJson(asObj(e))],
        singerBrief: _jstr(j, 'singer_brief'),
        musicGrp: asArr(j['music_grp']),
        totalAlbum: _jint(j, 'total_album'),
        totalMv: _jint(j, 'total_mv'),
        totalSong: _jint(j, 'total_song'),
        yinyueren: _jstr(j, 'yinyueren'),
        showSingerDesc: asBool(j['show_singer_desc']),
      );
}

class ToplistResult {
  ToplistResult({
    required this.code,
    required this.ts,
    required this.startTs,
    required this.traceid,
    required this.detail,
  });

  final int code;
  final int ts;

  final int startTs;

  final String traceid;
  final DetailData? detail;

  factory ToplistResult.fromJson(Map<String, dynamic> j) => ToplistResult(
        code: _jint(j, 'code'),
        ts: _jint(j, 'ts'),
        startTs: _jint(j, 'start_ts'),
        traceid: _jstr(j, 'traceid'),
        detail: j['detail'] == null ? null : DetailData.fromJson(asObj(j['detail'])),
      );
}

class DetailData {
  DetailData({required this.code, required this.data});

  final int code;
  final ToplistData? data;

  factory DetailData.fromJson(Map<String, dynamic> j) => DetailData(
        code: _jint(j, 'code'),
        data: j['data'] == null ? null : ToplistData.fromJson(asObj(j['data'])),
      );
}

class ToplistData {
  ToplistData({
    required this.data,
    required this.songInfoList,
    required this.extInfoList,
    required this.songTagInfoList,
    required this.indexInfoList,
  });

  final ToplistInfo? data;
  final List<dynamic> songInfoList;
  final List<dynamic> extInfoList;
  final dynamic songTagInfoList;
  final dynamic indexInfoList;

  factory ToplistData.fromJson(Map<String, dynamic> j) => ToplistData(
        data: j['data'] == null ? null : ToplistInfo.fromJson(asObj(j['data'])),
        songInfoList: asArr(j['songInfoList']),
        extInfoList: asArr(j['extInfoList']),
        songTagInfoList: j['songTagInfoList'],
        indexInfoList: j['indexInfoList'],
      );
}

class ToplistInfo {
  ToplistInfo({
    required this.topId,
    required this.recType,
    required this.topType,
    required this.updateType,
    required this.title,
    required this.titleDetail,
    required this.titleShare,
    required this.titleSub,
    required this.intro,
    required this.cornerMark,
    required this.period,
    required this.updateTime,
    required this.history,
    required this.listenNum,
    required this.totalNum,
    required this.song,
    required this.headPicUrl,
    required this.frontPicUrl,
    required this.mbFrontPicUrl,
    required this.mbHeadPicUrl,
    required this.pcSubTopIds,
    required this.pcSubTopTitles,
    required this.subTopIds,
    required this.adJumpUrl,
    required this.h5JumpUrl,
    required this.urlKey,
    required this.urlParams,
    required this.tjreport,
    required this.rt,
    required this.updateTips,
    required this.bannerText,
    required this.adShareContent,
    required this.abt,
    required this.cityId,
    required this.provId,
    required this.sinceCV,
    required this.musichallTitle,
    required this.musichallSubtitle,
    required this.musichallPicUrl,
    required this.specialScheme,
    required this.mbFrontLogoUrl,
    required this.mbHeadLogoUrl,
    required this.cityName,
    required this.magicColor,
    required this.topAlbumURL,
    required this.groupType,
    required this.icon,
    required this.adID,
    required this.mbIntroWebUrl,
    required this.mbLogoUrl,
  });

  final int topId;
  final int recType;
  final int topType;
  final int updateType;
  final String title;
  final String titleDetail;
  final String titleShare;
  final String titleSub;
  final String intro;
  final int cornerMark;
  final String period;
  final String updateTime;
  final HistoryData? history;
  final int listenNum;
  final int totalNum;
  final List<SongData> song;
  final String headPicUrl;
  final String frontPicUrl;
  final String mbFrontPicUrl;
  final String mbHeadPicUrl;
  final List<dynamic> pcSubTopIds;
  final List<dynamic> pcSubTopTitles;
  final List<dynamic> subTopIds;
  final String adJumpUrl;
  final String h5JumpUrl;

  final String urlKey;

  final String urlParams;

  final String tjreport;
  final int rt;
  final String updateTips;
  final String bannerText;
  final String adShareContent;
  final String abt;
  final int cityId;
  final int provId;
  final int sinceCV;
  final String musichallTitle;
  final String musichallSubtitle;
  final String musichallPicUrl;
  final String specialScheme;
  final String mbFrontLogoUrl;
  final String mbHeadLogoUrl;
  final String cityName;
  final MagicColor? magicColor;

  final String topAlbumURL;

  final int groupType;
  final int icon;

  final int adID;

  final String mbIntroWebUrl;
  final String mbLogoUrl;

  factory ToplistInfo.fromJson(Map<String, dynamic> j) => ToplistInfo(
        topId: _jint(j, 'topId'),
        recType: _jint(j, 'recType'),
        topType: _jint(j, 'topType'),
        updateType: _jint(j, 'updateType'),
        title: _jstr(j, 'title'),
        titleDetail: _jstr(j, 'titleDetail'),
        titleShare: _jstr(j, 'titleShare'),
        titleSub: _jstr(j, 'titleSub'),
        intro: _jstr(j, 'intro'),
        cornerMark: _jint(j, 'cornerMark'),
        period: _jstr(j, 'period'),
        updateTime: _jstr(j, 'updateTime'),
        history: j['history'] == null ? null : HistoryData.fromJson(asObj(j['history'])),
        listenNum: _jint(j, 'listenNum'),
        totalNum: _jint(j, 'totalNum'),
        song: [for (final e in asArr(j['song'])) SongData.fromJson(asObj(e))],
        headPicUrl: _jstr(j, 'headPicUrl'),
        frontPicUrl: _jstr(j, 'frontPicUrl'),
        mbFrontPicUrl: _jstr(j, 'mbFrontPicUrl'),
        mbHeadPicUrl: _jstr(j, 'mbHeadPicUrl'),
        pcSubTopIds: asArr(j['pcSubTopIds']),
        pcSubTopTitles: asArr(j['pcSubTopTitles']),
        subTopIds: asArr(j['subTopIds']),
        adJumpUrl: _jstr(j, 'adJumpUrl'),
        h5JumpUrl: _jstr(j, 'h5JumpUrl'),
        urlKey: _jstr(j, 'url_key'),
        urlParams: _jstr(j, 'url_params'),
        tjreport: _jstr(j, 'tjreport'),
        rt: _jint(j, 'rt'),
        updateTips: _jstr(j, 'updateTips'),
        bannerText: _jstr(j, 'bannerText'),
        adShareContent: _jstr(j, 'adShareContent'),
        abt: _jstr(j, 'abt'),
        cityId: _jint(j, 'cityId'),
        provId: _jint(j, 'provId'),
        sinceCV: _jint(j, 'sinceCV'),
        musichallTitle: _jstr(j, 'musichallTitle'),
        musichallSubtitle: _jstr(j, 'musichallSubtitle'),
        musichallPicUrl: _jstr(j, 'musichallPicUrl'),
        specialScheme: _jstr(j, 'specialScheme'),
        mbFrontLogoUrl: _jstr(j, 'mbFrontLogoUrl'),
        mbHeadLogoUrl: _jstr(j, 'mbHeadLogoUrl'),
        cityName: _jstr(j, 'cityName'),
        magicColor:
            j['magicColor'] == null ? null : MagicColor.fromJson(asObj(j['magicColor'])),
        topAlbumURL: _jstr(j, 'topAlbumURL'),
        groupType: _jint(j, 'groupType'),
        icon: _jint(j, 'icon'),
        adID: _jint(j, 'adID'),
        mbIntroWebUrl: _jstr(j, 'mbIntroWebUrl'),
        mbLogoUrl: _jstr(j, 'mbLogoUrl'),
      );
}

class HistoryData {
  HistoryData({required this.year, required this.subPeriod});

  final List<dynamic> year;
  final List<dynamic> subPeriod;

  factory HistoryData.fromJson(Map<String, dynamic> j) => HistoryData(
        year: asArr(j['year']),
        subPeriod: asArr(j['subPeriod']),
      );
}

class SongData {
  SongData({
    required this.rank,
    required this.rankType,
    required this.rankValue,
    required this.recType,
    required this.songId,
    required this.vid,
    required this.albumMid,
    required this.title,
    required this.singerName,
    required this.singerMid,
    required this.songType,
    required this.uuidCnt,
    required this.cover,
    required this.mvid,
  });

  final int rank;
  final int rankType;
  final String rankValue;
  final int recType;
  final int songId;
  final String vid;
  final String albumMid;
  final String title;
  final String singerName;
  final String singerMid;
  final int songType;
  final int uuidCnt;
  final String cover;
  final int mvid;

  factory SongData.fromJson(Map<String, dynamic> j) => SongData(
        rank: _jint(j, 'rank'),
        rankType: _jint(j, 'rankType'),
        rankValue: _jstr(j, 'rankValue'),
        recType: _jint(j, 'recType'),
        songId: _jint(j, 'songId'),
        vid: _jstr(j, 'vid'),
        albumMid: _jstr(j, 'albumMid'),
        title: _jstr(j, 'title'),
        singerName: _jstr(j, 'singerName'),
        singerMid: _jstr(j, 'singerMid'),
        songType: _jint(j, 'songType'),
        uuidCnt: _jint(j, 'uuidCnt'),
        cover: _jstr(j, 'cover'),
        mvid: _jint(j, 'mvid'),
      );
}

class MagicColor {
  MagicColor({required this.r, required this.g, required this.b});

  final int r;
  final int g;
  final int b;

  factory MagicColor.fromJson(Map<String, dynamic> j) => MagicColor(
        r: _jint(j, 'r'),
        g: _jint(j, 'g'),
        b: _jint(j, 'b'),
      );
}

class AlbumSongListResult {
  AlbumSongListResult({
    required this.code,
    required this.ts,
    required this.startTs,
    required this.traceId,
    required this.albumSonglist,
  });

  final int code;
  final int ts;

  final int startTs;

  final String traceId;

  final AlbumSonglistInfo? albumSonglist;

  factory AlbumSongListResult.fromJson(Map<String, dynamic> j) => AlbumSongListResult(
        code: _jint(j, 'code'),
        ts: _jint(j, 'ts'),
        startTs: _jint(j, 'start_ts'),
        traceId: _jstr(j, 'traceId'),
        albumSonglist: j['albumSonglist'] == null
            ? null
            : AlbumSonglistInfo.fromJson(asObj(j['albumSonglist'])),
      );
}

class AlbumSonglistInfo {
  AlbumSonglistInfo({required this.code, required this.data});

  final int code;
  final DataInfo? data;

  factory AlbumSonglistInfo.fromJson(Map<String, dynamic> j) => AlbumSonglistInfo(
        code: _jint(j, 'code'),
        data: j['data'] == null ? null : DataInfo.fromJson(asObj(j['data'])),
      );
}

class DataInfo {
  DataInfo({
    required this.albumMid,
    required this.totalNum,
    required this.songList,
    required this.classicList,
    required this.sort,
    required this.albumTips,
    required this.index,
    required this.scheduleStatus,
    required this.curBegin,
    required this.cdNewStyle,
    required this.cdNameMap,
  });

  final String albumMid;
  final int totalNum;
  final List<SongItem> songList;
  final List<dynamic> classicList;
  final int sort;
  final String albumTips;
  final int index;
  final int scheduleStatus;
  final int curBegin;
  final int cdNewStyle;
  final dynamic cdNameMap;

  factory DataInfo.fromJson(Map<String, dynamic> j) => DataInfo(
        albumMid: _jstr(j, 'albumMid'),
        totalNum: _jint(j, 'totalNum'),
        songList: [for (final e in asArr(j['songList'])) SongItem.fromJson(asObj(e))],
        classicList: asArr(j['classicList']),
        sort: _jint(j, 'sort'),
        albumTips: _jstr(j, 'albumTips'),
        index: _jint(j, 'index'),
        scheduleStatus: _jint(j, 'scheduleStatus'),
        curBegin: _jint(j, 'curBegin'),
        cdNewStyle: _jint(j, 'cdNewStyle'),
        cdNameMap: j['cdNameMap'],
      );
}

class SongItem {
  SongItem({
    required this.songInfo,
    required this.listenCount,
    required this.uploadTime,
    required this.isThemeSong,
    required this.teamStr,
  });

  final SongItemSongInfo? songInfo;
  final int listenCount;
  final String uploadTime;
  final int isThemeSong;
  final String teamStr;

  factory SongItem.fromJson(Map<String, dynamic> j) => SongItem(
        songInfo:
            j['songInfo'] == null ? null : SongItemSongInfo.fromJson(asObj(j['songInfo'])),
        listenCount: _jint(j, 'listenCount'),
        uploadTime: _jstr(j, 'uploadTime'),
        isThemeSong: _jint(j, 'isThemeSong'),
        teamStr: _jstr(j, 'teamStr'),
      );
}

class SongItemSongInfo {
  SongItemSongInfo({
    required this.id,
    required this.type,
    required this.mid,
    required this.name,
    required this.title,
    required this.subtitle,
    required this.singer,
    required this.album,
    required this.mv,
    required this.interval,
    required this.isOnly,
    required this.language,
    required this.genre,
    required this.indexCd,
    required this.indexAlbum,
    required this.timePublic,
    required this.status,
    required this.fnote,
    required this.file,
    required this.pay,
    required this.action,
    required this.kSong,
    required this.volume,
    required this.label,
    required this.url,
    required this.bpm,
    required this.version,
    required this.trace,
    required this.dataType,
    required this.modifyStamp,
    required this.pingPong,
    required this.aid,
    required this.ppUrl,
    required this.tid,
    required this.ov,
    required this.sa,
    required this.es,
    required this.vs,
    required this.vi,
    required this.kTag,
  });

  final int id;
  final int type;
  final String mid;
  final String name;
  final String title;
  final String subtitle;
  final List<Singer> singer;
  final Album? album;
  final Mv? mv;
  final int interval;

  final int isOnly;
  final int language;
  final int genre;

  final int indexCd;

  final int indexAlbum;

  final String timePublic;
  final int status;
  final int fnote;
  final FileInfo? file;
  final Pay? pay;
  final Action? action;

  final Ksong? kSong;
  final Volume? volume;

  final int label;
  final String url;
  final int bpm;
  final int version;
  final String trace;

  final int dataType;

  final int modifyStamp;

  final String pingPong;
  final int aid;
  final String ppUrl;
  final int tid;
  final int ov;
  final int sa;
  final String es;
  final List<String> vs;
  final List<int> vi;

  final String kTag;

  factory SongItemSongInfo.fromJson(Map<String, dynamic> j) => SongItemSongInfo(
        id: _jint(j, 'id'),
        type: _jint(j, 'type'),
        mid: _jstr(j, 'mid'),
        name: _jstr(j, 'name'),
        title: _jstr(j, 'title'),
        subtitle: _jstr(j, 'subtitle'),
        singer: [for (final e in asArr(j['singer'])) Singer.fromJson(asObj(e))],
        album: j['album'] == null ? null : Album.fromJson(asObj(j['album'])),
        mv: j['mv'] == null ? null : Mv.fromJson(asObj(j['mv'])),
        interval: _jint(j, 'interval'),
        isOnly: _jint(j, 'isOnly'),
        language: _jint(j, 'language'),
        genre: _jint(j, 'genre'),
        indexCd: _jint(j, 'index_cd'),
        indexAlbum: _jint(j, 'index_album'),
        timePublic: _jstr(j, 'time_public'),
        status: _jint(j, 'status'),
        fnote: _jint(j, 'fnote'),
        file: j['file'] == null ? null : FileInfo.fromJson(asObj(j['file'])),
        pay: j['pay'] == null ? null : Pay.fromJson(asObj(j['pay'])),
        action: j['action'] == null ? null : Action.fromJson(asObj(j['action'])),
        kSong: j['ksong'] == null ? null : Ksong.fromJson(asObj(j['ksong'])),
        volume: j['volume'] == null ? null : Volume.fromJson(asObj(j['volume'])),
        label: _jint(j, 'label'),
        url: _jstr(j, 'url'),
        bpm: _jint(j, 'bpm'),
        version: _jint(j, 'version'),
        trace: _jstr(j, 'trace'),
        dataType: _jint(j, 'data_type'),
        modifyStamp: _jint(j, 'modify_stamp'),
        pingPong: _jstr(j, 'pingpong'),
        aid: _jint(j, 'aid'),
        ppUrl: _jstr(j, 'ppurl'),
        tid: _jint(j, 'tid'),
        ov: _jint(j, 'ov'),
        sa: _jint(j, 'sa'),
        es: _jstr(j, 'es'),
        vs: [for (final e in asArr(j['vs'])) asStr(e)],
        vi: [for (final e in asArr(j['vi'])) asInt(e)],
        kTag: _jstr(j, 'k_tag'),
      );
}

class SongInfo {
  SongInfo({
    required this.id,
    required this.type,
    required this.mid,
    required this.name,
    required this.title,
    required this.subtitle,
    required this.singer,
    required this.album,
    required this.mv,
    required this.interval,
    required this.isonly,
    required this.language,
    required this.genre,
    required this.indexCd,
    required this.indexAlbum,
    required this.timePublic,
    required this.status,
    required this.fnote,
    required this.file,
    required this.pay,
    required this.action,
    required this.ksong,
    required this.volume,
    required this.label,
    required this.url,
    required this.bpm,
    required this.version,
    required this.trace,
    required this.dataType,
    required this.modifyStamp,
    required this.pingpong,
    required this.ppurl,
    required this.tid,
    required this.ov,
  });

  final int id;
  final int type;
  final String mid;
  final String name;
  final String title;
  final String subtitle;
  final List<Singer> singer;
  final Album? album;
  final Mv? mv;
  final int interval;

  final int isonly;
  final int language;
  final int genre;

  final int indexCd;

  final int indexAlbum;

  final String timePublic;
  final int status;
  final int fnote;
  final FileInfo? file;
  final Pay? pay;
  final Action? action;
  final Ksong? ksong;
  final Volume? volume;

  final String label;
  final String url;
  final int bpm;
  final int version;
  final String trace;

  final int dataType;

  final int modifyStamp;

  final String pingpong;

  final String ppurl;
  final int tid;
  final int ov;

  factory SongInfo.fromJson(Map<String, dynamic> j) => SongInfo(
        id: _jint(j, 'id'),
        type: _jint(j, 'type'),
        mid: _jstr(j, 'mid'),
        name: _jstr(j, 'name'),
        title: _jstr(j, 'title'),
        subtitle: _jstr(j, 'subtitle'),
        singer: [for (final e in asArr(j['singer'])) Singer.fromJson(asObj(e))],
        album: j['album'] == null ? null : Album.fromJson(asObj(j['album'])),
        mv: j['mv'] == null ? null : Mv.fromJson(asObj(j['mv'])),
        interval: _jint(j, 'interval'),
        isonly: _jint(j, 'isonly'),
        language: _jint(j, 'language'),
        genre: _jint(j, 'genre'),
        indexCd: _jint(j, 'index_cd'),
        indexAlbum: _jint(j, 'index_album'),
        timePublic: _jstr(j, 'time_public'),
        status: _jint(j, 'status'),
        fnote: _jint(j, 'fnote'),
        file: j['file'] == null ? null : FileInfo.fromJson(asObj(j['file'])),
        pay: j['pay'] == null ? null : Pay.fromJson(asObj(j['pay'])),
        action: j['action'] == null ? null : Action.fromJson(asObj(j['action'])),
        ksong: j['ksong'] == null ? null : Ksong.fromJson(asObj(j['ksong'])),
        volume: j['volume'] == null ? null : Volume.fromJson(asObj(j['volume'])),
        label: _jstr(j, 'label'),
        url: _jstr(j, 'url'),
        bpm: _jint(j, 'bpm'),
        version: _jint(j, 'version'),
        trace: _jstr(j, 'trace'),
        dataType: _jint(j, 'data_type'),
        modifyStamp: _jint(j, 'modify_stamp'),
        pingpong: _jstr(j, 'pingpong'),
        ppurl: _jstr(j, 'ppurl'),
        tid: _jint(j, 'tid'),
        ov: _jint(j, 'ov'),
      );
}

class Singer {
  Singer({
    required this.id,
    required this.mid,
    required this.name,
    required this.pmid,
    required this.title,
    required this.type,
  });

  final int id;
  final String mid;
  final String name;
  final String pmid;
  final String title;
  final int type;

  factory Singer.fromJson(Map<String, dynamic> j) => Singer(
        id: _jint(j, 'id'),
        mid: _jstr(j, 'mid'),
        name: _jstr(j, 'name'),
        pmid: _jstr(j, 'pmid'),
        title: _jstr(j, 'title'),
        type: _jint(j, 'type'),
      );
}

class Album {
  Album({
    required this.id,
    required this.mid,
    required this.name,
    required this.title,
    required this.subtitle,
    required this.timePublic,
    required this.pmid,
  });

  final int id;
  final String mid;
  final String name;
  final String title;
  final String subtitle;

  final String timePublic;

  final String pmid;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: _jint(j, 'id'),
        mid: _jstr(j, 'mid'),
        name: _jstr(j, 'name'),
        title: _jstr(j, 'title'),
        subtitle: _jstr(j, 'subtitle'),
        timePublic: _jstr(j, 'time_public'),
        pmid: _jstr(j, 'pmid'),
      );
}

class Mv {
  Mv({
    required this.id,
    required this.vid,
    required this.name,
    required this.title,
    required this.vt,
  });

  final int id;
  final String vid;
  final String name;
  final String title;
  final int vt;

  factory Mv.fromJson(Map<String, dynamic> j) => Mv(
        id: _jint(j, 'id'),
        vid: _jstr(j, 'vid'),
        name: _jstr(j, 'name'),
        title: _jstr(j, 'title'),
        vt: _jint(j, 'vt'),
      );
}

class FileInfo {
  FileInfo({
    required this.mediaMid,
    required this.size24aac,
    required this.size48aac,
    required this.size96aac,
    required this.size192ogg,
    required this.size192aac,
    required this.size128mp3,
    required this.size320mp3,
    required this.sizeApe,
    required this.sizeFlac,
    required this.sizeDts,
    required this.sizeTry,
    required this.tryBegin,
    required this.tryEnd,
    required this.url,
    required this.sizeHires,
    required this.hiresSample,
    required this.hiresBitdepth,
    required this.b30s,
    required this.e30s,
    required this.size96ogg,
  });

  final String mediaMid;

  final int size24aac;

  final int size48aac;

  final int size96aac;

  final int size192ogg;

  final int size192aac;

  final int size128mp3;

  final int size320mp3;

  final int sizeApe;

  final int sizeFlac;

  final int sizeDts;

  final int sizeTry;

  final int tryBegin;

  final int tryEnd;

  final String url;

  final int sizeHires;

  final int hiresSample;

  final int hiresBitdepth;

  final int b30s;

  final int e30s;

  final int size96ogg;

  factory FileInfo.fromJson(Map<String, dynamic> j) => FileInfo(
        mediaMid: _jstr(j, 'media_mid'),
        size24aac: _jint(j, 'size_24aac'),
        size48aac: _jint(j, 'size_48aac'),
        size96aac: _jint(j, 'size_96aac'),
        size192ogg: _jint(j, 'size_192ogg'),
        size192aac: _jint(j, 'size_192aac'),
        size128mp3: _jint(j, 'size_128mp3'),
        size320mp3: _jint(j, 'size_320mp3'),
        sizeApe: _jint(j, 'size_ape'),
        sizeFlac: _jint(j, 'size_flac'),
        sizeDts: _jint(j, 'size_dts'),
        sizeTry: _jint(j, 'size_try'),
        tryBegin: _jint(j, 'try_begin'),
        tryEnd: _jint(j, 'try_end'),
        url: _jstr(j, 'url'),
        sizeHires: _jint(j, 'size_hires'),
        hiresSample: _jint(j, 'hires_sample'),
        hiresBitdepth: _jint(j, 'hires_bitdepth'),
        b30s: _jint(j, 'b_30s'),
        e30s: _jint(j, 'e_30s'),
        size96ogg: _jint(j, 'size_96ogg'),
      );
}

class Pay {
  Pay({
    required this.payMonth,
    required this.priceTrack,
    required this.priceAlbum,
    required this.payPlay,
    required this.payDown,
    required this.payStatus,
    required this.timeFree,
  });

  final int payMonth;

  final int priceTrack;

  final int priceAlbum;

  final int payPlay;

  final int payDown;

  final int payStatus;

  final int timeFree;

  factory Pay.fromJson(Map<String, dynamic> j) => Pay(
        payMonth: _jint(j, 'pay_month'),
        priceTrack: _jint(j, 'price_track'),
        priceAlbum: _jint(j, 'price_album'),
        payPlay: _jint(j, 'pay_play'),
        payDown: _jint(j, 'pay_down'),
        payStatus: _jint(j, 'pay_status'),
        timeFree: _jint(j, 'time_free'),
      );
}

class Action {
  Action({
    required this.switchValue,
    required this.msgid,
    required this.alert,
    required this.icons,
    required this.msgshare,
    required this.msgfav,
    required this.msgdown,
    required this.msgpay,
  });

  final int switchValue;

  final int msgid;
  final int alert;
  final int icons;
  final int msgshare;
  final int msgfav;
  final int msgdown;
  final int msgpay;

  factory Action.fromJson(Map<String, dynamic> j) => Action(
        switchValue: _jint(j, 'switch'),
        msgid: _jint(j, 'msgid'),
        alert: _jint(j, 'alert'),
        icons: _jint(j, 'icons'),
        msgshare: _jint(j, 'msgshare'),
        msgfav: _jint(j, 'msgfav'),
        msgdown: _jint(j, 'msgdown'),
        msgpay: _jint(j, 'msgpay'),
      );
}

class Ksong {
  Ksong({required this.id, required this.mid});

  final int id;
  final String mid;

  factory Ksong.fromJson(Map<String, dynamic> j) => Ksong(
        id: _jint(j, 'id'),
        mid: _jstr(j, 'mid'),
      );
}

class Volume {
  Volume({required this.gain, required this.peak, required this.lra});

  final double gain;
  final double peak;
  final double lra;

  factory Volume.fromJson(Map<String, dynamic> j) => Volume(
        gain: asDouble(j['gain']),
        peak: asDouble(j['peak']),
        lra: asDouble(j['lra']),
      );
}
