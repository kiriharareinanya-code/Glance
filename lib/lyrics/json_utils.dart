///
///
library;

import 'dart:convert';

Map<String, dynamic> asObj(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<dynamic> asArr(dynamic v) => v is List ? v : const <dynamic>[];

List<Map<String, dynamic>> asObjArr(dynamic v) =>
    asArr(v).map(asObj).toList();

String asStr(dynamic v, [String def = '']) {
  if (v == null) return def;
  if (v is String) return v;
  return '$v';
}

int? asIntOrNull(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  if (v is bool) return v ? 1 : 0;
  return null;
}

int asInt(dynamic v, [int def = 0]) => asIntOrNull(v) ?? def;

double asDouble(dynamic v, [double def = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? def;
  return def;
}

bool asBool(dynamic v, [bool def = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return def;
}

dynamic jget(dynamic root, String path) {
  dynamic cur = root;
  for (final rawSeg in path.split('.')) {
    if (rawSeg.isEmpty) continue;
    var seg = rawSeg;
    final bracket = seg.indexOf('[');
    if (bracket >= 0) {
      final name = seg.substring(0, bracket);
      if (name.isNotEmpty) {
        cur = _member(cur, name);
      }
      final rest = seg.substring(bracket);
      final idxRe = RegExp(r'\[(\d+)\]');
      for (final m in idxRe.allMatches(rest)) {
        final list = asArr(cur);
        final i = int.parse(m.group(1)!);
        if (i < 0 || i >= list.length) return null;
        cur = list[i];
      }
    } else {
      cur = _member(cur, seg);
    }
    if (cur == null) return null;
  }
  return cur;
}

dynamic _member(dynamic cur, String name) {
  if (cur is Map) return cur[name];
  return null;
}

String jencode(Object? o) => jsonEncode(o);

T? decodeAs<T>(String body, T Function(Map<String, dynamic> json) fromJson) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    return fromJson(decoded.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

List<T>? decodeListAs<T>(
    String body, T Function(Map<String, dynamic> json) fromJson) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! List) return null;
    return <T>[for (final e in decoded) fromJson(asObj(e))];
  } catch (_) {
    return null;
  }
}
