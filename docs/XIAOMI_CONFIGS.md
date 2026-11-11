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

Status: replaced by `piano-battery-health` (`battery/`). It decrypts the
stock rules, applies LowSoh-FvDown, and sends the BasedOnCC table at boot and
whenever the cycle count bucket changes. A host build of its packer gives
496 bytes and checksum 12642 for the case above, the same as the stock
service. The tables only take effect with the fixed mca driver header.

## mi_thermald

Files: `odm/etc/thermal-*.conf` (47 profiles), `vendor/etc/thermal-map.conf`.

Encryption (evidence, `mi_thermald`): AES-128-CBC with the key and IV both
`thermalopenssl.h`. Both pointers are loaded from the GOT next to the
`thermalopenssl.h` strings in `.data`. A second path, used when
`persist.vendor.aes_whitebox.encrypt` is set, runs a 32-byte hex string from
`.data` through a white-box AES decrypt (`0xcd470`, tables at `0x52de0`).
Emulated with Unicorn, it yields `6bc1bee22e409f96e93d7e117393172a`, the
NIST AES test vector plaintext, used as key and IV. That key does not open
`thermal-boost.conf`, so its key is still unknown. `thermald-devices.conf`
and the `chg-only` profiles are plain text.

`thermald-devices.conf` maps the device names used by the rules to Linux
cooling devices (`cooling_name`, for example `gpu`, `battery`, `cdsp`,
`pause-cpuN`, `cpu-clusterN`) or to sysfs nodes (`path`, mostly under
`/sys/class/thermal/thermal_message` and the xm_power charger). Each entry
has a default target and `select_higher`, which says whether the highest or
the lowest request wins when several rules drive the same device. `cpu0` and
`cpu6` are not in the file, so they are built into `mi_thermald`. Inference:
they cap the frequency of CPU policy 0 and policy 6.

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

Status: `piano-thermald` (`thermal/`) runs next to `mi_thermald` in shadow
mode: it reads the same rules and device map and logs what it would set. A
host test against a fake sysfs tree steps through the `thermal-normal` trips
and clears as expected (for example `cpu0` 2.75 GHz down to 749 MHz and back).
To hand over control, compare its log with the stock daemon on the device,
then `setprop vendor.piano.thermald.active true`, which also stops
`mi_thermald`. CPU caps go through `thermal_message/cpu_limits` (`cpuN <kHz>`, held by the
mi_thermal driver as a kernel QoS request) when it exists, else
`scaling_max_freq`. `boost_limit` and `video_mode` are ignored on purpose:
`boost_limit` only gates mi_thermald's own boost feature, and `video_mode`
does not appear in the stock binary at all.

`sys.piano.thermald.profile=<name>` (set by Parts while a game is in front) swaps in the rules of
`thermal-<name>.conf` (sensors stay from `thermal-normal`); empty or
`normal` goes back. Host test: with `tgame` the CPU keeps 2.75 / 3.07 GHz up
to 48 °C, where `normal` starts limiting at 34-37 °C.

## IR blaster (`consumerir.qcom.so`)

The IR LED hangs off SPI. `/dev/ir_spi` (`drivers/media/rc/ir-spi.c`) shifts
the written buffer out at 1.92 MHz, 32 bits per word, MSB first;
`LIRC_SET_SEND_MODE` is reused to set the buffer length in bytes.

The stock HAL builds that buffer from a pattern like this:

- End time of each mark/space = running sum of the pattern minus 5 us. The
  total must stay below 0x111112 us.
- Bits = total * 1.92; bytes rounded up to whole 1 KiB blocks, zero padded.
- One carrier cycle = round(1920000 / carrier) bits, of which the first 40 %
  are on. The cycle counter restarts at every space.
- Carriers offered: 30, 33, 36, 38, 40 and 56 kHz.

`ir/IrSpiEncoder.h` follows the same steps; run against the stock library in
Unicorn it gives identical buffers for NEC frames, long and invalid patterns.
