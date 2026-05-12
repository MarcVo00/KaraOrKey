import http.server
import mimetypes

# Python's built-in server ignores .mjs — Flutter web needs it as JS module
mimetypes.add_type('application/javascript', '.mjs')
mimetypes.add_type('application/wasm', '.wasm')

handler = http.server.SimpleHTTPRequestHandler
httpd = http.server.HTTPServer(('', 8080), handler)
print("KaraOrKey Web  →  http://localhost:8080")
httpd.serve_forever()
