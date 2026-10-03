// Ported from Lyricify.Lyrics.Helper/Providers/Web/Netease/Response.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///     `Duration` → `duration`、`Album` → `album`、`Artists` → `artists`）；
/// `{ "result": { "songs": [ { "name","id","duration","artists","album","alias",... } ], "songCount": n }, "code": 200 }`。
library;

import '../../../json_utils.dart';

class SearchResult {
  SearchResult({
    required this.needLogin,
    required this.result,
    required this.code,
  });

  final bool needLogin;

  final SearchResultData result;

  final int code;

  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        needLogin: asBool(j['needLogin']),
        result: SearchResultData.fromJson(asObj(j['result'])),
        code: asInt(j['code']),
      );
}

class SearchResultData {
  SearchResultData({
    required this.songs,
    required this.songCount,
    required this.albums,
    required this.albumCount,
    required this.playlists,
    required this.playlistCount,
  });

  /* SearchType = SONG */

  final List<Song> songs;

  final int songCount;

  /* SearchType = ALBUM */

  final List<Album> albums;

  final int albumCount;

  /* SearchType = PLAYLIST */

  final List<SimplePlaylist> playlists;

  final int playlistCount;

  factory SearchResultData.fromJson(Map<String, dynamic> j) => SearchResultData(
        songs: [for (final e in asArr(j['songs'])) Song.fromJson(asObj(e))],
        songCount: asInt(j['songCount']),
        albums: [for (final e in asArr(j['albums'])) Album.fromJson(asObj(e))],
        albumCount: asInt(j['albumCount']),
        playlists: [
          for (final e in asArr(j['playlists'])) SimplePlaylist.fromJson(asObj(e))
        ],
        playlistCount: asInt(j['playlistCount']),
      );
}

class EapiSearchResultData extends SearchResultData {
  EapiSearchResultData({
    required super.songs,
    required super.songCount,
    required super.albums,
    required super.albumCount,
    required super.playlists,
    required super.playlistCount,
    required this.eapiSongs,
  });

  final List<EapiSong> eapiSongs;

  factory EapiSearchResultData.fromJson(Map<String, dynamic> j) =>
      EapiSearchResultData(
        songs: [for (final e in asArr(j['songs'])) Song.fromJson(asObj(e))],
        songCount: asInt(j['songCount']),
        albums: [for (final e in asArr(j['albums'])) Album.fromJson(asObj(e))],
        albumCount: asInt(j['albumCount']),
        playlists: [
          for (final e in asArr(j['playlists'])) SimplePlaylist.fromJson(asObj(e))
        ],
        playlistCount: asInt(j['playlistCount']),
        eapiSongs: [for (final e in asArr(j['songs'])) EapiSong.fromJson(asObj(e))],
      );
}

class EapiSearchResult {
  EapiSearchResult({
    required this.needLogin,
    required this.result,
    required this.code,
  });

  final bool needLogin;

  final EapiSearchResultData result;

  final int code;

  factory EapiSearchResult.fromJson(Map<String, dynamic> j) => EapiSearchResult(
        needLogin: asBool(j['needLogin']),
        result: EapiSearchResultData.fromJson(asObj(j['result'])),
        code: asInt(j['code']),
      );
}

class SongUrls {
  SongUrls({required this.data, required this.code});

  final List<Datum> data;
  final int code;

  factory SongUrls.fromJson(Map<String, dynamic> j) => SongUrls(
        data: [for (final e in asArr(j['data'])) Datum.fromJson(asObj(e))],
        code: asInt(j['code']),
      );
}

class Datum {
  Datum({
    required this.id,
    required this.url,
    required this.br,
    required this.size,
    required this.md5,
    required this.code,
    required this.expi,
    required this.type,
    required this.gain,
    required this.fee,
    required this.uf,
    required this.payed,
    required this.flag,
    required this.canExtend,
  });

