#!/bin/bash
# release_update.sh
# Publishes a new update for SkunkCrafts Updater users:
#   1. uploads your changed aircraft files to GitHub
#   2. rebuilds the SkunkCrafts file lists (checksums + sizes) and sets the version number you type in
#   3. uploads the lists last, so users never see a new version before its files are online
# Place this file in the aircraft root folder (next to tu154.acf) and run:  bash release_update.sh

set -e
REPO_URL="https://github.com/niko-230/Tu-154M_v3.X.git"
cd "$(dirname "$0")"

for f in skunkcrafts_updater.cfg push_to_github.sh .gitignore; do
  [ -f "$f" ] || { echo "Missing $f in this folder. Nothing was changed."; exit 1; }
done
command -v python3 >/dev/null || { echo "python3 not found. Run:  xcode-select --install   then try again."; exit 1; }

OLDVER=$(grep -m1 '^version|' skunkcrafts_updater.cfg | cut -d'|' -f2 | tr -d '\r')
echo "Current version shown in SkunkCrafts: ${OLDVER:-none}"
while true; do
  read -r -p "New version (e.g. 3.0.1): " NEWVER
  NEWVER=$(echo "$NEWVER" | tr -d '[:space:]')
  if [ -z "$NEWVER" ]; then echo "   Please type a version."; continue; fi
  case "$NEWVER" in *"|"*) echo "   The | character is not allowed."; continue;; esac
  if [ "$NEWVER" = "$OLDVER" ]; then echo "   That is the current version. Type a different one so users see the update."; continue; fi
  break
done
echo

# Retired files: anything listed in skunkcrafts_updater_blacklist.txt is removed
# from this folder automatically (so it also disappears from GitHub and from the
# update lists), and SkunkCrafts uses the same blacklist to remove it from users.
if [ -f skunkcrafts_updater_blacklist.txt ]; then
  echo "== Removing retired files listed in skunkcrafts_updater_blacklist.txt =="
  python3 - << 'PY'
import os
root = os.path.realpath(os.getcwd())
removed = 0
dirs = set()
for line in open("skunkcrafts_updater_blacklist.txt", encoding="utf-8"):
    p = line.strip().replace("\\", "/")
    if not p or p.startswith("#"):
        continue
    full = os.path.realpath(os.path.join(root, p))
    if not full.startswith(root + os.sep):      # never touch anything outside this folder
        continue
    if os.path.isfile(full):
        os.remove(full)
        removed += 1
        dirs.add(os.path.dirname(full))
# remove folders that are now empty (macOS .DS_Store files don't count)
for d in sorted(dirs, key=len, reverse=True):
    while d.startswith(root + os.sep):
        try:
            for junk in (".DS_Store",):
                jp = os.path.join(d, junk)
                if os.path.isfile(jp):
                    os.remove(jp)
            os.rmdir(d)
        except OSError:
            break
        d = os.path.dirname(d)
print(f"   {removed} retired files removed" if removed else "   nothing to remove (already gone)")
PY
  echo
fi

echo "== Step 1 of 3: building the new update lists =="
TMP=$(mktemp -d)
python3 - "$TMP" << 'PY'
import os, sys, zlib, subprocess
tmp = sys.argv[1]
skip_exact = {".gitignore", ".gitattributes", "push_to_github.sh", "release_update.sh", "skunkcrafts_updater.cfg"}
out = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                     capture_output=True, check=True).stdout
paths = sorted({p.decode("utf-8") for p in out.split(b"\0") if p})
white, sizes = [], []
for p in paths:
    if p in skip_exact or p.startswith(".github/") or p.startswith("skunkcrafts_updater") or not os.path.isfile(p):
        continue
    crc = 0
    with open(p, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            crc = zlib.crc32(chunk, crc)
    white.append(f"{p}|{crc & 0xFFFFFFFF}")
    sizes.append(f"{p}|{os.path.getsize(p)}")
open(os.path.join(tmp, "skunkcrafts_updater_whitelist.txt"), "w", newline="\n").write("\n".join(white) + "\n")
open(os.path.join(tmp, "skunkcrafts_updater_sizeslist.txt"), "w", newline="\n").write("\n".join(sizes) + "\n")
print(f"   {len(white)} files listed")
PY
echo

echo "== Step 2 of 3: uploading the aircraft files =="
bash push_to_github.sh "$REPO_URL"
echo

echo "== Step 3 of 3: publishing the new version number =="
mv "$TMP/skunkcrafts_updater_whitelist.txt" "$TMP/skunkcrafts_updater_sizeslist.txt" .
rmdir "$TMP"
NEWVER="$NEWVER" python3 - << 'PY'
import os
ver = os.environ["NEWVER"]
lines = open("skunkcrafts_updater.cfg").read().splitlines()
found = False
for i, l in enumerate(lines):
    if l.startswith("version|"):
        lines[i] = f"version|{ver}"
        found = True
if not found:
    lines.append(f"version|{ver}")
open("skunkcrafts_updater.cfg", "w", newline="\n").write("\n".join(lines) + "\n")
PY
bash push_to_github.sh "$REPO_URL"
echo
echo "Update published: version $NEWVER. Users get it the next time they run SkunkCrafts Updater."
