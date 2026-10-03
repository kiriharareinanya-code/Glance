// Ported from Lyricify.Lyrics.Helper/Providers/Web/Spotify/Models.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../../json_utils.dart';

class SearchResponse {
  SearchResponse({required this.tracks});

  factory SearchResponse.fromJson(Map<String, dynamic> j) => SearchResponse(
        tracks: j['tracks'] == null
            ? null
            : SearchTracks.fromJson(asObj(j['tracks'])),
      );

  SearchTracks? tracks;
}

class SearchTracks {
  SearchTracks({required this.items});

  factory SearchTracks.fromJson(Map<String, dynamic> j) => SearchTracks(
        items: j['items'] is List
            ? [for (final e in asArr(j['items'])) SearchTrackItem.fromJson(asObj(e))]
            : null,
      );

  List<SearchTrackItem>? items;
}

class SearchTrackItem {
  SearchTrackItem({
    required this.id,
    required this.name,
    required this.durationMs,
    required this.artists,
    required this.album,
  });

  factory SearchTrackItem.fromJson(Map<String, dynamic> j) => SearchTrackItem(
        id: asStr(j['id']),
        name: asStr(j['name']),
        durationMs: asInt(j['duration_ms']),
        artists: j['artists'] is List
            ? [for (final e in asArr(j['artists'])) SearchArtistItem.fromJson(asObj(e))]
            : null,
        album:
            j['album'] == null ? null : SearchAlbumItem.fromJson(asObj(j['album'])),
      );

  String id;

  String name;

  int durationMs;

  List<SearchArtistItem>? artists;

  SearchAlbumItem? album;
}

class SearchAlbumItem {
  SearchAlbumItem({required this.name, required this.artists});

  factory SearchAlbumItem.fromJson(Map<String, dynamic> j) => SearchAlbumItem(
        name: asStr(j['name']),
        artists: j['artists'] is List
            ? [for (final e in asArr(j['artists'])) SearchArtistItem.fromJson(asObj(e))]
            : null,
      );

  String name;

  List<SearchArtistItem>? artists;
}

class SearchArtistItem {
  SearchArtistItem({required this.name});

  factory SearchArtistItem.fromJson(Map<String, dynamic> j) =>
      SearchArtistItem(name: asStr(j['name']));

  String name;
}

class SpotifyTrackCandidate {
  SpotifyTrackCandidate({
    required this.id,
    required this.title,
    required this.artistName,
    required this.albumName,
    required this.durationMs,
  });

  factory SpotifyTrackCandidate.fromJson(Map<String, dynamic> j) =>
      SpotifyTrackCandidate(
        id: asStr(j['id']),
        title: asStr(j['title']),
        artistName: asStr(j['artist_name']),
        albumName: asStr(j['album_name']),
        durationMs: asIntOrNull(j['duration_ms']),
      );

  String id;

  String title;

  String artistName;

  String albumName;

  int? durationMs;
}

class SpotifyTokenResponse {
  SpotifyTokenResponse({
    required this.accessToken,
    required this.accessTokenExpirationTimestampMs,
    required this.isAnonymous,
  });

  factory SpotifyTokenResponse.fromJson(Map<String, dynamic> j) =>
      SpotifyTokenResponse(
        accessToken: j['accessToken'] == null ? null : asStr(j['accessToken']),
        accessTokenExpirationTimestampMs:
            asInt(j['accessTokenExpirationTimestampMs']),
        isAnonymous: j['isAnonymous'] == null ? null : asBool(j['isAnonymous']),
      );

  String? accessToken;

  int accessTokenExpirationTimestampMs;

  bool? isAnonymous;
}
