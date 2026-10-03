///
library;

import '../core/logger.dart';
import '../lyrics/http/lyrics_http.dart';
import '../lyrics/lyrics_log.dart';
import '../lyrics/providers/web/base_api.dart';
import 'context.dart';

class HostLyricsHttpClient implements LyricsHttpClient {
  HostLyricsHttpClient(this.ctx);

  final WidgetContext ctx;

  @override
  Future<LyricsHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    String? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final r = await ctx.httpRequest(
      url.toString(),
      method: method,
      headers: headers,
      body: body,
    );

    final status = (r['status'] as num?)?.toInt();
    if (status == null) {
    }

    return LyricsHttpResponse(
      statusCode: status ?? 0,
      body: '${r['text'] ?? r['data'] ?? ''}',
    );
  }
}

///
void installLyricsHost(WidgetContext ctx) {
  BaseApi.httpClient = HostLyricsHttpClient(ctx);
  lyricsLogFn = (message, {bool warn = false}) {
    if (warn) {
      Log.w('lyrics', message);
    } else {
      Log.i('lyrics', message);
    }
  };
}
