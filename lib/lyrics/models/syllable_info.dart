/// Ported from Lyricify.Lyrics.Helper/Models/ISyllableInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
/// Ported from Lyricify.Lyrics.Helper/Models/SyllableInfo.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

abstract class SyllableInfo {
  String get text;

  int get startTime;

  int get endTime;

  int get duration => endTime - startTime;
}

class TextSyllableInfo extends SyllableInfo {
  TextSyllableInfo([this.text = '', this.startTime = 0, this.endTime = 0]);

  @override
  String text;

  @override
  int startTime;

  @override
  int endTime;
}

class FullSyllableInfo extends SyllableInfo {
  FullSyllableInfo([List<TextSyllableInfo>? subItems])
      : subItems = subItems ?? <TextSyllableInfo>[];

  List<TextSyllableInfo> subItems;

  String? _text;
  int? _startTime;
  int? _endTime;

  @override
  String get text => _text ??= SyllableHelper.getTextFromSyllableList(subItems);

  @override
  int get startTime =>
      _startTime ??= subItems.isEmpty ? 0 : subItems.first.startTime;

  @override
  int get endTime =>
      _endTime ??= subItems.isEmpty ? 0 : subItems.last.endTime;

  void refreshProperties() {
    _text = null;
    _startTime = null;
    _endTime = null;
  }
}

class SyllableHelper {
  static String getTextFromSyllableList(List<SyllableInfo> syllableList) =>
      syllableList.map((t) => t.text).join();
}
