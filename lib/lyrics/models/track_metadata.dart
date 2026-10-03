/// Ported from Lyricify.Lyrics.Helper/Models/ITrackMetadata.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
/// Ported from Lyricify.Lyrics.Helper/Models/TrackMetadata.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

abstract class TrackMetadata {
  String? get title;

  set title(String? value);

  String? get artist;

  set artist(String? value);

  String? get album;

  set album(String? value);

  String? get albumArtist;

  set albumArtist(String? value);

  int? get durationMs;

  set durationMs(int? value);

  String? get isrc;

  set isrc(String? value);

  List<String>? get language;

  set language(List<String>? value);
}

class BasicTrackMetadata implements TrackMetadata {
  @override
  String? title;

  @override
  String? artist;

  @override
  String? album;

  @override
  String? albumArtist;

  @override
  int? durationMs;

  @override
  String? isrc;

  @override
  List<String>? language;
}

class TrackMultiArtistMetadata implements TrackMetadata {
  TrackMultiArtistMetadata();

  @override
  String? title;

  List<String> artists = <String>[];

  @override
  String? get artist => artists.join(', ');

  @override
  set artist(String? value) =>
      artists = (value ?? '').split(', ').toList();

  @override
  String? album;

  List<String> albumArtists = <String>[];

  @override
  String? get albumArtist => albumArtists.join(', ');

  @override
  set albumArtist(String? value) =>
      albumArtists = (value ?? '').split(', ').toList();

  @override
  int? durationMs;

  @override
  String? isrc;

  @override
  List<String>? language;

  static TrackMultiArtistMetadata getTrackMultiArtistMetadata(
      TrackMetadata track) {
    if (track is TrackMultiArtistMetadata) return track;

    final self = TrackMultiArtistMetadata();
    self.artist = track.artist;
    self.album = track.album;
    self.albumArtist = track.albumArtist;
    self.durationMs = track.durationMs;
    self.isrc = track.isrc;
    self.language = track.language;
    self.title = track.title;
    return self;
  }
}

class SpotifyTrackMetadata extends TrackMultiArtistMetadata {
  String? id;

  /// Spotify URI
  String? get uri => 'spotify:track:$id';
}
