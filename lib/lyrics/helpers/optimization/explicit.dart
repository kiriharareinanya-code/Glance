// Ported from Lyricify.Lyrics.Helper/Helpers/Optimization/Explicit.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
//   `str.Replace(a, b)` → `str.replaceAll(a, b)`；`str.Remove(i, 3)` + `str.Insert(i, "***")`
//   `Regex.Replace(input, pattern, matchEvaluator, RegexOptions.IgnoreCase)`
//     → `str.replaceAllMapped(RegExp(pattern, caseSensitive: false), evaluator)`。
//   `char.ToUpper(replacement[0]) + replacement[1..]` → `_toUpperFirstChar(replacement)`。
library;

class Explicit {
  Explicit._();

  ///
  static String clean(String str, [bool strong = false]) {
    if (strong) {
      str = fixExplicit(str)
          .replaceAll('bitches', '*****')
          .replaceAll('Bitches', '*****')
          .replaceAll('bitch', '*****')
          .replaceAll('Bitch', '*****')
          .replaceAll('damn', '****')
          .replaceAll('Damn', '****')
          .replaceAll('dammit', '******')
          .replaceAll('Dammit', '******')
          .replaceAll('dick', '****')
          .replaceAll('Dick', '****')
          .replaceAll('dope', '****')
          .replaceAll('Dope', '****')
          .replaceAll('fuck', '****')
          .replaceAll('Fuck', '****')
          .replaceAll('nigga', '*****')
          .replaceAll('Nigga', '*****')
          .replaceAll('nigras', '******')
          .replaceAll('Nigras', '******')
          .replaceAll('pussy', '*****')
          .replaceAll('Pussy', '*****')
          .replaceAll('sex', '***')
          .replaceAll('Sex', '***')
          .replaceAll('shit', '****')
          .replaceAll('Shit', '****')
          .replaceAll('weed', '****')
          .replaceAll('Weed', '****')
          .replaceAll('whore', '*****')
          .replaceAll('Whore', '*****')
          .replaceAll('cocaine', '*******')
          .replaceAll('Cocaine', '*******')
          .replaceAll('drug', '****')
          .replaceAll('Drug', '****');
      // Fix ass
      for (var i = 0; i < str.length - 2; i++) {
        if (str.substring(i, i + 3) == 'ass') {
          if (i > 0 && str[i - 1] != ' ' && str[i - 1] != '-') {
            i += 2;
            continue;
          } else if (i + 3 < str.length &&
              str[i + 3] != ' ' &&
              str[i + 3] != '-') {
            i += 2;
            continue;
          }
          str = _replaceAt(str, i, 3, '***');
          i += 2;
        }
      }
      // Fix Ass
      for (var i = 0; i < str.length - 2; i++) {
        if (str.substring(i, i + 3) == 'Ass') {
          if (i > 0 && str[i - 1] != ' ' && str[i - 1] != '-') {
            i += 2;
            continue;
          } else if (i + 3 < str.length &&
              str[i + 3] != ' ' &&
              str[i + 3] != '-') {
            i += 2;
            continue;
          }
          str = _replaceAt(str, i, 3, '***');
          i += 2;
        }
      }
      // Fix hoe
      for (var i = 0; i < str.length - 2; i++) {
        if (str.substring(i, i + 3) == 'hoe') {
          if (i > 0 && str[i - 1] != ' ' && str[i - 1] != '-') {
            i += 2;
            continue;
          } else if (i + 3 < str.length &&
              str[i + 3] != ' ' &&
              str[i + 3] != '-') {
            i += 2;
            continue;
          }
          str = _replaceAt(str, i, 3, '***');
          i += 2;
        }
      }
    } else {
      str = str
          .replaceAll('bitch', 'b***h')
          .replaceAll('Bitch', 'B***h')
          .replaceAll('damn', 'd**n')
          .replaceAll('Damn', 'D**n')
          .replaceAll('dammit', 'D**mit')
          .replaceAll('Dammit', 'D**mit')
          .replaceAll('dick', 'd**k')
          .replaceAll('Dick', 'D**k')
          .replaceAll('dope', 'd**e')
          .replaceAll('Dope', 'D**e')
          .replaceAll('fuck', 'f**k')
          .replaceAll('Fuck', 'F**k')
          .replaceAll('nigga', 'n***a')
          .replaceAll('Nigga', 'N***a')
          .replaceAll('nigras', 'n***as')
          .replaceAll('Nigras', 'N***as')
          .replaceAll('pussy', 'p***y')
          .replaceAll('Pussy', 'P***y')
          .replaceAll('sex', 's*x')
          .replaceAll('Sex', 'S*x')
          .replaceAll('shit', 's**t')
          .replaceAll('Shit', 'S**t')
          .replaceAll('weed', 'w**d')
          .replaceAll('Weed', 'W**d')
          .replaceAll('whore', 'w***e')
          .replaceAll('Whore', 'W***e');
      // Fix ass
      for (var i = 0; i < str.length - 2; i++) {
        if (str.substring(i, i + 3) == 'ass') {
          if (i > 0 && str[i - 1] != ' ' && str[i - 1] != '-') {
            i += 2;
            continue;
          } else if (i + 3 < str.length &&
              str[i + 3] != ' ' &&
              str[i + 3] != '-') {
            i += 2;
            continue;
          }
          str = _replaceAt(str, i, 3, 'a*s');
          i += 2;
        }
      }
      // Fix Ass
      for (var i = 0; i < str.length - 2; i++) {
        if (str.substring(i, i + 3) == 'Ass') {
          if (i > 0 && str[i - 1] != ' ' && str[i - 1] != '-') {
            i += 2;
            continue;
          } else if (i + 3 < str.length &&
              str[i + 3] != ' ' &&
              str[i + 3] != '-') {
            i += 2;
            continue;
          }
          str = _replaceAt(str, i, 3, 'A*s');
          i += 2;
        }
      }
      // Fix hoe
      for (var i = 0; i < str.length - 2; i++) {
        if (str.substring(i, i + 3) == 'hoe') {
          if (i > 0 && str[i - 1] != ' ' && str[i - 1] != '-') {
            i += 2;
            continue;
          } else if (i + 3 < str.length &&
              str[i + 3] != ' ' &&
              str[i + 3] != '-') {
            i += 2;
            continue;
          }
          str = _replaceAt(str, i, 3, 'h*e');
          i += 2;
        }
      }
    }
    return str;
  }

