#!/usr/bin/env python3
"""Loopback-only Emby contract fixture for the CineLark Postman collection."""

import argparse
import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


MOCK_TOKEN = "mock-access-token"
MOCK_USER_ID = "user-1"
PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


def user_data(state, item_id):
    return {
        "IsFavorite": item_id in state["favorite_item_ids"],
        "Played": item_id in state["played_item_ids"],
        "PlaybackPositionTicks": state["positions"].get(item_id, 0),
    }


def movie(state):
    return {
        "Id": "movie-1",
        "Name": "Arrival",
        "OriginalTitle": "Arrival",
        "Type": "Movie",
        "Overview": "A linguist works with the military to communicate with alien lifeforms.",
        "ProductionYear": 2016,
        "PremiereDate": "2016-09-01T00:00:00Z",
        "RunTimeTicks": 69600000000,
        "CommunityRating": 7.9,
        "ProviderIds": {"Tmdb": "329865", "Imdb": "tt2543164"},
        "ImageTags": {"Primary": "primary-v1", "Logo": "logo-v1"},
        "BackdropImageTags": ["backdrop-v1"],
        "UserData": user_data(state, "movie-1"),
        "People": [
            {"Id": "director-1", "Name": "Denis Villeneuve", "Type": "Director"},
            {
                "Id": "person-1",
                "Name": "Amy Adams",
                "Role": "Louise Banks",
                "Type": "Actor",
                "PrimaryImageTag": "person-v1",
            },
        ],
    }


def series(state):
    return {
        "Id": "series-1",
        "Name": "CineLark Test Series",
        "Type": "Series",
        "Overview": "A deterministic series fixture.",
        "ProductionYear": 2026,
        "ProviderIds": {"Tmdb": "100001"},
        "ImageTags": {"Primary": "series-primary-v1"},
        "UserData": user_data(state, "series-1"),
    }


def person():
    return {
        "Id": "person-1",
        "Name": "Amy Adams",
        "Type": "Person",
        "ProviderIds": {"Tmdb": "9273"},
        "ImageTags": {"Primary": "person-v1"},
    }


class MockState:
    def __init__(self):
        self.lock = threading.Lock()
        self.reset()

    def reset(self):
        self.favorite_item_ids = {"movie-1"}
        self.played_item_ids = set()
        self.positions = {"movie-1": 250000000}
        self.playback_events = []

    def snapshot(self):
        with self.lock:
            return {
                "favorite_item_ids": sorted(self.favorite_item_ids),
                "played_item_ids": sorted(self.played_item_ids),
                "positions": dict(self.positions),
                "playback_events": list(self.playback_events),
            }

    def values(self):
        return {
            "favorite_item_ids": self.favorite_item_ids,
            "played_item_ids": self.played_item_ids,
            "positions": self.positions,
        }


STATE = MockState()


