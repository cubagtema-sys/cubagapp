"""Every admin action that changes something writes to the audit log the
Audit page reads (audit_log, via log_audit / log_admin_action)."""
import glob
import re

# Routes that change data but are not admin actions, or log elsewhere.
EXEMPT = {
    ('news.py', '/test/refresh'),       # refreshes cached news only
}


def _admin_write_routes():
    for f in sorted(glob.glob('routes/*.py')):
        s = open(f).read()
        for part in re.split(r'\n(?=@\w+_bp\.route\()', s):
            m = re.match(r"@\w+_bp\.route\('([^']+)'(?:,\s*methods=\[([^\]]+)\])?", part)
            if not m or not re.search(r"'(POST|PUT|PATCH|DELETE)'", m.group(2) or ''):
                continue
            if not (re.search(r'@(admin_required|sub_admin_required|super_admin_required)', part[:400])
                    or '/admin' in m.group(1)):
                continue
            yield f.split('/')[-1], m.group(1), part


def test_admin_changes_are_audited():
    missing = [(f, r) for f, r, body in _admin_write_routes()
               if (f, r) not in EXEMPT and not re.search(r'log_audit\(|log_admin_action\(', body)]
    assert missing == []


def test_only_one_audit_table_is_written():
    import routes.admin as admin  # noqa: F401 (imports cleanly)
    writers = [f for f in glob.glob('routes/*.py') if 'INSERT INTO audit_log ' in open(f).read()]
    assert writers == []  # routes write through log_audit, which owns the INSERT
