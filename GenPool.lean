import MemTrain.Tray

/-!
  GenPool.lean — converts `data/kilgarriff-noun-lemmata.txt` into the
  generated array inside `MemTrain/Pool.lean`.

  The source file is `rank freq word class`, space-separated, one noun
  lemma per line, already sorted alphabetically by word. This program
  keeps that order for the output (stable, easy to diff across
  regenerations) but computes each word's difficulty `band` from its
  frequency rank among the whole list: the most frequent third of the
  pool is "common", the middle third "mid", the rest "rare".

  It only ever rewrites the text between the `GENERATED:BEGIN` /
  `GENERATED:END` markers in Pool.lean; everything else in that file is
  left untouched.

  Run:   lake exe genpool
-/

open MemTrain.Tray

def dataFile : System.FilePath := "data/kilgarriff-noun-lemmata.txt"
def poolFile : System.FilePath := "MemTrain/Pool.lean"

def beginMarker : String := "-- GENERATED:BEGIN"
def endMarker : String := "-- GENERATED:END"

structure Row where
  freq : Nat
  word : String
  deriving Inhabited

/-- Parse one `rank freq word class` line. The rank and class columns are
    read but not kept: rank is recomputed from `freq` below, and class is
    always "n" in this file. -/
def parseLine (line : String) : Option Row :=
  match line.splitOn " " with
  | [_rank, freqS, word, _class] => freqS.toNat?.map fun freq => { freq, word }
  | _ => none

def bandFor (rankFromTop total : Nat) : String :=
  if rankFromTop < total / 3 then "common"
  else if rankFromTop < 2 * total / 3 then "mid"
  else "rare"

/-- Words in this file are plain lowercase letters and hyphens, but escape
    defensively anyway rather than assume that stays true forever. -/
def escapeWord (s : String) : String :=
  s.foldl (fun acc c => acc ++ (if c == '"' || c == '\\' then "\\" else "") ++ c.toString) ""

def tokenLine (r : Row) (band : String) : String :=
  "  { word := \"" ++ escapeWord r.word ++ "\", freq := " ++ toString r.freq ++
    ", band := \"" ++ band ++ "\" },"

/-- Elaborating a `#[...]` literal recurses roughly once per element, and a
    pool this size overruns Lean's default recursion limit as one literal
    (raising `maxRecDepth` just trades that clean error for a real native
    stack overflow further down). Instead, split into chunks small enough
    to elaborate safely and concatenate them at runtime with `++`. -/
def chunkSize : Nat := 200

def renderTokens (rows : Array Row) (bands : Array String) : String :=
  let n := rows.size
  let lines := (rows.zip bands).map (fun (r, b) => tokenLine r b)
  let chunkCount := (n + chunkSize - 1) / chunkSize
  let idxs := List.range chunkCount
  let defs := idxs.map fun i =>
    let lo := i * chunkSize
    let hi := min n (lo + chunkSize)
    s!"private def tokens{i} : Array Token := #[\n" ++
      String.intercalate "\n" (lines.extract lo hi).toList ++ "\n]\n"
  let names := idxs.map fun i => s!"tokens{i}"
  String.intercalate "\n" defs ++
    "\ndef tokens : Array Token := " ++ String.intercalate " ++ " names ++ "\n"

/-- Replace the text between the markers in `skeleton` with `generated`,
    keeping everything outside the markers as-is. -/
def splice (skeleton generated : String) : Except String String :=
  match skeleton.splitOn beginMarker with
  | [before, rest] =>
    match rest.splitOn endMarker with
    | [_old, after] => .ok (before ++ beginMarker ++ "\n" ++ generated ++ endMarker ++ after)
    | _ => .error s!"expected exactly one {endMarker} marker in {poolFile}"
  | _ => .error s!"expected exactly one {beginMarker} marker in {poolFile}"

def main : IO Unit := do
  let raw ← IO.FS.readFile dataFile
  let rows := raw.splitOn "\n" |>.filterMap parseLine |>.toArray

  if rows.isEmpty then
    throw (IO.userError s!"No rows parsed from {dataFile}")

  let n := rows.size
  let byFreqDesc := (Array.range n).qsort (fun i j => rows[i]!.freq > rows[j]!.freq)

  let mut bands := Array.replicate n ""
  for pos in [0:n] do
    bands := bands.set! byFreqDesc[pos]! (bandFor pos n)

  let skeleton ← IO.FS.readFile poolFile
  match splice skeleton (renderTokens rows bands) with
  | .error e => throw (IO.userError e)
  | .ok updated => IO.FS.writeFile poolFile updated

  IO.println s!"Wrote {n} tokens into {poolFile}"
