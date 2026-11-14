#!/usr/bin/env python3
"""B142: directly reduce GPU resource retention in PR22908's Ruffle core.

Pinned upstream: jarca0123/ruffle 1e30e1fff3237f5d9aeabe4c4b66d05cb6f2585d
1. Avoid eager shape/bitmap GPU uploads during SWF preload.
2. Release bitmap, shape, morph-shape handles on LoaderInfo.unload.
3. Re-create the handles lazily if a still-live display object needs them.
This is a conservative code-level mitigation, not proof of a fixed iOS OOM.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(".")
def patch(path, olds):
    p = root/path
    s = p.read_text(encoding="utf-8")
    for old,new in olds:
        n=s.count(old)
        if n!=1:
            raise SystemExit(f"B142 PATCH MISMATCH: {path}, occurrences={n}, anchor={old[:125]!r}")
        s=s.replace(old,new,1)
    p.write_text(s,encoding="utf-8")
    print(f"[B142 GPU fix] updated {path}")

patch("core/src/character.rs",[
    ("use std::cell::OnceCell;", "use std::cell::RefCell;"),
    ("handle: OnceCell<BitmapHandle>,", "handle: RefCell<Option<BitmapHandle>>,"),
    ("handle: OnceCell::default(),", "handle: RefCell::new(None),"),
    ("""        // FIXME - use \`OnceCell::get_or_try_init\` when stabilized.
        if let Some(handle) = self.handle.get() {
            return Ok(handle.clone());
        }
        let decoded = self.compressed.decode()?;
        let new_handle = backend.register_bitmap(decoded)?;
        // FIXME - do we ever want to release this handle, to avoid taking up GPU memory?
        self.handle.set(new_handle.clone()).unwrap();
        Ok(new_handle)
""","""        if let Some(handle) = self.handle.borrow().as_ref() {
            return Ok(handle.clone());
        }
        let decoded = self.compressed.decode()?;
        let new_handle = backend.register_bitmap(decoded)?;
        *self.handle.borrow_mut() = Some(new_handle.clone());
        Ok(new_handle)
"""),
    ("    pub fn compressed(&self) -> &CompressedBitmap {",
     """    /// Drop cached GPU allocation when its SWF Loader unloads.
    /// Decoding and texture registration are lazy when referenced again.
    pub(crate) fn release_gpu_cache(&self) {
        self.handle.borrow_mut().take();
    }

    pub fn compressed(&self) -> &CompressedBitmap {""")
])

patch("core/src/display_object/graphic.rs",[
    ("""        library: Gc<'gc, RefLock<MovieLibrary<'gc>>>,
    ) -> Self {
        let library = library.borrow();
        let shared = GraphicShared {
            id: swf_shape.id,
            bounds: swf_shape.shape_bounds,
            render_handle: Some(context.renderer.register_shape(
                (&swf_shape).into(),
                &MovieLibrarySource { library: &library },
            )),
""","""        _library: Gc<'gc, RefLock<MovieLibrary<'gc>>>,
    ) -> Self {
        // Register graphics only when actually drawn. Preloading unused
        // scenes must not eagerly upload their embedded bitmap fills.
        let shared = GraphicShared {
            id: swf_shape.id,
            bounds: swf_shape.shape_bounds,
            render_handle: RefCell::new(None),
"""),
    ("            render_handle: None,","            render_handle: RefCell::new(None),"),
    ("    render_handle: Option<ShapeHandle>,","    render_handle: RefCell<Option<ShapeHandle>>,"),
    ("    fn set_shared(self, mc: &Mutation<'gc>, shared: Gc<'gc, GraphicShared<'gc>>) {",
     """    /// Return all cached geometry and bitmap-fill handles from this shape
    /// to the renderer when its source Loader unloads.
    pub(crate) fn release_gpu_cache(self) {
        let shared = self.0.shared.get();
        shared.render_handle.borrow_mut().take();
        *shared.scaled_handle.borrow_mut() = TessellationCache::new();
    }

    fn set_shared(self, mc: &Mutation<'gc>, shared: Gc<'gc, GraphicShared<'gc>>) {"""),
    ("""        } else if let Some(base_handle) = self.0.shared.get().render_handle.clone() {
            let transform = context.transform_stack.transform();

            // Calculate the current scale from the transform, to determine if
            // we can reuse a cached tessellation or need to retessellate.
            let matrix = &transform.matrix;
            let scale_x = f32::abs(matrix.a + matrix.c);
            let scale_y = f32::abs(matrix.b + matrix.d);
            let current_scale = ((scale_x * scale_x + scale_y * scale_y) / 2.0).sqrt();

            let handle = self.get_or_retessellate_handle(context, &base_handle, current_scale);

            context.commands.render_shape(handle, transform)
        }
    }
""",
"""        } else {
            let shared = self.0.shared.get();
            let base_handle = {
                let mut cached = shared.render_handle.borrow_mut();
                if cached.is_none() {
                    if let Some(library) = self.library() {
                        let library = library.borrow();
                        *cached = Some(context.renderer.register_shape(
                            (&shared.shape).into(),
                            &MovieLibrarySource { library: &library },
                        ));
                    }
                }
                cached.clone()
            };
            if let Some(base_handle) = base_handle {
                let transform = context.transform_stack.transform();
                let matrix = &transform.matrix;
                let scale_x = f32::abs(matrix.a + matrix.c);
                let scale_y = f32::abs(matrix.b + matrix.d);
                let current_scale = ((scale_x * scale_x + scale_y * scale_y) / 2.0).sqrt();
                let handle = self.get_or_retessellate_handle(context, &base_handle, current_scale);
                context.commands.render_shape(handle, transform)
            }
        }
    }
""")
])

patch("core/src/display_object/morph_shape.rs",[
    ("impl<'gc> MorphShape<'gc> {\n",
     """impl<'gc> MorphShape<'gc> {
    /// Release tessellated GPU handles without throwing away interpolated
    /// shape definitions; used by LoaderInfo.unload.
    pub(crate) fn release_gpu_cache(self) {
        let shared = self.0.shared.get();
        for frame in shared.frames.borrow_mut().values_mut() {
            frame.shape_handle.take();
        }
    }

"""),
])

patch("core/src/library.rs",[
    ("    pub fn get_font(&self, id: CharacterId) -> Option<Font<'gc>> {",
     """    /// Explicitly drop GPU-side caches for an unloaded movie library.
    /// The character definitions remain available to safely reload lazily.
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

    pub fn get_font(&self, id: CharacterId) -> Option<Font<'gc>> {"""),
])

patch("core/src/avm2/object/loaderinfo_object.rs",[
    ("""    pub fn unload(self, context: &mut UpdateContext<'gc>) {
        // Reset properties
""",
     """    pub fn unload(self, context: &mut UpdateContext<'gc>) {
        // A removed movie may have many bitmap-fill textures still cached in
        // its character definitions. Free only these GPU caches; retain all
        // ActionScript objects and compressed SWF data for correct semantics.
        let old_movie = match &*self.0.loaded_stream.borrow() {
            LoaderStream::Swf(movie, _) => Some(*movie),
            _ => None,
        };
        if let Some(movie) = old_movie {
            // Stage/root resources are not owned by this Loader.
            if Gc::as_ptr(movie) != Gc::as_ptr(*context.root_swf) {
                if let Some(library) =
                    context.library.library_for_movie(movie, context.gc_context)
                {
                    library.borrow().release_gpu_cache();
                }
            }
        }
        // Reset properties
""")
])
print("[B142 GPU fix] all 5 source files patched. No JS timer, login, SWF or UI changes.")
