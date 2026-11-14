#!/usr/bin/env python3
"""B144: bound retained GPU caches for repeat-loaded Flash SWFs on official Nightly.

Apply only after Patches/ruffle-official109-gpu-reclaim.py to the pinned
ruffle-rs/ruffle commit 65d984777f5acc28e18fe6c3e89d28266fc1fb75.

Rationale: B143 releases GPU handles on LoaderInfo.unload, but Flash apps
also create/reload movies without reliably invoking LoaderInfo.unload.
Their MovieLibraries dictionary is strongly retained. Under repeat fights,
some never trigger unload cleanup. Here a small, amortized LRU pass releases
GPU-only cached shape/bitmap handles of least recently accessed libraries.

All SWF bytes, ActionScript objects, symbol definitions and movie libraries
remain intact. A still-active scene can recreate a released GPU handle when
drawn again. No SWF/event/network/renderer/DPR/quality changes.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv)==2 else Path(".")
path = root / "core/src/library.rs"
s = path.read_text(encoding="utf-8")

def change(before, after):
    global s
    count = s.count(before)
    if count != 1:
        sys.exit(f"B144 patch failed; count={count}, anchor={before[:110]!r}")
    s = s.replace(before, after, 1)

change(
    "use std::collections::HashMap;",
    "use std::cell::Cell;\nuse std::collections::HashMap;"
)
change(
    """    swf: SwfMovie<'gc>,
    characters: HashMap<CharacterId, Character<'gc>>,""",
    """    swf: SwfMovie<'gc>,
    // Bookkeeping only: not part of SWF semantics or renderer quality.
    #[collect(require_static)]
    b144_last_gpu_use: Cell<u64>,
    #[collect(require_static)]
    b144_last_gpu_release: Cell<u64>,
    characters: HashMap<CharacterId, Character<'gc>>,"""
)
change(
    """            swf,
            characters: HashMap::new(),""",
    """            swf,
            b144_last_gpu_use: Cell::new(1),
            b144_last_gpu_release: Cell::new(0),
            characters: HashMap::new(),"""
)
change(
    """struct MovieLibraries<'gc>(HashMap<SwfMovie<'gc>, MovieLibrary<'gc>>);

impl<'gc> MovieLibraries<'gc> {
    fn new() -> Self {
        Self(HashMap::new())
    }

    fn get(&self, key: SwfMovie<'gc>) -> Option<&MovieLibrary<'gc>> {
        self.0.get(&key)
    }

    fn get_or_insert_mut(&mut self, movie: SwfMovie<'gc>) -> &mut MovieLibrary<'gc> {
        self.0
            .entry(movie)
            .or_insert_with(|| MovieLibrary::new(movie))
    }

    fn known_movies(&self) -> impl Iterator<Item = SwfMovie<'gc>> {
        self.0.keys().copied()
    }
}""",
    """struct MovieLibraries<'gc>(
    HashMap<SwfMovie<'gc>, MovieLibrary<'gc>>,
    #[collect(require_static)] Cell<u64>,
    #[collect(require_static)] Cell<u64>,
);

impl<'gc> MovieLibraries<'gc> {
    fn new() -> Self {
        Self(HashMap::new(), Cell::new(1), Cell::new(0))
    }

    fn next_gpu_access(&self) -> u64 {
        let now = self.1.get().saturating_add(1);
        self.1.set(now);
        now
    }

    fn get(&self, key: SwfMovie<'gc>) -> Option<&MovieLibrary<'gc>> {
        let library = self.0.get(&key);
        if let Some(library) = library {
            library.b144_last_gpu_use.set(self.next_gpu_access());
        }
        library
    }

    fn get_or_insert_mut(&mut self, movie: SwfMovie<'gc>) -> &mut MovieLibrary<'gc> {
        // This path also runs for duplicate Loader loads of the same SWF.
        // Never remove a library or any ActionScript object: that would
        // break live display objects holding the same movie.
        let is_new_movie = !self.0.contains_key(&movie);
        let now = self.next_gpu_access();
        if is_new_movie {
            let created = self.2.get().saturating_add(1);
            self.2.set(created);
            // Amortize scans and keep the newest 48 accessed movie caches.
            // All releases are non-destructive: only optional GPU handles.
            if created % 8 == 0 && self.0.len() > 48 {
                let mut eligible: Vec<_> = self.0.iter()
                    .filter_map(|(key, lib)| {
                        let last_use = lib.b144_last_gpu_use.get();
                        let last_release = lib.b144_last_gpu_release.get();
                        (last_use > last_release).then_some((last_use, *key))
                    })
                    .collect();
                eligible.sort_unstable_by_key(|(last_use, _)| *last_use);
                let to_release = eligible.len().saturating_sub(48).min(12);
                for (_, old_movie) in eligible.into_iter().take(to_release) {
                    if let Some(library) = self.0.get(&old_movie) {
                        library.release_gpu_cache();
                        library.b144_last_gpu_release
                            .set(library.b144_last_gpu_use.get());
                    }
                }
            }
        }
        let library = self.0.entry(movie)
            .or_insert_with(|| MovieLibrary::new(movie));
        library.b144_last_gpu_use.set(now);
        library
    }

    fn known_movies(&self) -> impl Iterator<Item = SwfMovie<'gc>> {
        self.0.keys().copied()
    }
}"""
)
path.write_text(s, encoding="utf-8")
assert "b144_last_gpu_release" in path.read_text()
assert "library.release_gpu_cache();" in path.read_text()
print("[B144] PASS: incremental LRU GPU cache reclamation installed in official 1.09")
