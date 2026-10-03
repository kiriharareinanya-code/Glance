/// Ported from Lyricify.Lyrics.Helper/Models/AdditionalFileInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
library;

abstract class IAdditionalFileInfo {}

class GeneralAdditionalInfo implements IAdditionalFileInfo {
  List<MapEntry<String, String>>? attributes;
}

class KrcAdditionalInfo extends GeneralAdditionalInfo {
  String? hash;
}

///
class SpotifyAdditionalInfo implements IAdditionalFileInfo {
  SpotifyAdditionalInfo(
    this.provider,
    this.providerLyricsId,
    this.providerDisplayName, [
    this.lyricsLanguage,
  ]);

  final String? provider;

  final String? providerLyricsId;

  final String? providerDisplayName;

  final String? lyricsLanguage;
}
