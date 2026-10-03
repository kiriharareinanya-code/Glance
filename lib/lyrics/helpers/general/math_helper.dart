// Ported from Lyricify.Lyrics.Helper/Helpers/General/MathHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
//
// `greaterThanZero(num)` / `greaterThan(num, num)` / `isBetween(num, num, num, {containEdge})`。
library;

class MathHelper {
  /// Returns the smaller of two 32-bit signed integers.
  ///
  static int? min(int? val1, int? val2) {
    if (val1 != null && val2 != null) {
      return val1 < val2 ? val1 : val2;
    }
    if (val1 != null) return val1;
    if (val2 != null) return val2;
    return null;
  }

  /// Returns the larger of two 32-bit signed integers.
  ///
  static int? max(int? val1, int? val2) {
    if (val1 != null && val2 != null) {
      return val1 > val2 ? val1 : val2;
    }
    if (val1 != null) return val1;
    if (val2 != null) return val2;
    return null;
  }

  /// Returns x if x is greater than zero, otherwise zero will be returned
  ///
  static num greaterThanZero(num x) {
    if (x < 0) return 0;
    return x;
  }

  /// Returns x if x is greater than a minimum value, otherwise the minimum value will be returned
  ///
  static num greaterThan(num x, num minValue) {
    if (x < minValue) return minValue;
    return x;
  }

  /// Returns whether x is between a and b
  ///
  /// [containEdge] Contain a and b or not
  ///
  static bool isBetween(num x, num a, num b, {bool containEdge = true}) {
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    if (!containEdge) {
      if (x < b && x > a) return true;
      return false;
    }
    if (x <= b && x >= a) return true;
    return false;
  }

  static (num, num) swap(num a, num b) => (b, a);
}
