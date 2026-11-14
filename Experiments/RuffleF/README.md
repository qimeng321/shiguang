# Shiguang F: Ruffle Rust lifecycle diagnostics

**Status:** source-level diagnostic experiment, NOT a stability fix. Do not merge into the 1.09 release branch.

- Baseline launcher: test D (2026-11-13 Ruffle, DPR 1.5, 30 FPS, battle HTTP cache ON).
- Upstream Ruffle source **pinned to commit** `65d984777f5acc28e18fe6c3e89d28266fc1fb75`, tag `nightly-2026-11-13`.
- Patch script: `Experiments/RuffleF/instrument_upstream.py`.
- CI: `.github/workflows/ruffle-rust-lifecycle-f.yml` compiles a **custom Rust/WebAssembly** Ruffle web selfhosted bundle on Linux and publishes the bundle as an Actions artifact.
- Original Shiguang production branch and IPA are unchanged.

## What F measures

1. A Rust-side sample every 90 processed frames: `movie_libraries` (`Library::known_movies().count()`), `registered_characters` (sum of each movie library's registered character count) and `in_flight_loaders` (`LoadManager` entries). These indicate registry retention but **not** live AVM2 GC objects or in-use heap bytes.
2. Native `render/webgl` Rust BitmapHandle creations and Drop calls, logged every 128 calls. Note: many devices may run Ruffle `wgpu-webgl` instead. If so, absence of native WebGL backend messages does **not** indicate a lack of textures.
3. Existing D page-level WASM linear memory size, JS-visible WebGL counters and native HTTP battle trace must remain in the host IPA.

Logs use `[F-Rust]`. This build never invokes forced GC or unload and does not alter ActionScript semantics. The custom engine **must be smoke-tested** with resource revision 2026111401 before considering its numbers comparable with test D.

## Expected test

First verify same WebGL renderer selection, correct player load, login, map entry and fight animation. Then compare `movie_libraries`, `registered_characters`, `in_flight_loaders` across consecutive battle transitions, together with D's WASM memory growth. A steadily increasing library registry with in-flight loaders returning to zero is evidence to investigate persistent movie-library references, **not** proof of an independent leak. Use repeat runs and do not assume resource-wave counters equal battle counts.

Upstream investigation: https://github.com/ruffle-rs/ruffle/discussions/24870
Related unmerged source work: https://github.com/ruffle-rs/ruffle/pull/23071 and https://github.com/ruffle-rs/ruffle/pull/22908

Safety: unsigned IPA requires local signing; all variants use the same localhost proxy ports, so close other variants before running. Do not use the experimental engine for regular play until tested.
