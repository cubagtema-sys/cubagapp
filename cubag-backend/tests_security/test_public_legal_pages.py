"""
Tests for public legal and compliance web pages:
- /privacy (Privacy Policy)
- /terms (Terms of Service)
- /delete-account (Account Deletion Request Form & Submission)
"""

import json
import pytest
from server import app
from config.db import get_db

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


def test_privacy_policy_html(client):
    """GET /privacy should render the responsive Privacy Policy HTML page."""
    res = client.get('/privacy')
    assert res.status_code == 200
    assert 'text/html' in res.content_type
    html = res.data.decode('utf-8')
    assert 'Privacy Policy' in html
    assert 'Data Protection Act, 2012 (Act 843)' in html
    assert 'Hubtel' in html
    assert 'Paystack' in html
    assert 'support@cubag.org' in html
    assert '/delete-account' in html


def test_privacy_policy_json(client):
    """GET /api/v1/public/privacy with Accept: application/json returns structured metadata."""
    res = client.get('/api/v1/public/privacy', headers={'Accept': 'application/json'})
    assert res.status_code == 200
    data = res.get_json()
    assert data['data_controller'] == 'Customs Brokers Association of Ghana (CUBAG)'
    assert 'Act 843' in data['jurisdiction']
    assert data['contact_email'] == 'support@cubag.org'


def test_terms_of_service_html(client):
    """GET /terms should render the Terms of Service HTML page."""
    res = client.get('/terms')
    assert res.status_code == 200
    assert 'text/html' in res.content_type
    html = res.data.decode('utf-8')
    assert 'Terms of Service' in html
    assert 'Customs Act, 2015 (Act 891)' in html
    assert 'Alternative Dispute Resolution Act' in html


def test_delete_account_get_html(client):
    """GET /delete-account should render the interactive web deletion request form."""
    res = client.get('/delete-account')
    assert res.status_code == 200
    assert 'text/html' in res.content_type
    html = res.data.decode('utf-8')
    assert 'Account &amp; Data Deletion Request' in html or 'Account & Data Deletion Request' in html
    assert '<form' in html
    assert 'name="email"' in html
    assert 'name="confirm_deletion"' in html


def test_delete_account_post_json(client):
    """POST /delete-account with JSON should record deletion request and return tracking code."""
    payload = {
        'full_name': 'Kofi Mensah',
        'email': 'kofi.mensah.test@example.com',
        'phone': '+233241234567',
        'license_number': 'CUBAG-TEST-001',
        'reason': 'leaving_profession',
        'notes': 'No longer practicing in Tema port.',
        'confirm_deletion': True
    }
    res = client.post('/delete-account', json=payload)
    assert res.status_code == 201
    data = res.get_json()
    assert data['success'] is True
    assert 'tracking_code' in data
    assert data['tracking_code'].startswith('DEL-')
    assert data['status'] == 'pending'


def test_delete_account_post_form(client):
    """POST /delete-account with URL-encoded form data should render confirmation receipt."""
    form_data = {
        'full_name': 'Ama Osei',
        'email': 'ama.osei.test@example.com',
        'phone': '+233209876543',
        'license_number': 'GRA-CHA-9988',
        'reason': 'duplicate_account',
        'confirm_deletion': 'yes'
    }
    res = client.post('/delete-account', data=form_data)
    assert res.status_code == 200
    assert 'text/html' in res.content_type
    html = res.data.decode('utf-8')
    assert 'Account Deletion Request Logged' in html
    assert 'Reference Tracking Code' in html
    assert 'ama.osei.test@example.com' in html


def test_delete_account_missing_email(client):
    """POST /delete-account without email should fail validation."""
    res = client.post('/delete-account', json={'confirm_deletion': True})
    assert res.status_code == 400
    data = res.get_json()
    assert data['success'] is False
    assert 'Email address is required' in data['message']


def test_delete_account_missing_confirmation(client):
    """POST /delete-account with form without confirmation checkbox should fail."""
    res = client.post('/delete-account', data={'email': 'test@example.com'})
    assert res.status_code == 400
    html = res.data.decode('utf-8')
    assert 'Unable to Process Request' in html
    assert 'confirm' in html
