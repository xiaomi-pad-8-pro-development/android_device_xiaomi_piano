# Device tree for the Xiaomi Pad 8 Pro (piano)

| | |
| --- | --- |
| Path | `device/xiaomi/piano` |
| Android | 17 |
| Firmware | HyperOS 4 China `OS4.0.6.0.XPYCNXM`, shipped in the ROM (the vendor tree needs Git LFS) |

## Needs

| Path | Repository |
| --- | --- |
| `device/xiaomi/piano-kernel` | [kernel prebuilts](https://github.com/xiaomi-pad-8-pro-development/android_device_xiaomi_piano-kernel) (`seventeen` plain, `seventeen-ksu` KernelSU) |
| `vendor/xiaomi/piano` | [vendor](https://github.com/xiaomi-pad-8-pro-development/android_vendor_xiaomi_piano) |
| `hardware/xiaomi` | [LineageOS](https://github.com/LineageOS/android_hardware_xiaomi) |

Optional trees from [local_manifests](https://github.com/xiaomi-pad-8-pro-development/local_manifests) are picked up when synced.

## Build

```
source build/envsetup.sh
lunch lineage_piano-cp2a-userdebug   # LineageOS, Evolution X
lunch custom_piano-cp2a-userdebug    # PixelOS
m bacon
```

Release builds set `PIANO_AVB_KEY_PATH`; otherwise the AOSP test key is used.

## Open replacements for Xiaomi services

| Service | Replaces | Notes |
| --- | --- | --- |
| `battery/piano-battery-health` | Xiaomi battery anti-aging | Reads the stock rules and sends the charge table for the battery's age |
| `thermal/piano-thermald` | `mi_thermald` | Runs next to it and only logs until `vendor.piano.thermald.active` is `true` |

The formats they read are in [docs/XIAOMI_CONFIGS.md](docs/XIAOMI_CONFIGS.md).

## Credits

Parts adapted from [xiaomi-haotian-devs sm8750-common](https://github.com/xiaomi-haotian-devs/android_device_xiaomi_sm8750-common) (`1c858a2`). Layout follows [xiaomi-pad-8-development](https://github.com/xiaomi-pad-8-development).