  final String id;
  final String url;
  final int br;
  final int size;
  final String md5;
  final int code;
  final int expi;
  final String type;
  final double gain;
  final int fee;
  final dynamic uf;
  final int payed;
  final int flag;
  final bool canExtend;

  factory Datum.fromJson(Map<String, dynamic> j) => Datum(
        id: asStr(j['id']),
        url: asStr(j['url']),
        br: asInt(j['br']),
        size: asInt(j['size']),
        md5: asStr(j['md5']),
        code: asInt(j['code']),
        expi: asInt(j['expi']),
        type: asStr(j['type']),
        gain: asDouble(j['gain']),
        fee: asInt(j['fee']),
        uf: j['uf'],
        payed: asInt(j['payed']),
        flag: asInt(j['flag']),
        canExtend: asBool(j['canExtend']),
      );
}

class LyricResult {
  LyricResult({
    required this.sgc,
    required this.sfy,
    required this.qfy,
    required this.nolyric,
    required this.uncollected,
    required this.transUser,
    required this.lyricUser,
    required this.lrc,
    required this.klyric,
    required this.tlyric,
    required this.romalrc,
    required this.yrc,
    required this.ytlrc,
    required this.yromalrc,
    required this.code,
  });

  final bool sgc;
  final bool sfy;
  final bool qfy;
  final bool nolyric;
  final bool uncollected;
  final LyricUser? transUser;
  final LyricUser? lyricUser;
  final Lyrics? lrc;
  final Lyrics? klyric;
  final Lyrics? tlyric;
  final Lyrics? romalrc;
  final Lyrics? yrc;
  final Lyrics? ytlrc;
  final Lyrics? yromalrc;
  final int code;

  static T? _opt<T>(dynamic v, T Function(Map<String, dynamic>) fromJson) =>
      v == null ? null : fromJson(asObj(v));

  factory LyricResult.fromJson(Map<String, dynamic> j) => LyricResult(
        sgc: asBool(j['sgc']),
        sfy: asBool(j['sfy']),
        qfy: asBool(j['qfy']),
        nolyric: asBool(j['nolyric']),
        uncollected: asBool(j['uncollected']),
        transUser: _opt(j['transUser'], LyricUser.fromJson),
        lyricUser: _opt(j['lyricUser'], LyricUser.fromJson),
        lrc: _opt(j['lrc'], Lyrics.fromJson),
        klyric: _opt(j['klyric'], Lyrics.fromJson),
        tlyric: _opt(j['tlyric'], Lyrics.fromJson),
        romalrc: _opt(j['romalrc'], Lyrics.fromJson),
        yrc: _opt(j['yrc'], Lyrics.fromJson),
        ytlrc: _opt(j['ytlrc'], Lyrics.fromJson),
        yromalrc: _opt(j['yromalrc'], Lyrics.fromJson),
        code: asInt(j['code']),
      );
}

class LyricUser {
  LyricUser({
    required this.id,
    required this.status,
    required this.demand,
    required this.userid,
    required this.nickname,
    required this.uptime,
  });

  final int id;
  final int status;
  final int demand;
  final int userid;
  final String nickname;
  final int uptime;

  factory LyricUser.fromJson(Map<String, dynamic> j) => LyricUser(
        id: asInt(j['id']),
        status: asInt(j['status']),
        demand: asInt(j['demand']),
        userid: asInt(j['userid']),
        nickname: asStr(j['nickname']),
        uptime: asInt(j['uptime']),
      );
}

class Lyrics {
  Lyrics({required this.version, required this.lyric});

  final int version;
  final String lyric;

  factory Lyrics.fromJson(Map<String, dynamic> j) => Lyrics(
        version: asInt(j['version']),
        lyric: asStr(j['lyric']),
      );
}

class PlaylistResult {
  PlaylistResult({
    required this.code,
    required this.urls,
    required this.relatedVideos,
    required this.playlist,
    required this.privileges,
  });

  final int code;

  final String urls;

  final String relatedVideos;

