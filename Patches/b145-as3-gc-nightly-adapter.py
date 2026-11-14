#!/usr/bin/env python3
"""Port PR23897 System.gc full-GC hint to official Nightly Nov13.

Nightly uses optimizer_settings (not older PR optimizer_enabled), so the
changes are matched to its actual fields. No forced per-frame GC.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1]) if len(sys.argv)==2 else Path(".")
def edit(path,changes):
    p=root/path
    s=p.read_text(encoding="utf-8")
    for a,b in changes:
        n=s.count(a)
        if n!=1:
            sys.exit(f"B145 System.gc mismatch {path}: count={n}; anchor={a[:120]!r}")
        s=s.replace(a,b,1)
    p.write_text(s,encoding="utf-8")
    print(f"[B145 GC] patched {path}")

edit("core/src/avm2.rs",[
    ("""    pub optimizer_settings: OptimizerSettings,
}""",
    """    pub optimizer_settings: OptimizerSettings,

    /// Set by AS3 System.gc and acted upon after the current frame.
    #[collect(require_static)]
    pub force_full_gc: std::cell::Cell<bool>,
}"""),
    ("""            optimizer_settings: OptimizerSettings::enable_all(),
        }""",
    """            optimizer_settings: OptimizerSettings::enable_all(),
            force_full_gc: std::cell::Cell::new(false),
        }""")
])
edit("core/src/avm2/globals/flash/system/System.as",[
    ("        public static function gc():void {}",
     "        public static native function gc():void;")
])
edit("core/src/avm2/globals/flash/system/system.rs",[
    ("pub fn set_clipboard<'gc>(",
     """/// AS3 System.gc requests a full cycle after the current AVM update.
pub fn gc<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    activation.context.avm2.force_full_gc.set(true);
    Ok(Value::Undefined)
}

pub fn set_clipboard<'gc>(""")
])
edit("core/src/player.rs",[
    ("""        // GC
        self.gc_arena.borrow_mut().collect_debt();

        rval""",
    """        // GC
        self.gc_arena.borrow_mut().collect_debt();

        // PR23897: explicit System.gc() requests one full collection.
        let request_full_gc = self.gc_arena.borrow().mutate(|_, root| {
            let data = root.data.borrow();
            let requested = data.avm2.force_full_gc.get();
            data.avm2.force_full_gc.set(false);
            requested
        });
        if request_full_gc {
            self.gc_arena.borrow_mut().finish_cycle();
        }

        rval""")
])
print("[B145 GC] full-cycle AS3 collection adapted to pinned Nightly.")
