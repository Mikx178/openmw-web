// streamfs.js — synchronous-read streaming files for the OpenMW WASM build.
//
// Mounts a URL as a read-only file in the emscripten FS whose bytes are fetched ON DEMAND
// in chunks by a helper Web Worker. The engine's synchronous main-thread read() spin-waits
// on a SharedArrayBuffer flag while the worker does the async range fetch — the standard
// emscripten sync-over-async pattern (requires crossOriginIsolated, which server.py's
// COOP/COEP headers provide). Fetched chunks are LRU-cached in JS memory.
//
// Why: modern Chrome forbids synchronous binary XHR on the main thread (so
// FS.createLazyFile aborts), and OpenMW reads BSAs synchronously on the main thread.
//
// Usage (from index.html preRun, after FS exists):
//   StreamFS.init();                                   // once
//   StreamFS.mount('/mwdata/Morrowind.bsa', 'mwdata/Morrowind.bsa', sizeBytes);
(function () {
  'use strict';
  const CHUNK = 2 * 1024 * 1024; // 2MB chunks
  const LRU_MAX = 48;            // ~96MB resident chunk cache per file set

  const S = { worker: null, ctrl: null, data: null, files: new Map(), lru: [], cache: new Map() };

  function workerSource() {
    return `
      let ctrl, data;
      onmessage = async (e) => {
        const m = e.data;
        if (m.init) { ctrl = new Int32Array(m.ctrl); data = new Uint8Array(m.data); return; }
        // m: {url, start, end, gen}
        try {
          const r = await fetch(m.url, { headers: { Range: 'bytes=' + m.start + '-' + (m.end - 1) } });
          if (!r.ok && r.status !== 206) throw new Error('HTTP ' + r.status);
          const buf = new Uint8Array(await r.arrayBuffer());
          data.set(buf.subarray(0, Math.min(buf.length, data.length)), 0);
          ctrl[1] = buf.length;         // bytes delivered
          Atomics.store(ctrl, 0, m.gen);  // completion flag = generation
          Atomics.notify(ctrl, 0);
        } catch (err) {
          ctrl[1] = -1;
          Atomics.store(ctrl, 0, m.gen);
          Atomics.notify(ctrl, 0);
        }
      };`;
  }

  let generation = 0;
  function fetchChunkSync(url, start, end) {
    const key = url + ':' + start;
    const hit = S.cache.get(key);
    if (hit) {
      // refresh LRU position
      const i = S.lru.indexOf(key);
      if (i >= 0) S.lru.splice(i, 1);
      S.lru.push(key);
      return hit;
    }
    const gen = ++generation;
    S.worker.postMessage({ url, start, end, gen });
    // Spin until the worker signals completion. The worker thread runs independently, so
    // this terminates; local fetches complete in ~1-5ms. (Atomics.wait is disallowed on
    // the main thread, so poll.)
    const t0 = performance.now();
    while (Atomics.load(S.ctrl, 0) !== gen) {
      if (performance.now() - t0 > 30000) throw new Error('streamfs: fetch timeout ' + url + '@' + start);
    }
    const n = S.ctrl[1];
    if (n < 0) throw new Error('streamfs: fetch failed ' + url + '@' + start);
    const chunk = new Uint8Array(n);
    chunk.set(S.data.subarray(0, n));
    S.cache.set(key, chunk);
    S.lru.push(key);
    if (S.lru.length > LRU_MAX) S.cache.delete(S.lru.shift());
    return chunk;
  }

  function readSync(url, size, buffer, offset, length, position) {
    let done = 0;
    while (done < length && position + done < size) {
      const pos = position + done;
      const cs = Math.floor(pos / CHUNK) * CHUNK;
      const ce = Math.min(cs + CHUNK, size);
      const chunk = fetchChunkSync(url, cs, ce);
      const within = pos - cs;
      const n = Math.min(length - done, chunk.length - within);
      if (n <= 0) break;
      buffer.set(chunk.subarray(within, within + n), offset + done);
      done += n;
    }
    return done;
  }

  window.StreamFS = {
    init() {
      if (S.worker) return;
      if (!self.crossOriginIsolated) throw new Error('streamfs needs crossOriginIsolated (COOP/COEP)');
      const ctrlBuf = new SharedArrayBuffer(8);
      const dataBuf = new SharedArrayBuffer(CHUNK);
      S.ctrl = new Int32Array(ctrlBuf);
      S.data = new Uint8Array(dataBuf);
      S.worker = new Worker(URL.createObjectURL(new Blob([workerSource()], { type: 'text/javascript' })));
      S.worker.postMessage({ init: 1, ctrl: ctrlBuf, data: dataBuf });
    },

    // Mount `url` (absolute-ized against the page) at FS path `path` with known byte size.
    mount(path, url, size) {
      const abs = new URL(url, location.href).href;
      const name = path.substring(path.lastIndexOf('/') + 1);
      const dir = path.substring(0, path.lastIndexOf('/')) || '/';
      const node = FS.createFile(dir, name, {}, /*canRead*/ true, /*canWrite*/ false);
      node.usedBytes = size; // some FS paths consult this
      const getattr = node.node_ops.getattr;
      node.node_ops = Object.assign({}, node.node_ops, {
        getattr(n) { const a = getattr(n); a.size = size; return a; },
      });
      node.stream_ops = Object.assign({}, node.stream_ops, {
        llseek(stream, off, whence) {
          let p = off;
          if (whence === 1) p += stream.position;
          else if (whence === 2) p += size;
          if (p < 0) throw new FS.ErrnoError(28 /*EINVAL*/);
          return p;
        },
        read(stream, buffer, offset, length, position) {
          return readSync(abs, size, buffer, offset, length, position);
        },
        write() { throw new FS.ErrnoError(63 /*EROFS*/); },
        mmap() { throw new FS.ErrnoError(52 /*ENOSYS: force read() path*/); },
      });
      return node;
    },
  };
})();
