/// 一次性探针（用完即删）：同名歌的歌词是不是同一首。
///
/// 背景：网易云的搜索接口**搜不到** en（王翊恩）版的《嚣张》（返回被
/// 「沈幼楚」这类刷榜账号污染），但同名条目很多且时长几乎一致。
/// 这里直接抓前几首同名歌的歌词，看它们是不是同一首词。
///
/// 跑法：flutter test test/_probe_netease.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _headers = {
  'Referer': 'https://music.163.com/',
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
};

Future<String> _get(HttpClient c, String url) async {
  final req = await c.getUrl(Uri.parse(url));
  _headers.forEach(req.headers.set);
  final res = await req.close();
  return res.transform(utf8.decoder).join();
}

void main() {
  test('检查同名的《嚣张》歌词是否一致', () async {
    final client = HttpClient();
    try {
      final body = await _get(
          client,
          'https://music.163.com/api/search/get'
              '?s=${Uri.encodeComponent('嚣张')}&type=1&limit=6');
      final songs =
          ((jsonDecode(body)['result'] as Map)['songs'] as List).cast<Map>();

      for (final s in songs) {
        final artists = [
          for (final a in (s['artists'] as List)) '${(a as Map)['name']}',
        ];
        final lyricBody = await _get(
            client,
            'https://music.163.com/api/song/lyric'
                '?id=${s['id']}&lv=1&kv=1&tv=-1');
        final lrc = '${(jsonDecode(lyricBody)['lrc'] as Map?)?['lyric'] ?? ''}';
        final texts = lrc
            .split('\n')
            .map((l) => l.replaceAll(RegExp(r'^\[.*?\]'), '').trim())
            .where((l) => l.isNotEmpty)
            .toList();
        // ignore: avoid_print
        print('\n「${s['name']}」/「${artists.join('/')}」'
            ' ${s['duration']}ms  共 ${texts.length} 行');
        for (final t in texts.take(3)) {
          // ignore: avoid_print
          print('    $t');
        }
      }
    } finally {
      client.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));
}
