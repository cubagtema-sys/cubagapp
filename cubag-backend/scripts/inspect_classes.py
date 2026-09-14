import re

FLUTTER_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_documents_page.dart"

with open(FLUTTER_FILE, "r", encoding="utf-8") as f:
    content = f.read()

# Let's inspect where the duplicated content is
# Let's search for the classes
classes = [
    'class AdminDocumentsPage ',
    'class _AdminDocumentsPageState ',
    'class AdminMemberDocumentsPage ',
    'class _AdminMemberDocumentsPageState ',
    'class _DocTable ',
    'class _DocRow ',
    'class _ActionButton ',
    'class _PreviewPanel ',
    'class _ManageRequirementsDialog ',
    'class _ManageRequirementsDialogState ',
]

for c in classes:
    count = content.count(c)
    print(f"{c}: {count} occurrences")
