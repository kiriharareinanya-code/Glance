// Ported from Lyricify.Lyrics.Helper/Decrypter/Qrc/DESHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
library;

class DESHelper {
  static const int encrypt = 1;
  static const int decrypt = 0;

  // PERF: reusable Feistel scratch buffers.
  //
  // Before, every [_f] round allocated a fresh `List<int>.filled(6, 0)` and every
  // [crypt] allocated a fresh `List<int>.filled(2, 0)`. 3DES runs `crypt` 3x
  // with 16 rounds each, so a single 8-byte block burned **48 + 3 = 51** list
  // allocations; a 20-80 kB QRC payload (2.5k-10k blocks) allocated ~150k-500k
  // short-lived lists just for bookkeeping.
  //
  // Sharing one static buffer is safe because DES here is a single synchronous
  // computation with no re-entrancy: [_f] and [crypt] are only ever reached
  // through [tripleDESCrypt] -> [tripleDESKeySetup]/[keySchedule] setup and a
  // linear block loop, and no callback can re-enter them. Each isolate
  // (the `compute` offload in `decrypter.dart` included) gets its own copy of
  // these statics, so there is no cross-isolate sharing either.
  static final List<int> _stateScratch = List<int>.filled(2, 0);
  static final List<int> _lrgStateScratch = List<int>.filled(6, 0);

  static int _bitnum(List<int> a, int b, int c) =>
      ((a[(b ~/ 32) * 4 + 3 - (b % 32) ~/ 8] >> (7 - (b % 8))) & 0x01) << c;

  static int _bitnumintr(int a, int b, int c) =>
      ((a >> (31 - b)) & 0x00000001) << c;

  static int _bitnumintl(int a, int b, int c) =>
      ((a << b) & 0x80000000) >> c;

  static int _sboxbit(int a) =>
      (a & 0x20) | ((a & 0x1f) >> 1) | ((a & 0x01) << 4);

  static const List<int> sbox1 = [
    14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, //
    0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8, //
    4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, //
    15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13,
  ];

  static const List<int> sbox2 = [
    15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, //
    3, 13, 4, 7, 15, 2, 8, 15, 12, 0, 1, 10, 6, 9, 11, 5, //
    0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, //
    13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9,
  ];

  static const List<int> sbox3 = [
    10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, //
    13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1, //
    13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, //
    1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12,
  ];

  static const List<int> sbox4 = [
    7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, //
    13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9, //
    10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, //
    3, 15, 0, 6, 10, 10, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14,
  ];

  static const List<int> sbox5 = [
    2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, //
    14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6, //
    4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, //
    11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3,
  ];

  static const List<int> sbox6 = [
    12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, //
    10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8, //
    9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, //
    4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13,
  ];

  static const List<int> sbox7 = [
    4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, //
    13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6, //
    1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, //
    6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12,
  ];

  static const List<int> sbox8 = [
    13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, //
    1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2, //
    7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, //
    2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11,
  ];

  static const List<int> _keyRndShift = [
    1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1,
  ];
  static const List<int> _keyPermC = [
    56, 48, 40, 32, 24, 16, 8, 0, 57, 49, 41, 33, 25, 17, //
    9, 1, 58, 50, 42, 34, 26, 18, 10, 2, 59, 51, 43, 35,
  ];
  static const List<int> _keyPermD = [
    62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37, 29, 21, //
    13, 5, 60, 52, 44, 36, 28, 20, 12, 4, 27, 19, 11, 3,
  ];
  static const List<int> _keyCompression = [
    13, 16, 10, 23, 0, 4, 2, 27, 14, 5, 20, 9, //
    22, 18, 11, 3, 25, 7, 15, 6, 26, 19, 12, 1, //
    40, 51, 30, 36, 46, 54, 29, 39, 50, 44, 32, 47, //
    43, 48, 38, 55, 33, 52, 45, 41, 49, 35, 28, 31,
  ];

