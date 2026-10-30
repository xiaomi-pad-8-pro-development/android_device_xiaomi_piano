# Device tree for the Xiaomi Pad 8 Pro (piano)

| | |
| --- | --- |
| Path | `device/xiaomi/piano` |
| Android | 17 |
| Firmware | HyperOS 4 China `OS4.0.5.0.XPYCNXM` (flash it first) |

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

## Credits

Parts adapted from [xiaomi-haotian-devs sm8750-common](https://github.com/xiaomi-haotian-devs/android_device_xiaomi_sm8750-common) (`1c858a2`). Layout follows [xiaomi-pad-8-development](https://github.com/xiaomi-pad-8-development).
