import MemTrain.Tray
import MemTrain.Pool

def main : IO Unit := do
  let cfg := MemTrain.Tray.config
  let css ← IO.FS.readFile cfg.styleFile
  let js ← IO.FS.readFile cfg.scriptFile
  let html := MemTrain.Tray.render cfg MemTrain.Pool.tokens css js
  IO.FS.writeFile cfg.outFile html
  IO.println s!"Wrote {cfg.outFile}"
