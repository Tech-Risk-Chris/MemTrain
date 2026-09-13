/-
  Tray.lean — a static site generator for a lexical Kim's Game.

  Emits a single self-contained `index.html`: no build step, no runtime,
  nothing to serve but bytes. Drop it in an S3 bucket and open it.

  Run:   lean --run Tray.lean
  Or:    lake env lean --run Tray.lean   (if you put it in a lake project)

  The word pool is compiled into the page as a JSON literal; sampling
  happens in the browser on each round, so one file gives unlimited rounds.
-/

namespace MemTrain.Tray

/-- One item on the tray. `freq` and `band` come from the BNC frequency
    list; `band` is the difficulty dial (sampling can be restricted to one). -/
structure Token where
  word : String
  freq : Nat := 0
  band : String := ""
  deriving Repr, Inhabited

/-- Page-level settings baked into the generated file. -/
structure Config where
  title     : String := "Tray"
  subtitle  : String := "Fifteen words, one minute, then write down what you can."
  trayCount : Nat := 15
  studySecs : Nat := 60
  outFile   : System.FilePath := "index.html"
  deriving Inhabited

/-! ## Escaping -/

/-- Escape a string for a JSON literal living inside a `script` element.
    `<`, `>` and `&` go out as escapes so no word can close the tag. -/
def jsEscape (s : String) : String :=
  s.foldl (fun acc c =>
    let e : String :=
      match c with
      | '"'  => "\\\""
      | '\\' => "\\\\"
      | '<'  => "\\u003c"
      | '>'  => "\\u003e"
      | '&'  => "\\u0026"
      | '\n' => "\\n"
      | '\r' => "\\r"
      | '\t' => "\\t"
      | c    => c.toString
    acc ++ e) ""

/-- Escape a string for HTML text content. -/
def htmlEscape (s : String) : String :=
  s.foldl (fun acc c =>
    let e : String :=
      match c with
      | '<' => "&lt;"
      | '>' => "&gt;"
      | '&' => "&amp;"
      | '"' => "&quot;"
      | c   => c.toString
    acc ++ e) ""

/-! ## Serialisation -/

def Token.toJson (t : Token) : String :=
  "{\"w\":\"" ++ jsEscape t.word ++ "\",\"f\":" ++ toString t.freq ++
  ",\"b\":\"" ++ jsEscape t.band ++ "\"}"

def poolToJson (ts : Array Token) : String :=
  if ts.isEmpty then "[]"
  else "[\n  " ++ String.intercalate ",\n  " (ts.toList.map Token.toJson) ++ "\n]"

def Config.toJson (c : Config) : String :=
  "{\"count\":" ++ toString c.trayCount ++
  ",\"secs\":" ++ toString c.studySecs ++ "}"

/-! ## The page

The HTML is split into three raw chunks with the generated data spliced
between them. Nothing here uses `#`, so `r#"..."#` stays well-formed. -/

def headA : String := r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>"#

