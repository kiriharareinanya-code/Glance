///
///
library;

typedef LyricsLogFn = void Function(String message, {bool warn});

LyricsLogFn lyricsLogFn = _noopLog;

void _noopLog(String message, {bool warn = false}) {}

void lyricsLog(String message, {bool warn = false}) =>
    lyricsLogFn(message, warn: warn);
