/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Turns a consumer IR pattern into the bit stream the piano ir_spi driver
 * shifts out at 1.92 MHz, 32 bits per word, MSB first. Matches the stock
 * consumerir.qcom.so output byte for byte (see docs/XIAOMI_CONFIGS.md).
 */

#pragma once

#include <cstdint>
#include <vector>

namespace piano::ir {

constexpr uint32_t kSpiHz = 1920000;
constexpr uint32_t kMaxTotalUs = 0x111112;  // keeps the bit count in 32 bits
constexpr int32_t kCarrierFreqs[] = {30000, 33000, 36000, 38000, 40000, 56000};

// Returns an empty vector when the pattern can't be sent.
inline std::vector<uint8_t> EncodePattern(int32_t carrier_hz, const std::vector<int32_t>& pattern) {
    if (carrier_hz < 1 || pattern.empty()) return {};

    // End time of each mark/space, 5 us early like stock.
    std::vector<int32_t> ends(pattern.size());
    int32_t t = -5;
    for (size_t i = 0; i < pattern.size(); i++) ends[i] = t += pattern[i];
    if (static_cast<uint32_t>(t) >= kMaxTotalUs) return {};
    uint32_t total_us = t;

    uint64_t scaled = static_cast<uint64_t>(total_us * 1920u) * 0x10624dd3u;
    uint32_t bits = scaled >> 38;  // total_us * 1.92
    uint32_t bytes = (scaled >> 41) + ((bits & 7) != 0);
    if (bytes & 0x3ff) bytes = (bytes & 0xffc00) + 0x400;  // whole 1 KiB blocks

    std::vector<uint8_t> out(bytes, 0);
    auto* words = reinterpret_cast<uint32_t*>(out.data());

    uint32_t period = (kSpiHz + carrier_hz / 2) / carrier_hz;     // bits per cycle
    uint32_t on = (static_cast<uint64_t>(period * 10) * 0x51eb851fu) >> 35;  // 40 %
    uint32_t phase = 0, word = 0;
    int shift = 31;

    for (uint32_t b = 0; b < bits; b++) {
        uint32_t us = (static_cast<uint64_t>(b * 1000) * 0x88888889u) >> 42;
        size_t seg = 0;
        while (seg < ends.size() && static_cast<int32_t>(us) > ends[seg]) seg++;

        bool lit = false;
        if (seg < ends.size()) {
            if (seg & 1) {
                phase = 0;  // space
            } else if (phase++ < on) {
                lit = true;
            } else if (phase == period) {
                phase = 0;
            }
        }
        if (lit) words[word] |= 1u << shift;
        if (--shift < 0 || b == bits - 1) {
            word++;
            shift = 31;
        }
    }
    return out;
}

}  // namespace piano::ir
