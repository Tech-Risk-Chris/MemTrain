/-
  Tray.lean — a static site generator for a lexical Kim's Game.

  Emits a single self-contained `index.html`: no build step for the reader,
  nothing to serve but bytes. Drop it in an S3 bucket and open it.

  Generation itself reads `style.css` and `script.js` from disk and splices
  them into the page, so the CSS/JS source gets real editor tooling; the
  *output* file is still one flat page with everything inlined.

  Run:   lake exe memtrain

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
  styleFile : System.FilePath := "MemTrain/style.css"
  scriptFile : System.FilePath := "MemTrain/script.js"
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

The HTML is split into raw chunks with the generated data — and the CSS/JS
read from disk by `render` — spliced between them. Nothing here uses `#`,
so `r#"..."#` stays well-formed. -/

def headA : String := r#"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>"#

/-- Everything up to the opening `<style>` tag; `render` splices the
    contents of `style.css` right after this. -/
def headB1 : String := r#"</title>
<style>
"#

/-- Everything from the closing `</style>` tag through the opening
    `<script>` tag. -/
def headB2 : String := r#"</style>
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

/-- Everything after the JS content: closing `</script>` through
    `</html>`. -/
def tailB : String := r#"
</script>
</body>
</html>
"#

/-- Splice the given CSS and JS (read by the caller from `cfg.styleFile`
    and `cfg.scriptFile`) into the page alongside the generated data.
    Kept pure — the filesystem reads happen at the call site — so the
    resulting HTML is still one flat, self-contained file. -/
def render (cfg : Config) (ts : Array Token) (css js : String) : String :=
  headA ++ htmlEscape cfg.title ++ headB1 ++ css ++ headB2
    ++ "const PAGE = {\"title\":\"" ++ jsEscape cfg.title
    ++ "\",\"subtitle\":\"" ++ jsEscape cfg.subtitle ++ "\"};\n"
    ++ "const CFG = " ++ cfg.toJson ++ ";\n"
    ++ "const POOL = " ++ poolToJson ts ++ ";\n"
    ++ js ++ tailB

def config : Config := {}

end MemTrain.Tray
