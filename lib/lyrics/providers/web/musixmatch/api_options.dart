// Ported from Lyricify.Lyrics.Helper/Providers/Web/MusixMatch/ApiOptions.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import 'dart:math' as math;

import '../base_api.dart';

class ApiOptions {
  ApiOptions() {
    useAndroid();
  }

  String apiBaseUrl = '';

  String appId = '';

  String? userAgent;

  String? cookie;

  Duration timeout = Duration.zero;

  String Function() requestIdFactory = _newGuidN;

  void useAndroid() {
    apiBaseUrl = 'https://apic.musixmatch.com/ws/1.1/';
    appId = 'android-player-v1.0';
    userAgent = 'Dalvik/2.1.0 (Linux; U; Android 13)';
    cookie = 'AWSELB=0; AWSELBCORS=0';
    timeout = const Duration(seconds: 4);
    requestIdFactory = _newGuidN;
  }

  void useDesktop() {
    apiBaseUrl = 'https://apic-desktop.musixmatch.com/ws/1.1/';
    appId = 'web-desktop-app-v1.0';
    userAgent = BaseApi.userAgent;
    cookie = 'AWSELB=0; AWSELBCORS=0';
    timeout = const Duration(seconds: 4);
    requestIdFactory = () =>
        DateTime.now().toUtc().millisecondsSinceEpoch.toString();
  }

  void useMobile() {
    useAndroid();
  }

  static final math.Random _rng = math.Random.secure();

  static String _newGuidN() {
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(_rng.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }
}
