#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/xiaomi/piano

# Generic ramdisk allow list
$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_ramdisk.mk)

# Project ID Quota
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# Virtual A/B
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/vabc_features.mk)

# Dalvik vm configs
$(call inherit-product, frameworks/native/build/phone-xhdpi-6144-dalvik-heap.mk)

# Qualcomm
$(call inherit-product, hardware/qcom-caf/common/common.mk)

# A/B
AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_system=true \
    POSTINSTALL_PATH_system=system/bin/otapreopt_script \
    FILESYSTEM_TYPE_system=erofs \
    POSTINSTALL_OPTIONAL_system=true

AB_OTA_POSTINSTALL_CONFIG += \
    RUN_POSTINSTALL_vendor=true \
    POSTINSTALL_PATH_vendor=bin/checkpoint_gc \
    FILESYSTEM_TYPE_vendor=erofs \
    POSTINSTALL_OPTIONAL_vendor=true

PRODUCT_PACKAGES += \
    checkpoint_gc \
    otapreopt_script

PRODUCT_VIRTUAL_AB_COMPRESSION_METHOD := lz4

# AAPT
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

# ANT+
PRODUCT_PACKAGES += \
    com.dsi.ant@1.0.vendor

# Audio
PRODUCT_PACKAGES += \
    audioadsprpcd \
    audio.primary.default \
    audio.r_submix.default \
    audio.usb.default \
    audiohalservice.qti \
    libaudiohalvendorextn \
    libmemunreachable.vendor \
    qtiaudiohalvendorextn

PRODUCT_PACKAGES += \
    libagm_compress_plugin \
    libagm_mixer_plugin \
    libagm_pcm_plugin \
    libaudiochargerlistener \
    libaudiopreprocessing \
    libaudioserviceexampleimpl \
    libbatterylistener \
    libbundleaidl \
    libcustomva_intf \
    libdownmixaidl \
    libdynamicsprocessingaidl \
    libdynproc \
    libeffectproxy \
    libfmpal \
    libhfp_pal \
    libhotword_intf \
    libldnhncr \
    libloudnessenhanceraidl \
    libpaleventnotifier \
    libpalipcservice \
    libreverbaidl \
    libreverbwrapper \
    libsoundtriggerhal.qti \
    libvisualizeraidl \
    libvui_intf

PRODUCT_PACKAGES += \
    libalsautilsv2.vendor \
    libaudioutils_shim \
    libmediautils_vendor.vendor \
    libtinyalsav2.vendor

# Bluetooth audio comes from the stock AIDL prebuilts; the legacy AOSP module
# pulls in newer source-side dependencies.
PRODUCT_PACKAGES -= \
    audio.bluetooth.default

AUDIO_HAL_DIR := hardware/qcom-caf/sm8750/audio/primary-hal

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/audio/audio_module_config_primary.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/audio_module_config_primary.xml \
    $(LOCAL_PATH)/configs/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_ODM)/etc/audio_policy_configuration.xml \
    $(LOCAL_PATH)/configs/audio/audio_policy_engine_default_stream_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_engine_default_stream_volumes.xml \
    $(LOCAL_PATH)/configs/audio/audio_policy_engine_product_strategies.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_engine_product_strategies.xml \
    $(LOCAL_PATH)/configs/audio/audio_policy_engine_stream_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_engine_stream_volumes.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.audio.low_latency.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.audio.low_latency.xml \
    frameworks/native/data/etc/android.hardware.audio.pro.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.audio.pro.xml \
    frameworks/native/data/etc/android.software.midi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.midi.xml

# Bluetooth
PRODUCT_PACKAGES += \
    lib_bt_aptx \
    lib_bt_ble \
    lib_bt_bundle

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml

# Boot control
PRODUCT_PACKAGES += \
    android.hardware.boot-service.qti \
    android.hardware.boot-service.qti.recovery

# Camera
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.camera.concurrent.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.concurrent.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml \
    frameworks/native/data/etc/android.hardware.camera.full.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.full.xml \
    frameworks/native/data/etc/android.hardware.camera.raw.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.raw.xml

