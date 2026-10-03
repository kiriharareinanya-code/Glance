// Ported from Lyricify.Lyrics.Helper/Providers/Provider.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import 'i_provider.dart';
import 'i_provider_result.dart';

abstract class Provider implements IProvider {
  String get name;

  String get displayName;

  IProviderResult obtainLyrics();
}
