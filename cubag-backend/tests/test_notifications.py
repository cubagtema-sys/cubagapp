import pytest


def test_notifications_route_exists(client):
    resp = client.options('/api/v1/notifications/')
    assert resp.status_code != 404, 'Notifications route not found — check /api/v1/ versioning'


def test_notifications_unread_count_requires_auth(client):
    resp = client.get('/api/v1/notifications/unread-count')
    assert resp.status_code in (401, 403)


def test_notifications_mark_read_requires_auth(client):
    resp = client.post('/api/v1/notifications/mark-read', json={})
    assert resp.status_code in (401, 403)
