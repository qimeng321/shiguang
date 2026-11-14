#!/usr/bin/env python3
"""Apply a minimal standalone Shiguang gameplay proof-of-concept to native Ruffle iOS.

This script runs in GitHub Actions after cloning a fixed upstream native Ruffle
revision. It only edits the temporary clone, never the release Swift app.
"""
from pathlib import Path

root=Path("native-ruffle")

def replace(path, old, new, count=1):
    p=root/path
    text=p.read_text()
    found=text.count(old)
    if found != count:
        raise SystemExit(f"{path}: expected {count} occurrences, got {found}: {old[:90]!r}")
    p.write_text(text.replace(old,new))

replace("Cargo.toml",
        'url = "2.5.2"\n',
        'url = "2.5.2"\nzip = { version = "2.4.2", default-features = false, features = ["deflate"] }\npercent-encoding = "2.3.1"\n')
replace("src/lib.rs", "mod storage;\n",
        "mod storage;\nmod shiguang_game;\n")
replace("src/app_delegate.rs",
        "            storage::setup();\n            true\n",
        "            storage::setup();\n"
        "            if let Err(e) = crate::shiguang_game::start_server() {\n"
        '                tracing::error!("Native game HTTP server: {e}");\n'
        "            }\n"
        "            true\n")
replace("src/library_controller.rs",
        "use std::cell::OnceCell;\n",
        "use std::cell::OnceCell;\nuse std::path::{Path, PathBuf};\nuse std::sync::OnceLock;\n")
replace("src/library_controller.rs",
        "    ns_string, MainThreadMarker, NSArray, NSBundle, NSCoder, NSIndexPath, NSInteger, NSObject,\n",
        "    ns_string, MainThreadMarker, NSArray, NSBundle, NSCoder, NSIndexPath, NSInteger, NSObject,\n"
        "    NSRunLoop, NSRunLoopCommonModes, NSTimer,\n")
replace("src/library_controller.rs",
        "        fn _show_document_picker(&self, _sender: Option<&AnyObject>) {\n"
        "            self.show_document_picker();\n"
        "        }\n",
        "        fn _show_document_picker(&self, _sender: Option<&AnyObject>) {\n"
        "            self.show_document_picker();\n"
        "        }\n\n"
        "        #[unsafe(method(shiguangImportTimer:))]\n"
        "        fn _shiguang_import_timer(&self, _timer: &NSTimer) {\n"
        "            self.poll_shiguang_import();\n"
        "        }\n")
replace("src/library_controller.rs",
        "            if storage::movie_from_url(&url).is_none() {\n"
        "                storage::add_movie(&url);\n"
        "            } else {\n"
        "                // TODO: Give the user an option here?\n"
        '                tracing::error!("did not add existing movie {url:?}");\n'
        "            }\n",
        "            if let Some(name) = url.path() {\n"
        "                let path = PathBuf::from(name.to_string());\n"
        "                let ext = path.extension().and_then(|s| s.to_str())\n"
        '                    .unwrap_or("").to_ascii_lowercase();\n'
        '                if ext == "srom" || ext == "zip" {\n'
        "                    if let Err(e) = crate::shiguang_game::begin_import(path) {\n"
        '                        tracing::error!("Shiguang SROM import not started: {e}");\n'
        "                        self.navigationItem().setTitle(Some(&NSString::from_str(&e)));\n"
        "                    } else {\n"
        "                        self.navigationItem().setTitle(Some(ns_string!(\"正在解压拾光号…\")));\n"
        "                    }\n"
        "                    return;\n"
        "                }\n"
        "            }\n"
        "            if storage::movie_from_url(&url).is_none() {\n"
        "                storage::add_movie(&url);\n"
        "            } else {\n"
        '                tracing::error!("did not add existing movie {url:?}");\n'
        "            }\n")
replace("src/library_controller.rs",
        "        self.setup_logo();\n",
        "        self.setup_logo();\n"
        "        let timer = unsafe {\n"
        "            NSTimer::timerWithTimeInterval_target_selector_userInfo_repeats(\n"
        "                0.75, self, sel!(shiguangImportTimer:), None, true)\n"
        "        };\n"
        "        unsafe { NSRunLoop::mainRunLoop().addTimer_forMode(&timer, NSRunLoopCommonModes) };\n")
