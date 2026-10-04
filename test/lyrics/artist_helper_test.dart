// 对应上游 Lyricify.Lyrics.Helper/Searchers/Helpers/ArtistHelper.cs（Apache-2.0）的移植测试。
// 被测文件：lib/lyrics/searchers/helpers/artist_helper.dart
//
// ---------------------------------------------------------------------------
// 上游条目数统计（pwsh；数字 2077 就是写进下面断言的常量）：
//
//   $f = 'C:\Users\81157\Documents\deepseek-harness\default-workspace\refs\Lyricify-Lyrics-Helper\Lyricify.Lyrics.Helper\Searchers\Helpers\ArtistHelper.cs'
//   $lines = Get-Content -LiteralPath $f -Encoding UTF8
//   "total lines : $($lines.Count)"                                           # 2158
//   "new( 行数   : $((($lines | Select-String '^\s*new\(')).Count)"          # 2077
//   # 数据块 = 第 73..2149 行（1-based），区间内每一行都匹配
//   # ^\s{12}new\("([^"]*)", "(.*)", "(.*)"\),$   -> 区间内不匹配行数 = 0
//   # 数据块之外的 `new(` 行数 = 0（文件里只有 ArtistNamePairs 用 new(...) 初始化）
//
// 结论：上游 `ArtistNamePairs` 共 2077 条；`new(` 只出现在该数据块中，因此 2077 就是条目数。
// ---------------------------------------------------------------------------
//
// 校验和 0xC1870AD1 = FNV-1a 32bit，对整表每行 "<spotifyId>|<name>|<chineseName>\n"
// 的 UTF-16 code unit 逐个运算（生成时由上游 .cs 直接算出）。截断/漏条/改字都会让它变化。

import 'package:flutter_test/flutter_test.dart';
import 'package:vectra/lyrics/searchers/helpers/artist_helper.dart';

/// 上游 C# 文件里的条目数（统计命令见文件头）。
const int kUpstreamPairCount = 2077;

/// 整表 FNV-1a 32bit 校验和（由上游 .cs 生成）。
const int kUpstreamChecksum = 3246852817;

