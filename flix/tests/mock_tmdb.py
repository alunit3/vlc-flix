"""Tiny stand-in for the TMDB v3 API, to test the Flix artwork / synopsis service offline.

    python -I flix/tests/mock_tmdb.py [--port 8098] [--log requests.log]

Point VLC at it with
    --flix-tmdb-token=testtoken --flix-tmdb-base-url=http://127.0.0.1:8098/3
    --flix-tmdb-image-url=http://127.0.0.1:8098/t/p

Behaviour:
  GET /3/search/movie|tv        -> "Chappie" (2015) for query "chappie", nothing otherwise
  GET /3/movie/<id>|/tv/<id>    -> details with external_ids (imdb_id)
  GET /3/trending/movie/week    -> ten movies
  GET /3/discover/movie|tv      -> 45 generated titles (sort_by, with_genres, date and rating filters, page)
  GET /3/genre/movie|tv/list    -> a few genres
  GET /t/p/<size>/<file>        -> a small generated picture
All endpoints under /3 need "Authorization: Bearer testtoken". Every request is logged as a
JSON line (path, query, authorization).
"""
import argparse
import json
import struct
import sys
import zlib
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

TOKEN = "testtoken"

MOVIES = {
    201: ("Chappie", "2015-03-04", "Chappie is a robot taught to think and feel by a young engineer.",
          "Humanity's last hope isn't human.", 120, ["Science Fiction", "Action", "Crime"], "tt1823672"),
}
for n in range(1, 11):
    MOVIES[n] = ("Trending Movie %d" % n, "2026-0%d-01" % (n % 9 + 1),
                 "Synopsis of trending movie %d." % n, "", 90 + n, ["Drama"], "tt%07d" % (7000000 + n))


GENRES = {28: "Action", 35: "Comedy", 18: "Drama", 878: "Science Fiction", 27: "Horror"}
GENRE_IDS = list(GENRES)
for n in range(1, 46):
    year = 1980 + n
    MOVIES[300 + n] = ("Discover Movie %d" % n, "%d-06-15" % year, "Synopsis of discover movie %d." % n,
                       "", 80 + n, [GENRES[GENRE_IDS[n % 5]]], "tt%07d" % (8000000 + n))


def genre_ids(movie_id):
    return [GENRE_IDS[movie_id % 5]] if movie_id > 300 else [18]


def png(width, height, rgb):
    """A plain vertical gradient PNG (the service stores it as .jpg, Qt sniffs the content)."""
    rows = b""
    for y in range(height):
        shade = 0.4 + 0.6 * y / height
        pixel = bytes(int(c * shade) for c in rgb)
        rows += b"\x00" + pixel * width

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def detail(movie_id):
    title, date, overview, tagline, runtime, genres, imdb = MOVIES[movie_id]
    return {
        "id": movie_id, "title": title, "release_date": date, "overview": overview,
        "tagline": tagline, "runtime": runtime, "vote_average": 7.0 + movie_id % 3 / 10,
        "genres": [{"id": i, "name": g} for i, g in enumerate(genres)],
        "poster_path": "/poster%d.jpg" % movie_id, "backdrop_path": "/backdrop%d.jpg" % movie_id,
        "imdb_id": imdb, "external_ids": {"imdb_id": imdb},
        "genre_ids": genre_ids(movie_id), "popularity": 100.0 - movie_id % 50,
        "first_air_date": date,
    }


def make_handler(log_path):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, *args):
            pass

        def _send(self, status, payload, ctype="application/json"):
            data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            url = urlparse(self.path)
            query = {k: v[0] for k, v in parse_qs(url.query).items()}
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps({"path": url.path, "query": query,
                                    "auth": self.headers.get("Authorization")}) + "\n")

            if url.path.startswith("/t/p/"):
                name = url.path.rsplit("/", 1)[-1]
                if name.startswith("poster"):
                    return self._send(200, png(200, 300, (180, 60, 60)), "image/png")
                return self._send(200, png(320, 180, (60, 90, 160)), "image/png")

            if not url.path.startswith("/3/"):
                return self._send(404, {"status_message": "unknown"})
            if self.headers.get("Authorization") != "Bearer " + TOKEN:
                return self._send(401, {"status_message": "Invalid API key"})

            parts = url.path[3:].strip("/").split("/")
            if parts[0] == "search":
                wanted = query.get("query", "").lower()
                hits = [detail(201)] if wanted == "chappie" else (
                    [detail(i) for i in range(301, 346)] if wanted == "discover" else [])
                return self._send(200, {"page": 1, "results": hits})
            if parts[0] == "genre" and len(parts) == 3:
                return self._send(200, {"genres": [{"id": i, "name": n} for i, n in GENRES.items()]})
            if parts[0] == "discover":
                rows = [detail(i) for i in range(301, 346)]
                gens = [int(g) for g in query.get("with_genres", "").replace("|", ",").split(",") if g]
                if gens:
                    rows = [r for r in rows if set(r["genre_ids"]) & set(gens)]
                for key in ("primary_release_date.gte", "first_air_date.gte"):
                    if key in query:
                        rows = [r for r in rows if r["release_date"] >= query[key]]
                for key in ("primary_release_date.lte", "first_air_date.lte"):
                    if key in query:
                        rows = [r for r in rows if r["release_date"] <= query[key]]
                if "vote_average.gte" in query:
                    rows = [r for r in rows if r["vote_average"] >= float(query["vote_average.gte"])]
                sort = query.get("sort_by", "popularity.desc")
                field = {"popularity": "popularity", "primary_release_date": "release_date",
                         "first_air_date": "release_date", "vote_average": "vote_average"}.get(sort.split(".")[0], "popularity")
                rows.sort(key=lambda r: r[field], reverse=sort.endswith(".desc"))
                page = int(query.get("page", "1"))
                return self._send(200, {"page": page, "total_pages": max(1, (len(rows) + 19) // 20),
                                        "results": rows[(page - 1) * 20:page * 20]})
            if parts == ["trending", "movie", "week"]:
                return self._send(200, {"page": 1, "results": [detail(n) for n in range(1, 11)]})
            if parts[0] in ("movie", "tv") and len(parts) == 2 and parts[1].isdigit() \
                    and int(parts[1]) in MOVIES:
                return self._send(200, detail(int(parts[1])))
            return self._send(404, {"status_message": "not found"})

    return Handler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8098)
    ap.add_argument("--log", default="mock_tmdb.log")
    args = ap.parse_args()
    open(args.log, "w").close()
    server = HTTPServer(("127.0.0.1", args.port), make_handler(args.log))
    print("mock TMDB on http://127.0.0.1:%d/3, log: %s" % (args.port, args.log))
    sys.stdout.flush()
    server.serve_forever()


if __name__ == "__main__":
    main()
