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


/// Dispatch text from a real iOS on-screen keyboard to Flash's focused text field.
/// No keyboard content is transmitted to the game server by the bridge; Ruffle
/// itself handles Flash input and the game may then send it as normal.
#[no_mangle]
pub unsafe extern "C" fn shiguang_native_player_send_text(
    opaque: *mut c_void, utf8: *const c_char,
) -> bool {
    if opaque.is_null() || utf8.is_null() { return false; }
    let Ok(text) = CStr::from_ptr(utf8).to_str() else { return false; };
    let controller = &*(opaque as *const crate::PlayerController);
    let mut player = controller.player_lock();
    for codepoint in text.chars() {
        player.handle_event(ruffle_core::events::PlayerEvent::TextInput { codepoint });
    }
    true
}

/// 0 = Backspace; 1 = Enter. Used by the simple iOS keyboard bridge.
#[no_mangle]
pub unsafe extern "C" fn shiguang_native_player_text_control(
    opaque: *mut c_void, action: u32,
) -> bool {
    if opaque.is_null() { return false; }
    use ruffle_core::events::{PlayerEvent, TextControlCode};
    let code = match action {
        0 => TextControlCode::Backspace,
        1 => TextControlCode::Enter,
        _ => return false,
    };
    let controller = &*(opaque as *const crate::PlayerController);
    controller.player_lock().handle_event(PlayerEvent::TextControl { code });
    true
}
