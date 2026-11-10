"""In-memory stand-in for psycopg2 used by the security regression tests.

Tests register responders: ``FAKE_DB.on(regex, rows_or_callable)``. Every SQL
statement executed by the app is matched against responders (latest first);
unmatched statements return no rows. All executed statements are recorded in
``FAKE_DB.log`` so tests can assert that something was (or was NOT) written.
"""
import re


class FakeDB:
    def __init__(self):
        self.reset()

    def reset(self):
        self.responders = []
        self.log = []

    def on(self, pattern, result):
        self.responders.append((re.compile(pattern, re.I | re.S), result))

    def respond(self, sql, params):
        norm = ' '.join(str(sql).split())
        self.log.append((norm, params))
        for rx, result in reversed(self.responders):
            if rx.search(norm):
                rows = result(params) if callable(result) else result
                return [dict(r) for r in (rows or [])]
        return []

    def executed(self, pattern):
        rx = re.compile(pattern, re.I | re.S)
        return [(s, p) for s, p in self.log if rx.search(s)]


FAKE_DB = FakeDB()


class FakeCursor:
    def __init__(self):
        self._rows = []
        self.rowcount = 0
        self.description = None

    def execute(self, sql, params=None):
        self._rows = FAKE_DB.respond(sql, params)
        self.rowcount = len(self._rows)

    def executemany(self, sql, seq):
        for p in seq:
            self.execute(sql, p)

    def fetchone(self):
        return self._rows.pop(0) if self._rows else None

    def fetchall(self):
        rows, self._rows = self._rows, []
        return rows

    def fetchmany(self, n=1):
        rows, self._rows = self._rows[:n], self._rows[n:]
        return rows

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def __iter__(self):
        return iter(self.fetchall())


class FakeConnection:
    closed = 0
    autocommit = False

    def cursor(self, *a, **k):
        return FakeCursor()

    def commit(self):
        FAKE_DB.log.append(('COMMIT', None))

    def rollback(self):
        FAKE_DB.log.append(('ROLLBACK', None))

    def close(self):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False
