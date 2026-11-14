//! FFI bridge used only by the isolated Shiguang iOS hybrid test build.
//! The game's SwiftUI home screen and asset server stay in Swift; this
//! creates a true native Rust/Metal player, never a WKWebView.
use std::ffi::{c_char, c_void, CStr};

use objc2::rc::Retained;
use objc2::ClassType;
use objc2_foundation::MainThreadMarker;
use ruffle_frontend_utils::content::{ContentDescriptor, PlayingContent};
use ruffle_frontend_utils::player_options::PlayerOptions;
use ruffle_render::quality::StageQuality;
use url::Url;

/// Returns a retained UIViewController pointer. The Swift caller owns exactly
/// one +1 reference and must balance it via Unmanaged.takeRetainedValue().
/// Call only from the iOS main thread, like any other UIKit initializer.
#[no_mangle]
pub unsafe extern "C" fn shiguang_native_player_create(url_c: *const c_char, quality: u32) -> *mut c_void {
    if url_c.is_null() { return std::ptr::null_mut(); }
    let Some(main) = MainThreadMarker::new() else { return std::ptr::null_mut(); };
    let Ok(raw) = CStr::from_ptr(url_c).to_str() else { return std::ptr::null_mut(); };
    let Ok(url) = Url::parse(raw) else { return std::ptr::null_mut(); };
    if url.scheme() != "http" || url.host_str() != Some("127.0.0.1") {
        // Never invoke the native player on arbitrary untrusted remote URLs.
        return std::ptr::null_mut();
    }
    // These ObjC runtime classes were registered by UIApplication::main in
    // the stand-alone upstream app, but the embedded player needs to register
    // them explicitly inside the existing SwiftUI UIApplication.
    let _ = crate::PlayerView::class();
    let _ = crate::PlayerController::class();
    let mut opts = PlayerOptions::default();
    opts.quality = Some(match quality {
        0 => StageQuality::Low,
        2 => StageQuality::High,
        _ => StageQuality::Medium,
    });
    let player = crate::PlayerController::new(
        main,
        PlayingContent::DirectFile(ContentDescriptor { url, root_content_path: None }),
        opts,
    );
    let ptr = Retained::as_ptr(&player) as *mut c_void;
    std::mem::forget(player);
    ptr
}
