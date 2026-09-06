/**
 * LRC 歌词解析（纯函数，可单独用 node 跑验证：test/js/lrc_verify.js）
 *
 * 单独成文件是为了能脱离 QuickJS 测——里面全是边界条件：一行多个时间戳、
 * 毫秒 2 位还是 3 位、[ti:]/[ar:] 这类元信息、时间戳乱序、空行。
 * 这些错了不会崩，只会让歌词错半拍，肉眼很难发现，所以必须有断言兜着。
 */

/* global globalThis */
(function (root) {
  'use strict';

  // [mm:ss.xx] 或 [mm:ss:xx]（少数源用冒号）或 [mm:ss]
  var TIME_RE = /\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;

  // 元信息行：[ti:标题] [ar:歌手] [al:专辑] [by:] [offset:] 等
  var META_RE = /^\[[a-zA-Z]+:/;

  /**
   * 把 LRC 文本解析成按时间升序的数组。
   * @param {string} text
   * @returns {Array<{t:number, s:string}>} t 是毫秒
   */
  function parse(text) {
    if (typeof text !== 'string' || !text) return [];
    var out = [];
    var lines = text.split(/\r?\n/);
    var offset = 0;

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line) continue;

      // [offset:-500] 是整体时移，正数表示歌词提前
      var om = /^\[offset:\s*([+-]?\d+)\s*\]/i.exec(line);
      if (om) {
        offset = parseInt(om[1], 10) || 0;
        continue;
      }

      TIME_RE.lastIndex = 0;
      var stamps = [];
      var m;
      while ((m = TIME_RE.exec(line)) !== null) {
        var min = parseInt(m[1], 10);
        var sec = parseInt(m[2], 10);
        var frac = m[3];
        var ms = 0;
        if (frac !== undefined) {
          // "5" -> 500ms，"50" -> 500ms，"500" -> 500ms
          // 两位是百分秒（绝大多数 LRC），三位才是毫秒
          if (frac.length === 1) ms = parseInt(frac, 10) * 100;
          else if (frac.length === 2) ms = parseInt(frac, 10) * 10;
          else ms = parseInt(frac, 10);
        }
        stamps.push(min * 60000 + sec * 1000 + ms);
      }

      if (stamps.length === 0) continue;

      // 去掉所有时间戳后剩下的才是正文
      var textPart = line.replace(TIME_RE, '').trim();
      // 元信息行（[ti:...]）不会匹配上 TIME_RE，所以走不到这儿；
      // 但有的源会写成 [00:00.00][ti:xxx]，兜一下
      if (META_RE.test(textPart)) continue;

      for (var k = 0; k < stamps.length; k++) {
        out.push({ t: stamps[k] - offset, s: textPart });
      }
    }

    // 源文件不保证有序（一行多时间戳就必然乱序）
    out.sort(function (a, b) { return a.t - b.t; });
    return out;
  }

  /**
   * 找出 posMs 时刻应该高亮第几行。
   * 返回 -1 表示还没到第一句（前奏）。
   *
   * 用二分而不是遍历：这个函数每 100ms 调一次，歌词可能上百行。
   */
  function indexAt(lines, posMs) {
    if (!lines || lines.length === 0) return -1;
    if (posMs < lines[0].t) return -1;
    var lo = 0, hi = lines.length - 1, ans = 0;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      if (lines[mid].t <= posMs) { ans = mid; lo = mid + 1; }
      else { hi = mid - 1; }
    }
    return ans;
  }

  /**
   * 把网易云的原文与翻译两段 LRC 合成一段：翻译接在原文后面。
   * 时间戳对不上的翻译行直接丢掉——宁可不显示，也不要错位显示。
   */
  function merge(main, trans) {
    if (!trans || trans.length === 0) return main;
    var map = {};
    for (var i = 0; i < trans.length; i++) map[trans[i].t] = trans[i].s;
    var out = [];
    for (var k = 0; k < main.length; k++) {
      var tr = map[main[k].t];
      out.push({
        t: main[k].t,
        s: main[k].s,
        tr: tr && tr !== main[k].s ? tr : ''
      });
    }
    return out;
  }

  /** 毫秒 -> "m:ss"，超过一小时才带小时位 */
  function fmt(ms) {
    if (!isFinite(ms) || ms < 0) ms = 0;
    var total = Math.floor(ms / 1000);
    var s = total % 60;
    var m = Math.floor(total / 60) % 60;
    var h = Math.floor(total / 3600);
    var mm = h > 0 && m < 10 ? '0' + m : String(m);
    var ss = s < 10 ? '0' + s : String(s);
    return h > 0 ? h + ':' + mm + ':' + ss : mm + ':' + ss;
  }

  // 常用繁→简映射（限标题/歌手归一化与查询变体用）。不求全——歌词搜索
  // 是拿它消除简繁差异带来的字面差异，搜索引擎自己也会做归一，这里只需
  // 覆盖歌名里高频出现的字。错字/漏字的代价是「该加的分没加上」，不会
  // 把正确结果挡在门外（见 pickSong 的注释）。
  var T2S_SRC = '東东專专愛爱陽阳無无樂乐語语聲声雲云電电畫画見见貝贝頁页門门問问間间聞闻閱阅書书寫写學学覺觉覽览優优傷伤價价眾众會会傳传偉伟側侧兒儿蘭兰興兴養养內内關关務务動动勢势華华協协單单賣卖衛卫廠厂歷历壓压縣县參参雙双變变葉叶號号嘆叹員员團团園园圍围國国圖图圓圆場场壞坏塊块堅坚壇坛處处備备復复夠够頭头夾夹奪夺奮奋婦妇媽妈娛娱孫孙寧宁寶宝實实寵宠審审層层歲岁豈岂崗岗島岛嶺岭峽峡幣币帥帅師师帳帐簾帘帶带幫帮寬宽慶庆庫库應应廢废棄弃彌弥彎弯歸归當当錄录徹彻從从憶忆憂忧懷怀態态憐怜總总戀恋懇恳惡恶惱恼懸悬驚惊懼惧慘惨慣惯願愿戰战撲扑執执擴扩掃扫揚扬擔担擬拟攏拢擇择掛挂摯挚擋挡掙挣揮挥損损換换據据擲掷攬揽擱搁擺摆搖摇攤摊撐撑敵敌敗败賬账貨货質质販贩貪贪貧贫貫贯費费賀贺賊贼賈贾資资賞赏賜赐賠赔賺赚賽赛讚赞贈赠贏赢趕赶趨趋躍跃踐践輪轮軟软軸轴輕轻載载較较輔辅輛辆輸输達达遷迁過过運运還还這这進进遠远違违連连遲迟點点臨临緊紧髒脏髮发麗丽舉举舊旧藝艺藥药蘇苏補补裝装裡里視视計计訊讯記记許许論论設设訪访證证評评詞词話话該该詳详誤误説说調调談谈請请諸诸讀读識识議议讓让財财賢贤購购軍军車车極极機机權权殺杀毀毁氣气汉汉決决淨净準准濕湿满满滨滨滾滚潜潜潔洁烏乌為为爾尔猶犹獄狱獎奖獨独獲获瑪玛瓊琼瘋疯盜盗盡尽监监盘盘矿矿碼码確确禮礼種种穩稳窮穷竊窃豎竖競竞筆笔簡简級级純纯紙纸細细紹绍經经維维網网綜综錯错難难響响顆颗飛飞飯饭馆馆馬马體体魚鱼鳥鸟麦麦麼么檔档檢检灣湾營营櫻樱狀状獅狮藍蓝製制規规覓觅註注認认護护豐丰賓宾蹟迹邊边適适選选鄉乡鄭郑針针韓韩頂顶頻频顧顾風风馳驰驅驱雞鸡';
  var T2S = {};
  for (var ti = 0; ti < T2S_SRC.length; ti += 2) T2S[T2S_SRC[ti]] = T2S_SRC[ti + 1];

  /** 繁体折叠到简体（逐字查表，表外字符原样返回） */
  function toSimplified(s) {
    return String(s || '').replace(/[㐀-鿿豈-﫿]/g, function (ch) {
      return T2S[ch] || ch;
    });
  }

  /** 归一化：所有标题/歌手比对的唯一入口——忽略大小写、空格、标点、
   *  括号内容、全角/半角、简繁差异。改规则要过 lrc_verify。 */
  function norm(s) {
    return toSimplified(String(s || ''))
      .replace(/[！-～　]/g, function (ch) {
        return ch === '　' ? ' ' : String.fromCharCode(ch.charCodeAt(0) - 0xFEE0);
      })
      .toLowerCase()
      .replace(/[（(\[].*?[)）\]]/g, '')
      .replace(/[\s\-_·,，.。!！?？'"“”‘’]/g, '');
  }

  /** 二元组 Dice 相似度：0~1。标题模糊比对的量化器——中文按字、
   *  英文按字母对，「字面对不上但确实像」的候选能据此拿到分 */
  function sim(a, b) {
    a = norm(a); b = norm(b);
    if (!a || !b) return 0;
    if (a === b) return 1;
    if (a.length < 2 || b.length < 2) return a === b ? 1 : 0;
    var ga = {}, na = 0;
    for (var i = 0; i < a.length - 1; i++) {
      var g = a.substr(i, 2);
      ga[g] = (ga[g] || 0) + 1; na++;
    }
    var nb = 0, inter = 0;
    for (var j = 0; j < b.length - 1; j++) {
      var gb = b.substr(j, 2); nb++;
      if (ga[gb]) { inter++; ga[gb]--; }
    }
    return na + nb === 0 ? 0 : (2 * inter) / (na + nb);
  }

  /**
   * 标题查询变体，按优先级排序（已按归一化去重，原始标题永远第一）。
   *
   * 覆盖的失败场景：
   *   「夜に駆ける (Yoru ni Kakeru)」→ 去括号 / 括号内罗马音单独当标题
   *   「Shape of You (Live)」        → 去掉 (Live) 再搜
   *   「陽光下的星星」                 → 繁体折叠成简体再搜
   *   「中英日混合标题」               → 拉丁段 / CJK 段各自单独试
   */
  function titleVariants(title) {
    var out = [], seen = {};
    function push(v) {
      // 去重键用**原始字符串**而不是 norm：norm 会剥掉括号内容，
      // 「X (Y)」和「X」就会被误判成同一个变体——而它们对搜索引擎
      // 是完全不同的查询，恰恰是要分开尝试的对象
      v = String(v || '').replace(/\s{2,}/g, ' ').trim();
      if (!v || seen[v]) return;
      seen[v] = 1;
      if (!norm(v)) return;
      out.push(v);
    }
    var t = String(title || '').trim();
    if (!t) return out;
    push(t);
    var bare = t.replace(/[（(\[].*?[)）\]]/g, '').trim();
    push(bare);
    var m = /[（(\[]([^)）\]]{2,})[)）\]]/.exec(t);
    if (m) push(m[1].trim());
    push(toSimplified(t));
    push(toSimplified(bare));
    var latin = t.replace(/[^ -~]/g, '').trim();
    if (latin && latin !== t) push(latin);
    var cjk = t.replace(/[^　-鿿豈-﫿]/g, '').trim();
    if (cjk && cjk !== t) push(cjk);
    return out;
  }

  // 伴奏 / remix / 现场版之类的衍生版本
  var JUNK = /(伴奏|instrumental|remix|dj版|纯享|翻自|cover|live|现场|demo|加速|减速|钢琴版|吉他版)/i;

  /**
   * 从搜索结果里挑一首。
   *
   * 两条实测教训写在这里，别再踩：
   *   1. 只按时长最接近会选错。搜「泡泡 牛佳钰」时，纯伴奏版与原曲只差 31ms，
   *      光比时长会挑中伴奏——歌词是对的，歌是错的。所以要给伴奏/Remix 扣分。
   *   2. 标题不能按字面严格比。播放器给的常是繁体（Spotify 上「陽光下的星星」），
   *      而曲库里是简体「阳光下的星星」，字面永远对不上。搜索引擎自己已经做过
   *      繁简归一了（实测搜繁体能返回简体结果），所以这里的打分只负责**排除
   *      明显不对的**，不该再去重做一遍模糊匹配——否则会把正确结果挡在门外。
   *
   * @param {Array} songs 网易云搜索返回的 songs
   * @param {string} title @param {string} artist @param {number} durMs 来自 SMTC
   * @returns {object|null} 选中的 song，或 null 表示没有够格的
   */
  function pickSong(songs, title, artist, durMs) {
    if (!songs || !songs.length) return null;
    var nt = norm(title), na = norm(artist);
    var best = null, bestScore = -1e9;

    for (var i = 0; i < songs.length; i++) {
      var s = songs[i];
      var names = [];
      for (var k = 0; k < (s.artists || []).length; k++) names.push(s.artists[k].name);
      var an = norm(names.join('/'));
      var sn = norm(s.name);
      var score = 0;

      // 歌手是最硬的信号：对上加分，明确对不上重扣，取不到就不表态
      if (na && an) {
        if (an.indexOf(na) >= 0 || na.indexOf(an) >= 0) score += 60;
        else score -= 40;
      }

      // 时长：3 秒内视为一致
      if (durMs > 0 && s.duration > 0) {
        var diff = Math.abs(s.duration - durMs);
        if (diff <= 3000) score += 50;
        else score -= Math.min(50, (diff - 3000) / 1000 * 3);
      }

      // 标题只加分不重扣（繁简、异体字、翻译名都会让字面对不上）。
      // 分档：字面相等 > 互相包含 > 二元组相似度。歌手单独搜时 nt 为空，
      // 必须跳过，否则 indexOf('') 恒成立会给所有结果加包含分。
      if (nt && sn) {
        if (sn === nt) score += 40;
        else if (sn.indexOf(nt) >= 0 || nt.indexOf(sn) >= 0) score += 25;
        else {
          var si = sim(sn, nt);
          if (si >= 0.3) score += Math.round(si * 30);
        }
      }

      // 原曲名里本来就写着 Live/Remix 时不该扣
      if (JUNK.test(s.name) && !JUNK.test(title)) score -= 70;

      // 搜索引擎的排序本身就是信息，靠前的略微加分
      score += Math.max(0, 10 - i * 2);

      if (score > bestScore) { bestScore = score; best = s; }
    }
    // 够不到门槛就宁可显示"没找到"，也不要贴一首别的歌的歌词
    return bestScore >= 60 ? best : null;
  }

  var api = {
    parse: parse,
    indexAt: indexAt,
    merge: merge,
    fmt: fmt,
    norm: norm,
    toSimplified: toSimplified,
    sim: sim,
    titleVariants: titleVariants,
    pickSong: pickSong
  };

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;   // node 跑验证时用
  } else {
    root.LRC = api;         // QuickJS 里挂到全局，index.js 直接用
  }
})(typeof globalThis !== 'undefined' ? globalThis : this);