/// 整表校验和；算法与生成时一致：逐行 `"<id>|<name>|<cn>\n"` 的 UTF-16 code unit。
int _tableChecksum(List<ArtistNamePair> pairs) {
  var h = 0x811C9DC5;
  for (final p in pairs) {
    for (final c in '${p.spotifyId}|${p.name}|${p.chineseName}\n'.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
  }
  return h;
}

void main() {
  group('数据表完整性与上游一致', () {
    test('条目数 == 上游 2077 条', () {
      expect(ArtistHelper.artistNamePairs.length, kUpstreamPairCount);
    });

    test('整表校验和 == 上游（防止截断/漏条/改字）', () {
      expect(_tableChecksum(ArtistHelper.artistNamePairs), kUpstreamChecksum);
    });

    test('顺序与上游一致：首条 / 末条', () {
      final first = ArtistHelper.artistNamePairs.first;
      expect(first.spotifyId, '2elBjNSdBE2Y3f0j1mjrql');
      expect(first.name, 'Jay Chou');
      expect(first.chineseName, '周杰倫');

      final last = ArtistHelper.artistNamePairs.last;
      expect(last.spotifyId, '53JsFUDYcN2jw6v1nF7Z82');
      expect(last.name, 'Kuniyuki Takahashi');
      expect(last.chineseName, '高橋邦之');
    });

    test('每条都有非空的 spotifyId / name / chineseName', () {
      for (final p in ArtistHelper.artistNamePairs) {
        expect(p.spotifyId, isNotEmpty, reason: 'empty id: $p');
        expect(p.name, isNotEmpty, reason: 'empty name: $p');
        expect(p.chineseName, isNotEmpty, reason: 'empty chineseName: $p');
      }
    });
  });

  group('chineselizeArtist：抽样必须与上游一致', () {
    // 抽样 39 条（含英文 / 日文 / CJK 混合 / 中文名带空格 / 重复 Name），
    // 期望值全部直接取自上游 .cs 的同名条目。
    const samples = <(String, String)>[
      ("Jay Chou", "周杰倫"),
      ("Will Pan", "潘瑋柏"),
      ("Rainie Yang", "楊丞琳"),
      ("UchikubiGokumonDoukoukai", "打首獄門同好会"),
      ("su-xing-cyu", "四星球"),
      ("Kuniyuki Takahashi", "高橋邦之"),
      ("Sodagreen", "蘇打綠"),
      ("sodagreen", "蘇打綠"),
      ("Taku Iwasaki", "岩崎琢"),
      ("Sam-seng-hiàn-gē", "三牲獻藝"),
      ("Bae 林采欣", "林采欣"),
      ("Clémentine", "橘兒"),
      ("YAØ", "耀樂團"),
      ("李玉璽", "李玉玺"),
      ("Shallow Levée", "浅堤"),
      ("Lil’ Ashes", "小塵埃"),
      ("中島みゆき", "中島美雪"),
      ("Frandé", "法蘭黛樂團"),
      ("Kôhei Dojima", "堂島孝平"),
      ("Saburō Moroi", "諸井三郎"),
      ("ヒプノシスマイク -A.R.B- (Division All Stars)", "催眠麥克風 -A.R.B- (Division All Stars)"),
      ("Masaru Sato", "佐藤勝"),
      ("Chika Nishiwaki", "西脇千花"),
      ("Vivian Lai", "黎瑞恩"),
      ("Kazuki Kato", "加藤和樹"),
      ("Yo Hitoto", "一青窈"),
      ("Destroyers", "击沉女孩"),
      ("Kaho Hung", "洪嘉豪"),
      ("Tomoko Aran", "亜蘭知子"),
      ("Takeharu Nobuhara", "延原武春"),
      ("Landy Wen", "温岚"),
      ("EXILE TAKAHIRO", "放浪兄弟 TAKAHIRO"),
      ("Kohichi Makigami", "巻上公一"),
      ("Jin Hashimoto", "橋本仁"),
      ("Hidemaro Konoye", "近衛 秀麿"),
      ("Koji Kikkawa", "吉川晃司"),
      ("Ikuko Kawai", "川井郁子"),
      ("Yumiko Takahashi", "高橋由美子"),
      ("Ryoko Shinohara", "篠原涼子"),
    ];

    test('抽样 39 条逐条比对', () {
      expect(samples.length, greaterThanOrEqualTo(30));
      for (final (input, expected) in samples) {
        expect(ArtistHelper.chineselizeArtist(input), expected, reason: input);
      }
    });
  });

  group('chineselizeArtist：精确匹配语义（照抄上游）', () {
    test('重名条目返回首次出现的 ChineseName（上游 foreach 首个命中）', () {
      // 上游第 1266 行 "Taku Iwasaki" -> "岩崎琢"，第 1973 行同名 -> "岩崎 琢"；
      // C# 的 foreach 在第一条就 return，所以期望 "岩崎琢"。
      expect(ArtistHelper.chineselizeArtist('Taku Iwasaki'), '岩崎琢');
      // "Sodagreen"（第 392 行）与 "sodagreen"（第 1515 行）是两条不同 Name，值相同。
      expect(ArtistHelper.chineselizeArtist('Sodagreen'), '蘇打綠');
      expect(ArtistHelper.chineselizeArtist('sodagreen'), '蘇打綠');
    });

    test('大小写敏感，不做忽略大小写匹配', () {
      // sodagreen 是仅大小写不同的重名组；反向/其它大小写都算未命中。
      expect(ArtistHelper.chineselizeArtist('JAY CHOU'), 'JAY CHOU');
      expect(ArtistHelper.chineselizeArtist('jay chou'), 'jay chou');
      expect(ArtistHelper.chineselizeArtist('SODAGREEN'), 'SODAGREEN');
    });

    test('是精确匹配而不是包含匹配 / 前缀匹配', () {
      expect(ArtistHelper.chineselizeArtist('Jay Chou feat. Someone'), 'Jay Chou feat. Someone');
      expect(ArtistHelper.chineselizeArtist('Jay'), 'Jay');
      expect(ArtistHelper.chineselizeArtist('Jay Chou '), 'Jay Chou ');
      expect(ArtistHelper.chineselizeArtist(' Jay Chou'), ' Jay Chou');
    });

    test('未命中原样返回（不是空串、不抛异常）', () {
      const unknown = <String>[
        'No Such Artist 12345',
        '不存在的歌手',
        '不存在のアーティスト',
        '~~~',
        'Various Artists',
      ];
      for (final name in unknown) {
        expect(ArtistHelper.chineselizeArtist(name), name, reason: name);
        expect(ArtistHelper.chineselizeArtist(name), isNotEmpty);
      }
    });

    test('空串 / 纯空白返回空串（上游 string.IsNullOrWhiteSpace 分支）', () {
      expect(ArtistHelper.chineselizeArtist(''), '');
      expect(ArtistHelper.chineselizeArtist('   '), '');
      expect(ArtistHelper.chineselizeArtist('\t\n '), '');
      expect(ArtistHelper.chineselizeArtist(null), '');
    });
  });

  group('列表版本', () {
    test('toChineselizeArtists 与逐个调用结果一致，且不改动入参', () {
      final input = <String>[
        'Jay Chou',
        'Taku Iwasaki',
        'No Such Artist 12345',
        '',
        '   ',
        'Aimyon',
        'sodagreen',
        '不存在のアーティスト',
      ];
      final snapshot = List<String>.of(input);

      final out = ArtistHelper.toChineselizeArtists(input);

      expect(out.length, input.length);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], ArtistHelper.chineselizeArtist(input[i]), reason: input[i]);
      }
      expect(out, <String>['周杰倫', '岩崎琢', 'No Such Artist 12345', '', '', '愛繆', '蘇打綠', '不存在のアーティスト']);
      expect(input, snapshot, reason: 'toChineselizeArtists 不应改动入参');
      expect(identical(out, input), isFalse);
    });

    test('整表所有 Name 经列表版本结果与逐个调用一致', () {
      final names = ArtistHelper.artistNamePairs.map((p) => p.name).toList();
      final out = ArtistHelper.toChineselizeArtists(names);
      expect(out.length, kUpstreamPairCount);
      for (var i = 0; i < names.length; i++) {
        expect(out[i], ArtistHelper.chineselizeArtist(names[i]), reason: names[i]);
      }
    });

    test('chineselizeArtists 原地修改（对应上游 void 重载，无返回值）', () {
      final list = <String>['Jay Chou', 'No Such Artist 12345'];
      ArtistHelper.chineselizeArtists(list);
      expect(list, <String>['周杰倫', 'No Such Artist 12345']);
    });

    test('空列表', () {
      final empty = <String>[];
      expect(ArtistHelper.toChineselizeArtists(empty), isEmpty);
      ArtistHelper.chineselizeArtists(empty);
      expect(empty, isEmpty);
    });
  });
}
