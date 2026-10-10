"""Tiny stand-in for the OpenSubtitles.com REST API, to test the Flix subtitle service offline.

    python -I flix/tests/mock_opensubtitles.py [--port 8099] [--log requests.log]

Point VLC at it with --flixsubs-base-url=http://127.0.0.1:8099/api/v1
and --flixsubs-api-key=testkey --flixsubs-user=tester --flixsubs-password=secret.

Behaviour:
  POST /api/v1/login      -> token when the account is tester/secret, else 401
  GET  /api/v1/subtitles  -> one English result per request. A request with moviehash_match=only
                             answers "no result" unless --hash-hits is given, so the service must
                             fall back to the title + year search.
  POST /api/v1/download   -> link to /dl/<id>.srt, needs the bearer token
  GET  /dl/<id>.srt       -> a small valid SRT

Every request is appended to the log as one JSON line (path, query, selected headers), which is
what the tests read to check what the client asked for.
"""
import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

API_KEY = "testkey"
TOKEN = "tok-123"
FILE_ID = 4242

SRT = (
    "1\n00:00:01,000 --> 00:00:19,000\nHello from the mock server.\n\n"
    "2\n00:00:19,500 --> 00:00:39,000\nThis subtitle was downloaded by Flix.\n\n"
)


def make_handler(log_path, hash_hits):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, *args):          # keep the console quiet
            pass

        def _record(self, body=None):
            url = urlparse(self.path)
            entry = {
                "method": self.command,
                "path": url.path,
                "query": {k: v[0] for k, v in parse_qs(url.query).items()},
                "api_key": self.headers.get("Api-Key"),
                "auth": self.headers.get("Authorization"),
                "agent": self.headers.get("User-Agent"),
            }
            if body:
                entry["body"] = json.loads(body.decode() or "{}")
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(entry) + "\n")
            return url, entry

        def _send(self, status, payload, ctype="application/json"):
            data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            url, entry = self._record()
            if url.path.startswith("/dl/"):
                return self._send(200, SRT.encode("utf-8"), "application/x-subrip")
            if entry["api_key"] != API_KEY:
                return self._send(401, {"message": "bad api key"})
            if url.path == "/api/v1/subtitles":
                query = entry["query"]
                if query.get("moviehash_match") == "only" and not hash_hits:
                    return self._send(200, {"total_count": 0, "data": []})
                hit = bool(query.get("moviehash"))
                return self._send(200, {"total_count": 1, "page": 1, "total_pages": 1, "data": [{
                    "id": "1", "type": "subtitle",
                    "attributes": {
                        "language": (query.get("languages") or "en").split(",")[0],
                        "download_count": 1234, "from_trusted": True,
                        "moviehash_match": hit,
                        "feature_details": {"feature_id": 77, "title": query.get("query", "?")},
                        "files": [{"file_id": FILE_ID, "file_name": "mock.release.srt"}],
                    }}]})
            return self._send(404, {"message": "unknown path"})

        def do_POST(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length)
            url, entry = self._record(body)
            if url.path == "/api/v1/login":
                data = entry.get("body", {})
                if data.get("username") == "tester" and data.get("password") == "secret":
                    return self._send(200, {"token": TOKEN, "status": 200,
                                            "user": {"allowed_downloads": 20}})
                return self._send(401, {"message": "bad credentials"})
            if url.path == "/api/v1/download":
                if entry["auth"] != "Bearer " + TOKEN:
                    return self._send(401, {"message": "no token"})
                host = self.headers.get("Host")
                return self._send(200, {"link": "http://%s/dl/%d.srt" % (host, FILE_ID),
                                        "file_name": "mock.release.srt", "remaining": 19})
            return self._send(404, {"message": "unknown path"})

    return Handler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--log", default="mock_opensubtitles.log")
    ap.add_argument("--hash-hits", action="store_true",
                    help="answer hash searches with a result (default: no result)")
    args = ap.parse_args()
    open(args.log, "w").close()
    server = HTTPServer(("127.0.0.1", args.port), make_handler(args.log, args.hash_hits))
    print("mock OpenSubtitles on http://127.0.0.1:%d/api/v1, log: %s" % (args.port, args.log))
    sys.stdout.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
