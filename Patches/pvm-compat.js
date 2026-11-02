// PVM compatibility shim for the known Shiguang Client.swf only.
// The Ruffle 0.7.1 URLStream implementation delegates to URLLoader,
// whose close() is still a stub. When the game reloads during PROGRESS,
// an old COMPLETE event may interrupt the new version request.
// Patch bytes are applied in memory only; installed .srom stays untouched.
window.ShiguangPVMCompat = async function (resourceURL, report) {
  const response = await fetch(resourceURL, {cache: 'no-store'});
  if (!response.ok) throw Error('Client.swf HTTP ' + response.status);
  const original = new Uint8Array(await response.arrayBuffer());
  const hash = await crypto.subtle.digest('SHA-256', original);
  const fingerprint = [...new Uint8Array(hash)].map(n => n.toString(16).padStart(2, '0')).join('');
  if (fingerprint !== 'd64a9e3af813324f6e1f9844e74eee16dee5d76a4c8a26c417585467a3c3e59f') {
    report('Client.swf 指纹不同，保留原始游戏代码（不应用兼容补丁）');
    return null;
  }
  if (original[0] !== 67 || original[1] !== 87 || original[2] !== 83) {
    report('游戏文件不是预期的 CWS 格式，跳过补丁');
    return null;
  }
  // Older macOS WebKit lacks DecompressionStream. Use bundled pako as offline fallback.
  const hasPako = !!(window.pako && typeof window.pako.inflate === 'function');
  if (!hasPako && !window.DecompressionStream) {
    report('兼容补丁失败：缺少 pako 与 DecompressionStream，无法解压 CWS');
    return null;
  }
  report(hasPako ? 'PVM 解压器：内置 pako（兼容旧版 WebKit）' : 'PVM 解压器：DecompressionStream');
  async function inflate(bytes) {
    if (hasPako) return window.pako.inflate(bytes);
    const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate'));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }
  const body = await inflate(original.subarray(8));
  if (body.length !== 132210) throw Error('Client.swf 解压长度不符合预期');
  const patchResponse = await fetch('/ruffle/pvm-compat.b64', {cache: 'no-store'});
  if (!patchResponse.ok) throw Error('补丁数据不可用：HTTP ' + patchResponse.status);
  const compact = (await patchResponse.text()).trim();
  const patch = Uint8Array.from(atob(compact), c => c.charCodeAt(0));
  const operations = JSON.parse(new TextDecoder().decode(await inflate(patch)));
  const result = new Uint8Array(132266);
  let src = 0, dst = 0;
  for (const [start, end, replacement] of operations) {
    if (start < src || end < start || end > body.length) throw Error('无效补丁偏移');
    result.set(body.subarray(src, start), dst); dst += start - src;
    const bytes = Uint8Array.from(atob(replacement), c => c.charCodeAt(0));
    result.set(bytes, dst); dst += bytes.length; src = end;
  }
  result.set(body.subarray(src), dst); dst += body.length - src;
  if (dst !== result.length) throw Error('兼容补丁长度校验失败');
  // v3.1 second stage: replace ByteLoader's stale COMPLETE cleanup.
  // First-stage PVM patch is retained; the original .srom is never edited.
  const byteResponse = await fetch('/ruffle/byte-loader-followup.b64', {cache: 'no-store'});
  if (!byteResponse.ok) throw Error('ByteLoader 兼容补丁不可用：HTTP ' + byteResponse.status);
  const bytePack = Uint8Array.from(atob((await byteResponse.text()).trim()), c => c.charCodeAt(0));
  const byteChanges = JSON.parse(new TextDecoder().decode(await inflate(bytePack)));
  const combined = new Uint8Array(132272);
  let from = 0, to = 0;
  for (const [start, end, replacement] of byteChanges) {
    if (start < from || end < start || end > result.length) throw Error('ByteLoader 补丁偏移异常');
    combined.set(result.subarray(from, start), to); to += start - from;
    const bytes = Uint8Array.from(atob(replacement), c => c.charCodeAt(0));
    combined.set(bytes, to); to += bytes.length; from = end;
  }
  combined.set(result.subarray(from), to); to += result.length - from;
  if (to !== combined.length) throw Error('ByteLoader 补丁长度校验失败');
  // Ruffle supports in-memory FWS via DataLoadOptions.
  const movie = new Uint8Array(8 + combined.length);
  movie[0] = 70; movie[1] = 87; movie[2] = 83; movie[3] = original[3];
  new DataView(movie.buffer).setUint32(4, movie.length, true);
  movie.set(combined, 8);
  const sha = await crypto.subtle.digest('SHA-256', movie);
  const computed = [...new Uint8Array(sha)].map(n => n.toString(16).padStart(2, '0')).join('');
  if (computed !== 'b4a6db67d2af3d47f079e2f24f84c13000eff2517165b889dd7d57287a6256af') {
    throw Error('ByteLoader 兼容补丁哈希校验不通过');
  }
  report('已应用 PVM + ByteLoader 双层事件兼容补丁（内存校验通过）');
  return movie;
};
