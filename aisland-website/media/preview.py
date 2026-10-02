"""Local static preview with byte-range support for the native video player."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse
import re

class RangeHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        raw = self.headers.get("Range")
        path = Path(self.translate_path(self.path))
        if not raw or not path.is_file():
            return super().do_GET()
        match = re.fullmatch(r"bytes=(\d+)-(\d*)", raw)
        size = path.stat().st_size
        if not match:
            self.send_error(416)
            return
        start = int(match[1])
        end = min(int(match[2]) if match[2] else size - 1, size - 1)
        if start > end:
            self.send_error(416)
            return
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(str(path)))
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with path.open("rb") as stream:
            stream.seek(start)
            self.wfile.write(stream.read(end - start + 1))

    def end_headers(self):
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

root = Path(__file__).resolve().parents[1] / "dist"
parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=4319)
args = parser.parse_args()
ThreadingHTTPServer(("127.0.0.1", args.port), partial(RangeHandler, directory=str(root))).serve_forever()
