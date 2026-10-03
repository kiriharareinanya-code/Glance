///
///
///
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class LyricsHttpResponse {
  const LyricsHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  bool get ok => statusCode >= 200 && statusCode < 300;

  @override
  String toString() => 'LyricsHttpResponse($statusCode, ${body.length}B)';
}

class LyricsHttpException implements Exception {
  const LyricsHttpException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'LyricsHttpException: $message'
      : 'LyricsHttpException($statusCode): $message';
}

abstract class LyricsHttpClient {
  ///
  Future<LyricsHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 15),
  });
}

///
class DirectLyricsHttpClient implements LyricsHttpClient {
  DirectLyricsHttpClient({
    http.Client? client,
    String? proxyHost,
    int? proxyPort,
    String? proxyUsername,
    String? proxyPassword,
  }) : _client = client ??
            _buildClient(proxyHost, proxyPort, proxyUsername, proxyPassword);

  final http.Client _client;

  static http.Client _buildClient(
      String? proxyHost, int? proxyPort, String? username, String? password) {
    if (proxyHost == null || proxyHost.isEmpty || proxyPort == null) {
      return http.Client();
    }
    final io = HttpClient();
    io.findProxy = (uri) => 'PROXY $proxyHost:$proxyPort';
    if (username != null && username.isNotEmpty) {
      io.authenticateProxy = (host, port, scheme, realm) {
        io.addProxyCredentials(host, port, realm ?? '',
            HttpClientBasicCredentials(username, password ?? ''));
        return Future.value(true);
      };
    }
    return IOClient(io);
  }

  static DirectLyricsHttpClient withProxy(String host, int port,
          {String? username, String? password}) =>
      DirectLyricsHttpClient(
          proxyHost: host,
          proxyPort: port,
          proxyUsername: username,
          proxyPassword: password);

  @override
  Future<LyricsHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final request = http.Request(method.toUpperCase(), url);
    if (headers != null) {
      headers.forEach((k, v) => request.headers[k] = v);
    }
    if (body != null) {
      request.bodyBytes = utf8.encode(body);
    }

    final streamed = await _client.send(request).timeout(timeout);
    final res = await http.Response.fromStream(streamed);
    return LyricsHttpResponse(
      statusCode: res.statusCode,
      body: utf8.decode(res.bodyBytes, allowMalformed: true),
    );
  }
}