class EmbyMockHandler(BaseHTTPRequestHandler):
    server_version = "CineLarkEmbyMock/1.0"

    def log_message(self, format_string, *args):
        print("[%s] %s" % (self.log_date_time_string(), format_string % args))

    def do_GET(self):
        self.route("GET")

    def do_POST(self):
        self.route("POST")

    def do_DELETE(self):
        self.route("DELETE")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Allow", "GET, POST, DELETE, OPTIONS")
        self.end_headers()

    def route(self, method):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)

        if path == "/__mock__/state" and method == "GET":
            return self.send_json(200, STATE.snapshot())
        if path == "/__mock__/reset" and method == "POST":
            with STATE.lock:
                STATE.reset()
            return self.send_json(200, STATE.snapshot())
        if path == "/emby/System/Info/Public" and method == "GET":
            return self.send_json(
                200,
                {
                    "Id": "cinelark-mock-server",
                    "ServerName": "CineLark Local Mock",
                    "Version": "4.9.0.0",
                    "LocalAddress": "http://127.0.0.1:8097/emby",
                },
            )
        if path == "/emby/Users/AuthenticateByName" and method == "POST":
            body = self.read_json()
            if body.get("Username") != "mock" or body.get("Pw") != "mock":
                return self.send_json(401, {"error": "Invalid credentials"})
            return self.send_json(
                200,
                {
                    "AccessToken": MOCK_TOKEN,
                    "ServerId": "cinelark-mock-server",
                    "User": {"Id": MOCK_USER_ID, "Name": "Mock User"},
                },
            )

        if not self.is_authorized():
            return self.send_json(401, {"error": "Missing or invalid Emby token"})

        if path == "/emby/Users/%s/Views" % MOCK_USER_ID and method == "GET":
            return self.send_json(
                200,
                {
                    "Items": [
                        {
                            "Id": "movies",
                            "Name": "Movies",
                            "Type": "CollectionFolder",
                            "CollectionType": "movies",
                            "ChildCount": 1,
                        },
                        {
                            "Id": "series",
                            "Name": "TV Shows",
                            "Type": "CollectionFolder",
                            "CollectionType": "tvshows",
                            "ChildCount": 1,
                        },
                    ],
                    "TotalRecordCount": 2,
                },
            )

        if path == "/emby/Users/%s/Items/Latest" % MOCK_USER_ID and method == "GET":
            return self.send_json(200, [movie(STATE.values()), series(STATE.values())])

        if path == "/emby/Users/%s/Items/Resume" % MOCK_USER_ID and method == "GET":
            return self.send_json(
                200,
                {"Items": [movie(STATE.values())], "TotalRecordCount": 1},
            )

        items_prefix = "/emby/Users/%s/Items/" % MOCK_USER_ID
        if path.startswith(items_prefix) and method == "GET":
            item_id = path[len(items_prefix) :]
            values = {
                "movie-1": movie(STATE.values()),
                "series-1": series(STATE.values()),
                "person-1": person(),
            }
            if item_id in values:
                return self.send_json(200, values[item_id])
            return self.send_json(404, {"error": "Item not found"})

        if path == "/emby/Users/%s/Items" % MOCK_USER_ID and method == "GET":
            return self.send_json(200, self.query_items(query))

        if path == "/emby/Shows/series-1/Seasons" and method == "GET":
            return self.send_json(
                200,
                {
                    "Items": [
                        {
                            "Id": "season-1",
                            "Name": "Season 1",
                            "Type": "Season",
                            "IndexNumber": 1,
                            "ChildCount": 1,
                            "ImageTags": {"Primary": "season-v1"},
                            "UserData": {"Played": False, "PlaybackPositionTicks": 0},
                        }
                    ],
                    "TotalRecordCount": 1,
                },
            )

        if path == "/emby/Shows/series-1/Episodes" and method == "GET":
            return self.send_json(
                200,
                {
                    "Items": [
                        {
                            "Id": "episode-1",
                            "Name": "Pilot",
                            "Type": "Episode",
                            "SeriesId": "series-1",
                            "SeasonId": "season-1",
                            "IndexNumber": 1,
                            "Overview": "The first fixture episode.",
                            "RunTimeTicks": 36000000000,
                            "MediaSourceCount": 1,
                            "ImageTags": {"Primary": "episode-v1"},
                            "UserData": {"Played": False, "PlaybackPositionTicks": 0},
                        }
                    ],
                    "TotalRecordCount": 1,
                },
            )

        if path == "/emby/Items/movie-1/PlaybackInfo" and method == "POST":
            return self.send_json(
                200,
                {
                    "MediaSources": [
                        {
                            "Id": "media-source-1",
                            "Name": "Direct Play Fixture",
                            "Path": "/fixtures/arrival.mkv",
                            "Container": "mkv",
                            "SupportsDirectPlay": True,
                            "SupportsDirectStream": True,
                            "DirectStreamUrl": "Videos/movie-1/stream?static=true&MediaSourceId=media-source-1",
                        }
                    ],
                    "PlaySessionId": "play-session-1",
                },
            )

        if path in {
            "/emby/Sessions/Playing",
            "/emby/Sessions/Playing/Progress",
            "/emby/Sessions/Playing/Stopped",
        } and method == "POST":
            body = self.read_json()
            with STATE.lock:
                STATE.playback_events.append({"path": path, "body": body})
                item_id = body.get("ItemId")
                if item_id:
                    STATE.positions[item_id] = int(body.get("PositionTicks", 0))
            return self.send_empty(204)

        favorite_prefix = "/emby/Users/%s/FavoriteItems/" % MOCK_USER_ID
        if path.startswith(favorite_prefix) and method in {"POST", "DELETE"}:
            item_id = path[len(favorite_prefix) :]
            with STATE.lock:
                if method == "POST":
                    STATE.favorite_item_ids.add(item_id)
                else:
                    STATE.favorite_item_ids.discard(item_id)
            return self.send_empty(204)

        played_prefix = "/emby/Users/%s/PlayedItems/" % MOCK_USER_ID
        if path.startswith(played_prefix) and method in {"POST", "DELETE"}:
            item_id = path[len(played_prefix) :]
            with STATE.lock:
                if method == "POST":
                    STATE.played_item_ids.add(item_id)
                else:
                    STATE.played_item_ids.discard(item_id)
            return self.send_empty(204)

        if path.startswith("/emby/Items/") and "/Images/" in path and method == "GET":
            return self.send_bytes(200, "image/png", PNG_1X1)

        if path.startswith("/emby/Videos/") and path.endswith("/stream") and method == "GET":
            return self.send_json(501, {"error": "Media streaming is outside the mock contract"})

        return self.send_json(404, {"error": "Unhandled mock route", "method": method, "path": path})

    def query_items(self, query):
        state = STATE.values()
        values = [movie(state), series(state)]
        include_types = set(
            value.strip().lower()
            for item in query.get("IncludeItemTypes", [])
            for value in item.split(",")
            if value.strip()
        )
        if include_types:
            values = [item for item in values if item["Type"].lower() in include_types]
        search_term = query.get("SearchTerm", [""])[0].strip().lower()
        if search_term:
            values = [item for item in values if search_term in item["Name"].lower()]
        if query.get("IsFavorite", [""])[0].lower() == "true":
            values = [item for item in values if item["UserData"]["IsFavorite"]]
        if "IsResumable" in query.get("Filters", []):
            values = [item for item in values if item["UserData"]["PlaybackPositionTicks"] > 0]
        if query.get("PersonIds"):
            values = [movie(state)]
        start = int(query.get("StartIndex", ["0"])[0])
        limit = int(query.get("Limit", [str(len(values) or 1)])[0])
        return {"Items": values[start : start + limit], "TotalRecordCount": len(values)}

    def is_authorized(self):
        value = self.headers.get("X-Emby-Authorization", "")
        return 'Token="%s"' % MOCK_TOKEN in value

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length == 0:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}

    def send_json(self, status, value):
        payload = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_bytes(status, "application/json; charset=utf-8", payload)

    def send_empty(self, status):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def send_bytes(self, status, content_type, payload):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8097)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), EmbyMockHandler)
    print("CineLark Emby mock listening on http://127.0.0.1:%d/emby" % args.port)
    print("Credentials: mock / mock")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping mock server")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
