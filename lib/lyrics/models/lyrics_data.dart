/// Ported from Lyricify.Lyrics.Helper/Models/LyricsData.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
library;

import 'file_info.dart';
import 'line_info.dart';
import 'track_metadata.dart';

class LyricsData {
  FileInfo? file;

  List<LineInfo>? lines;

  List<String>? writers;

  TrackMetadata? trackMetadata;
}
