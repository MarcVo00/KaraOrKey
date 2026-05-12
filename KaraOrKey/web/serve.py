import http.server

class KaraOrKeyHandler(http.server.SimpleHTTPRequestHandler):
    # Bypass Windows registry MIME types — force correct types for Flutter web
    _MIME_OVERRIDES = {
        '.mjs':  'application/javascript',
        '.js':   'application/javascript',
        '.wasm': 'application/wasm',
    }

    def guess_type(self, path):
        for ext, mime in self._MIME_OVERRIDES.items():
            if str(path).endswith(ext):
                return mime
        return super().guess_type(path)

    def log_message(self, fmt, *args):
        print(f"  {args[0]}  {args[1]}")

httpd = http.server.HTTPServer(('', 8080), KaraOrKeyHandler)
print("KaraOrKey Web  →  http://localhost:8080")
httpd.serve_forever()
