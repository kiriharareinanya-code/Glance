// Ported from Lyricify.Lyrics.Helper/Searchers/Helpers/ArtistHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//
//   $f = "$refs\Lyricify-Lyrics-Helper\Lyricify.Lyrics.Helper\Searchers\Helpers\ArtistHelper.cs"
//   (Get-Content -LiteralPath $f -Encoding UTF8 | Select-String -Pattern '^\s*new\(').Count   # => 2077
//
// 1. `public record class Artist(string SpotifyId, string Name, string ChineseName)` → `class ArtistNamePair`。
//
library;

///
///
class ArtistNamePair {
  const ArtistNamePair(this.spotifyId, this.name, this.chineseName);

  final String spotifyId;

  final String name;

  final String chineseName;

  @override
  String toString() => 'ArtistNamePair($spotifyId, $name, $chineseName)';
}

typedef Artist = ArtistNamePair;

///
class ArtistHelper {
  ArtistHelper._();

  ///
  static String chineselizeArtist(String? artist) {
    if (artist == null || artist.trim().isEmpty) return '';

    for (final item in artistNamePairs) {
      if (item.name == artist) return item.chineseName;
    }

    return artist;
  }

  ///
  static void chineselizeArtists(List<String> artists) {
    for (var i = 0; i < artists.length; i++) {
      artists[i] = chineselizeArtist(artists[i]);
    }
  }

  ///
  static List<String> toChineselizeArtists(List<String> artists) {
    final newList = <String>[];

    for (var i = 0; i < artists.length; i++) {
      newList.add(chineselizeArtist(artists[i]));
    }

    return newList;
  }

  ///
  static final List<ArtistNamePair> artistNamePairs = <ArtistNamePair>[
  ];
}
