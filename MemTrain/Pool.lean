import MemTrain.Tray

/-!
  Pool.lean — the word pool for the tray.

  This is generated data, not logic: nothing in here should need editing by
  hand once the BNC frequency list is wired up. Bands are free-form strings;
  whatever distinct values appear here become the difficulty selector on the
  page, and an empty pool renders a page that says so.
-/

namespace MemTrain.Pool

open MemTrain.Tray

def tokens : Array Token := #[
  { word := "anvil",    freq := 12,  band := "rare" },
  { word := "harbour",  freq := 210, band := "mid" },
  { word := "thimble",  freq := 9,   band := "rare" },
  { word := "kettle",   freq := 84,  band := "mid" },
  { word := "ladder",   freq := 150, band := "mid" }
]

end MemTrain.Pool
