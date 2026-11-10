# Xiaomi battery and thermal configs

Two stock Xiaomi services read encrypted config files: battery anti-aging
(`vendor.xiaomi.hardware.batteryantiaging-service`) and `mi_thermald`. This
page records how they are encrypted and what they contain, so the rules can be
read, compared between firmware releases and, later, moved to open services.

`tools/decrypt-xiaomi-configs.py <vendor/xiaomi/piano/proprietary> <out>`
writes the plain text of every config it can decrypt.

## How this was read

Static analysis of the OS4.0.6.0 blobs with REA (Hopper) and `llvm-objdump`.
**Evidence** means read from code or data. **Inference** means a reading that
was not confirmed on the device.

## Battery anti-aging

Files: `odm/etc/charger/BAA_config_piano.json`, `BAA_config_common.json`.

Encryption (evidence, `libbaa_common.so`): text starts with `BAA_ENC:`, then
base64. The decoded bytes are a 16-byte IV followed by AES-128-CBC data.
`AESEncryption::aes_cbc_decrypt_base64` passes the first 16 bytes as the IV to
`EVP_DecryptInit_ex`. The key is the static `AESEncryption::KEY`, a libc++
short string in `.data`: `michargerbattery`.

Strategies enabled for piano (`supported_strategy_index` `[1, 3]`):

- **LowSoh-FvDown.** With a cycle count between 200 and 800 and
  `/sys/class/qcom-battery/soh` below 85, the service writes 40 to
  `/sys/class/qcom-battery/smart_batt` and to the smart charge
  `smart_fv` node. That lowers the float voltage by 40 mV (cap 50 mV).
- **BasedOnCC-VolDown.** Charge tables by cycle count (1-100, 101-300,
  301-1000, above 1000) and by battery type (`ro.boot.hwc` CN or GL). Each table
  has JEITA termination voltage and current per temperature band, plus wired
  step charging (FFC and normal). For example, at 101-300 cycles and 18-35 °C,
  FFC terminates at 4530 mV / 2350 mA.

The BasedOnCC tables do not go through sysfs. `BasedOnCC_VolDown::sendDataWithIoctl`
packs them with `ParseSpecData` and `applyFvAndChecksum` into a 4 KB buffer
and sends it with `ioctl(fd, 0xd0001001)` on `/dev/smart_charge_cdev`. The
service also writes the table to `/data/vendor/batteryantiaging/BAA_battSpec.csv`.

Buffer layout (evidence: the stock service run as root under KernelSU on
2026-11-10; the driver logged the header, and a rebuild from the decrypted
JSON gave the same length and checksum):

| Part | Layout |
|---|---|
| Header, 9 × u32 | `total_len`, `checksum`, `type` (0), then counts `jeita_ffc`, `jeita_normal`, `wired_ffc`, `wired_normal`, `wls_ffc`, `wls_normal` |
| JEITA entries, 5 × s32 | `idx`, `min`, `max`, `vterm`, `iterm`, FFC first then normal |
| Wired curves | u32 `type` (1), u32 `ffc` (1 or 0), s32 `idx`, `min`, `max`, u32 `step_size`, then `step_size` × (s32 `mv`, `ma_h`, `ma_l`); FFC first |
| Checksum | byte sum of the first `total_len` bytes with the checksum field set to 0 |

For 121 cycles (index 2, CN battery) the counts are 2/9/2/2/0/0 and the buffer
is 496 bytes with checksum 12642.

The reconstructed `struct smart_basp_header` in our 6.12 mca driver orders the
first three fields `type, total_len, checksum` and sums from byte 4 including
the checksum field, so it rejects every buffer ("Invalid total_len: 0"). On
this ROM the stock service is also blocked by SELinux from its persist
folder.

Status: the stock service stays until the driver header is fixed. With the
layout known, an open service can build the same buffer from the plain JSON.

## mi_thermald

Files: `odm/etc/thermal-*.conf` (47 profiles), `vendor/etc/thermal-map.conf`.

Encryption (evidence, `mi_thermald`): AES-128-CBC with the key and IV both
`thermalopenssl.h`. Both pointers are loaded from the GOT next to the
`thermalopenssl.h` strings in `.data`. A second path derives a 32-byte key
when `persist.vendor.aes_whitebox.encrypt` is set. It is not used by these
files. `thermal-boost.conf`, the `chg-only` profiles and `thermald-devices.conf`
use neither key.

The profiles use the Qualcomm thermal-engine format: `virtual` sensors that
weight several thermistors, `monitor` rules and `ss` (step) rules with
`trig`/`clr`/`target` columns. `thermal-map.conf` maps scene IDs to profiles
(0 normal, 7 class0, 18-20 games, 15 camera, and so on).

Inference: HyperOS switches scenes through the framework. AOSP has no such
client, so only scene 0, `thermal-normal.conf`, applies. Main limits in that
profile, driven by `VIRTUAL-SENSOR` (battery, quiet, charger, Wi-Fi and CPU
thermistors):

| Rule | Starts at | Limit steps |
|---|---|---|
| `SS-CPU0` (cores 0-5) | 37 °C | 2.40 GHz, down to 749 MHz at 48 °C |
| `SS-CPU6` (cores 6-7) | 34 °C | 2.65 GHz, down to 1.02 GHz at 44 °C |
| `MONITOR-GPU`, `MONITOR-BAT`, `MONITOR-BCL` | per rule | GPU, charge current, battery current limit |

Status: `mi_thermald` stays. An open replacement must implement the virtual,
monitor and ss rules and the device actions behind names like `cpu0`, `gpu`
and `battery`. Those actions come from `thermald-devices.conf`, which is still
encrypted.
