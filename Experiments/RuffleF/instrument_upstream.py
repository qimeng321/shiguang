#!/usr/bin/env python3
"""F experiment: read-only Rust probes for pinned upstream Ruffle nightly-2026-11-13.
Run from the pinned upstream checkout root. Fail closed on any source mismatch.
No GC policy, SWF semantics, game logic or rendering behavior is changed.
"""
from pathlib import Path

def rewrite(path, old, new, expected=1):
    f = Path(path)
    source = f.read_text(encoding="utf-8")
    observed = source.count(old)
    if observed != expected:
        raise SystemExit(f"F patch failed for {path}: expected {expected}, found {observed}")
    f.write_text(source.replace(old, new), encoding="utf-8")
    print(f"F patched {path} ({observed} anchors)")

rewrite("core/src/loader.rs",
    "    /// Add a new loader to the `LoadManager`.",
    """    /// F diagnostic: count in-flight movie loaders (not all SWF objects).
    /// Read-only; the method does not modify loader state.
    pub fn f_diagnostic_in_flight_count(&self) -> usize {
        self.0.len()
    }

    /// Add a new loader to the `LoadManager`.""")

rewrite("core/src/player.rs",
    "            LocalConnections::update_connections(context);\n",
    """            LocalConnections::update_connections(context);

            // F diagnostic: collect actual Rust-side movie-library registry metrics.
            // One sample per 90 game frames. Does not force GC, unload or prune.
            #[cfg(target_arch = "wasm32")]
            {
                use std::sync::atomic::{AtomicU64, Ordering};
                static F_FRAME_COUNTER: AtomicU64 = AtomicU64::new(0);
                let frame = F_FRAME_COUNTER.fetch_add(1, Ordering::Relaxed) + 1;
                if frame % 90 == 0 {
                    let known_movies = context.library.known_movies().count();
                    let registered_characters: usize = context.library.known_movies()
                        .map(|movie| {
                            context.library.library_for_movie(movie)
                                .map_or(0, |lib| lib.characters().len())
                        }).sum();
                    let in_flight = context.load_manager.f_diagnostic_in_flight_count();
                    tracing::warn!(
                        "[F-Rust] frame={} movie_libraries={} registered_characters={} in_flight_loaders={} (library registry entries, not live GC objects)",
                        frame, known_movies, registered_characters, in_flight
                    );
                }
            }
""")

# Native WebGL backend: count Rust BitmapHandle ownership and Drop calls.
# Note: wgpu-webgl may be used instead; a missing counter does not prove zero textures.
path = Path("render/webgl/src/lib.rs")
raw = path.read_text(encoding="utf-8")
anchor = "#[derive(Debug)]\nstruct RegistryData {"
assert raw.count(anchor) == 1
replacement = """// F diagnostic for the legacy native WebGL backend only. If wgpu-webgl is
// selected, use the existing D JavaScript WebGL counters instead.
#[cfg(target_arch = "wasm32")]
static F_BITMAP_HANDLES_CREATED: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(0);
#[cfg(target_arch = "wasm32")]
static F_BITMAP_HANDLES_DROPPED: std::sync::atomic::AtomicU64 =
    std::sync::atomic::AtomicU64::new(0);

#[derive(Debug)]
struct RegistryData {"""
raw = raw.replace(anchor, replacement)
anchor = "        self.gl.delete_texture(Some(&self.texture));\n"
assert raw.count(anchor) == 1
raw = raw.replace(anchor, """        self.gl.delete_texture(Some(&self.texture));
        #[cfg(target_arch = "wasm32")]
        {
            use std::sync::atomic::Ordering;
            let dropped = F_BITMAP_HANDLES_DROPPED.fetch_add(1, Ordering::Relaxed) + 1;
            if dropped % 128 == 0 {
                log::warn!(
                    "[F-Rust] native_webgl_bitmap_dropped={} created={} (no VRAM measurement)",
                    dropped, F_BITMAP_HANDLES_CREATED.load(Ordering::Relaxed)
                );
            }
        }
""")
anchor = "        Ok(BitmapHandle(Arc::new(RegistryData {"
assert raw.count(anchor) == 2
raw = raw.replace(anchor, """        #[cfg(target_arch = "wasm32")]
        {
            use std::sync::atomic::Ordering;
            let created = F_BITMAP_HANDLES_CREATED.fetch_add(1, Ordering::Relaxed) + 1;
            if created % 128 == 0 {
                log::warn!(
                    "[F-Rust] native_webgl_bitmap_created={} dropped={} (no VRAM measurement)",
                    created, F_BITMAP_HANDLES_DROPPED.load(Ordering::Relaxed)
                );
            }
        }
        Ok(BitmapHandle(Arc::new(RegistryData {""")
path.write_text(raw, encoding="utf-8")
print("F patched render/webgl/src/lib.rs (2 constructors, 1 Drop)")

assert "[F-Rust] frame=" in Path("core/src/player.rs").read_text()
assert "[F-Rust] native_webgl_bitmap_" in path.read_text()
print("F PATCH OK - data collection only, no behavior changes")
