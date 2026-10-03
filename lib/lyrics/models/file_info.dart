/// Ported from Lyricify.Lyrics.Helper/Models/FileInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
library;

import 'additional_file_info.dart';
import 'lyrics_types.dart';

class FileInfo {
  LyricsTypes type = LyricsTypes.unknown;

  SyncTypes syncTypes = SyncTypes.unknown;

  IAdditionalFileInfo? additionalInfo;
}
