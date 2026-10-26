# Device tree for the Xiaomi Pad 8 Pro (piano)

Android 17 device tree for the Xiaomi Pad 8 Pro (`piano`, Snapdragon 8 Elite,
SM8750). Stock files come from HyperOS 4 China `OS4.0.5.0.XPYCNXM`; flash
that firmware before installing a build from this tree.

Goes in `device/xiaomi/piano`.

## Getting the sources

Add the [local manifest](https://github.com/xiaomi-pad-8-pro-development/local_manifests)
to your ROM checkout:

```
git clone https://github.com/xiaomi-pad-8-pro-development/local_manifests -b seventeen .repo/local_manifests
repo sync
```

## Trees

| Path | Repository | |
| --- | --- | --- |
| `device/xiaomi/piano` | this repository | required |
| `device/xiaomi/piano-kernel` | [android_device_xiaomi_piano-kernel](https://github.com/xiaomi-pad-8-pro-development/android_device_xiaomi_piano-kernel) | required |
| `vendor/xiaomi/piano` | [android_vendor_xiaomi_piano](https://github.com/xiaomi-pad-8-pro-development/android_vendor_xiaomi_piano) | required |
| `hardware/xiaomi` | [LineageOS android_hardware_xiaomi](https://github.com/LineageOS/android_hardware_xiaomi) | required |
| `device/xiaomi/piano-xiaomi-parts` | [android_device_xiaomi_piano-xiaomi-parts](https://github.com/xiaomi-pad-8-pro-development/android_device_xiaomi_piano-xiaomi-parts) | optional |
| `device/xiaomi/piano-alxp-parts` | [android_device_xiaomi_piano-alxp-parts](https://github.com/xiaomi-pad-8-pro-development/android_device_xiaomi_piano-alxp-parts) | optional |
| `device/xiaomi/piano-patches` | [android_device_xiaomi_piano-patches](https://github.com/xiaomi-pad-8-pro-development/android_device_xiaomi_piano-patches) | optional |
| `vendor/xiaomi/piano-xiaomi-camera` | [android_vendor_xiaomi_piano-xiaomi-camera](https://github.com/xiaomi-pad-8-pro-development/android_vendor_xiaomi_piano-xiaomi-camera) | optional |
| `vendor/xiaomi/piano-xiaomi-notes` | [android_vendor_xiaomi_piano-xiaomi-notes](https://github.com/xiaomi-pad-8-pro-development/android_vendor_xiaomi_piano-xiaomi-notes) | optional |
| `device/xiaomi/piano-aosp-notes` | [android_device_xiaomi_piano-aosp-notes](https://github.com/xiaomi-pad-8-pro-development/android_device_xiaomi_piano-aosp-notes) | optional |

Optional trees are picked up when synced; the device builds without them.
`device/xiaomi/piano-kernel` has two branches: `seventeen` for the plain
kernel and `seventeen-ksu` for the one with KernelSU-Next.
Release builds set `PIANO_AVB_KEY_PATH` to their AVB key; otherwise the AOSP
test key is used.

## Building

```
source build/envsetup.sh
lunch lineage_piano-cp2a-userdebug   # LineageOS, Evolution X
lunch custom_piano-cp2a-userdebug    # PixelOS
m bacon
```

## Credits

Parts of this tree are adapted from
[xiaomi-haotian-devs/android_device_xiaomi_sm8750-common](https://github.com/xiaomi-haotian-devs/android_device_xiaomi_sm8750-common)
(lineage-23.2, `1c858a2`); original copyright and licence notices are kept.
The layout follows [xiaomi-pad-8-development](https://github.com/xiaomi-pad-8-development).
