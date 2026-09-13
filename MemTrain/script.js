(function () {
  "use strict";

  var q = function (c) { return document.querySelector("." + c); };
  var STORE = "tray.history.v1";

  var el = {
    title:   q("js-title"),
    sub:     q("js-subtitle"),
    date:    q("js-date"),
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

  // Default the date field to today (local time, not UTC — building the
  // string by hand avoids the off-by-one-day trap of toISOString() near
  // midnight in timezones behind UTC).
  (function () {
    var pad2 = function (n) { return (n < 10 ? "0" : "") + n; };
    var today = new Date();
    el.date.value = today.getFullYear() + "-" + pad2(today.getMonth() + 1) + "-" + pad2(today.getDate());
  })();

  // ---- helpers ---------------------------------------------------------

  // Matching is generous: case, accents and punctuation are ignored, so
  // "Fjord" and "fjord." both count. Plurals do not — that is the test.
  var key = function (s) {
    return s.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]/g, "");
  };

  // Turn "2026-09-13" into 20260913, so the same date always gives the
  // same tray — that's how family members share a tray without agreeing
  // on anything more than "today's date" (or any other date they pick).
  var dateSeed = function (dateStr) {
    return parseInt(dateStr.replace(/-/g, ""), 10) || 0;
  };

  // Math.random() can't be seeded, so sampling needs its own small PRNG
  // (mulberry32) whenever the tray has to be reproducible from a seed.
  var mulberry32 = function (seed) {
    return function () {
      seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
      var t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  };

  var sample = function (list, n, rng) {
    var a = list.slice();
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(rng() * (i + 1));
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

    var rng = mulberry32(dateSeed(el.date.value));
    target = sample(pool, n, rng);
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

  // These are all single words, never compounds with an internal space, so
  // splitting on space or comma lets someone type several at once without
  // the whole line being scored as one (wrong) guess.
  var addWord = function () {
    var raw = el.word.value;
    el.word.value = "";
    el.word.focus();

    raw.split(/[\s,]+/).forEach(function (w) {
      w = w.trim();
      if (!w) { return; }
      var k = key(w);
      if (!k) { return; }
      var dup = given.some(function (g) { return key(g) === k; });
      if (dup) { return; }
      given.push(w);
    });

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
