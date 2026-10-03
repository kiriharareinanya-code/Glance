// Ported from Lyricify.Lyrics.Helper/Providers/Web/Netease/EapiHelper.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
///
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:pointycastle/paddings/pkcs7.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';

import '../../../http/lyrics_http.dart';

class EapiHelper {
  static Future<String> postAsync(
    String url,
    LyricsHttpClient httpClient,
    Map<String, String> data,
  ) async {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Referer': 'https://music.163.com/',
    };
    final header = <String, String>{
      '__csrf': '',
      'appver': '8.0.0',
      'buildver': getCurrentTotalSeconds().toString(),
      'channel': '',
      'deviceId': '',
      'mobilename': '',
      'resolution': '1920x1080',
      'os': 'android',
      'osver': '',
      'requestId':
          '${getCurrentTotalMilliseconds()}_${(Random().nextDouble() * 1000).floor().toString().padLeft(4, '0')}',
      'versioncode': '140',
      'MUSIC_U': '',
    };
    headers['Cookie'] = header.entries.map((t) => '${t.key}=${t.value}').join('; ');
    data['header'] = jsonEncode(header);
    final data2 = eApi(url, data);
    url = url.replaceAll(RegExp(r'\w*api'), 'eapi');

    final res = await httpClient.send(
      method: 'POST',
      url: Uri.parse(url),
      headers: {
        ...headers,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: Uri(queryParameters: data2).query,
    );
    if (!res.ok) {
    }
    return res.body;
  }

  static int getCurrentTotalSeconds() {
    final timeSpan = DateTime.now().toUtc().difference(DateTime.utc(1970, 1, 1));
    return timeSpan.inSeconds;
  }

  static int getCurrentTotalMilliseconds() {
    final timeSpan = DateTime.now().toUtc().difference(DateTime.utc(1970, 1, 1));
    return timeSpan.inMilliseconds;
  }

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 9; PCT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.64 HuaweiBrowser/10.0.3.311 Mobile Safari/537.36';

  /// `Encoding.ASCII.GetBytes("e82ckenh8dichen8")`。
  static final List<int> eapiKey = _ascii('e82ckenh8dichen8');

  static Map<String, String> eApi(String url, Object? object) {
    url = url.replaceAll('https://interface3.music.163.com/e', '/');
    url = url.replaceAll('https://interface.music.163.com/e', '/');
    final text = jsonEncode(object);
    final message = 'nobody${url}use${text}md5forencrypt';
    final digest = message.toByteArrayUtf8().computeMd5().toHexStringLower();
    final data = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';
    return <String, String>{
      'params': aesEncrypt(data.toByteArrayUtf8(), eapiKey, null).toHexStringUpper(),
    };
  }

  static Uint8List decrypt(List<int> cipherBuffer) =>
      aesDecrypt(cipherBuffer, eapiKey, null);

  ///
  static Uint8List aesEncrypt(
    List<int> buffer,
    List<int> key,
    List<int>? iv, {
    bool useCbc = false,
  }) {
    final engine = useCbc ? CBCBlockCipher(AESEngine()) : ECBBlockCipher(AESEngine());
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), engine)
      ..init(
        true,
        PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
          useCbc
              ? ParametersWithIV<KeyParameter>(
                  KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv!))
              : KeyParameter(Uint8List.fromList(key)),
          null,
        ),
      );
    return cipher.process(Uint8List.fromList(buffer));
  }

  static Uint8List aesEncryptCbc(List<int> buffer, List<int> key, List<int> iv) =>
      aesEncrypt(buffer, key, iv, useCbc: true);

  static Uint8List aesDecrypt(
    List<int> buffer,
    List<int> key,
    List<int>? iv, {
    bool useCbc = false,
  }) {
    final engine = useCbc ? CBCBlockCipher(AESEngine()) : ECBBlockCipher(AESEngine());
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), engine)
      ..init(
        false,
        PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
          useCbc
              ? ParametersWithIV<KeyParameter>(
                  KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv!))
              : KeyParameter(Uint8List.fromList(key)),
          null,
        ),
      );
    return cipher.process(Uint8List.fromList(buffer));
  }
}

List<int> _ascii(String value) =>
    value.codeUnits.map((c) => c <= 0x7f ? c : 0x3f).toList();

extension NeteaseEapiExtensions on String {
  List<int> toByteArrayUtf8() => utf8.encode(this);
}

extension NeteaseEapiBytesExtensions on List<int> {
  String toHexStringLower() =>
      map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join();

  String toHexStringUpper() =>
      map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0').toUpperCase()).join();

  String toBase64String() => base64.encode(this);

  List<int> computeMd5() => crypto.md5.convert(this).bytes;
}
