import os
import shutil

SRC = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag_flutter/build/web"
DST_STATIC = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag-backend/static"
DST_DIST = "/Users/guyman-gh/Downloads/CUB-26/CUSTOMS/cubag-backend/dist"

if not os.path.exists(SRC):
    print("build/web does not exist yet!")
    exit(1)

print("Copying build/web to static...")
for item in os.listdir(SRC):
    s = os.path.join(SRC, item)
    d = os.path.join(DST_STATIC, item)
    if os.path.isdir(s):
        if os.path.exists(d):
            shutil.rmtree(d)
        shutil.copytree(s, d)
    else:
        shutil.copy2(s, d)

print("Copying build/web to dist...")
for item in os.listdir(SRC):
    s = os.path.join(SRC, item)
    d = os.path.join(DST_DIST, item)
    if os.path.isdir(s):
        if os.path.exists(d):
            shutil.rmtree(d)
        shutil.copytree(s, d)
    else:
        shutil.copy2(s, d)

print("Sync completed successfully!")
