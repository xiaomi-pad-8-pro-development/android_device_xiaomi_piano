#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
#
# SPDX-FileCopyrightText: 2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

import hashlib
import sys
from pathlib import Path

import extract_utils.tools
from extract_utils.fixups import flatten_fixups
from extract_utils.fixups_blob import (
    blob_fixup,
    blob_fixups_user_type,
)
from extract_utils.fixups_lib import (
    lib_fixup_remove,
    lib_fixups,
    lib_fixups_user_type,
)
from extract_utils.main import (
    ExtractUtils,
    ExtractUtilsModule,
)
from extract_utils.tools import (
    DEFAULT_PATCHELF_VERSION,
    patchelf_version_path_map,
)
from extract_utils.utils import run_cmd

namespace_imports = [
    'device/xiaomi/piano',
    'hardware/qcom-caf/wlan',
    'hardware/qcom-caf/sm8750',
    'hardware/xiaomi',
    'vendor/qcom/opensource/commonsys/display',
    'vendor/qcom/opensource/commonsys-intf/display',
    'vendor/qcom/opensource/dataservices',
]

def lib_fixup_vendor_suffix(lib: str, partition: str, *args, **kwargs):
    return f'{lib}-{partition}' if partition == 'vendor' else None


# Preserve stock vendor ABIs without replacing platform source modules.
def lib_fixup_stock_vendor(lib: str, partition: str, *args, **kwargs):
    return f'{lib}-vendor' if partition in ('vendor', 'odm') else None


def camera_libui_runpath(ctx, file, file_path, *args, **kwargs):
    # Load the stock GraphicBuffer ABI in the camera provider without
    # replacing libui for other vendor processes. Keep its original SONAME.
    run_cmd([patchelf_version_path_map[DEFAULT_PATCHELF_VERSION],
             '--set-rpath', '/vendor/lib64/camera', file_path])

lib_fixups: lib_fixups_user_type = {
    **lib_fixups,
    (
        'vendor.qti.diaghal@1.0',
        'vendor.qti.diaghal-V1-ndk',
        'vendor.qti.ImsRtpService-V1-ndk',
        'android.hardware.bluetooth.audio-impl',
        'libbluetooth_audio_session_aidl',
    ): lib_fixup_vendor_suffix,
    (
        'android.hardware.graphics.common-V5-ndk',
        'libmialgo',
        'libaudioserviceexampleimpl',
    ): lib_fixup_remove,
    (
        'libjpegdecoder',
        'libjpegencoder',
        'libultrahdr',
    ): lib_fixup_stock_vendor,
}


