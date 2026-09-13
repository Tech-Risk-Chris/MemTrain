import MemTrain.Tray

def main : IO Unit := do
  let html := MemTrain.Tray.render MemTrain.Tray.config MemTrain.Tray.tokens
  IO.FS.writeFile MemTrain.Tray.config.outFile html
  IO.println s!"Wrote {MemTrain.Tray.config.outFile}"