def headB : String := r#"</title>
<style>
  :root {
    --baize:      rgb(28, 58, 50);
    --baize-deep: rgb(19, 41, 35);
    --baize-lift: rgb(40, 76, 66);
    --chalk:      rgb(238, 234, 221);
    --chalk-dim:  rgb(166, 180, 172);
    --brass:      rgb(201, 160, 84);
    --rust:       rgb(198, 112, 94);
  }
  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body {
    margin: 0;
    padding: 2.5rem 1.5rem 5rem;
    background: var(--baize);
    color: var(--chalk);
    font-family: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
    font-size: 17px;
    line-height: 1.55;
  }
  .wrap { max-width: 46rem; margin: 0 auto; }

  .masthead { margin-bottom: 2rem; }
  .masthead h1 {
    margin: 0;
    font-size: clamp(2rem, 7vw, 3.25rem);
    font-weight: 400;
    letter-spacing: -0.02em;
    line-height: 1.05;
  }
  .masthead p {
    margin: 0.5rem 0 0;
    max-width: 34em;
    color: var(--chalk-dim);
    font-style: italic;
  }

  .controls {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    gap: 1.25rem;
    padding: 1rem 0 1.5rem;
    border-bottom: 1px solid var(--baize-lift);
  }
  .field { display: flex; flex-direction: column; gap: 0.3rem; }
  .field span { font-size: 0.82rem; color: var(--chalk-dim); }
  input, select, button {
    font: inherit;
    color: inherit;
    background: var(--baize-deep);
    border: 1px solid var(--baize-lift);
    border-radius: 2px;
    padding: 0.45rem 0.6rem;
  }
  input[type="number"] { width: 5rem; }
  button { cursor: pointer; border-color: var(--brass); }
  button:hover { background: var(--baize-lift); }
  button:focus-visible, input:focus-visible, select:focus-visible {
    outline: 2px solid var(--brass);
    outline-offset: 2px;
  }
  .primary {
    background: var(--brass);
    color: var(--baize-deep);
    font-weight: 600;
    padding: 0.5rem 1.4rem;
  }
  .primary:hover { background: rgb(219, 179, 104); }

  .tray {
    position: relative;
    margin: 2rem 0;
    padding: 1.75rem 1.5rem;
    background: var(--baize-deep);
    border: 1px solid var(--baize-lift);
    box-shadow: inset 0 0 0 6px var(--baize-deep), inset 0 0 0 7px rgba(201, 160, 84, 0.25);
    min-height: 11rem;
  }
  .clock {
    position: absolute;
    top: 0; left: 0;
    height: 3px;
    width: 100%;
    background: var(--brass);
    transform-origin: left;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(8.5rem, 1fr));
    gap: 0.85rem 1.25rem;
  }
  .grid li {
    list-style: none;
    font-size: 1.22rem;
    letter-spacing: 0.01em;
  }
  .grid { margin: 0; padding: 0; }
  .empty { margin: 0; color: var(--chalk-dim); font-style: italic; }
  .covered { color: var(--chalk-dim); font-style: italic; margin: 0; }

  .recall { display: flex; gap: 0.6rem; flex-wrap: wrap; }
  .recall input { flex: 1 1 14rem; }
  .tally { margin: 0.6rem 0 0; color: var(--chalk-dim); font-size: 0.88rem; }
  ol.given { margin: 1rem 0 0; padding-left: 2.2rem; columns: 2; column-gap: 2rem; }
  ol.given li { padding-left: 0.2rem; }
  @media (max-width: 30rem) { ol.given { columns: 1; } }

  .score {
    font-size: clamp(2.5rem, 10vw, 4rem);
    line-height: 1;
    margin: 0 0 0.4rem;
    font-variant-numeric: tabular-nums;
  }
  .score em { font-style: normal; color: var(--chalk-dim); }
  .verdict { margin: 0 0 1.5rem; color: var(--chalk-dim); }
  .bucket { margin: 0 0 1.1rem; }
  .bucket h3 {
    margin: 0 0 0.25rem;
    font-size: 0.95rem;
    font-weight: 600;
    color: var(--chalk-dim);
  }
  .bucket p { margin: 0; }
  .missed { color: var(--rust); }
  .extra { color: var(--chalk-dim); }

  .ledger { margin-top: 3rem; border-top: 1px solid var(--baize-lift); padding-top: 1.25rem; }
  .ledger h2 { font-size: 1rem; font-weight: 600; margin: 0 0 0.75rem; color: var(--chalk-dim); }
  table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
  th, td { text-align: left; padding: 0.3rem 0.75rem 0.3rem 0; font-size: 0.9rem; }
  th { font-weight: 600; color: var(--chalk-dim); }
  tbody tr + tr td { border-top: 1px solid var(--baize-lift); }
  .hidden { display: none; }
  @media (prefers-reduced-motion: reduce) { .clock { transition: none !important; } }
</style>
</head>
<body>
<div class="wrap">

  <header class="masthead">
    <h1 class="js-title"></h1>
    <p class="js-subtitle"></p>
  </header>

  <div class="controls">
    <label class="field"><span>Words on the tray</span>
      <input class="js-count" type="number" min="3" max="60" step="1"></label>
    <label class="field"><span>Seconds to study</span>
      <input class="js-secs" type="number" min="5" max="600" step="5"></label>
    <label class="field js-bandfield hidden"><span>Frequency band</span>
      <select class="js-band"></select></label>
    <button class="primary js-start">Lay out the tray</button>
  </div>

  <section class="tray">
    <div class="clock js-clock hidden"></div>
    <ul class="grid js-grid"></ul>
    <p class="js-trayNote empty">The tray is empty. Set your numbers and lay it out.</p>
  </section>

  <section class="js-recallPanel hidden">
    <div class="recall">
      <input class="js-word" type="text" autocomplete="off" autocapitalize="off"
             spellcheck="false" placeholder="A word you remember">
      <button class="js-add">Add</button>
      <button class="js-score">Score the round</button>
    </div>
    <p class="tally js-tally" aria-live="polite"></p>
    <ol class="given js-given"></ol>
  </section>

  <section class="js-resultPanel hidden">
    <p class="score js-scoreLine"></p>
    <p class="verdict js-verdict"></p>
    <div class="bucket js-missedBox">
      <h3>Left on the tray</h3>
      <p class="missed js-missed"></p>
    </div>
    <div class="bucket js-extraBox">
      <h3>Words you added that were never there</h3>
      <p class="extra js-extra"></p>
    </div>
    <button class="primary js-again">Lay out a fresh tray</button>
  </section>

  <section class="ledger js-ledger hidden">
    <h2>Recent rounds</h2>
    <table>
      <thead><tr><th>When</th><th>Recalled</th><th>Tray</th><th>Study</th></tr></thead>
      <tbody class="js-ledgerBody"></tbody>
    </table>
    <p class="tally js-mean"></p>
  </section>

