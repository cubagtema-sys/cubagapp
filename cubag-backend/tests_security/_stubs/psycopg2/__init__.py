"""Test-only psycopg2 stand-in (see tests_security/fakedb.py)."""
from fakedb import FakeConnection


class Error(Exception):
    pass


class OperationalError(Error):
    pass


class IntegrityError(Error):
    pass


class DatabaseError(Error):
    pass


class InterfaceError(Error):
    pass


class ProgrammingError(Error):
    pass


class errors:  # noqa: N801 - mimic module attribute
    UniqueViolation = IntegrityError


def connect(*a, **k):
    return FakeConnection()
