"""Parsing and durable state for the optional Survivor League Discord relay."""
import hashlib
import re
import sqlite3
from urllib.parse import unquote

MARKER = re.compile(r"\[(SurvivorLeague(?:Kill|Death|CommunityJoin|Snapshot|SnapshotRow|SnapshotEnd)|SurvivorLeagueCommunityAudit)\]\s*(.*)")


def fields(body):
    return dict(part.split("=", 1) for part in body.split(" | ") if "=" in part)


def parse(line):
    match = MARKER.search(line)
    if not match:
        return None
    kind, body = match.groups()
    if kind == "SurvivorLeagueCommunityAudit":
        if not body.startswith("Settlement completed | "):
            return None
        return kind, fields(body)
    if kind in ("SurvivorLeagueSnapshot", "SurvivorLeagueSnapshotRow", "SurvivorLeagueSnapshotEnd"):
        return kind, fields(body)
    return kind, body.strip()


def connect(path):
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS cursors (source TEXT PRIMARY KEY, offset INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS outbox (id TEXT PRIMARY KEY, kind TEXT NOT NULL, body TEXT NOT NULL, sent INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS snapshot (id INTEGER PRIMARY KEY CHECK(id=1), season INTEGER, started INTEGER, ends INTEGER, batch TEXT);
        CREATE TABLE IF NOT EXISTS standings (username TEXT PRIMARY KEY, display_name TEXT, rank INTEGER, kills INTEGER, total INTEGER, streak INTEGER, best INTEGER);
        CREATE TABLE IF NOT EXISTS batches (batch TEXT PRIMARY KEY, season INTEGER, started INTEGER, ends INTEGER, expected INTEGER);
        CREATE TABLE IF NOT EXISTS batch_rows (batch TEXT, username TEXT, display_name TEXT, rank INTEGER, kills INTEGER, total INTEGER, streak INTEGER, best INTEGER, PRIMARY KEY(batch, username));
    """)
    return db


def integer(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def ingest(db, source, offset, line, next_offset):
    """Commit each complete line and its cursor together. Never publish partial batches."""
    event = parse(line)
    with db:
        if event:
            kind, body = event
            if kind == "SurvivorLeagueSnapshot":
                if body.get("v") == "1" and body.get("batch"):
                    db.execute("INSERT OR IGNORE INTO batches VALUES (?,?,?,?,?)", (body["batch"], integer(body.get("season")), integer(body.get("started")), integer(body.get("ends")), integer(body.get("count"))))
            elif kind == "SurvivorLeagueSnapshotRow":
                batch = body.get("batch", "")
                if db.execute("SELECT 1 FROM batches WHERE batch=?", (batch,)).fetchone():
                    db.execute("INSERT OR REPLACE INTO batch_rows VALUES (?,?,?,?,?,?,?,?)", (batch, unquote(body.get("user", "")), unquote(body.get("name", "")), integer(body.get("rank")), integer(body.get("kills")), integer(body.get("total")), integer(body.get("streak")), integer(body.get("best"))))
            elif kind == "SurvivorLeagueSnapshotEnd":
                batch = body.get("batch", "")
                meta = db.execute("SELECT season,started,ends,expected FROM batches WHERE batch=?", (batch,)).fetchone()
                count = db.execute("SELECT count(*) FROM batch_rows WHERE batch=?", (batch,)).fetchone()[0]
                if meta and count == meta[3]:
                    db.execute("DELETE FROM standings")
                    db.execute("INSERT INTO standings SELECT username,display_name,rank,kills,total,streak,best FROM batch_rows WHERE batch=?", (batch,))
                    db.execute("INSERT OR REPLACE INTO snapshot VALUES (1,?,?,?,?)", (*meta[:3], batch))
                    db.execute("DELETE FROM batches")
                    db.execute("DELETE FROM batch_rows")
            else:
                body_text = body if isinstance(body, str) else str(body)
                event_id = hashlib.sha256(f"{source}:{offset}:{line}".encode()).hexdigest()
                db.execute("INSERT OR IGNORE INTO outbox(id,kind,body) VALUES (?,?,?)", (event_id, kind, body_text))
        db.execute("INSERT OR REPLACE INTO cursors VALUES (?,?)", (source, next_offset))


def leaderboard(db, limit=10):
    meta = db.execute("SELECT season,started,ends FROM snapshot WHERE id=1").fetchone()
    rows = db.execute("SELECT rank,display_name,kills,total,streak,best FROM standings ORDER BY rank LIMIT ?", (limit,)).fetchall()
    return meta, rows
