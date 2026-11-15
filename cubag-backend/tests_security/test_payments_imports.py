"""routes/payments.py uses json at module level (saving codes and bank splits)."""
import routes.payments as payments


def test_json_is_imported():
    assert 'json' in vars(payments)