  final Playlist? playlist;

  final List<Privilege> privileges;

  factory PlaylistResult.fromJson(Map<String, dynamic> j) => PlaylistResult(
        code: asInt(j['code']),
        urls: asStr(j['urls']),
        relatedVideos: asStr(j['relatedVideos']),
        playlist:
            j['playlist'] == null ? null : Playlist.fromJson(asObj(j['playlist'])),
        privileges: [
          for (final e in asArr(j['privileges'])) Privilege.fromJson(asObj(e))
        ],
      );
}

class AlbumResult {
  AlbumResult({required this.songs, required this.code, required this.album});

  final List<Song> songs;
  final int code;
  final Album? album;

  factory AlbumResult.fromJson(Map<String, dynamic> j) => AlbumResult(
        songs: [for (final e in asArr(j['songs'])) Song.fromJson(asObj(e))],
        code: asInt(j['code']),
        album: j['album'] == null ? null : Album.fromJson(asObj(j['album'])),
      );
}

class SimplePlaylist {
  SimplePlaylist({
    required this.id,
    required this.name,
    required this.coverImgUrl,
    required this.userId,
    required this.creator,
    required this.description,
    required this.playCount,
    required this.trackCount,
  });

  final String id;

  final String name;

  final String coverImgUrl;

  final int userId;

  final Creator? creator;

  final String description;

  final int playCount;

  final int trackCount;

  factory SimplePlaylist.fromJson(Map<String, dynamic> j) => SimplePlaylist(
        id: asStr(j['id']),
        name: asStr(j['name']),
        coverImgUrl: asStr(j['coverImgUrl']),
        userId: asInt(j['userId']),
        creator: j['creator'] == null ? null : Creator.fromJson(asObj(j['creator'])),
        description: asStr(j['description']),
        playCount: asInt(j['playCount']),
        trackCount: asInt(j['trackCount']),
      );
}

class Playlist extends SimplePlaylist {
  Playlist({
    required super.id,
    required super.name,
    required super.coverImgUrl,
    required super.userId,
    required super.creator,
    required super.description,
    required super.playCount,
    required super.trackCount,
    required this.coverImgId,
    required this.createTime,
    required this.status,
    required this.subscribedCount,
    required this.shareCount,
    required this.commentCount,
    required this.tags,
    required this.tracks,
  });

  final int coverImgId;

  final int createTime;

  final int status;

  final int subscribedCount;

  final int shareCount;

  final int commentCount;

  final List<String> tags;

  final List<Song> tracks;

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: asStr(j['id']),
        name: asStr(j['name']),
        coverImgUrl: asStr(j['coverImgUrl']),
        userId: asInt(j['userId']),
        creator: j['creator'] == null ? null : Creator.fromJson(asObj(j['creator'])),
        description: asStr(j['description']),
        playCount: asInt(j['playCount']),
        trackCount: asInt(j['trackCount']),
        coverImgId: asInt(j['coverImgId']),
        createTime: asInt(j['createTime']),
        status: asInt(j['status']),
        subscribedCount: asInt(j['subscribedCount']),
        shareCount: asInt(j['shareCount']),
        commentCount: asInt(j['commentCount']),
        tags: [for (final e in asArr(j['tags'])) asStr(e)],
        tracks: [for (final e in asArr(j['tracks'])) Song.fromJson(asObj(e))],
      );
}

class Album {
  Album({
    required this.paid,
    required this.onSale,
    required this.picId,
    required this.alias,
    required this.commentThreadId,
    required this.publishTime,
    required this.company,
    required this.copyrightId,
    required this.picUrl,
    required this.artist,
    required this.briefDesc,
    required this.tags,
    required this.artists,
    required this.status,
    required this.description,
    required this.subType,
    required this.blurPicUrl,
    required this.companyId,
    required this.pic,
    required this.name,
    required this.id,
    required this.type,
    required this.size,
    required this.picIdStr,
    required this.info,
  });