replace("src/library_controller.rs",
        "        self.logo_view().start();\n",
        "        self.logo_view().start();\n"
        "        static AUTO_LAUNCH: OnceLock<()> = OnceLock::new();\n"
        "        if crate::shiguang_game::installed() && AUTO_LAUNCH.set(()).is_ok() {\n"
        "            self.launch_shiguang_game();\n"
        "        }\n")
replace("src/library_controller.rs",
        "            &NSArray::from_slice(&[ns_string!(RUF_UTI), ns_string!(SWF_UTI)]),\n",
        "            &NSArray::from_slice(&[ns_string!(RUF_UTI), ns_string!(SWF_UTI), ns_string!(\"public.data\")]),\n")
replace("src/library_controller.rs",
        "            UIDocumentPickerMode::Open,\n",
        "            UIDocumentPickerMode::Import,\n")
replace("src/library_controller.rs",
        "    fn toggle_editing(&self, button: &UIBarButtonItem) {\n",
        "    fn poll_shiguang_import(&self) {\n"
        "        if crate::shiguang_game::in_progress() {\n"
        "            let message = format!(\"解压中 {}%（请保持应用运行）\", crate::shiguang_game::progress());\n"
        "            self.navigationItem().setTitle(Some(&NSString::from_str(&message)));\n"
        "            return;\n"
        "        }\n"
        "        if let Some(result) = crate::shiguang_game::take_result() {\n"
        "            match result {\n"
        "                Ok(()) => {\n"
        '                    self.navigationItem().setTitle(Some(ns_string!("拾光号原生测试")));\n'
        "                    self.launch_shiguang_game();\n"
        "                }\n"
        "                Err(error) => {\n"
        '                    tracing::error!("SROM import error: {error}");\n'
        "                    let message = format!(\"导入失败: {}\", error.chars().take(38).collect::<String>());\n"
        "                    self.navigationItem().setTitle(Some(&NSString::from_str(&message)));\n"
        "                }\n"
        "            }\n"
        "        }\n"
        "    }\n\n"
        "    fn launch_shiguang_game(&self) {\n"
        "        if let Err(error) = crate::shiguang_game::start_server() {\n"
        "            self.navigationItem().setTitle(Some(&NSString::from_str(&error)));\n"
        "            return;\n"
        "        }\n"
        "        let url = NSURL::URLWithString(&NSString::from_str(crate::shiguang_game::GAME_URL))\n"
        '            .expect("game localhost URL must be valid");\n'
        "        if storage::movie_from_url(&url).is_none() {\n"
        "            storage::add_movie(&url);\n"
        "        }\n"
        "        if let Some(movie) = storage::movie_from_url(&url) {\n"
        "            let player = crate::PlayerController::empty(MainThreadMarker::from(self));\n"
        "            player.setup_movie(&movie);\n"
        "            if let Some(nav) = self.navigationController() {\n"
        "                nav.pushViewController_animated(&player, true);\n"
        "            }\n"
        "        }\n"
        "    }\n\n"
        "    fn toggle_editing(&self, button: &UIBarButtonItem) {\n")
# Change the displayed name and package identifier only inside the cloned test player.
replace("ruffle-ios.xcodeproj/project.pbxproj",
        'PRODUCT_BUNDLE_IDENTIFIER = "rs.ruffle.ruffle-ios";',
        'PRODUCT_BUNDLE_IDENTIFIER = "cn.shiguanghao.nativegame.test";',2)
replace("ruffle-ios.xcodeproj/project.pbxproj",
        'INFOPLIST_KEY_CFBundleDisplayName = Ruffle;',
        'INFOPLIST_KEY_CFBundleDisplayName = "拾光号原生测试";',2)
# The game loads resources over loopback HTTP.
replace("Info.plist",
        "<dict>\n\t<key>CFBundleDocumentTypes</key>",
        "<dict>\n"
        "\t<key>NSAppTransportSecurity</key>\n"
        "\t<dict><key>NSAllowsLocalNetworking</key><true/></dict>\n"
        "\t<key>CFBundleDocumentTypes</key>")
native = Path("NativeRuffle/src/shiguang_game.rs")
assert native.is_file(), "Native Ruffle game module must be present in the repository"
target = root/"src/shiguang_game.rs"
target.write_bytes(native.read_bytes())
print("Native Shiguang test patched: ZIP/SROM picker, background install, HTTP/127.0.0.1, auto-launch.")
