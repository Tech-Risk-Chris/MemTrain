import MemTrain.Tray
import MemTrain.Pool

def main : IO Unit := do
  let html := MemTrain.Tray.render MemTrain.Tray.config MemTrain.Pool.tokens
  IO.FS.writeFile MemTrain.Tray.config.outFile html
  IO.println s!"Wrote {MemTrain.Tray.config.outFile}"
