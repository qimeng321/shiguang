#!/usr/bin/env python3
"""Port narrow GPU cache lifetime fix to exact OFFICIAL Ruffle Nightly 2026-11-13 source.

Pinned upstream commit: 65d984777f5acc28e18fe6c3e89d28266fc1fb75
Keeps shader/rendering/quality/backend logic untouched. There is intentionally no
large-scale PR22908 source replacement. Fail fast if upstream layout differs.
"""
import sys
from pathlib import Path

root=Path(sys.argv[1]) if len(sys.argv)==2 else Path(".")
def patch(path,replacements):
    f=root/path
    s=f.read_text(encoding="utf-8")
    for before,after in replacements:
        # A JS-authored source string may retain a slash before a literal Rust backtick.
        before=before.replace(chr(92)+chr(96), chr(96))
        count=s.count(before)
        if count!=1:
            sys.exit(f"[B143] Source mismatch {path}: occurrence={count}, anchor={before[:100]!r}")
        s=s.replace(before,after,1)
    f.write_text(s,encoding="utf-8")
    print(f"[B143] patched {path}")

patch("core/src/character.rs",[
    ("use std::cell::OnceCell;","use std::cell::RefCell;"),
    ("handle: OnceCell<BitmapHandle>,","handle: RefCell<Option<BitmapHandle>>,"),
    ("handle: OnceCell::default(),","handle: RefCell::new(None),"),
    ("""        // FIXME - use \`OnceCell::get_or_try_init\` when stabilized.
        if let Some(handle) = self.handle.get() {
            return Ok(handle.clone());
        }
        let decoded = self.compressed.decode()?;
        let new_handle = backend.register_bitmap(decoded)?;
        // FIXME - do we ever want to release this handle, to avoid taking up GPU memory?
        self.handle.set(new_handle.clone()).unwrap();
        Ok(new_handle)
""".replace("\\\`","\`"),"""        if let Some(handle) = self.handle.borrow().as_ref() {
            return Ok(handle.clone());
        }
        let decoded = self.compressed.decode()?;
        let new_handle = backend.register_bitmap(decoded)?;
        *self.handle.borrow_mut() = Some(new_handle.clone());
        Ok(new_handle)
"""),
    ("    pub fn compressed(&self) -> &CompressedBitmap {", """    /// Release cached GPU texture when its SWF Loader unloads.
    /// Compressed bitmap data is retained; texture is recreated on next use.
    pub(crate) fn release_gpu_cache(&self) {
        self.handle.borrow_mut().take();
    }

    pub fn compressed(&self) -> &CompressedBitmap {"""),
])

patch("core/src/display_object/graphic.rs",[
    ("    pub fn set_avm2_class(self, mc: &Mutation<'gc>, class: Avm2ClassObject<'gc>) {",
     """    /// Original Nightly already tessellates lazily. Clear its bounded
    /// shape GPU handles when the associated SWF is unloaded.
    pub(crate) fn release_gpu_cache(self) {
        *self.0.shared.get().scaled_handle.borrow_mut() = TessellationCache::new();
    }

    pub fn set_avm2_class(self, mc: &Mutation<'gc>, class: Avm2ClassObject<'gc>) {"""),
])

patch("core/src/display_object/morph_shape.rs",[
    ("impl<'gc> MorphShape<'gc> {\n",
     """impl<'gc> MorphShape<'gc> {
    /// Release tessellated shape handles; preserve interpolation definitions.
    pub(crate) fn release_gpu_cache(self) {
        let shared = self.0.shared.get();
        for frame in shared.frames.borrow_mut().values_mut() {
            frame.shape_handle.take();
        }
    }

"""),
])

patch("core/src/library.rs",[
    ("    pub fn register_character(&mut self, id: CharacterId, character: Character<'gc>) -> bool {",
     """    /// Release GPU caches for SWF assets when LoaderInfo unloads.
    /// Do not delete symbol tables, classes or ActionScript objects.
    pub fn release_gpu_cache(&self) {
        for character in self.characters.values() {
            match character {
                Character::Bitmap(bitmap) => bitmap.release_gpu_cache(),
                Character::Graphic(graphic) => graphic.release_gpu_cache(),
                Character::MorphShape(morph) => morph.release_gpu_cache(),
                _ => {}
            }
        }
    }

    pub fn register_character(&mut self, id: CharacterId, character: Character<'gc>) -> bool {"""),
])

patch("core/src/avm2/object/loaderinfo_object.rs",[
    ("        // Reset properties\n        let movie = &context.root_swf;",
     """        // Free GPU caches for the movie that this Loader just unloaded,
        // after dispatching its unload event, before replacing LoaderInfo.
        // Root SWF cache remains untouched. Other live display objects can
        // regenerate their textures/shape handles on next render if needed.
        let unloaded_movie = match &*self.0.loaded_stream.borrow() {
            LoaderStream::Swf(movie, _) => Some(*movie),
            _ => None,
        };
        if let Some(movie) = unloaded_movie {
            if !SwfMovie::ptr_eq(&movie, context.root_swf) {
                if let Some(lib) = context.library.library_for_movie(movie) {
                    lib.release_gpu_cache();
                }
            }
        }

        // Reset properties
        let movie = &context.root_swf;"""),
])
print("[B143] Official Nightly GPU cache reclaim patch applied; renderer, DPR and quality untouched.")
