#!/bin/bash
# Update vendor/xiaomi/piano and the pins in this device tree to a new
# HyperOS China stable release. Run by .github/workflows/hyperos-update.yml
# from the root of a workspace that has this tree at device/xiaomi/piano.
set -euo pipefail

ROOT=$PWD
DEV=$ROOT/device/xiaomi/piano
VEN=$ROOT/vendor/xiaomi/piano
WORK=$ROOT/work
ORG=xiaomi-pad-8-pro-development
VENDOR_REPO=$ORG/android_vendor_xiaomi_piano
# The extract-utils and prebuilts commits the ROM trees use (lineage-24.0).
EXTRACT_UTILS=78ba5d58c4b06712e18bb387a2a72eac8fbc8d70
EXTRACT_TOOLS=aaeb969a477321411279c03799f45ae9f94f770b
TRACKER=https://raw.githubusercontent.com/XiaomiFirmwareUpdater/miui-updates-tracker/master/data/latest.yml
AUTHOR_NAME='MUHAMMAD ALIF DANIEL BIN MOHD HAIRUL HEZZELIN'
AUTHOR_EMAIL=alifdaniel.personalspace@gmail.com
mkdir -p "$WORK"

current=$(sed -n '1s/.*China \(OS[0-9.]*\.[A-Z]*\).*/\1/p' "$DEV/proprietary-files.txt")
echo "Current: $current"

# Pick the newest piano China stable recovery package for Android 17.
curl -fsSL "$TRACKER" -o "$WORK/latest.yml"
python3 - "$WORK/latest.yml" "${FORCE_VERSION:-}" > "$WORK/target.env" <<'EOF'
import sys, yaml
rows = yaml.safe_load(open(sys.argv[1]))
force = sys.argv[2]
rows = [r for r in rows if r.get('codename') == 'piano' and r.get('method') == 'Recovery'
        and str(r.get('android', '')).startswith('17') and r.get('branch') == 'Stable']
if force:
    rows = [r for r in rows if r['version'] == force]
if not rows:
    sys.exit('No matching piano release in the tracker')
key = lambda r: tuple(int(x) for x in r['version'][2:].split('.')[:4])
r = max(rows, key=key)
print(f"VERSION={r['version']}\nURL={r['link']}\nMD5={r['md5']}")
EOF
. "$WORK/target.env"
echo "Latest: $VERSION"

