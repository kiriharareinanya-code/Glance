/// Ported from Lyricify.Lyrics.Helper/Models/LyricsTypes.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
/// Ported from Lyricify.Lyrics.Helper/Models/SyncTypes.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

enum LyricsTypes {
  unknown,
  lyricifySyllable,
  lyricifyLines,
  lrc,
  qrc,
  krc,
  yrc,
  ttml,
  spotify,
  musixmatch,
}

enum LyricsRawTypes {
  unknown,
  lyricifySyllable,
  lyricifyLines,
  lrc,

  qrc,

  qrcFull,
  krc,

  yrc,

  yrcFull,
  ttml,

  appleJson,
  spotify,
  musixmatch,
}

enum SyncTypes {
  unknown,

  syllableSynced,

  lineSynced,

  mixedSynced,

  unsynced,
}
