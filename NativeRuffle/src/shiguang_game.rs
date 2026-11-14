//! Separate, experimental SROM import and localhost asset server for Native Ruffle.
//! Never mutates the Swift/Web formal client's stored resources.
use std::{
    env,
    fs::{self, File},
    io::{self, Read, Seek, SeekFrom, Write},
    net::{TcpListener, TcpStream},
    path::{Component, Path, PathBuf},
    sync::{Mutex, OnceLock},
    thread,
    time::Duration,
};

const MAX_FILES: usize = 120_000;
const MAX_UNPACKED_BYTES: u64 = 16 * 1024 * 1024 * 1024;
const HTTP_ADDR: &str = "127.0.0.1:18765";
pub const GAME_URL: &str = "http://127.0.0.1:18765/Client.swf";

#[derive(Default)]
struct ImportState {
    running: bool,
    result: Option<Result<(), String>>,
    percent: usize,
}
static IMPORT: OnceLock<Mutex<ImportState>> = OnceLock::new();
fn import_state() -> &'static Mutex<ImportState> {
    IMPORT.get_or_init(|| Mutex::new(ImportState::default()))
}
fn base() -> PathBuf {
    let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_else(env::temp_dir);
    home.join("Library").join("Application Support").join("ShiguangNativeTest")
}
fn game_root() -> PathBuf { base().join("Game") }
pub fn installed() -> bool {
    game_root().join("Client.swf").metadata().map(|x| x.len() > 64).unwrap_or(false)
}
pub fn in_progress() -> bool {
    import_state().lock().map(|s| s.running).unwrap_or(false)
}
pub fn progress() -> usize {
    import_state().lock().map(|s| s.percent).unwrap_or(0)
}
pub fn take_result() -> Option<Result<(), String>> {
    import_state().lock().ok().and_then(|mut s| s.result.take())
}
fn set_percent(percent: usize) {
    if let Ok(mut s) = import_state().lock() {
        s.percent = percent.min(99);
    }
}
pub fn begin_import(source: PathBuf) -> Result<(), String> {
    {
        let mut s = import_state().lock().map_err(|e| e.to_string())?;
        if s.running { return Err("另一个资源包仍在解压中".into()); }
        s.running = true;
        s.percent = 0;
        s.result = None;
    }
    thread::spawn(move || {
        let result = import_archive(&source);
        if let Err(message) = &result {
            tracing::error!("[原生拾光号] SROM 导入失败: {message}");
        } else {
            tracing::info!("[原生拾光号] SROM 导入成功，游戏入口可用");
        }
        if let Ok(mut s) = import_state().lock() {
            s.running = false;
            s.percent = 100;
            s.result = Some(result);
        }
    });
    Ok(())
}
fn import_archive(source: &Path) -> Result<(), String> {
    let parent = base();
    fs::create_dir_all(&parent).map_err(|e| format!("无法创建游戏目录: {e}"))?;
    let stage = parent.join("Game.extracting");
    let backup = parent.join("Game.previous");
    if stage.exists() {
        fs::remove_dir_all(&stage).map_err(|e| format!("无法清除上次未完成的临时文件: {e}"))?;
    }
    fs::create_dir_all(&stage).map_err(|e| format!("创建临时目录失败: {e}"))?;
    let extract_result = (|| -> Result<(), String> {
        let f = File::open(source).map_err(|e| format!("无法读取所选 SROM: {e}"))?;
        let mut zip = zip::ZipArchive::new(f).map_err(|e| format!("不是受支持的 ZIP/SROM: {e}"))?;
        if zip.len() > MAX_FILES { return Err("资源文件数量超出安全限制".into()); }
        let total: u64 = (0..zip.len()).try_fold(0u64, |acc, i| {
            let entry = zip.by_index(i).map_err(|e| format!("读取 ZIP 目录失败 #{i}: {e}"))?;
            acc.checked_add(entry.size()).ok_or("资源包体积溢出".to_string())
        })?;
        if total > MAX_UNPACKED_BYTES { return Err("解压体积超过 16GiB 安全限制".into()); }
        let mut done = 0u64;
        let file_count = zip.len();
        for i in 0..file_count {
            let mut entry = zip.by_index(i).map_err(|e| format!("读取文件 #{i} 失败: {e}"))?;
            let rel = entry.enclosed_name().ok_or_else(|| format!("发现非法相对路径: {}", entry.name()))?.to_path_buf();
            if rel.as_os_str().is_empty() { continue; }
            if rel.components().any(|c| !matches!(c, Component::Normal(_))) {
                return Err(format!("ZIP 路径非法: {}", entry.name()));
            }
            if entry.unix_mode().map(|m| (m & 0o170000) == 0o120000).unwrap_or(false) {
                return Err(format!("ZIP 不允许符号链接: {}", entry.name()));
            }
            let out_path = stage.join(rel);
            if entry.is_dir() {
                fs::create_dir_all(&out_path).map_err(|e| format!("无法建立目录 {}: {e}", out_path.display()))?;
            } else {
                if let Some(parent) = out_path.parent() {
                    fs::create_dir_all(parent).map_err(|e| format!("创建资源目录失败: {e}"))?;
                }
                let mut out = File::create(&out_path).map_err(|e| format!("写入资源失败 {}: {e}", out_path.display()))?;
                io::copy(&mut entry, &mut out).map_err(|e| format!("解压写入失败 {}: {e}", out_path.display()))?;
                done = done.saturating_add(entry.size());
            }
            if i % 64 == 0 || i + 1 == file_count {
                set_percent(if total > 0 { ((done.saturating_mul(90) / total) as usize).min(90) } else { 90 });
            }
        }
        let entry = stage.join("Client.swf");
        if !entry.is_file() || entry.metadata().map(|m| m.len()).unwrap_or(0) < 64 {
            return Err("资源包未找到根目录 Client.swf；请使用完整拾光号美化包".into());
        }
        // A few files must exist before changing the currently installed game.
        for rel in ["config/dll.xml", "version.swf", "login/Login.swf"] {
            if !stage.join(rel).is_file() {
                return Err(format!("完整资源缺少必要文件: {rel}"));
            }
        }
        set_percent(94);
        Ok(())
    })();
    if let Err(error) = extract_result {
        let _ = fs::remove_dir_all(&stage);
        return Err(error);
    }
    if backup.exists() {
        fs::remove_dir_all(&backup).map_err(|e| format!("无法清除旧备份: {e}"))?;
    }
    let old_game = game_root();
    let had_old = old_game.exists();
    if had_old {
        fs::rename(&old_game, &backup).map_err(|e| format!("备份旧游戏失败: {e}"))?;
    }
    if let Err(error) = fs::rename(&stage, &old_game) {
        if had_old {
            let _ = fs::rename(&backup, &old_game);
        }
        return Err(format!("安装新资源包失败（原有资源尽量保留）: {error}"));
    }
    set_percent(98);
    if had_old { let _ = fs::remove_dir_all(&backup); }
    // The picker uses Import mode; its sandboxed copy can be discarded after use.
    // Never delete the original picked file unless it lives in the OS inbox.
    let inbox = env::var_os("HOME").map(PathBuf::from).unwrap_or_default().join("Documents").join("Inbox");
    if source.starts_with(&inbox) { let _ = fs::remove_file(source); }
    Ok(())
}