  static void keySchedule(List<int> key, List<List<int>> schedule, int mode) {
    var i = 0;
    var j = 0;
    var toGen = 0;
    var c = 0;
    var d = 0;

    i = 0;
    j = 31;
    c = 0;
    for (; i < 28; ++i) {
      c |= _bitnum(key, _keyPermC[i], j);
      --j;
    }

    i = 0;
    j = 31;
    d = 0;
    for (; i < 28; ++i) {
      d |= _bitnum(key, _keyPermD[i], j);
      --j;
    }

    for (i = 0; i < 16; ++i) {
      c = (((c << _keyRndShift[i]) | (c >> (28 - _keyRndShift[i]))) &
              0xfffffff0) &
          0xffffffff;
      d = (((d << _keyRndShift[i]) | (d >> (28 - _keyRndShift[i]))) &
              0xfffffff0) &
          0xffffffff;

      if (mode == decrypt) {
        toGen = 15 - i;
      } else {
        toGen = i;
      }

      for (j = 0; j < 6; ++j) {
        schedule[toGen][j] = 0;
      }

      for (j = 0; j < 24; ++j) {
        schedule[toGen][j ~/ 8] |= _bitnumintr(c, _keyCompression[j], 7 - (j % 8));
      }

      for (; j < 48; ++j) {
        schedule[toGen][j ~/ 8] |=
            _bitnumintr(d, _keyCompression[j] - 27, 7 - (j % 8));
      }
    }
  }

  static void _ip(List<int> state, List<int> input) {
    state[0] = _bitnum(input, 57, 31) |
        _bitnum(input, 49, 30) |
        _bitnum(input, 41, 29) |
        _bitnum(input, 33, 28) |
        _bitnum(input, 25, 27) |
        _bitnum(input, 17, 26) |
        _bitnum(input, 9, 25) |
        _bitnum(input, 1, 24) |
        _bitnum(input, 59, 23) |
        _bitnum(input, 51, 22) |
        _bitnum(input, 43, 21) |
        _bitnum(input, 35, 20) |
        _bitnum(input, 27, 19) |
        _bitnum(input, 19, 18) |
        _bitnum(input, 11, 17) |
        _bitnum(input, 3, 16) |
        _bitnum(input, 61, 15) |
        _bitnum(input, 53, 14) |
        _bitnum(input, 45, 13) |
        _bitnum(input, 37, 12) |
        _bitnum(input, 29, 11) |
        _bitnum(input, 21, 10) |
        _bitnum(input, 13, 9) |
        _bitnum(input, 5, 8) |
        _bitnum(input, 63, 7) |
        _bitnum(input, 55, 6) |
        _bitnum(input, 47, 5) |
        _bitnum(input, 39, 4) |
        _bitnum(input, 31, 3) |
        _bitnum(input, 23, 2) |
        _bitnum(input, 15, 1) |
        _bitnum(input, 7, 0);

    state[1] = _bitnum(input, 56, 31) |
        _bitnum(input, 48, 30) |
        _bitnum(input, 40, 29) |
        _bitnum(input, 32, 28) |
        _bitnum(input, 24, 27) |
        _bitnum(input, 16, 26) |
        _bitnum(input, 8, 25) |
        _bitnum(input, 0, 24) |
        _bitnum(input, 58, 23) |
        _bitnum(input, 50, 22) |
        _bitnum(input, 42, 21) |
        _bitnum(input, 34, 20) |
        _bitnum(input, 26, 19) |
        _bitnum(input, 18, 18) |
        _bitnum(input, 10, 17) |
        _bitnum(input, 2, 16) |
        _bitnum(input, 60, 15) |
        _bitnum(input, 52, 14) |
        _bitnum(input, 44, 13) |
        _bitnum(input, 36, 12) |
        _bitnum(input, 28, 11) |
        _bitnum(input, 20, 10) |
        _bitnum(input, 12, 9) |
        _bitnum(input, 4, 8) |
        _bitnum(input, 62, 7) |
        _bitnum(input, 54, 6) |
        _bitnum(input, 46, 5) |
        _bitnum(input, 38, 4) |
        _bitnum(input, 30, 3) |
        _bitnum(input, 22, 2) |
        _bitnum(input, 14, 1) |
        _bitnum(input, 6, 0);
  }