  static String fixExplicit(String str) {
    for (final (pattern, replacement) in _replacements) {
      str = str.replaceAllMapped(
        RegExp(pattern, caseSensitive: false),
        (match) {
          final original = match.group(0)!;
          return _isUpper(original[0])
              ? _toUpperFirstChar(replacement)
              : replacement;
        },
      );
    }
    return str;
  }

  static const List<(String pattern, String replacement)> _replacements = [
    (r'a\*s', 'ass'),
    (r'a\*\*', 'ass'),
    (r'b\*{3}h', 'bitch'),
    (r'b\*{2}ch', 'bitch'),
    (r'b\*{5}s', 'bitches'),
    (r'd\*{2}n', 'damn'),
    (r'd\*{2}mit', 'dammit'),
    (r'd\*{2}k', 'dick'),
    (r'd\*{2}e', 'dope'),
    (r'f\*{2}k', 'fuck'),
    (r'f\*ck', 'fuck'),
    (r'fu\*k', 'fuck'),
    (r'h\*e', 'hoe'),
    (r'h\*{2}s', 'hoes'),
    (r'mother\*{4}', 'motherfuck'),
    (r'n\*{3}a', 'nigga'),
    (r'n\*{2}ga', 'nigga'),
    (r'ni\*{2}a', 'nigga'),
    (r'n\*{3}as', 'nigras'),
    (r'p\*{3}y', 'pussy'),
    (r'p\*{2}sy', 'pussy'),
    (r'sh\*t', 'shit'),
    (r's\*x', 'sex'),
    (r's\*{2}t', 'shit'),
    (r'w\*{2}d', 'weed'),
    (r'w\*{3}e', 'whore'),
    (r'c\*{4}e', 'cocaine'),
    (r'd\*{2}g', 'drug'),
  ];

  static String _replaceAt(
    String str,
    int startIndex,
    int length,
    String replacement,
  ) =>
      str.substring(0, startIndex) +
      replacement +
      str.substring(startIndex + length);

  ///
  static String _toUpperFirstChar(String value) {
    if (value.isEmpty) return value;
    final upper = value[0].toUpperCase();
    return upper + value.substring(1);
  }

  static bool _isUpper(String character) {
    if (character.isEmpty) return false;
    final upper = character.toUpperCase();
    final lower = character.toLowerCase();
    return upper == character && lower != character;
  }
}
