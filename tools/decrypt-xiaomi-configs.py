#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: 2026 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Decrypts the Xiaomi battery anti-aging and mi_thermald configs so they can
# be read and compared. See docs/XIAOMI_CONFIGS.md.
#
# Usage: decrypt-xiaomi-configs.py <vendor/xiaomi/piano/proprietary> <out dir>

import base64
import os
import subprocess
import sys

# AES-128-CBC. Battery anti-aging: key from libbaa_common.so
# (AESEncryption::KEY), IV is the first 16 bytes of the base64 payload.
# mi_thermald: key and IV are the same string, from mi_thermald .data.
BAA_KEY = b"michargerbattery"
THERMAL_KEY = b"thermalopenssl.h"


def aes_cbc_decrypt(data, key, iv):
    return subprocess.run(
        ["openssl", "enc", "-d", "-aes-128-cbc", "-K", key.hex(), "-iv", iv.hex()],
        input=data,
        capture_output=True,
        check=True,
    ).stdout


def decrypt_baa(path):
    text = open(path, "rb").read().strip()
    if not text.startswith(b"BAA_ENC:"):
        return text
    raw = base64.b64decode(text[len(b"BAA_ENC:"):])
    return aes_cbc_decrypt(raw[16:], BAA_KEY, raw[:16])


def decrypt_thermal(path):
    return aes_cbc_decrypt(open(path, "rb").read(), THERMAL_KEY, THERMAL_KEY)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__ or "usage: decrypt-xiaomi-configs.py <proprietary> <out>")
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)

    jobs = []
    charger = os.path.join(src, "odm/etc/charger")
    if os.path.isdir(charger):
        jobs += [(os.path.join(charger, f), decrypt_baa)
                 for f in sorted(os.listdir(charger)) if f.startswith("BAA_config")]
    for d in ("odm/etc", "vendor/etc"):
        base = os.path.join(src, d)
        if os.path.isdir(base):
            jobs += [(os.path.join(base, f), decrypt_thermal)
                     for f in sorted(os.listdir(base))
                     if f.startswith("thermal") and f.endswith(".conf")]

    for path, fn in jobs:
        name = os.path.basename(path)
        try:
            data = fn(path)
        except subprocess.CalledProcessError:
            print(f"skip {name}: plain text or another key")
            continue
        open(os.path.join(out, name), "wb").write(data)
        print(f"ok   {name}")


if __name__ == "__main__":
    main()
