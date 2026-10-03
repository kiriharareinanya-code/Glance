// Ported from Lyricify.Lyrics.Helper/Providers/IProviderResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../searchers/isearcher.dart';
import 'i_provider.dart';

abstract class IProviderResult {
  IProvider get provider;

  ISearchResult get searchResult;
}
