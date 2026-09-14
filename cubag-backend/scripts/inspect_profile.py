import os

PROFILE_FILE = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/lib/pages/profile_page.dart"

with open(PROFILE_FILE, "r", encoding="utf-8") as f:
    orig = f.read()

print("Original profile_page.dart length:", len(orig))