  static void _invIp(List<int> state, List<int> input) {
    input[3] = _bitnumintr(state[1], 7, 7) |
        _bitnumintr(state[0], 7, 6) |
        _bitnumintr(state[1], 15, 5) |
        _bitnumintr(state[0], 15, 4) |
        _bitnumintr(state[1], 23, 3) |
        _bitnumintr(state[0], 23, 2) |
        _bitnumintr(state[1], 31, 1) |
        _bitnumintr(state[0], 31, 0);

    input[2] = _bitnumintr(state[1], 6, 7) |
        _bitnumintr(state[0], 6, 6) |
        _bitnumintr(state[1], 14, 5) |
        _bitnumintr(state[0], 14, 4) |
        _bitnumintr(state[1], 22, 3) |
        _bitnumintr(state[0], 22, 2) |
        _bitnumintr(state[1], 30, 1) |
        _bitnumintr(state[0], 30, 0);

    input[1] = _bitnumintr(state[1], 5, 7) |
        _bitnumintr(state[0], 5, 6) |
        _bitnumintr(state[1], 13, 5) |
        _bitnumintr(state[0], 13, 4) |
        _bitnumintr(state[1], 21, 3) |
        _bitnumintr(state[0], 21, 2) |
        _bitnumintr(state[1], 29, 1) |
        _bitnumintr(state[0], 29, 0);

    input[0] = _bitnumintr(state[1], 4, 7) |
        _bitnumintr(state[0], 4, 6) |
        _bitnumintr(state[1], 12, 5) |
        _bitnumintr(state[0], 12, 4) |
        _bitnumintr(state[1], 20, 3) |
        _bitnumintr(state[0], 20, 2) |
        _bitnumintr(state[1], 28, 1) |
        _bitnumintr(state[0], 28, 0);

    input[7] = _bitnumintr(state[1], 3, 7) |
        _bitnumintr(state[0], 3, 6) |
        _bitnumintr(state[1], 11, 5) |
        _bitnumintr(state[0], 11, 4) |
        _bitnumintr(state[1], 19, 3) |
        _bitnumintr(state[0], 19, 2) |
        _bitnumintr(state[1], 27, 1) |
        _bitnumintr(state[0], 27, 0);

    input[6] = _bitnumintr(state[1], 2, 7) |
        _bitnumintr(state[0], 2, 6) |
        _bitnumintr(state[1], 10, 5) |
        _bitnumintr(state[0], 10, 4) |
        _bitnumintr(state[1], 18, 3) |
        _bitnumintr(state[0], 18, 2) |
        _bitnumintr(state[1], 26, 1) |
        _bitnumintr(state[0], 26, 0);

    input[5] = _bitnumintr(state[1], 1, 7) |
        _bitnumintr(state[0], 1, 6) |
        _bitnumintr(state[1], 9, 5) |
        _bitnumintr(state[0], 9, 4) |
        _bitnumintr(state[1], 17, 3) |
        _bitnumintr(state[0], 17, 2) |
        _bitnumintr(state[1], 25, 1) |
        _bitnumintr(state[0], 25, 0);

    input[4] = _bitnumintr(state[1], 0, 7) |
        _bitnumintr(state[0], 0, 6) |
        _bitnumintr(state[1], 8, 5) |
        _bitnumintr(state[0], 8, 4) |
        _bitnumintr(state[1], 16, 3) |
        _bitnumintr(state[0], 16, 2) |
        _bitnumintr(state[1], 24, 1) |
        _bitnumintr(state[0], 24, 0);
  }

