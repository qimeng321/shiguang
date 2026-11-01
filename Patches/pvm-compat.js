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
  if (!window.DecompressionStream) {
    report('此 WebKit 不支持 DecompressionStream，保留原始文件');
    return null;
  }
  async function inflate(bytes) {
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
  // Ruffle supports in-memory FWS via DataLoadOptions.
  const movie = new Uint8Array(8 + result.length);
  movie[0] = 70; movie[1] = 87; movie[2] = 83; movie[3] = original[3];
  new DataView(movie.buffer).setUint32(4, movie.length, true);
  movie.set(result, 8);
  report('已对原版 Client.swf 应用 PVM 事件兼容补丁（仅内存、不改资源包）');
  return movie;
};
