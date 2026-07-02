import http.server, socketserver, os
PORT = int(os.environ.get('PORT', '8795'))

class H(http.server.SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def send_head(self):
        # Serve a precompressed sibling (<file>.br) when present, fresh, and accepted —
        # roughly halves the first-visit download of the .esm/.wasm/.data payloads.
        # (wasm-build/make_br.sh generates them; the mtime check falls back to the raw
        # file if a redeploy left a stale .br behind.)
        path = self.translate_path(self.path.split('?', 1)[0])
        br = path + '.br'
        if (not path.endswith('.br') and os.path.isfile(path) and os.path.isfile(br)
                and os.path.getmtime(br) >= os.path.getmtime(path)
                and 'br' in self.headers.get('Accept-Encoding', '')):
            try:
                f = open(br, 'rb')
            except OSError:
                return super().send_head()
            self.send_response(200)
            self.send_header('Content-Type', self.guess_type(path))
            self.send_header('Content-Length', str(os.fstat(f.fileno()).st_size))
            self.send_header('Content-Encoding', 'br')
            self.end_headers()
            return f
        return super().send_head()

    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'cross-origin')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate')
        super().end_headers()

socketserver.TCPServer.allow_reuse_address = True
socketserver.ThreadingTCPServer(('', PORT), H).serve_forever()