# USB (UVC) webcams, like the stock external camera provider. Its config is
# the stock vendor/etc/external_camera_config.xml.
PRODUCT_PACKAGES += \
    android.hardware.camera.provider-V1-external-service

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.camera.external.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.external.xml

# Characteristics
PRODUCT_CHARACTERISTICS := tablet

# Core features
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/tablet_core_hardware.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/tablet_core_hardware.xml

# Display
# Respect fixed-orientation apps on the internal display.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/display/display_settings.xml:$(TARGET_COPY_OUT_VENDOR)/etc/display_settings.xml

# Dolby
PRODUCT_PACKAGES += \
    DolbyManager

# DRM
PRODUCT_PACKAGES += \
    android.hardware.drm-service.clearkey

# Fastboot
PRODUCT_PACKAGES += \
    android.hardware.fastboot-service.example_recovery \
    fastbootd

# Fingerprint
PRODUCT_PACKAGES += \
    android.hardware.biometrics.fingerprint-V5-ndk_xiaomi \
    android.hardware.sensors-V2-ndk_xiaomi \
    mfp-daemon

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.fingerprint.xml:$(TARGET_COPY_OUT_ODM)/etc/permissions/android.hardware.fingerprint.xml

# GNSS
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_ODM)/etc/permissions/android.hardware.location.gps.xml

# Graphics: gralloc, the mapper, the allocator and the display helper
# libraries build from hardware/qcom-caf/sm8750/display with the ABI the stock
# composer links. snapalloc builds from source too: the stock one links the
# same libraries and loads the same Adreno, camera and memory helpers with
# dlopen. libdisplaydebug, libdrmutils, libfilefinder and libgpu_tonemapper
# stay stock.
PRODUCT_PACKAGES += \
    android.hardware.graphics.mapper@4.0-impl-qti-display \
    libdisplayconfig.qti \
    libgralloc.qti \
    libhistogram \
    libqdMetaData \
    libqdutils \
    libqservice \
    mapper.qti \
    vendor.qti.hardware.display.allocator-service \
    vendor.qti.hardware.display.config-V12-ndk.vendor \
    vendor.qti.hardware.display.demura-service \
    vendor.qti.hardware.display.snapalloc-impl

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.opengles.aep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.opengles.aep.xml \
    frameworks/native/data/etc/android.hardware.vulkan.compute-0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.compute-0.xml \
    frameworks/native/data/etc/android.hardware.vulkan.level-1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.level-1.xml \
    frameworks/native/data/etc/android.hardware.vulkan.version-1_1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.version-1_1.xml \
    frameworks/native/data/etc/android.hardware.vulkan.version-1_3.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.version-1_3.xml \
    frameworks/native/data/etc/android.software.opengles.deqp.level-2023-03-01.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.opengles.deqp.level.xml \
    frameworks/native/data/etc/android.software.vulkan.deqp.level-2023-03-01.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.vulkan.deqp.level.xml

# Health
PRODUCT_PACKAGES += \
    android.hardware.health-service.qti \
    android.hardware.health-service.qti_recovery

$(call soong_config_set,lineage_health,charging_control_charging_path,/sys/class/xm_power/charger/smart_charge/smart_night)
$(call soong_config_set,lineage_health,charging_control_charging_enabled,0)
$(call soong_config_set,lineage_health,charging_control_charging_disabled,1)
$(call soong_config_set_bool,lineage_health,charging_control_supports_bypass,false)

PRODUCT_PACKAGES += \
    vendor.lineage.health-service.default

# Init
PRODUCT_PACKAGES += \
    fstab.qcom \
    init.class_main.sh \
    init.kernel.extra_free_kbytes.sh \
    init.kernel.init_boot-memory.sh \
    init.kernel.post_boot-memory.sh \
    init.kernel.post_boot-sun.sh \
    init.kernel.post_boot-sun_5_2.sh \
    init.kernel.post_boot-sun_6_0.sh \
    init.kernel.post_boot-sun_default_6_2.sh \
    init.kernel.post_boot.sh \
    init.piano.audio.rc \
    init.piano.rc \
    init.piano.wallpaper.rc \
    init.qcom.class_core.sh \
    init.qcom.early_boot.sh \
    init.qcom.post_boot.sh \
    init.qcom.rc \
    init.qcom.sh \
    init.qti.kernel.rc \
    init.qti.kernel.sh \
    init.qti.kernel.target.rc \
    init.recovery.qcom.rc \
    init.target.rc \
    init.xiaomi.rc \
    piano-body-color.sh \
    ueventd.qcom.rc

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/rootdir/etc/fstab.qcom:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.qcom