blob_fixups: blob_fixups_user_type = {
    # Persist is mounted during fs; QSEE must not start in the earlier init phase.
    'vendor/etc/init/qseecomd.rc': blob_fixup()
        .regex_replace(r'on init\n    start vendor.qseecomd',
                       'on post-fs\n    start vendor.qseecomd')
        .regex_replace(r'    class core\n', '    class core\n    disabled\n'),
    'odm/bin/hw/mfp-daemon': blob_fixup()
        .replace_needed(
            'android.hardware.biometrics.fingerprint-V5-ndk.so',
            'android.hardware.biometrics.fingerprint-V5-ndk_xiaomi.so'
        )
        .replace_needed(
            'android.hardware.sensors-V2-ndk.so',
            'android.hardware.sensors-V2-ndk_xiaomi.so'
        ),
    # host_init_verifier requires an explicit user; these stock services
    # already ran as root by default.
    'vendor/etc/init/audiohalservice_qti.rc': blob_fixup()
        .regex_replace(
            r'(service set_diag_state [^\n]*\n)',
            r'\1    user root\n'
        ),
    'vendor/etc/display/DPU12__.xml': blob_fixup()
        .regex_replace(r'<Param9>1.05</Param9>', '<Param9>1.04</Param9>'),
    'vendor/etc/init/nicmd.rc': blob_fixup()
        .regex_replace(
            r'(service vendor\.nicmd [^\n]*\n)',
            r'\1    user root\n'
        ),
    'odm/etc/init/vendor.xiaomi.hw.touchfeature-service.rc': blob_fixup()
        .regex_replace(
            r'(service touch-kmsg-init-sh [^\n]*\n)',
            r'\1    user root\n'
        ),
    # idmanager's attestation check crashes on unlocked devices; it is still
    # started on demand through its AIDL interfaces.
    'odm/etc/init/vendor.xiaomi.hardware.idmanager.rc': blob_fixup()
        .regex_replace(
            r'    start vendor.idmanger\n',
            ''
        ),
    'odm/etc/init/init.mfp-daemon.aidl.rc': blob_fixup()
        .regex_replace(
            r'\n    seclabel u:r:vendor_mfp-daemon:s0',
            ''
        ),
    (
       'vendor/lib64/libwfdmmsrc_proprietary.so',
    ): blob_fixup()
        .replace_needed(
            'android.media.audio.common.types-V2-ndk.so',
            'android.media.audio.common.types-V3-ndk.so'
        ),
    'vendor/lib64/hw/libaudiocorehal.qti.so': blob_fixup()
        .replace_needed('android.hardware.audio.core.sounddose-V1-ndk.so', 'android.hardware.audio.core.sounddose-V2-ndk_xiaomi.so'),
    # Lower the PAL log level so low latency playback stops flooding logcat.
    (
        'odm/etc/audio/sku_sun/resourcemanager_sun_mtp.xml',
        'vendor/etc/audio/sku_sun/resourcemanager_sun_mtp.xml',
    ): blob_fixup()
        .regex_replace('logging_level" value ="0x7"', 'logging_level" value ="0x3"'),
    # Stub memLoggerEnqueue with "return 0": it looks up an uninitialized
    # mutex and floods logcat with COMU errors while audio renders.
    'vendor/lib64/libarmemlog.so': blob_fixup()
        .sig_replace(
            '3f 23 03 d5 ff 43 01 d1 fd 7b 01 a9 f7 13 00 f9',
            'e0 03 1f 2a c0 03 5f d6 1f 20 03 d5 1f 20 03 d5',
        ),
    'vendor/lib64/libaudioserviceexampleimpl.so': blob_fixup()
        .add_needed('libaudioutils_shim.so')
        .replace_needed('android.hardware.audio.core.sounddose-V2-ndk.so', 'android.hardware.audio.core.sounddose-V2-ndk_xiaomi.so')
        .replace_needed('libaudio_aidl_conversion_common_ndk.so', 'libaudio_aidl_conversion_common_ndk_xiaomi.so'),
    (
        'vendor/lib64/soundfx/libbundleaidl.so',
        'vendor/lib64/soundfx/libdlbvolaidl.so',
        'vendor/lib64/soundfx/libhwdapaidl.so',
        'vendor/lib64/soundfx/liblvacfsprocessingaidl.so',
        'vendor/lib64/soundfx/libmiwndnsprocessingaidl.so',
        'vendor/lib64/soundfx/libozoaidl.so',
        'vendor/lib64/soundfx/libspatializeraidl.so',
        'vendor/lib64/soundfx/libswgamedapaidl.so',
        'vendor/lib64/soundfx/libswspatializeraidl.so',
        'vendor/lib64/libswspatializeraidl_ext.so',
    ): blob_fixup()
        .replace_needed(
            'libaudio_aidl_conversion_common_ndk.so',
            'libaudio_aidl_conversion_common_ndk_xiaomi.so'
        ),
     (
       'vendor/lib64/libsxrservice.so'
     ): blob_fixup()
        .replace_needed(
            'android.hardware.common-V2-ndk_platform.so',
            'android.hardware.common-V2-ndk.so'
        ),
    (
        'vendor/lib64/libqti-perfd.so',
    ): blob_fixup()
        .replace_needed('vendor.qti.hardware.display.config-V5-ndk.so', 'vendor.qti.hardware.display.config-V12-ndk.so'),
    (
        'vendor/lib64/soundfx/libquasar.so',
    ): blob_fixup()
        .replace_needed('libtinyxml2.so', 'libtinyxml2-v34.so'),
    (
        'vendor/lib64/libapengine.so',
    ): blob_fixup()
        .replace_needed('vendor.qti.hardware.display.config-V5-ndk.so', 'vendor.qti.hardware.display.config-V12-ndk.so')
        .replace_needed(
            'libtinyxml2.so',
            'libtinyxml2-v34.so'
        ),
     (
       'odm/bin/hw/vendor.xiaomi.hw.touchfeature-service',
       'odm/lib64/hw/displayfeature.default.so',
       'odm/lib64/libadaptivehdr.so',
       'odm/lib64/libcolortempmode.so',
       'odm/lib64/libdither.so',
       'odm/lib64/libdynamicelvss.so',
       'odm/lib64/libflatmode.so',
       'odm/lib64/libhistprocess.so',
       'odm/lib64/libmiBrightness.so',
       'odm/lib64/libmiSensorCtrl.so',
       'odm/lib64/libpaperMode.so',
       'odm/lib64/librhytheyecare.so',
       'odm/lib64/libsdr2hdr.so',
       'odm/lib64/libsre.so',
       'odm/lib64/libtruetone.so',
       'odm/lib64/libvideomode.so',
       'vendor/lib64/libgnss.so',
     ): blob_fixup()
        .replace_needed(
            'android.hardware.sensors-V2-ndk.so',
            'android.hardware.sensors-V3-ndk.so'
        ),
     (
       'odm/lib64/hw/displayfeature.default.so',
     ): blob_fixup()
        .replace_needed(
            'android.hardware.sensors-V2-ndk.so',
            'android.hardware.sensors-V3-ndk.so'
        )
        .replace_needed(
            'libtinyxml2.so',
            'libtinyxml2-v34.so'
        ),
    'vendor/bin/system_dlkm_modprobe.sh': blob_fixup()
        .regex_replace(
            r'for kernel_ver_dir in \$\{system_dlkm_dir\}/\*;',
            'for kernel_ver_dir in ${system_dlkm_dir} ${system_dlkm_dir}/*;',
        ),
    (
       'vendor/lib64/libqcodec2_core.so',
    ): blob_fixup()
        .replace_needed(
            'android.hardware.graphics.common-V5-ndk.so',
            'android.hardware.graphics.common-V7-ndk.so'
        )
        .add_needed('libcodec2_shim.so'),
    (
       'vendor/lib64/libar-pal.so',
       'odm/lib64/libaudioroute_ext.so',
    ): blob_fixup()
        .add_needed('libaudioroute-xiaomi.so'),
    (
       'odm/lib64/libqc_hal.so',
       'odm/lib64/hw/fingerprint.qcom_us.so',
    ): blob_fixup()
        .replace_needed(
            'android.hardware.biometrics.fingerprint-V5-ndk.so',
            'android.hardware.biometrics.fingerprint-V4-ndk.so'
        )
        .replace_needed(
            'android.hardware.sensors-V2-ndk.so',
            'android.hardware.sensors-V3-ndk.so'
        ),
     (
       'odm/lib64/libmiXmlParser.so',
       'vendor/bin/poweropt-service',
       'vendor/lib64/libaodoptfeature.so',
       'vendor/lib64/libaudiocloudctrl.so',
       'vendor/lib64/libcamerapoweroptfeature.so',
       'vendor/lib64/libgamepoweroptfeature.so',
       'vendor/lib64/liblearningmodule.so',
       'vendor/lib64/liboffscreenpoweroptfeature.so',
       'vendor/lib64/libpowercallback.so',
       'vendor/lib64/libpowercore.so',
       'vendor/lib64/libpsmoptfeature.so',
       'vendor/lib64/libstandbyfeature.so',
       'vendor/lib64/libvideooptfeature.so',
     ): blob_fixup()
        .replace_needed(
            'libtinyxml2.so',
            'libtinyxml2-v34.so'
        ),
    (
       'vendor/lib64/hw/libaudioeffecthal.qti.so',
    ): blob_fixup()
        .binary_regex_replace(b'libtinyxml2.so\\0', b'libtinyxmlQ.so\\0'),
    (
       'vendor/lib64/libtinyxmlQ.so',
    ): blob_fixup()
        .binary_regex_replace(b'libtinyxml2.so\\0', b'libtinyxmlQ.so\\0'),
    (
       'vendor/lib64/libVoiceSdk.so',
       'vendor/lib64/libcapiv2uvvendor.so',
       'vendor/lib64/liblistensoundmodel2vendor.so',
    ): blob_fixup()
        .replace_needed('libtensorflowlite_c.so', 'libtensorflowlite_c_vendor.so'),
    # The stock camera provider uses the Android 14 tinyxml2 ABI and the
    # stock GraphicBuffer ABI.
    'vendor/bin/hw/vendor.qti.camera.provider-service_64': blob_fixup()
        .replace_needed('libtinyxml2.so', 'libtinyxml2-v34.so')
        .add_needed('libui.so')
        .call(camera_libui_runpath, need_tmp_dir=False),
    # These blobs were built against the Android 14 tinyxml2 ABI; the current
    # libtinyxml2 crashes them.
    tuple(
        [f'odm/lib64/camera/plugins/com.xiaomi.plugin.{p}.so' for p in (
            'anchor', 'offlineawbideal', 'offlineb2y', 'offlineformatconvertor',
            'offlinehdrraw2y', 'offlineheic', 'offlinei2y', 'offlinejpeg',
            'offlinemfnr', 'offlinemlawb', 'offlinetintlesshdr', 'offlinetintless',
            'offlineyuvreprocess', 'offlineyuvsplit')] +
        ['vendor/lib64/libcamxcoreutils.so', 'vendor/lib64/libcamxods.so',
         'vendor/lib64/libmicamera_aidl_provider.so',
         'vendor/lib64/libmicamera_hal_core.so', 'vendor/lib64/libsimulation.so']
    ): blob_fixup()
        .replace_needed('libtinyxml2.so', 'libtinyxml2-v34.so'),
    # Stock HyperOS audio config carries MIUI framework extensions that the
    # Lineage framework rejects, dropping the whole primary module or engine
    # configuration. Strip only those parts.
    'odm/etc/audio/audio_module_config_primary.xml': blob_fixup()
        .regex_replace(r'(?s)        <!-- MIUI ADD: Audio_MultiRoute -->\n        <route type="mix" sink="proxy_out" sources="([^"]*),virtual_deep_buffer" />\n.*?<!-- END Audio_MultiRoute -->\n',
                       r'        <route type="mix" sink="proxy_out" sources="\1" />\n')
        .regex_replace(r'(?s)[ \t]*<!-- MIUI ADD: Audio_MultiRoute -->\n.*?<!-- END Audio_MultiRoute -->\n', ''),
    'odm/etc/audio_policy_engine_product_strategies_mi.xml': blob_fixup()
        .regex_replace(r' +<Attributes> <Usage value="AUDIO_USAGE_BLUETOOTH_SCO"/> </Attributes>\n', ''),
    # MIUI device categories are unknown to AOSP. The MIUI media index runs to
    # 150; AOSP stops at 100, so map the speaker curve onto 0-100 and keep the
    # stock maximum (-0.3 dB) at the top of the range.
    'odm/etc/audio_policy_engine_stream_volumes_mi.xml': blob_fixup()
        .regex_replace(r'[ \t]*<volume deviceCategory="DEVICE_CATEGORY_(?:USB|A2DP|HEADSET_CE|HEADSET_SPATIALIZER_CE)[A-Z0-9_]*" ref="[^"]*"/>\n', '')
        .regex_replace(r'(?s)[ \t]*<volume deviceCategory="DEVICE_CATEGORY_(?:USB|A2DP|HEADSET_CE|HEADSET_SPATIALIZER_CE)[A-Z0-9_]*">\n.*?</volume>\n', '')
        .regex_replace(r'<point>60,-2950</point>\n( +)<point>70,-2600</point>\n +<point>80,-2250</point>\n +<point>90,-1900</point>\n +<point>100,-1550</point>\n +<point>110,-1200</point>\n +<point>120,-850</point>\n +<point>130,-550</point>\n +<point>140,-250</point>\n +<point>150,-30</point>',
                       r'<point>59,-2950</point>\n\1<point>69,-2600</point>\n\1<point>79,-2250</point>\n\1<point>89,-1900</point>\n\1<point>99,-1550</point>\n\1<point>100,-30</point>'),
    # Stock libprocessgroup exports SetTaskProfiles wrappers Android 16 dropped.
    'vendor/lib64/libcameraopt.so': blob_fixup().add_needed('libprocessgroup_shim.so'),
    # Stock ships these with a malformed declaration ('<?xml=version').
    tuple(f'odm/etc/camera/{n}motiontuning.xml' for n in (
        '', 'enhance_', 'snsc_', 'snsc_bokeh_', 'snsc_enhance_', 'snsc_noface_')):
        blob_fixup().regex_replace(r'^<\?xml=version', '<?xml version'),
}  # fmt: skip

