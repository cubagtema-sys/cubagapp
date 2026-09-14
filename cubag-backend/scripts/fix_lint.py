FLUTTER_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/admin_documents_page.dart"

with open(FLUTTER_FILE, "r", encoding="utf-8") as f:
    text = f.read()

# Replace multiple underscores with named unused variables
text = text.replace("(_, __)", "(_, index)")

with open(FLUTTER_FILE, "w", encoding="utf-8") as f:
    f.write(text)

print("Replaced (_, __) occurrences.")
