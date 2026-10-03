/// Ported from Lyricify.Lyrics.Helper/Providers/Web/Proxy.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
library;

import 'dart:io';

import 'package:http/io_client.dart';

import '../../http/lyrics_http.dart';
import 'base_api.dart';

class Proxy {
  static void setProxy(String host, int port,
      [String? username, String? password]) {
    BaseApi.httpClient = DirectLyricsHttpClient.withProxy(
      host,
      port,
      username: username,
      password: password,
    );
  }

  static void disableProxy() {
    final io = HttpClient();
    io.findProxy = (uri) => 'DIRECT';
    BaseApi.httpClient = DirectLyricsHttpClient(client: IOClient(io));
  }

  static void clearProxy() {
    BaseApi.httpClient = DirectLyricsHttpClient();
  }
}
