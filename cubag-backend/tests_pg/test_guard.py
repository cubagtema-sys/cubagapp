"""The production guard itself — runs everywhere, needs no database."""
from conftest import is_safe_test_dsn


def test_local_test_database_is_accepted():
    assert is_safe_test_dsn('host=127.0.0.1 port=5432 user=postgres dbname=cubag_test')
    assert is_safe_test_dsn('postgresql://postgres@localhost:5432/cubag_test')


def test_remote_or_non_test_databases_are_refused():
    assert not is_safe_test_dsn('')
    assert not is_safe_test_dsn('postgresql://u:p@aws-1-eu-west-1.pooler.supabase.com:6543/postgres')
    assert not is_safe_test_dsn('postgresql://u:p@aws-1-eu-west-1.pooler.supabase.com:6543/cubag_test')
    assert not is_safe_test_dsn('host=127.0.0.1 dbname=postgres')
    assert not is_safe_test_dsn('host=db.internal dbname=cubag_test')
