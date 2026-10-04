// 用**真正的上游解析器**生成黄金样本。
//
// 为什么需要它：Vectra 里的 test/fixtures/lyricify/*.golden.json 是判定移植是否
// 与上游一致的 ground truth。之前只有 LRC/QRC/KRC/YRC/LyricifySyllable/
// LyricifyLines 六种格式有黄金样本，**TTML(Apple)、Spotify、Musixmatch 三种没有**——
// 也就是说这三个解析器从来没被真实输出校验过。这个工具补上那一块。
//
// 输出格式必须与已有黄金样本完全一致（test/fixtures/lyricify/*.golden.json）：
//   { file:{type,syncTypes,attributes,krcHash}, writers, trackMetadata:{...},
//     lines:[ {kind,text,startTime,endTime,alignment, syllableCount?,syllables?,
//              translations?,pronunciation?,subLine?} ] }
//   音节：{ kind:"SyllableInfo"|"FullSyllableInfo", text,startTime,endTime,
//            subItems?:[...] }
//
// 用法：dotnet run --project _goldengen -- <fixture目录> <输出目录>
using Lyricify.Lyrics.Helpers;
using Lyricify.Lyrics.Models;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

// 上游模型叫 FileInfo，和 System.IO.FileInfo 撞名，这里显式消歧。
using FileInfo = Lyricify.Lyrics.Models.FileInfo;

internal static class Program
{
    // (文件名, LyricsRawTypes, 解析后是否套用上游的"标准化"优化)
    // 既有的 7 份黄金样本是**裸解析**结果（不套 Standardize*），照着来：
    // 先按裸解析生成，再逐一和既有样本做字节比对，7/7 相同才算这个工具可信，
    // 之后新样本（TTML/Spotify/Musixmatch）才有资格当 ground truth。
    private static readonly (string File, LyricsRawTypes Type, bool Optimize)[] Targets =
    {
        ("LrcDemo.txt", LyricsRawTypes.Lrc, false),
        ("QrcDemo.txt", LyricsRawTypes.Qrc, false),
        ("KrcDemo.txt", LyricsRawTypes.Krc, false),
        ("YrcDemo.txt", LyricsRawTypes.Yrc, false),
        ("LyricifySyllableDemo.txt", LyricsRawTypes.LyricifySyllable, false),
        ("LsMixQrcDemo.txt", LyricsRawTypes.LyricifySyllable, false),
        ("LyricifyLinesDemo.txt", LyricsRawTypes.LyricifyLines, false),
        ("SpotifyDemo.txt", LyricsRawTypes.Spotify, false),
        ("SpotifySyllableDemo.txt", LyricsRawTypes.Spotify, false),
        ("SpotifyUnsyncedDemo.txt", LyricsRawTypes.Spotify, false),
        ("MusixmatchDemo.txt", LyricsRawTypes.Musixmatch, false),
        // AppleSyllableDemo.txt 是 Apple 的 JSON 信封
        // （{"data":[{"type":"syllable-lyrics","attributes":{"ttml":"<tt .../>"}}]}），
        // 不是裸 TTML，所以要用 AppleJson 而不是 Ttml——用错类型解析出来是 0 行。
        ("AppleSyllableDemo.txt", LyricsRawTypes.AppleJson, false),
    };

