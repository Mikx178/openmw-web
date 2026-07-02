import http.server, socketserver, os
PORT = int(os.environ.get('PORT', '8795'))
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy','same-origin')
        self.send_header('Cross-Origin-Embedder-Policy','require-corp')
        self.send_header('Cross-Origin-Resource-Policy','cross-origin')
        self.send_header('Cache-Control','no-store, no-cache, must-revalidate')
        super().end_headers()
socketserver.TCPServer.allow_reuse_address=True
socketserver.TCPServer(('',PORT),H).serve_forever()