  final bool paid;
  final bool onSale;
  final int picId;
  final List<dynamic> alias;
  final String commentThreadId;
  final int publishTime;
  final String company;
  final int copyrightId;
  final String picUrl;
  final Artist? artist;
  final dynamic briefDesc;
  final String tags;
  final List<Artist> artists;
  final int status;
  final String description;
  final dynamic subType;
  final String blurPicUrl;
  final int companyId;
  final int pic;
  final String name;
  final int id;
  final String type;

  final int size;
  final String picIdStr;
  final Info? info;

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        paid: asBool(j['paid']),
        onSale: asBool(j['onSale']),
        picId: asInt(j['picId']),
        alias: asArr(j['alias']),
        commentThreadId: asStr(j['commentThreadId']),
        publishTime: asInt(j['publishTime']),
        company: asStr(j['company']),
        copyrightId: asInt(j['copyrightId']),
        picUrl: asStr(j['picUrl']),
        artist: j['artist'] == null ? null : Artist.fromJson(asObj(j['artist'])),
        briefDesc: j['briefDesc'],
        tags: asStr(j['tags']),
        artists: [for (final e in asArr(j['artists'])) Artist.fromJson(asObj(e))],
        status: asInt(j['status']),
        description: asStr(j['description']),
        subType: j['subType'],
        blurPicUrl: asStr(j['blurPicUrl']),
        companyId: asInt(j['companyId']),
        pic: asInt(j['pic']),
        name: asStr(j['name']),
        id: asInt(j['id']),
        type: asStr(j['type']),
        size: asInt(j['size']),
        picIdStr: asStr(j['picIdStr']),
        info: j['info'] == null ? null : Info.fromJson(asObj(j['info'])),
      );
}

class Song {
  Song({
    required this.name,
    required this.id,
    required this.artists,
    required this.alias,
    required this.album,
    required this.duration,
    required this.publishTime,
    required this.privilege,
  });

  final String name;
  final String id;
  final List<Ar>? artists;
  final List<dynamic>? alias;
  final Al? album;

  final int duration;

  final int publishTime;
  final Privilege? privilege;

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        name: asStr(j['name']),
        id: asStr(j['id']),
        artists: j['artists'] == null
            ? null
            : [for (final e in asArr(j['artists'])) Ar.fromJson(asObj(e))],
        alias: j['alias'] == null ? null : asArr(j['alias']),
        album: j['album'] == null ? null : Al.fromJson(asObj(j['album'])),
        duration: asInt(j['duration']),
        publishTime: asInt(j['publishTime']),
        privilege:
            j['privilege'] == null ? null : Privilege.fromJson(asObj(j['privilege'])),
      );
}

class EapiSong {
  EapiSong({
    required this.name,
    required this.id,
    required this.artists,
    required this.alias,
    required this.album,
    required this.duration,
    required this.publishTime,
    required this.privilege,
  });

  final String name;
  final String id;

  /// `[JsonProperty("ar")]`
  final List<Ar>? artists;

  /// `[JsonProperty("alia")]`
  final List<dynamic>? alias;

  /// `[JsonProperty("al")]`
  final Al? album;

  /// `[JsonProperty("dt")]`
  final int duration;

  final int publishTime;
  final Privilege? privilege;

  factory EapiSong.fromJson(Map<String, dynamic> j) => EapiSong(
        name: asStr(j['name']),
        id: asStr(j['id']),
        artists: j['ar'] == null
            ? null
            : [for (final e in asArr(j['ar'])) Ar.fromJson(asObj(e))],
        alias: j['alia'] == null ? null : asArr(j['alia']),
        album: j['al'] == null ? null : Al.fromJson(asObj(j['al'])),
        duration: asInt(j['dt']),
        publishTime: asInt(j['publishTime']),
        privilege:
            j['privilege'] == null ? null : Privilege.fromJson(asObj(j['privilege'])),
      );
}

