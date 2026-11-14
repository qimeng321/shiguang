#!/usr/bin/env python3
"""B145 lightweight, truthful memory telemetry for exact official Nightly.

Apply AFTER B143 GPU release patch. Does NOT pretend live MovieLibrary data
can be freed by simply clearing GPU handles. Does NOT alter core display logic,
renderer, DPR, frame rate, game resources, network protocol or login.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1]) if len(sys.argv)==2 else Path(".")
p=root/"core/src/library.rs"
s=p.read_text(encoding="utf-8")
def replace(old,new):
    global s
    count=s.count(old)
    if count!=1:
        sys.exit(f"B145 telemetry mismatch {count}: {old[:120]!r}")
    s=s.replace(old,new,1)

replace("use std::collections::HashMap;","use std::cell::Cell;\nuse std::collections::HashMap;")
replace(
    """pub struct MovieLibrary<'gc> {
    swf: SwfMovie<'gc>,
    characters:""",
    """pub struct MovieLibrary<'gc> {
    swf: SwfMovie<'gc>,
    // Counts release calls, not bytes actually freed. The latter are
    // managed by WebKit and cannot be read through this structure.
    #[collect(require_static)]
    b145_gpu_release_calls: Cell<u32>,
    characters:"""
)
replace(
    """        Self {
            swf,
            characters: HashMap::new(),""",
    """        Self {
            swf,
            b145_gpu_release_calls: Cell::new(0),
            characters: HashMap::new(),"""
)
replace(
    """    pub fn release_gpu_cache(&self) {
        for character in self.characters.values() {""",
    """    pub fn release_gpu_cache(&self) {
        self.b145_gpu_release_calls
            .set(self.b145_gpu_release_calls.get().saturating_add(1));
        for character in self.characters.values() {"""
)
replace(
    """    fn get_or_insert_mut(&mut self, movie: SwfMovie<'gc>) -> &mut MovieLibrary<'gc> {
        self.0
            .entry(movie)
            .or_insert_with(|| MovieLibrary::new(movie))
    }""",
    """    fn get_or_insert_mut(&mut self, movie: SwfMovie<'gc>) -> &mut MovieLibrary<'gc> {
        let is_new = !self.0.contains_key(&movie);
        if is_new && self.0.len() > 0 && self.0.len() % 8 == 0 {
            // Unlike launcher RSS, this measures Ruffle's linear WASM
            // memory, which the browser cannot reliably reduce on GC.
            let release_calls: u64 = self.0.values()
                .map(|lib| u64::from(lib.b145_gpu_release_calls.get()))
                .sum();
            #[cfg(target_arch = "wasm32")]
            {
                let pages = core::arch::wasm32::memory_size::<0>();
                tracing::warn!(
                    "[B145-MEM] registered_movie_libraries={} gpu_release_calls={} wasm_pages={} wasm_mib={}",
                    self.0.len(), release_calls, pages, (pages as u64) / 16,
                );
            }
            #[cfg(not(target_arch = "wasm32"))]
            tracing::warn!(
                "[B145-MEM] registered_movie_libraries={} gpu_release_calls={}",
                self.0.len(), release_calls
            );
        }
        self.0
            .entry(movie)
            .or_insert_with(|| MovieLibrary::new(movie))
    }"""
)
p.write_text(s,encoding="utf-8")
print("[B145] movie-library allocation stats, GPU release invocation count and real WASM memory pages installed")
