#!/usr/bin/env python3
"""Generate the deterministic database-browser fixture."""

from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile


fixture = Path(__file__).with_name("fixture")
fixture.mkdir(exist_ok=True)
destination = fixture / "bookstore.db"
with tempfile.NamedTemporaryFile(dir=fixture, suffix=".db", delete=False) as pending:
    generated = Path(pending.name)
try:
    # The connection context manager only commits; Windows cannot replace a
    # database file until its connection is closed.
    with closing(sqlite3.connect(generated)) as database, database:
        database.executescript("""
            CREATE TABLE books(id INTEGER PRIMARY KEY, title TEXT NOT NULL, price REAL, cover BLOB, note TEXT);
            CREATE TABLE authors(id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE loans(id INTEGER PRIMARY KEY, book INTEGER NOT NULL, day INTEGER NOT NULL);
        """)
        database.executemany(
            "INSERT INTO books VALUES (?, ?, ?, ?, ?)",
            ((identifier, f"Book {identifier:05d}", (identifier % 100) * 1.25,
              b"\x01\x02\x03" if identifier % 10 == 0 else None,
              None if identifier % 7 == 0 else "available")
             for identifier in range(1, 10_001)),
        )
        database.executemany("INSERT INTO authors VALUES (?, ?)", ((1, "Ada"), (2, "Grace")))
        # Ten times the host's row limit, so reading every loan takes pages.
        database.executemany(
            "INSERT INTO loans VALUES (?, ?, ?)",
            ((identifier, (identifier * 7919) % 10_000 + 1, identifier // 40)
             for identifier in range(1, 100_001)),
        )
    generated.replace(destination)
finally:
    generated.unlink(missing_ok=True)