# Stock init and module-loading scripts use the vendor shell and tools.
PRODUCT_PACKAGES += \
    sh_vendor \
    toolbox_vendor \
    toybox_vendor

# Input
# Keyboard cover: its special keys, and arrow keys that do not rotate with
# the display.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/idc/Vendor_15d9_Product_00a3.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/Vendor_15d9_Product_00a3.idc \
    $(LOCAL_PATH)/configs/keylayout/Vendor_15d9_Product_00a3.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/Vendor_15d9_Product_00a3.kl

# Focus Pen 3: its touch-film buttons must not type characters, like stock.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/idc/Vendor_0022_Product_5081.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/Vendor_0022_Product_5081.idc \
    $(LOCAL_PATH)/configs/keychars/Vendor_0022_Product_5081.kcm:$(TARGET_COPY_OUT_VENDOR)/usr/keychars/Vendor_0022_Product_5081.kcm

# IPACM
PRODUCT_PACKAGES += \
    ipacm \
    IPACM_cfg.xml \
    IPACM_Filter_cfg.xml

# IR
PRODUCT_PACKAGES += \
    android.hardware.ir-service.example

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.consumerir.xml:$(TARGET_COPY_OUT_ODM)/etc/permissions/android.hardware.consumerir.xml

# Keymint
PRODUCT_PACKAGES += \
    android.hardware.hardware_keystore.xml

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.keystore.app_attest_key.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.keystore.app_attest_key.xml \
    frameworks/native/data/etc/android.software.device_id_attestation.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.device_id_attestation.xml

# Lights
PRODUCT_PACKAGES += \
    vendor.qti.hardware.lights.service

# Linker config
PRODUCT_VENDOR_LINKER_CONFIG_FRAGMENTS += \
    $(LOCAL_PATH)/configs/linker.config.json

# LiveDisplay: reading mode and touch polling rate through the stock Xiaomi
# display and touch features
PRODUCT_PACKAGES += \
    vendor.lineage.livedisplay-service.piano

# Media
PRODUCT_COPY_FILES += \
    $(AUDIO_HAL_DIR)/configs/common/codec2/media_codecs_c2_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_c2_audio.xml \
    $(AUDIO_HAL_DIR)/configs/common/codec2/service/1.0/c2audio.vendor.base-arm64.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/c2audio.vendor.base-arm64.policy \
    $(AUDIO_HAL_DIR)/configs/common/codec2/service/1.0/c2audio.vendor.ext-arm64.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/c2audio.vendor.ext-arm64.policy

# Memtrack
PRODUCT_PACKAGES += \
    vendor.qti.hardware.memtrack-service

# Mountpoints
$(call soong_config_set,rfs,mpss_firmware_symlink_target,modem_firmware)

PRODUCT_PACKAGES += \
    product_vm-system_mountpoint \
    rfs_msm_mpss_readonly_mbnconfig_symlink \
    vendor_bt_firmware_mountpoint \
    vendor_dsp_mountpoint \
    vendor_firmware_mnt_mountpoint \
    vendor_modem_firmware_mountpoint \
    vendor_vm-system_mountpoint

# Network
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.software.ipsec_tunnels.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.ipsec_tunnels.xml

# Overlays
PRODUCT_PACKAGES += \
    FrameworkOverlayPiano \
    LineageSDKOverlayPiano \
    SettingsOverlayPiano \
    SettingsProviderOverlayPiano \
    SystemUIOverlayPiano \
    WifiOverlayPiano

# Partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# Power
PRODUCT_PACKAGES += \
    android.hardware.power-service-qti