# Keep stock V6 audio types separate from the unfrozen platform V6 module.
blob_fixups = flatten_fixups(blob_fixups)
for source, destination in (
    ('vendor/lib64/libaudioserviceexampleimpl.so', 'vendor/lib64/libaudioserviceexampleimpl.so'),
    ('vendor/lib64/soundfx/libbundleaidl.so', 'vendor/lib64/soundfx/libbundleaidl.so'),
    ('vendor/lib64/soundfx/libdownmixaidl.so', 'vendor/lib64/soundfx/libdownmixaidl.so'),
    ('vendor/lib64/soundfx/libdynamicsprocessingaidl.so', 'vendor/lib64/soundfx/libdynamicsprocessingaidl.so'),
    ('vendor/lib64/soundfx/libhwdapaidl.so', 'vendor/lib64/soundfx/libhwdapaidl.so'),
    ('vendor/lib64/soundfx/libloudnessenhanceraidl.so', 'vendor/lib64/soundfx/libloudnessenhanceraidl.so'),
    ('vendor/lib64/soundfx/liblvacfsprocessingaidl.so', 'vendor/lib64/soundfx/liblvacfsprocessingaidl.so'),
    ('vendor/lib64/soundfx/libmiwndnsprocessingaidl.so', 'vendor/lib64/soundfx/libmiwndnsprocessingaidl.so'),
    ('vendor/lib64/soundfx/libozoaidl.so', 'vendor/lib64/soundfx/libozoaidl.so'),
    ('vendor/lib64/soundfx/libreverbaidl.so', 'vendor/lib64/soundfx/libreverbaidl.so'),
    ('vendor/lib64/soundfx/libvisualizeraidl.so', 'vendor/lib64/soundfx/libvisualizeraidl.so'),
    ('vendor/lib64/android.hardware.audio.core.sounddose-V2-ndk.so', 'vendor/lib64/android.hardware.audio.core.sounddose-V2-ndk_xiaomi.so'),
    ('vendor/lib64/libaudio_aidl_conversion_common_ndk.so', 'vendor/lib64/libaudio_aidl_conversion_common_ndk_xiaomi.so'),
    ('vendor/lib64/hw/android.hardware.bluetooth.audio_sw.so', 'vendor/lib64/hw/android.hardware.bluetooth.audio_sw.so'),
):
    fixup = blob_fixups.get(destination, blob_fixups.get(source, blob_fixup()))
    blob_fixups[destination] = fixup.replace_needed(
        'android.media.audio.common.types-V6-ndk.so',
        'android.media.audio.common.types-V6-ndk_xiaomi.so')

module = ExtractUtilsModule(
    'piano',
    'xiaomi',
    blob_fixups=blob_fixups,
    lib_fixups=lib_fixups,
    namespace_imports=namespace_imports,
    check_elf=True,
)

if __name__ == '__main__':
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_dir():
        raise SystemExit('Supply exactly one offline OS4.0.5.0.XPYCNXM dump directory')
    source = Path(sys.argv[1])
    for line in Path(__file__).with_name('proprietary-files.txt').read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        spec, expected, *_ = line.split('|')
        name = spec.lstrip('-').split(';')[0].split(':')[0]
        path = source / name
        if not path.is_file() or hashlib.sha1(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f'Missing or mismatched pinned stock input: {name}')
    utils = ExtractUtils.device(module)
    utils.run()