newer=$(python3 -c "
import sys
k=lambda v: tuple(int(x) for x in v[2:].split('.')[:4])
print(int(k('$VERSION') > k('$current')))")
if [ "$newer" != 1 ] && [ -z "${FORCE_VERSION:-}" ]; then
    echo "Already on $current; nothing to do."
    exit 0
fi
BRANCH=auto/$VERSION
if [ "$DRY_RUN" != true ] && git -C "$DEV" ls-remote --exit-code origin "refs/heads/$BRANCH" >/dev/null; then
    echo "Branch $BRANCH already exists; a pull request is open or was handled."
    exit 0
fi

# Room for the 10 GB package plus the unpacked partitions.
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache /usr/local/share/boost
sudo apt-get -qq update
sudo apt-get -qq install -y erofs-utils aria2 git-lfs >/dev/null
df -h "$ROOT" | tail -1

# The trees extract-utils expects.
mkdir -p "$ROOT/tools" "$ROOT/prebuilts"
git clone -q --filter=blob:none https://github.com/LineageOS/android_tools_extract-utils "$ROOT/tools/extract-utils"
git -C "$ROOT/tools/extract-utils" checkout -q $EXTRACT_UTILS
git init -q "$ROOT/prebuilts/extract-tools"
git -C "$ROOT/prebuilts/extract-tools" fetch -q --depth 1 https://github.com/LineageOS/android_prebuilts_extract-tools $EXTRACT_TOOLS
git -C "$ROOT/prebuilts/extract-tools" checkout -q FETCH_HEAD
git clone -q --depth 1 -b "$BASE_BRANCH" "https://github.com/$VENDOR_REPO" "$VEN"
git -C "$VEN" lfs install --local >/dev/null
git -C "$VEN" lfs pull

# Download and unpack.
aria2c -q -x 16 -s 16 -d "$WORK" -o ota.zip "$URL"
echo "$MD5  $WORK/ota.zip" | md5sum -c -
FW=$(grep -v '^#' "$DEV/proprietary-firmware.txt" | sed -n 's/\.img;.*//p' | tr '\n' ',')
PARTS=$(grep -v '^#' "$DEV/proprietary-files.txt" | sed 's/^-//' | cut -d/ -f1 | sort -u | tr '\n' ',')
mkdir -p "$WORK/images" "$WORK/dump"
# payload.bin is stored uncompressed; hand ota_extractor its offset in the zip.
OFFSET=$(python3 - "$WORK/ota.zip" <<'EOF'
import struct, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
i = z.getinfo('payload.bin')
assert i.compress_type == zipfile.ZIP_STORED
with open(sys.argv[1], 'rb') as f:
    f.seek(i.header_offset)
    h = f.read(30)
    n, e = struct.unpack('<HH', h[26:30])
print(i.header_offset + 30 + n + e)
EOF
)
"$ROOT/prebuilts/extract-tools/linux-x86/bin/ota_extractor" \
    -payload "$WORK/ota.zip" -payload_offset "$OFFSET" -output_dir "$WORK/images" -partitions "${PARTS}${FW%,}"
rm -f "$WORK/ota.zip"
for p in ${PARTS//,/ }; do
    fsck.erofs --extract="$WORK/dump/$p" "$WORK/images/$p.img" >/dev/null
    rm -f "$WORK/images/$p.img"
done
for f in ${FW//,/ }; do
    mv "$WORK/images/$f.img" "$WORK/dump/$f.img"
done

# Re-pin every stock input to the new release; list what disappeared.
python3 - "$DEV/proprietary-files.txt" "$WORK/dump" "$VERSION" > "$WORK/pins.txt" <<'EOF'
import hashlib, re, sys
from pathlib import Path
path, src, ver = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
out, missing, changed = [], [], 0
for line in path.read_text().splitlines():
    if not line or line.startswith('#'):
        out.append(re.sub(r'China OS[0-9.]+\.[A-Z]+', f'China {ver}', line))
        continue
    parts = line.split('|')
    name = parts[0].lstrip('-').split(';')[0].split(':')[0]
    f = src / name
    if not f.is_file():
        missing.append(name)
        out.append(line)
        continue
    h = hashlib.sha1(f.read_bytes()).hexdigest()
    if len(parts) > 1 and parts[1] != h:
        parts[1] = h
        changed += 1
    out.append('|'.join(parts))
path.write_text('\n'.join(out) + '\n')
print(f'CHANGED={changed}')
print(f'MISSING={len(missing)}')
for m in missing:
    print(f'#missing {m}')
EOF
cat "$WORK/pins.txt" | head -60
if grep -q '^MISSING=[1-9]' "$WORK/pins.txt"; then
    echo "The new release dropped pinned files; this needs a person." >&2
    exit 1
fi
sed -i "s/offline OS[0-9.]*\.[A-Z]* dump/offline $VERSION dump/" "$DEV/extract-files.py"
sed -i "s/^# Firmware shipped with the ROM, from piano OS[0-9.]*\.[A-Z]*/# Firmware shipped with the ROM, from piano $VERSION/" "$DEV/proprietary-firmware.txt"
sed -i "s/HyperOS 4 China \`OS[0-9.]*\.[A-Z]*\`/HyperOS 4 China \`$VERSION\`/" "$DEV/README.md" "$VEN/README.md"

# The vendor security patch level follows the blobs.
SPL=$(sed -n 's/^ro.vendor.build.security_patch=//p' "$WORK/dump/vendor/build.prop")
[ -n "$SPL" ] && sed -i "s/^VENDOR_SECURITY_PATCH := .*/VENDOR_SECURITY_PATCH := $SPL/" "$DEV/BoardConfig.mk"

(cd "$DEV" && PYTHONPATH=../../../tools/extract-utils python3 ./extract-files.py "$WORK/dump") > "$WORK/extract.log" 2>&1 \
    || { tail -40 "$WORK/extract.log"; exit 1; }

# Only the blobs change: keep the hand-kept vendor makefiles (the source audio
# HAL replaces the stock libar-pal module) and files outside the lists.
git -C "$VEN" checkout -- Android.bp piano-vendor.mk
git -C "$VEN" ls-files -d -z | xargs -0 -r git -C "$VEN" checkout --

{
    echo "HyperOS China \`$current\` to \`$VERSION\`, from [the tracker]($URL)."
    echo
    echo "- $(sed -n 's/CHANGED=//p' "$WORK/pins.txt") pinned blobs changed"
    echo "- $(git -C "$VEN" status --porcelain radio | wc -l) firmware images changed"
    echo "- Vendor security patch: ${SPL:-unknown}"
    echo
    echo "Build and boot-test before merging. Check that \`BOOT_SECURITY_PATCH\` matches the stock boot image, and rebuild recovery so decryption keeps working."
} > "$WORK/summary.md"
cat "$WORK/summary.md"
git -C "$DEV" status --short | head -20
git -C "$VEN" status --short | wc -l

[ "$DRY_RUN" = true ] && { echo "Dry run: no pull requests."; exit 0; }

commit() {
    git -C "$1" checkout -q -b "$BRANCH"
    git -C "$1" add -A
    git -C "$1" -c user.name="$AUTHOR_NAME" -c user.email="$AUTHOR_EMAIL" \
        commit -q -m "piano: Update blobs to $VERSION" -m "Generated by the HyperOS update workflow."
}
commit "$VEN"
git -C "$VEN" push -q "https://x-access-token:$VENDOR_TOKEN@github.com/$VENDOR_REPO" "$BRANCH"
GH_TOKEN=$VENDOR_TOKEN gh pr create -R "$VENDOR_REPO" -B "$BASE_BRANCH" -H "$BRANCH" \
    -t "piano: Update blobs to $VERSION" -F "$WORK/summary.md"
commit "$DEV"
git -C "$DEV" push -q origin "$BRANCH"
gh pr create -R "$GITHUB_REPOSITORY" -B "$BASE_BRANCH" -H "$BRANCH" \
    -t "piano: Update blobs to $VERSION" -F "$WORK/summary.md"
