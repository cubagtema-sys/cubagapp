"""Uploads must never silently land on the live server's (deploy-wiped) disk."""
import pytest

import file_storage as fs


def _fail_upload(calls):
    def fake(*a, **k):
        calls.append(1)
        return None
    return fake


def test_live_server_refuses_local_fallback(monkeypatch):
    calls = []
    monkeypatch.setenv('FLY_APP_NAME', 'cubag-api-server')
    monkeypatch.setattr(fs, '_upload_to_supabase', _fail_upload(calls))
    saved_local = []
    monkeypatch.setattr(fs, '_save_local', lambda *a, **k: saved_local.append(1) or '/static/uploads/x')
    with pytest.raises(fs.UploadStorageError):
        fs.save_file(b'data', 'slip.jpg', subfolder='receipts')
    assert len(calls) == 2, 'cloud upload should be retried once'
    assert saved_local == [], 'must not write to the ephemeral disk'


def test_retry_succeeds_after_one_blip(monkeypatch):
    monkeypatch.setenv('FLY_APP_NAME', 'cubag-api-server')
    results = iter([None, 'https://x.supabase.co/storage/v1/object/public/uploads/receipts/a.jpg'])
    monkeypatch.setattr(fs, '_upload_to_supabase', lambda *a, **k: next(results))
    url = fs.save_file(b'data', 'slip.jpg', subfolder='receipts')
    assert url.startswith('https://x.supabase.co/')


def test_local_fallback_still_works_in_development(monkeypatch):
    monkeypatch.delenv('FLY_APP_NAME', raising=False)
    monkeypatch.delenv('REQUIRE_CLOUD_STORAGE', raising=False)
    monkeypatch.setattr(fs, '_upload_to_supabase', lambda *a, **k: None)
    monkeypatch.setattr(fs, '_save_local', lambda b, sub, name: f'/static/uploads/{sub}/{name}')
    assert fs.save_file(b'data', 'slip.jpg', subfolder='receipts').startswith('/static/uploads/receipts/')


def test_failed_storage_check_is_retested_after_a_minute(monkeypatch):
    checks = []

    def fake_test():
        checks.append(1)
        fs._supabase_ok = len(checks) > 1  # down first, up on the re-check
        return fs._supabase_ok

    monkeypatch.setattr(fs, '_test_supabase', fake_test)
    monkeypatch.setattr(fs, '_supabase_ok', None)
    t = [1000.0]
    import time
    monkeypatch.setattr(time, 'monotonic', lambda: t[0])
    assert fs.supabase_available() is False
    t[0] += 10
    assert fs.supabase_available() is False and len(checks) == 1  # cached briefly
    t[0] += 61
    assert fs.supabase_available() is True and len(checks) == 2  # re-tested