</div>
<script>
"#

def tailJs : String := r#"
(function () {
  "use strict";

  var q = function (c) { return document.querySelector("." + c); };
  var STORE = "tray.history.v1";

  var el = {
    title:   q("js-title"),
    sub:     q("js-subtitle"),
    count:   q("js-count"),
    secs:    q("js-secs"),
    bandBox: q("js-bandfield"),
    band:    q("js-band"),
    start:   q("js-start"),
    clock:   q("js-clock"),
    grid:    q("js-grid"),
    note:    q("js-trayNote"),
    recall:  q("js-recallPanel"),
    word:    q("js-word"),
    add:     q("js-add"),
    scoreBt: q("js-score"),
    tally:   q("js-tally"),
    given:   q("js-given"),
    result:  q("js-resultPanel"),
    line:    q("js-scoreLine"),
    verdict: q("js-verdict"),
    missBox: q("js-missedBox"),
    missed:  q("js-missed"),
    extBox:  q("js-extraBox"),
    extra:   q("js-extra"),
    again:   q("js-again"),
    ledger:  q("js-ledger"),
    rows:    q("js-ledgerBody"),
    mean:    q("js-mean")
  };

  el.title.textContent = PAGE.title;
  el.sub.textContent = PAGE.subtitle;
  el.count.value = CFG.count;
  el.secs.value = CFG.secs;

  // ---- helpers ---------------------------------------------------------

  // Matching is generous: case, accents and punctuation are ignored, so
  // "Fjord" and "fjord." both count. Plurals do not — that is the test.
  var key = function (s) {
    return s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]/g, "");
  };

  var sample = function (list, n) {
    var a = list.slice();
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a.slice(0, Math.min(n, a.length));
  };

  var show = function (node, on) { node.classList.toggle("hidden", !on); };

  // ---- band filter -----------------------------------------------------

  var bands = [];
  POOL.forEach(function (t) {
    if (t.b && bands.indexOf(t.b) === -1) { bands.push(t.b); }
  });
  bands.sort();
  if (bands.length > 1) {
    var opt = document.createElement("option");
    opt.value = ""; opt.textContent = "Any";
    el.band.appendChild(opt);
    bands.forEach(function (b) {
      var o = document.createElement("option");
      o.value = b; o.textContent = b;
      el.band.appendChild(o);
    });
    show(el.bandBox, true);
  }

  // ---- round state -----------------------------------------------------

  var target = [];   // tokens on the tray
  var given = [];    // what the player typed, in order
  var timer = null;
  var studySecs = CFG.secs;

  var render = function () {
    el.given.innerHTML = "";
    given.forEach(function (w) {
      var li = document.createElement("li");
      li.textContent = w;
      el.given.appendChild(li);
    });
    el.tally.textContent = given.length === 0
      ? "Nothing written down yet."
      : given.length + (given.length === 1 ? " word written down." : " words written down.");
  };

  var layOut = function () {
    var n = Math.max(3, Math.min(60, parseInt(el.count.value, 10) || CFG.count));
    studySecs = Math.max(5, Math.min(600, parseInt(el.secs.value, 10) || CFG.secs));
    var band = el.band.value;
    var pool = band ? POOL.filter(function (t) { return t.b === band; }) : POOL;

    if (pool.length === 0) {
      el.grid.innerHTML = "";
      el.note.textContent = "No words are loaded. Fill the token array in Tray.lean and regenerate the page.";
      show(el.note, true);
      return;
    }

    target = sample(pool, n);
    given = [];
    show(el.note, false);
    show(el.result, false);
    show(el.recall, false);

    el.grid.innerHTML = "";
    target.forEach(function (t) {
      var li = document.createElement("li");
      li.textContent = t.w;
      el.grid.appendChild(li);
    });

    el.start.disabled = true;
    show(el.clock, true);
    var started = Date.now();
    el.clock.style.transform = "scaleX(1)";
    timer = setInterval(function () {
      var left = 1 - (Date.now() - started) / (studySecs * 1000);
      if (left <= 0) { cover(); return; }
      el.clock.style.transform = "scaleX(" + left + ")";
    }, 80);
  };

  var cover = function () {
    clearInterval(timer);
    show(el.clock, false);
    el.grid.innerHTML = "";
    el.note.textContent = "Tray covered. Write down every word you can, in any order.";
    show(el.note, true);
    show(el.recall, true);
    el.start.disabled = false;
    render();
    el.word.focus();
  };

  var addWord = function () {
    var raw = el.word.value.trim();
    el.word.value = "";
    el.word.focus();
    if (!raw) { return; }
    var k = key(raw);
    if (!k) { return; }
    var dup = given.some(function (w) { return key(w) === k; });
    if (dup) { return; }
    given.push(raw);
    render();
  };

  var scoreRound = function () {
    show(el.recall, false);
    show(el.note, false);

    var wanted = target.map(function (t) { return t.w; });
    var wantedKeys = wanted.map(key);
    var givenKeys = given.map(key);

    var hits = wanted.filter(function (w, i) { return givenKeys.indexOf(wantedKeys[i]) !== -1; });
    var missed = wanted.filter(function (w, i) { return givenKeys.indexOf(wantedKeys[i]) === -1; });
    var extra = given.filter(function (w) { return wantedKeys.indexOf(key(w)) === -1; });

    el.line.innerHTML = hits.length + " <em>of " + wanted.length + "</em>";
    var pct = Math.round((hits.length / wanted.length) * 100);
    el.verdict.textContent = pct + " percent, with " + studySecs + " seconds of study.";

    el.missed.textContent = missed.join(", ");
    show(el.missBox, missed.length > 0);
    el.extra.textContent = extra.join(", ");
    show(el.extBox, extra.length > 0);

    show(el.result, true);
    record(hits.length, wanted.length, studySecs);
  };

  // ---- ledger ----------------------------------------------------------

  var load = function () {
    try { return JSON.parse(localStorage.getItem(STORE)) || []; }
    catch (e) { return []; }
  };

  var record = function (hit, n, secs) {
    var log = load();
    log.push({ t: Date.now(), hit: hit, n: n, secs: secs });
    try { localStorage.setItem(STORE, JSON.stringify(log.slice(-200))); } catch (e) {}
    drawLedger();
  };

  var drawLedger = function () {
    var log = load();
    if (log.length === 0) { show(el.ledger, false); return; }
    var recent = log.slice(-10).reverse();
    el.rows.innerHTML = "";
    recent.forEach(function (r) {
      var tr = document.createElement("tr");
      var d = new Date(r.t);
      [d.toLocaleString(), r.hit, r.n, r.secs + "s"].forEach(function (v) {
        var td = document.createElement("td");
        td.textContent = v;
        tr.appendChild(td);
      });
      el.rows.appendChild(tr);
    });
    var rate = log.reduce(function (a, r) { return a + r.hit / r.n; }, 0) / log.length;
    el.mean.textContent = "Mean recall over " + log.length +
      (log.length === 1 ? " round: " : " rounds: ") + Math.round(rate * 100) + " percent.";
    show(el.ledger, true);
  };

  // ---- wiring ----------------------------------------------------------

  el.start.addEventListener("click", layOut);
  el.again.addEventListener("click", layOut);
  el.add.addEventListener("click", addWord);
  el.scoreBt.addEventListener("click", scoreRound);
  el.word.addEventListener("keydown", function (e) {
    if (e.key === "Enter") { e.preventDefault(); addWord(); }
  });

  if (POOL.length === 0) {
    el.note.textContent = "No words are loaded. Fill the token array in Tray.lean and regenerate the page.";
    el.start.disabled = true;
  }
  drawLedger();
})();
</script>
</body>
</html>
"#

def render (cfg : Config) (ts : Array Token) : String :=
  headA ++ htmlEscape cfg.title ++ headB
    ++ "const PAGE = {\"title\":\"" ++ jsEscape cfg.title
    ++ "\",\"subtitle\":\"" ++ jsEscape cfg.subtitle ++ "\"};\n"
    ++ "const CFG = " ++ cfg.toJson ++ ";\n"
    ++ "const POOL = " ++ poolToJson ts ++ ";\n"
    ++ tailJs

def config : Config := {}

end MemTrain.Tray
