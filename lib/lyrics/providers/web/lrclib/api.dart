// Ported from Lyricify.Lyrics.Helper/Providers/Web/LRCLIB/Api.cs (Apache-2.0, WXRIW/Lyricify-Lyrics-Helper)
///
library;

import '../../../json_utils.dart';
import '../../web/base_api.dart';
import 'response.dart';

class Api extends BaseApi {
  @override
  String? get httpRefer => null;

  @override
  Map<String, String>? get additionalHeaders => {
        'User-Agent':
            'Lyricify-Lyrics-Helper (https://github.com/WXRIW/Lyricify-Lyrics-Helper)'
      };

  static const String baseUrl = 'https://lrclib.net/api';

  // <summary>
  // </summary>
  // <returns></returns>
  Future<List<SearchResultItem>?> search(
    String trackName, [
    String? artistName,
    String? albumName,
    double? duration,
  ]) async {
    var url = '$baseUrl/search?track_name=${Uri.encodeComponent(trackName)}';

    if (artistName != null && artistName.isNotEmpty) {
      url += '&artist_name=${Uri.encodeComponent(artistName)}';
    }

    if (albumName != null && albumName.isNotEmpty) {
      url += '&album_name=${Uri.encodeComponent(albumName)}';
    }

    if (duration != null) {
      url += '&duration=$duration';
    }

    try {
      final response = await getAsync(url);
      return decodeListAs(response, SearchResultItem.fromJson);
    } catch (_) {
      return null;
    }
  }

  // <summary>
  // </summary>
  // <returns></returns>
  Future<GetLyricResult?> get(
    String trackName,
    String artistName, [
    String? albumName,
    double? duration,
  ]) async {
    var url =
        '$baseUrl/get?track_name=${Uri.encodeComponent(trackName)}&artist_name=${Uri.encodeComponent(artistName)}';

    if (albumName != null && albumName.isNotEmpty) {
      url += '&album_name=${Uri.encodeComponent(albumName)}';
    }

    if (duration != null) {
      url += '&duration=$duration';
    }

    try {
      final response = await getAsync(url);
      return decodeAs(response, GetLyricResult.fromJson);
    } catch (_) {
      return null;
    }
  }

  // <summary>
  // </summary>
  // <param name="id">LRCLIB ID</param>
  // <returns></returns>
  Future<GetLyricResult?> getById(int id) async {
    final url = '$baseUrl/get/$id';

    try {
      final response = await getAsync(url);
      return decodeAs(response, GetLyricResult.fromJson);
    } catch (_) {
      return null;
    }
  }
}