static HTTP_READY: OnceLock<Result<(), String>> = OnceLock::new();
pub fn start_server() -> Result<(), String> {
    HTTP_READY.get_or_init(|| {
        let listener = TcpListener::bind(HTTP_ADDR)
            .map_err(|e| format!("无法开启原生资源服务 {HTTP_ADDR}: {e}"))?;
        thread::Builder::new().name("shiguang-native-http".into()).spawn(move || {
            for accepted in listener.incoming() {
                match accepted {
                    Ok(stream) => {
                        let _ = thread::Builder::new().name("shiguang-static-file".into()).spawn(move || {
                            if let Err(e) = serve(stream) { tracing::debug!("资源服务: {e}"); }
                        });
                    }
                    Err(e) => tracing::error!("[原生拾光号] HTTP 接受连接失败: {e}"),
                }
            }
        }).map_err(|e| format!("无法启动资源服务线程: {e}"))?;
        tracing::info!("[原生拾光号] 本地资源服务运行于 http://{HTTP_ADDR}");
        Ok(())
    }).clone()
}
fn write_error(mut s: &TcpStream, status: &str, message: &str) {
    let _ = write!(s, "HTTP/1.1 {status}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{}", message.len(), message);
}
fn mime(path: &Path) -> &'static str {
    match path.extension().and_then(|x| x.to_str()).unwrap_or("").to_ascii_lowercase().as_str() {
        "swf" => "application/x-shockwave-flash",
        "xml" => "application/xml",
        "js" => "application/javascript",
        "html" => "text/html; charset=utf-8",
        "css" => "text/css",
        "json" => "application/json",
        "wasm" => "application/wasm",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "mp3" => "audio/mpeg",
        "mp4" => "video/mp4",
        "ttf" => "font/ttf",
        "otf" => "font/otf",
        _ => "application/octet-stream",
    }
}
fn serve(mut s: TcpStream) -> io::Result<()> {
    s.set_read_timeout(Some(Duration::from_secs(8)))?;
    s.set_write_timeout(Some(Duration::from_secs(35)))?;
    let mut header = Vec::<u8>::new();
    let mut chunk = [0u8; 2048];
    while header.len() < 32 * 1024 && !header.windows(4).any(|x| x == b"\r\n\r\n") {
        let n = s.read(&mut chunk)?;
        if n == 0 { return Ok(()); }
        header.extend_from_slice(&chunk[..n]);
    }
    if header.len() >= 32 * 1024 {
        write_error(&s, "431 Request Header Fields Too Large", "headers too large");
        return Ok(());
    }
    let text = String::from_utf8_lossy(&header);
    let mut lines = text.split("\r\n");
    let first = lines.next().unwrap_or("");
    let parts: Vec<_> = first.split_whitespace().collect();
    if parts.len() < 2 { write_error(&s, "400 Bad Request", "invalid request"); return Ok(()); }
    let method = parts[0];
    if method == "OPTIONS" {
        write!(s,"HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, HEAD, OPTIONS\r\nAccess-Control-Allow-Headers: Range, Content-Type\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")?;
        return Ok(());
    }
    if method != "GET" && method != "HEAD" {
        write_error(&s, "405 Method Not Allowed", "only GET/HEAD");
        return Ok(());
    }
    let target = parts[1].split('?').next().unwrap_or("/");
    let decoded = percent_encoding::percent_decode_str(target).decode_utf8_lossy();
    // The current game bundle sometimes lacks ip.txt; native sockets connect
    // directly to the live host (unlike the browser's WebSocket proxy).
    if decoded == "/ip.txt" {
        let text = "202.189.22.79:22973";
        write!(s, "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n", text.len())?;
        if method == "GET" { s.write_all(text.as_bytes())?; }
        return Ok(());
    }
    let path = Path::new(decoded.trim_start_matches('/'));
    if decoded.contains('\\') || path.components().any(|c| !matches!(c, Component::Normal(_))) {
        write_error(&s, "403 Forbidden", "invalid path");
        return Ok(());
    }
    let actual = game_root().join(path);
    if !actual.is_file() { write_error(&s, "404 Not Found", "missing game resource"); return Ok(()); }
    let mut f = File::open(&actual)?;
    let total = f.metadata()?.len();
    let mut start = 0u64;
    let mut end = total.saturating_sub(1);
    let mut ranged = false;
    for line in lines {
        if line.to_ascii_lowercase().starts_with("range:") {
            if let Some(value) = line.split(':').nth(1).and_then(|v| v.trim().strip_prefix("bytes=")) {
                let mut halves = value.split('-');
                if let Ok(v) = halves.next().unwrap_or("").trim().parse::<u64>() {
                    if v < total {
                        start = v;
                        if let Some(last) = halves.next().filter(|x| !x.trim().is_empty()) {
                            if let Ok(v) = last.trim().parse::<u64>() { end = end.min(v); }
                        }
                        ranged = true;
                    }
                }
            }
            break;
        }
    }
    let count = if total > 0 && end >= start { end - start + 1 } else { 0 };
    let code = if ranged { "206 Partial Content" } else { "200 OK" };
    write!(s, "HTTP/1.1 {code}\r\nContent-Type: {}\r\nAccept-Ranges: bytes\r\nContent-Length: {count}\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: public, max-age=60\r\nConnection: close\r\n", mime(&actual))?;
    if ranged { write!(s, "Content-Range: bytes {start}-{end}/{total}\r\n")?; }
    write!(s, "\r\n")?;
    if method == "GET" && count > 0 {
        f.seek(SeekFrom::Start(start))?;
        io::copy(&mut f.take(count), &mut s)?;
    }
    Ok(())
}
