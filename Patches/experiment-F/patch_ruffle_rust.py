#!/usr/bin/env python3
"""F diagnostic-only patch for upstream Ruffle nightly-2026-11-13.
Tag: 65d984777f5acc28e18fe6c3e89d28266fc1fb75.
No GC behaviour, SWF loading, rendering or unloading logic is altered.
"""
from pathlib import Path

def one(path, old, new):
    p=Path(path)
    value=p.read_text(encoding="utf-8")
    assert value.count(old)==1, f"{path}: expected exactly one anchor, got {value.count(old)}"
    p.write_text(value.replace(old,new,1),encoding="utf-8")

one("core/src/library.rs",
    """    pub fn known_movies(&self) -> impl Iterator<Item = SwfMovie<'gc>> {
        self.movie_libraries.known_movies()
    }
""",
    """    pub fn known_movies(&self) -> impl Iterator<Item = SwfMovie<'gc>> {
        self.movie_libraries.known_movies()
    }

    // Shiguang F: read-only diagnostic of the strongly held SWF movie registry.
    // These are stored definitions, not currently visible display objects.
    pub fn shiguang_diag_movie_counts(&self) -> (usize, usize) {
        let movies = self.movie_libraries.0.len();
        let characters: usize = self.movie_libraries.0.values()
            .map(|library| library.characters().len())
            .sum();
        (movies, characters)
    }
""")
one("core/src/loader.rs",
    """    pub fn new() -> Self {
        Self(SlotMap::with_key())
    }
""",
    """    pub fn new() -> Self {
        Self(SlotMap::with_key())
    }

    // Shiguang F: in-flight loaders only, not all completed movie definitions.
    pub fn shiguang_diag_active_loaders(&self) -> usize {
        self.0.len()
    }
""")
one("core/src/player.rs",
    """            for cb in std::mem::take(context.post_frame_callbacks) {
                (cb.callback)(context, cb.data);
            }
        });

        self.needs_render = true;
""",
    """            for cb in std::mem::take(context.post_frame_callbacks) {
                (cb.callback)(context, cb.data);
            }

            // Shiguang F: observational counters at first frame then every
            // 150 frames. No forced GC, no resource release, no runtime hook.
            #[cfg(target_arch = "wasm32")]
            {
                use std::sync::atomic::{AtomicU64, Ordering};
                static FRAME_COUNTER: AtomicU64 = AtomicU64::new(0);
                let frame = FRAME_COUNTER.fetch_add(1, Ordering::Relaxed) + 1;
                if frame == 1 || frame % 150 == 0 {
                    let (movies, characters) = context.library.shiguang_diag_movie_counts();
                    let active = context.load_manager.shiguang_diag_active_loaders();
                    tracing::warn!(
                        target: "shiguang_f_rust",
                        "[F-RUST] frames={} known_movies={} characters={} active_loaders={}",
                        frame, movies, characters, active
                    );
                }
            }
        });

        self.needs_render = true;
""")

for path, marker in [
    ("core/src/library.rs","shiguang_diag_movie_counts"),
    ("core/src/loader.rs","shiguang_diag_active_loaders"),
    ("core/src/player.rs","[F-RUST] frames="),
]:
    assert marker in Path(path).read_text(encoding="utf-8")
print("PASS: Rust F read-only library/loader/frame counters installed")