  static int _f(int state, List<int> key) {
    final lrgstate = _lrgStateScratch;
    int t1, t2;

    t1 = _bitnumintl(state, 31, 0) |
        ((state & 0xf0000000) >> 1) |
        _bitnumintl(state, 4, 5) |
        _bitnumintl(state, 3, 6) |
        ((state & 0x0f000000) >> 3) |
        _bitnumintl(state, 8, 11) |
        _bitnumintl(state, 7, 12) |
        ((state & 0x00f00000) >> 5) |
        _bitnumintl(state, 12, 17) |
        _bitnumintl(state, 11, 18) |
        ((state & 0x000f0000) >> 7) |
        _bitnumintl(state, 16, 23);

    t2 = _bitnumintl(state, 15, 0) |
        ((state & 0x0000f000) << 15) |
        _bitnumintl(state, 20, 5) |
        _bitnumintl(state, 19, 6) |
        ((state & 0x00000f00) << 13) |
        _bitnumintl(state, 24, 11) |
        _bitnumintl(state, 23, 12) |
        ((state & 0x000000f0) << 11) |
        _bitnumintl(state, 28, 17) |
        _bitnumintl(state, 27, 18) |
        ((state & 0x0000000f) << 9) |
        _bitnumintl(state, 0, 23);

    lrgstate[0] = (t1 >> 24) & 0x000000ff;
    lrgstate[1] = (t1 >> 16) & 0x000000ff;
    lrgstate[2] = (t1 >> 8) & 0x000000ff;
    lrgstate[3] = (t2 >> 24) & 0x000000ff;
    lrgstate[4] = (t2 >> 16) & 0x000000ff;
    lrgstate[5] = (t2 >> 8) & 0x000000ff;

    lrgstate[0] ^= key[0];
    lrgstate[1] ^= key[1];
    lrgstate[2] ^= key[2];
    lrgstate[3] ^= key[3];
    lrgstate[4] ^= key[4];
    lrgstate[5] ^= key[5];

    state = (sbox1[_sboxbit(lrgstate[0] >> 2)] << 28) |
        (sbox2[_sboxbit(((lrgstate[0] & 0x03) << 4) | (lrgstate[1] >> 4))] << 24) |
        (sbox3[_sboxbit(((lrgstate[1] & 0x0f) << 2) | (lrgstate[2] >> 6))] << 20) |
        (sbox4[_sboxbit(lrgstate[2] & 0x3f)] << 16) |
        (sbox5[_sboxbit(lrgstate[3] >> 2)] << 12) |
        (sbox6[_sboxbit(((lrgstate[3] & 0x03) << 4) | (lrgstate[4] >> 4))] << 8) |
        (sbox7[_sboxbit(((lrgstate[4] & 0x0f) << 2) | (lrgstate[5] >> 6))] << 4) |
        sbox8[_sboxbit(lrgstate[5] & 0x3f)];

    state = _bitnumintl(state, 15, 0) |
        _bitnumintl(state, 6, 1) |
        _bitnumintl(state, 19, 2) |
        _bitnumintl(state, 20, 3) |
        _bitnumintl(state, 28, 4) |
        _bitnumintl(state, 11, 5) |
        _bitnumintl(state, 27, 6) |
        _bitnumintl(state, 16, 7) |
        _bitnumintl(state, 0, 8) |
        _bitnumintl(state, 14, 9) |
        _bitnumintl(state, 22, 10) |
        _bitnumintl(state, 25, 11) |
        _bitnumintl(state, 4, 12) |
        _bitnumintl(state, 17, 13) |
        _bitnumintl(state, 30, 14) |
        _bitnumintl(state, 9, 15) |
        _bitnumintl(state, 1, 16) |
        _bitnumintl(state, 7, 17) |
        _bitnumintl(state, 23, 18) |
        _bitnumintl(state, 13, 19) |
        _bitnumintl(state, 31, 20) |
        _bitnumintl(state, 26, 21) |
        _bitnumintl(state, 2, 22) |
        _bitnumintl(state, 8, 23) |
        _bitnumintl(state, 18, 24) |
        _bitnumintl(state, 12, 25) |
        _bitnumintl(state, 29, 26) |
        _bitnumintl(state, 5, 27) |
        _bitnumintl(state, 21, 28) |
        _bitnumintl(state, 10, 29) |
        _bitnumintl(state, 3, 30) |
        _bitnumintl(state, 24, 31);

    return state;
  }

  ///
  static void crypt(List<int> input, List<int> output, List<List<int>> key) {
    final state = _stateScratch;
    int idx, t;

    _ip(state, input);

    for (idx = 0; idx < 15; ++idx) {
      t = state[1];
      state[1] = _f(state[1], key[idx]) ^ state[0];
      state[0] = t;
    }

    state[0] = _f(state[1], key[15]) ^ state[0];

    _invIp(state, output);
    for (var i = 0; i < output.length; i++) {
      output[i] &= 0xFF;
    }
  }

  ///
  static void tripleDESKeySetup(
    List<int> key,
    List<List<List<int>>> schedule,
    int mode,
  ) {
    if (mode == encrypt) {
      keySchedule(key.sublist(0), schedule[0], mode);
      keySchedule(key.sublist(8), schedule[1], decrypt);
      keySchedule(key.sublist(16), schedule[2], mode);
    } else {
      /*if (mode == DES_DECRYPT*/
      keySchedule(key.sublist(0), schedule[2], mode);
      keySchedule(key.sublist(8), schedule[1], encrypt);
      keySchedule(key.sublist(16), schedule[0], mode);
    }
  }

  static void tripleDESCrypt(
    List<int> input,
    List<int> output,
    List<List<List<int>>> key,
  ) {
    crypt(input, output, key[0]);
    crypt(output, output, key[1]);
    crypt(output, output, key[2]);
  }
}
