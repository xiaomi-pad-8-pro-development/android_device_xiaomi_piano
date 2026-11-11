/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Consumer IR HAL for the piano IR blaster (/dev/ir_spi), replacing the
 * stock consumerir.qcom.so behind the AOSP example service.
 */

#define LOG_TAG "android.hardware.ir-service.piano"

#include <aidl/android/hardware/ir/BnConsumerIr.h>
#include <android-base/logging.h>
#include <android-base/unique_fd.h>
#include <android/binder_manager.h>
#include <android/binder_process.h>
#include <fcntl.h>
#include <linux/lirc.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include "IrSpiEncoder.h"

using aidl::android::hardware::ir::BnConsumerIr;
using aidl::android::hardware::ir::ConsumerIrFreqRange;

namespace {

constexpr char kDevice[] = "/dev/ir_spi";

class ConsumerIr : public BnConsumerIr {
    ndk::ScopedAStatus getCarrierFreqs(std::vector<ConsumerIrFreqRange>* out) override {
        out->clear();
        for (int32_t hz : piano::ir::kCarrierFreqs) out->push_back({.minHz = hz, .maxHz = hz});
        return ndk::ScopedAStatus::ok();
    }

    ndk::ScopedAStatus transmit(int32_t carrier_hz, const std::vector<int32_t>& pattern) override {
        std::vector<uint8_t> buf = piano::ir::EncodePattern(carrier_hz, pattern);
        if (buf.empty()) return ndk::ScopedAStatus::fromExceptionCode(EX_ILLEGAL_ARGUMENT);

        android::base::unique_fd fd(open(kDevice, O_RDWR | O_CLOEXEC));
        if (fd < 0) {
            PLOG(ERROR) << "open " << kDevice;
            return ndk::ScopedAStatus::fromExceptionCode(EX_SERVICE_SPECIFIC);
        }
        // The driver reuses LIRC_SET_SEND_MODE to set the transfer length.
        uint32_t len = buf.size();
        if (ioctl(fd.get(), LIRC_SET_SEND_MODE, &len) < 0 ||
            write(fd.get(), buf.data(), len) != static_cast<ssize_t>(len)) {
            PLOG(ERROR) << "send " << len << " bytes";
            return ndk::ScopedAStatus::fromExceptionCode(EX_SERVICE_SPECIFIC);
        }
        return ndk::ScopedAStatus::ok();
    }
};

}  // namespace

int main() {
    ABinderProcess_setThreadPoolMaxThreadCount(0);
    auto ir = ndk::SharedRefBase::make<ConsumerIr>();
    const std::string name = std::string(ConsumerIr::descriptor) + "/default";
    CHECK_EQ(AServiceManager_addService(ir->asBinder().get(), name.c_str()), STATUS_OK);
    ABinderProcess_joinThreadPool();
    return EXIT_FAILURE;
}