class Info {
  Info({
    required this.commentThread,
    required this.latestLikedUsers,
    required this.liked,
    required this.comments,
    required this.resourceType,
    required this.resourceId,
    required this.commentCount,
    required this.likedCount,
    required this.shareCount,
    required this.threadId,
  });

  final CommentThread? commentThread;
  final dynamic latestLikedUsers;
  final bool liked;
  final dynamic comments;
  final int resourceType;
  final int resourceId;
  final int commentCount;
  final int likedCount;
  final int shareCount;
  final String threadId;

  factory Info.fromJson(Map<String, dynamic> j) => Info(
        commentThread: j['commentThread'] == null
            ? null
            : CommentThread.fromJson(asObj(j['commentThread'])),
        latestLikedUsers: j['latestLikedUsers'],
        liked: asBool(j['liked']),
        comments: j['comments'],
        resourceType: asInt(j['resourceType']),
        resourceId: asInt(j['resourceId']),
        commentCount: asInt(j['commentCount']),
        likedCount: asInt(j['likedCount']),
        shareCount: asInt(j['shareCount']),
        threadId: asStr(j['threadId']),
      );
}

class CommentThread {
  CommentThread({
    required this.id,
    required this.resourceInfo,
    required this.resourceType,
    required this.commentCount,
    required this.likedCount,
    required this.shareCount,
    required this.hotCount,
    required this.latestLikedUsers,
    required this.resourceId,
    required this.resourceOwnerId,
    required this.resourceTitle,
  });

  final String id;
  final ResourceInfo? resourceInfo;
  final int resourceType;
  final int commentCount;
  final int likedCount;
  final int shareCount;
  final int hotCount;
  final dynamic latestLikedUsers;
  final int resourceId;
  final int resourceOwnerId;
  final String resourceTitle;

  factory CommentThread.fromJson(Map<String, dynamic> j) => CommentThread(
        id: asStr(j['id']),
        resourceInfo: j['resourceInfo'] == null
            ? null
            : ResourceInfo.fromJson(asObj(j['resourceInfo'])),
        resourceType: asInt(j['resourceType']),
        commentCount: asInt(j['commentCount']),
        likedCount: asInt(j['likedCount']),
        shareCount: asInt(j['shareCount']),
        hotCount: asInt(j['hotCount']),
        latestLikedUsers: j['latestLikedUsers'],
        resourceId: asInt(j['resourceId']),
        resourceOwnerId: asInt(j['resourceOwnerId']),
        resourceTitle: asStr(j['resourceTitle']),
      );
}

class Artist {
  Artist({
    required this.img1V1Id,
    required this.topicPerson,
    required this.picId,
    required this.briefDesc,
    required this.albumSize,
    required this.img1V1Url,
    required this.picUrl,
    required this.alias,
    required this.trans,
    required this.musicSize,
    required this.name,
    required this.id,
    required this.publishTime,
    required this.mvSize,
    required this.followed,
  });

  final int img1V1Id;
  final int topicPerson;
  final int picId;
  final dynamic briefDesc;
  final int albumSize;
  final String img1V1Url;
  final String picUrl;
  final List<String> alias;
  final String trans;
  final int musicSize;
  final String name;
  final int id;
  final int publishTime;
  final int mvSize;
  final bool followed;

  factory Artist.fromJson(Map<String, dynamic> j) => Artist(
        img1V1Id: asInt(j['img1v1Id']),
        topicPerson: asInt(j['topicPerson']),
        picId: asInt(j['picId']),
        briefDesc: j['briefDesc'],
        albumSize: asInt(j['albumSize']),
        img1V1Url: asStr(j['img1v1Url']),
        picUrl: asStr(j['picUrl']),
        alias: [for (final e in asArr(j['alias'])) asStr(e)],
        trans: asStr(j['trans']),
        musicSize: asInt(j['musicSize']),
        name: asStr(j['name']),
        id: asInt(j['id']),
        publishTime: asInt(j['publishTime']),
        mvSize: asInt(j['mvSize']),
        followed: asBool(j['followed']),
      );
}

