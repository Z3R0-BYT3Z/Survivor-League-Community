import tempfile
import unittest
from pathlib import Path

from league import connect, ingest, leaderboard


class LeagueTest(unittest.TestCase):
    def test_snapshot_is_atomic_and_names_are_escaped(self):
        with tempfile.TemporaryDirectory() as folder:
            db = connect(str(Path(folder) / "test.sqlite"))
            lines = [
                "[SurvivorLeagueSnapshot] v=1 | batch=a | season=4 | started=10 | ends=100 | count=1\n",
                "[SurvivorLeagueSnapshotRow] batch=a | rank=1 | user=Zero | name=Z%7Cero%0A | kills=42 | total=100 | streak=9 | best=20\n",
            ]
            offset = 0
            for line in lines:
                ingest(db, "log", offset, line, offset + len(line))
                offset += len(line)
            self.assertEqual(leaderboard(db), (None, []))
            end = "[SurvivorLeagueSnapshotEnd] batch=a\n"
            ingest(db, "log", offset, end, offset + len(end))
            meta, rows = leaderboard(db)
            self.assertEqual(meta, (4, 10, 100))
            self.assertEqual(rows[0], (1, "Z|ero\n", 42, 100, 9, 20))

    def test_outbox_deduplicates_replayed_event(self):
        with tempfile.TemporaryDirectory() as folder:
            db = connect(str(Path(folder) / "test.sqlite"))
            line = "LOG : General> [SurvivorLeagueDeath] Zero died\n"
            ingest(db, "log", 10, line, 10 + len(line))
            ingest(db, "log", 10, line, 10 + len(line))
            self.assertEqual(db.execute("SELECT count(*) FROM outbox").fetchone()[0], 1)


if __name__ == "__main__":
    unittest.main()