PRODUCT_COPY_FILES += \
    vendor/qcom/opensource/power/config/sun/powerhint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/powerhint.xml

# PowerShare
$(call soong_config_set,lineage_powershare,powershare_path,/sys/class/qcom-battery/reverse_chg_mode)

PRODUCT_PACKAGES += \
    vendor.lineage.powershare-service.default

# Protobuf, for the stock vendor blobs
PRODUCT_PACKAGES += \
    libprotobuf-cpp-full \
    libprotobuf-cpp-lite

# QSPA
PRODUCT_PACKAGES += \
    qspa_vendor.rc \
    vendor.qti.qspa-service

# Sensors
PRODUCT_PACKAGES += \
    android.hardware.sensors-service.xiaomi-sm8750-multihal

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.dynamic.head_tracker.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.dynamic.head_tracker.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepcounter.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.stepcounter.xml \
    frameworks/native/data/etc/android.hardware.sensor.stepdetector.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/sku_sun/android.hardware.sensor.stepdetector.xml

# Shims
PRODUCT_PACKAGES += \
    libprocessgroup_shim

# Interface libraries that stock camera and libui blobs load. Their modules
# are built without dependency lists, so name them here.
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator-V1-ndk.vendor \
    android.hardware.graphics.common-V5-ndk.vendor \
    android.hardware.sensors-V2-ndk.vendor \
    vendor.qti.hardware.camera.offlinecamera-V2-ndk.vendor \
    vendor.qti.hardware.display.config-V2-ndk.vendor

# Shipping API level
PRODUCT_SHIPPING_API_LEVEL := 36

# The stock kernel uses 4 KB pages and the prebuilt compat libraries are
# 4 KB aligned, so skip the 16 KB ELF check.
PRODUCT_CHECK_PREBUILT_MAX_PAGE_SIZE := false

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH) \
    hardware/xiaomi

# Thermal
PRODUCT_PACKAGES += \
    android.hardware.thermal-service.qti

# Touchscreen
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml

# Update engine
PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier

PRODUCT_PACKAGES_DEBUG += \
    update_engine_client

# USB
PRODUCT_PACKAGES += \
    android.hardware.usb-service.qti \
    android.hardware.usb.gadget-service.qti

PRODUCT_PACKAGES += \
    init.qcom.usb.rc \
    init.qcom.usb.sh \
    usb_compositions.conf

PRODUCT_SOONG_NAMESPACES += \
    vendor/qcom/opensource/usb/etc

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.host.xml

# Verified boot
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.software.verified_boot.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.verified_boot.xml

# Vndservice manager
PRODUCT_PACKAGES += \
    vndservicemanager

# WiFi
PRODUCT_PACKAGES += \
    android.hardware.wifi-service \
    firmware_WCNSS_qcom_cfg.ini_symlink \
    firmware_wlan_mac.bin_symlink \
    firmware_wlanmdsp.otaupdate_symlink \
    hostapd \
    hostapd_cli \
    libpasn \
    libwifi-hal \
    libwifi-hal-qcom \
    libwpa_client \
    wpa_cli \
    wpa_supplicant \
    wpa_supplicant.conf

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.wifi.aware.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.aware.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml \
    frameworks/native/data/etc/android.hardware.wifi.passpoint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.passpoint.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml

# WiFi Display
PRODUCT_PACKAGES += \
    libwfdaac_vendor

# Vendor
$(call inherit-product, vendor/xiaomi/piano/piano-vendor.mk)

# Optional trees, included when synced
$(call inherit-product-if-exists, device/xiaomi/piano-alxp-parts/alxpparts.mk)
$(call inherit-product-if-exists, device/xiaomi/piano-patches/patches.mk)
$(call inherit-product-if-exists, device/xiaomi/piano-xiaomi-parts/pianoparts.mk)
$(call inherit-product-if-exists, vendor/xiaomi/piano-xiaomi-camera/miuicamera.mk)
$(call inherit-product-if-exists, vendor/xiaomi/piano-xiaomi-notes/notes.mk)
