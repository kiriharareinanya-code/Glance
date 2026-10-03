// Ported from Lyricify.Lyrics.Helper/Providers/NeteaseProviderResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../searchers/isearcher.dart';
import 'i_provider.dart';
import 'i_provider_result.dart';

class NeteaseProviderResult implements IProviderResult {
  NeteaseProviderResult();

  @override
  IProvider get provider => throw UnimplementedError();

  @override
  ISearchResult get searchResult => throw UnimplementedError();
}