class Creator {
  Creator({
    required this.userId,
    required this.nickname,
    required this.signature,
    required this.description,
    required this.avatarUrl,
  });

  final int userId;

  final String nickname;

  final String signature;

  final String description;

  final String avatarUrl;

  factory Creator.fromJson(Map<String, dynamic> j) => Creator(
        userId: asInt(j['userId']),
        nickname: asStr(j['nickname']),
        signature: asStr(j['signature']),
        description: asStr(j['description']),
        avatarUrl: asStr(j['avatarUrl']),
      );
}

class ResourceInfo {
  ResourceInfo({
    required this.id,
    required this.userId,
    required this.name,
    required this.imgUrl,
    required this.creator,
  });

  final int id;
  final int userId;
  final String name;
  final dynamic imgUrl;
  final Creator? creator;

  factory ResourceInfo.fromJson(Map<String, dynamic> j) => ResourceInfo(
        id: asInt(j['id']),
        userId: asInt(j['userId']),
        name: asStr(j['name']),
        imgUrl: j['imgUrl'],
        creator: j['creator'] == null ? null : Creator.fromJson(asObj(j['creator'])),
      );
}

class Privilege {
  Privilege({
    required this.id,
    required this.fee,
    required this.payed,
    required this.st,
    required this.pl,
    required this.dl,
    required this.sp,
    required this.cp,
    required this.subp,
    required this.cs,
    required this.maxbr,
    required this.fl,
    required this.toast,
    required this.flag,
  });

  final int id;
  final int fee;
  final int payed;
  final int st;
  final int pl;
  final int dl;
  final int sp;
  final int cp;
  final int subp;
  final bool cs;
  final int maxbr;
  final int fl;
  final bool toast;
  final int flag;

  factory Privilege.fromJson(Map<String, dynamic> j) => Privilege(
        id: asInt(j['id']),
        fee: asInt(j['fee']),
        payed: asInt(j['payed']),
        st: asInt(j['st']),
        pl: asInt(j['pl']),
        dl: asInt(j['dl']),
        sp: asInt(j['sp']),
        cp: asInt(j['cp']),
        subp: asInt(j['subp']),
        cs: asBool(j['cs']),
        maxbr: asInt(j['maxbr']),
        fl: asInt(j['fl']),
        toast: asBool(j['toast']),
        flag: asInt(j['flag']),
      );
}

class DetailResult {
  DetailResult({required this.songs, required this.privileges, required this.code});

  final List<Song> songs;
  final List<Privilege> privileges;
  final int code;

  factory DetailResult.fromJson(Map<String, dynamic> j) => DetailResult(
        songs: [for (final e in asArr(j['songs'])) Song.fromJson(asObj(e))],
        privileges: [
          for (final e in asArr(j['privileges'])) Privilege.fromJson(asObj(e))
        ],
        code: asInt(j['code']),
      );
}

class Al {
  Al({
    required this.id,
    required this.name,
    required this.picUrl,
    required this.tns,
    required this.pic,
  });

  final int id;
  final String name;
  final String picUrl;
  final List<dynamic> tns;
  final int pic;

  factory Al.fromJson(Map<String, dynamic> j) => Al(
        id: asInt(j['id']),
        name: asStr(j['name']),
        picUrl: asStr(j['picUrl']),
        tns: asArr(j['tns']),
        pic: asInt(j['pic']),
      );
}

class Ar {
  Ar({
    required this.id,
    required this.name,
    required this.tns,
    required this.alias,
  });

  final int id;
  final String name;
  final List<dynamic> tns;
  final List<dynamic> alias;

  factory Ar.fromJson(Map<String, dynamic> j) => Ar(
        id: asInt(j['id']),
        name: asStr(j['name']),
        tns: asArr(j['tns']),
        alias: asArr(j['alias']),
      );
}
