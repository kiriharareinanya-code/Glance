// Ported from Lyricify.Lyrics.Helper/Providers/QQMusicProviderResult.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
library;

import '../searchers/isearcher.dart';
import 'i_provider.dart';
import 'i_provider_result.dart';

class QQMusicProviderResult implements IProviderResult {
  QQMusicProviderResult();

  @override
  IProvider get provider => throw UnimplementedError();

  @override
  ISearchResult get searchResult => throw UnimplementedError();
}