    private static void Main(string[] args)
    {
        string fixtures = args.Length > 0 ? args[0] : throw new ArgumentException("需要 fixture 目录");
        string outDir = args.Length > 1 ? args[1] : throw new ArgumentException("需要输出目录");
        Directory.CreateDirectory(outDir);

        foreach (var (file, type, optimize) in Targets)
        {
            string src = Path.Combine(fixtures, file);
            if (!File.Exists(src))
            {
                Console.WriteLine($"SKIP  {file}（不存在）");
                continue;
            }

            LyricsData data;
            string source = File.ReadAllText(src);
            LyricsRawTypes effective = type;
            try
            {
                // ParseHelper.ParseHelper.cs:33-45 **没有** AppleJson 分支（返回 null）——
                // Apple 的 JSON 信封是由 Providers/Web/AppleMusic/Api.cs 拆出
                // data[].attributes.ttml 之后再交给 TtmlParser 的。这里照抄那条路径。
                if (type == LyricsRawTypes.AppleJson)
                {
                    JObject envelope = JObject.Parse(source);
                    JToken? ttml = envelope["data"]?[0]?["attributes"]?["ttml"];
                    if (ttml == null)
                    {
                        Console.WriteLine($"FAIL  {file}: JSON 里没有 data[0].attributes.ttml");
                        continue;
                    }
                    source = ttml.ToString();
                    effective = LyricsRawTypes.Ttml;
                }

                data = ParseHelper.ParseLyrics(source, effective);
            }
            catch (Exception e)
            {
                Console.WriteLine($"FAIL  {file}: {e.GetType().Name}: {e.Message}");
                continue;
            }

            if (data?.Lines == null)
            {
                Console.WriteLine($"FAIL  {file}: 解析结果为 null");
                continue;
            }

            if (optimize)
            {
                if (type == LyricsRawTypes.Yrc)
                {
                    Lyricify.Lyrics.Helpers.Optimization.Yrc.StandardizeYrcLyrics(data.Lines);
                }
                else if (type == LyricsRawTypes.Musixmatch)
                {
                    Lyricify.Lyrics.Helpers.Optimization.Musixmatch.StandardizeMusixmatchLyrics(data.Lines);
                }
            }

            JObject root = new()
            {
                ["file"] = DumpFile(data.File),
                ["writers"] = data.Writers == null ? JValue.CreateNull() : new JArray(data.Writers),
                ["trackMetadata"] = data.TrackMetadata == null ? JValue.CreateNull() : DumpMetadata(data.TrackMetadata),
                ["lines"] = new JArray(data.Lines.Select(DumpLine).ToArray()),
            };

            string golden = Path.Combine(outDir, Path.GetFileNameWithoutExtension(file) + ".golden.json");
            File.WriteAllText(golden, root.ToString(Formatting.Indented));
            Console.WriteLine($"OK    {Path.GetFileName(golden)}  lines={data.Lines.Count} type={data.File?.Type} sync={data.File?.SyncTypes}");
        }
    }

    private static JObject DumpFile(FileInfo f)
    {
        // 既有黄金样本里 attributes 是**键值对的数组**（[["ti","..."],...]），
        // 不是对象——照着来，否则新样本和旧样本没法用同一份比较代码。
        JArray attributes = new();
        string krcHash = null;
        if (f?.AdditionalInfo is GeneralAdditionalInfo general && general.Attributes != null)
        {
            foreach (var kv in general.Attributes)
            {
                attributes.Add(new JArray(kv.Key, kv.Value));
            }
        }

        if (f?.AdditionalInfo is KrcAdditionalInfo krc)
        {
            krcHash = krc.Hash;
        }

        return new JObject
        {
            ["type"] = f?.Type.ToString(),
            ["syncTypes"] = f?.SyncTypes.ToString(),
            ["attributes"] = attributes.Count == 0 ? JValue.CreateNull() : attributes,
            ["krcHash"] = krcHash is null ? JValue.CreateNull() : JToken.FromObject(krcHash),
        };
    }

    private static JObject DumpMetadata(ITrackMetadata m) => new()
    {
        ["title"] = m?.Title is null ? JValue.CreateNull() : JToken.FromObject(m.Title),
        ["artist"] = m?.Artist is null ? JValue.CreateNull() : JToken.FromObject(m.Artist),
        ["album"] = m?.Album is null ? JValue.CreateNull() : JToken.FromObject(m.Album),
        ["durationMs"] = m?.DurationMs is null ? JValue.CreateNull() : JToken.FromObject(m.DurationMs),
    };

    private static JObject DumpLine(ILineInfo line)
    {
        JObject o = new()
        {
            ["kind"] = line.GetType().Name,
            ["text"] = line.Text,
            ["startTime"] = line.StartTime is null ? JValue.CreateNull() : JToken.FromObject(line.StartTime),
            ["endTime"] = line.EndTime is null ? JValue.CreateNull() : JToken.FromObject(line.EndTime),
            ["alignment"] = line.LyricsAlignment.ToString(),
        };

        if (line is SyllableLineInfo syl && syl.Syllables != null)
        {
            o["syllableCount"] = syl.Syllables.Count;
            o["syllables"] = new JArray(syl.Syllables.Select(DumpSyllable).ToArray());
        }

        if (line is IFullLineInfo full)
        {
            JObject tr = new();
            foreach (var kv in full.Translations)
            {
                tr[kv.Key] = kv.Value;
            }
            o["translations"] = tr;
            o["pronunciation"] = full.Pronunciation is null ? JValue.CreateNull() : JToken.FromObject(full.Pronunciation);
        }

        if (line.SubLine != null)
        {
            o["subLine"] = DumpLine(line.SubLine);
        }

        return o;
    }

    private static JObject DumpSyllable(ISyllableInfo s)
    {
        JObject o = new()
        {
            ["kind"] = s.GetType().Name,
            ["text"] = s.Text,
            ["startTime"] = s.StartTime,
            ["endTime"] = s.EndTime,
        };

        if (s is FullSyllableInfo full && full.SubItems != null)
        {
            o["subItems"] = new JArray(full.SubItems.Select(DumpSyllable).ToArray());
        }

        return o;
    }
}