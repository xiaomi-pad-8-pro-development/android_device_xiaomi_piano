/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Open replacement for Xiaomi's battery anti-aging service.
 *
 * Reads the stock rules (odm/etc/charger/BAA_config_*.json, AES-128-CBC with
 * the key from libbaa_common.so) and applies the two strategies piano enables:
 *
 *  - LowSoh-FvDown: in the configured cycle range with health below the
 *    threshold, lower the float voltage through smart_fv.
 *  - BasedOnCC-VolDown: pick the charge table for the battery type and cycle
 *    count, pack it in the layout the mca smart charge driver reads and send
 *    it to /dev/smart_charge_cdev. See docs/XIAOMI_CONFIGS.md.
 *
 * The tables are re-sent when the cycle count bucket changes.
 */

#define LOG_TAG "piano-battery-health"

#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/properties.h>
#include <android-base/strings.h>
#include <android-base/unique_fd.h>
#include <fcntl.h>
#include <json/json.h>
#include <openssl/evp.h>
#include <sys/ioctl.h>
#include <unistd.h>

#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <vector>

using android::base::GetProperty;
using android::base::ReadFileToString;
using android::base::Trim;
using android::base::WriteStringToFile;

namespace {

constexpr char kKey[] = "michargerbattery";
constexpr char kPrefix[] = "BAA_ENC:";
constexpr char kDeviceConfig[] = "/odm/etc/charger/BAA_config_piano.json";
constexpr char kCommonConfig[] = "/odm/etc/charger/BAA_config_common.json";
constexpr char kCdev[] = "/dev/smart_charge_cdev";
constexpr unsigned long kSmartChgDataCmd = 0xd0001001;  // _IOWR(0x10, 1, 4096)
constexpr size_t kBufSize = 4096;
constexpr unsigned kPollSeconds = 30 * 60;

std::optional<std::string> Base64Decode(const std::string& in) {
    std::string out(in.size() / 4 * 3 + 3, '\0');
    int n = EVP_DecodeBlock(reinterpret_cast<uint8_t*>(out.data()),
                            reinterpret_cast<const uint8_t*>(in.data()), in.size());
    if (n < 0) return std::nullopt;
    // EVP_DecodeBlock counts '=' padding as zero bytes.
    size_t pad = 0;
    for (auto it = in.rbegin(); it != in.rend() && *it == '='; ++it) pad++;
    out.resize(n - pad);
    return out;
}

std::optional<std::string> Decrypt(const std::string& path) {
    std::string text;
    if (!ReadFileToString(path, &text)) return std::nullopt;
    text = Trim(text);
    if (!android::base::StartsWith(text, kPrefix)) return text;  // plain JSON

    auto raw = Base64Decode(text.substr(strlen(kPrefix)));
    if (!raw || raw->size() <= 16) return std::nullopt;

    const auto* iv = reinterpret_cast<const uint8_t*>(raw->data());
    const auto* in = iv + 16;
    int in_len = raw->size() - 16;
    std::string out(in_len + 16, '\0');
    int len = 0, fin = 0;

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    bool ok = ctx &&
              EVP_DecryptInit_ex(ctx, EVP_aes_128_cbc(), nullptr,
                                 reinterpret_cast<const uint8_t*>(kKey), iv) == 1 &&
              EVP_DecryptUpdate(ctx, reinterpret_cast<uint8_t*>(out.data()), &len, in,
                                in_len) == 1 &&
              EVP_DecryptFinal_ex(ctx, reinterpret_cast<uint8_t*>(out.data()) + len, &fin) == 1;
    EVP_CIPHER_CTX_free(ctx);
    if (!ok) return std::nullopt;
    out.resize(len + fin);
    return out;
}

std::optional<Json::Value> LoadConfig() {
    for (const char* path : {kDeviceConfig, kCommonConfig}) {
        auto text = Decrypt(path);
        if (!text) continue;
        Json::Value root;
        Json::CharReaderBuilder builder;
        std::string errs;
        std::unique_ptr<Json::CharReader> reader(builder.newCharReader());
        if (reader->parse(text->data(), text->data() + text->size(), &root, &errs)) {
            LOG(INFO) << "Loaded " << path;
            return root;
        }
        LOG(ERROR) << "Bad JSON in " << path << ": " << errs;
    }
    return std::nullopt;
}

std::optional<int> ReadInt(const std::string& path) {
    std::string s;
    if (path.empty() || !ReadFileToString(path, &s)) return std::nullopt;
    char* end = nullptr;
    long v = strtol(Trim(s).c_str(), &end, 10);
    if (end == nullptr || *end != '\0') return std::nullopt;
    return static_cast<int>(v);
}

bool StrategyEnabled(const Json::Value& root, int index) {
    for (const auto& v : root["strategy"]["supported_strategy_index"])
        if (v.asInt() == index) return true;
    return false;
}

// LowSoh-FvDown (strategy 1).
void ApplyLowSoh(const Json::Value& root) {
    const auto& s = root["LowSoh-FvDown"];
    if (!StrategyEnabled(root, 1) || !s["enable_by_default"].asBool()) return;

    const auto& nodes = s["sysfs_node"];
    auto cycles = ReadInt(nodes["cyclecount"]["path"].asString());
    auto soh = ReadInt(nodes["soh"]["path"].asString());
    if (!cycles || !soh) return;

    bool aged = *cycles >= nodes["cyclecount"]["range_min"].asInt() &&
                *cycles <= nodes["cyclecount"]["range_max"].asInt() &&
                *soh < nodes["soh"]["threshold"].asInt();
    const auto& fv = root["strategy"]["smart_fv"];
    int max_mv = fv["decrease_mv_max"].asInt();
    int mv = aged ? std::min(nodes["smart_fv"]["value"].asInt(), max_mv) : 0;

    // Like stock, leave the float voltage alone while the battery is nearly
    // full; the step is applied on a later pass, below the threshold.
    int soc_limit = fv.get("soc_threshold", 90).asInt();
    auto soc = ReadInt("/sys/class/power_supply/battery/capacity");
    if (mv > 0 && soc && *soc >= soc_limit) {
        LOG(INFO) << "LowSoh: soc " << *soc << " >= " << soc_limit << ", not set";
        return;
    }

    for (const char* key : {"smart_fv", "smart_batt"}) {
        std::string path = nodes[key]["path"].asString();
        if (!path.empty() && access(path.c_str(), W_OK) == 0)
            WriteStringToFile(std::to_string(mv), path);
    }
    LOG(INFO) << "LowSoh: cycles=" << *cycles << " soh=" << *soh << " fv_down=" << mv << "mV";
}

void Put32(std::vector<uint8_t>& b, uint32_t v) {
    uint8_t p[4];
    memcpy(p, &v, 4);
    b.insert(b.end(), p, p + 4);
}

std::string BatteryType(const Json::Value& vendor) {
    std::string hwc = GetProperty("ro.boot.hwc", "");
    const auto& map = vendor["batt_type_get_by_property"];
    for (const auto& id : map.getMemberNames()) {
        const auto& e = map[id];
        for (const auto& v : e["ro.boot.hwc"])
            if (v.asString() == hwc) return e["batt_type_name"].asString();
    }
    return "CN-battery";
}

int CycleIndex(const Json::Value& battery, int cycles) {
    for (const auto& e : battery["cyclecount_index_map"])
        if (cycles >= e["min"].asInt() && cycles <= e["max"].asInt()) return e["idx"].asInt();
    return -1;
}

// Layout from docs/XIAOMI_CONFIGS.md. Returns an empty vector on error.
std::vector<uint8_t> PackTable(const Json::Value& table) {
    std::vector<uint8_t> body;
    const auto& jeita = table["jeita-term-para"];
    const auto& wire = table["wire"];

    for (const char* k : {"FFC", "normal"}) {
        for (const auto& e : jeita[k]) {
            Put32(body, e["idx"].asInt());
            Put32(body, e["temp-min"].asInt());
            Put32(body, e["temp-max"].asInt());
            Put32(body, e["vterm"].asInt());
            Put32(body, e["iterm"].asInt());
        }
    }
    for (const char* k : {"FFC", "normal"}) {
        uint32_t ffc = strcmp(k, "FFC") == 0;
        for (const auto& e : wire[k]) {
            Put32(body, 1);  // wired
            Put32(body, ffc);
            Put32(body, e["temp"]["idx"].asInt());
            Put32(body, e["temp"]["min"].asInt());
            Put32(body, e["temp"]["max"].asInt());
            Put32(body, e["step"].size());
            for (const auto& s : e["step"]) {
                Put32(body, s["mV"].asInt());
                Put32(body, s["mA_h"].asInt());
                Put32(body, s["mA_l"].asInt());
            }
        }
    }

    std::vector<uint8_t> buf;
    uint32_t total = 9 * 4 + body.size();
    if (total > kBufSize) return {};
    Put32(buf, total);
    Put32(buf, 0);  // checksum, filled below
    Put32(buf, 0);  // type
    Put32(buf, jeita["FFC"].size());
    Put32(buf, jeita["normal"].size());
    Put32(buf, wire["FFC"].size());
    Put32(buf, wire["normal"].size());
    Put32(buf, 0);  // wireless FFC
    Put32(buf, 0);  // wireless normal
    buf.insert(buf.end(), body.begin(), body.end());

    uint32_t sum = 0;
    for (uint8_t c : buf) sum += c;
    memcpy(buf.data() + 4, &sum, 4);
    return buf;
}

// BasedOnCC-VolDown (strategy 3). Returns the cycle index that was sent.
int ApplyBasedOnCC(const Json::Value& root, int last_index) {
    const auto& s = root["BasedOnCC-VolDown"];
    if (!StrategyEnabled(root, 3) || !s["enable_by_default"].asBool()) return last_index;

    auto cycles = ReadInt(s["sysfs_node"]["cyclecount"]["path"].asString());
    if (!cycles) return last_index;

    // Only vendor_id_2 is defined for piano.
    const auto& vendor = s["vendor_id_2"];
    std::string type = BatteryType(vendor);
    const auto& battery = vendor[type];
    int index = CycleIndex(battery, *cycles);
    if (index < 0 || index == last_index) return last_index;

    const Json::Value* table = nullptr;
    for (const auto& t : battery["cyclecount"])
        if (t["cyclecount_index"].asInt() == index) table = &t;
    if (!table) return last_index;

    std::vector<uint8_t> buf = PackTable(*table);
    if (buf.empty()) {
        LOG(ERROR) << "Table too large";
        return last_index;
    }
    uint32_t sum;
    memcpy(&sum, buf.data() + 4, 4);
    buf.resize(kBufSize, 0);

    android::base::unique_fd fd(open(kCdev, O_RDWR | O_CLOEXEC));
    if (fd < 0) {
        PLOG(ERROR) << "open " << kCdev;
        return last_index;
    }
    // The driver checks and applies the table when the file is closed.
    if (ioctl(fd.get(), kSmartChgDataCmd, buf.data()) < 0) {
        PLOG(ERROR) << "ioctl";
        return last_index;
    }
    LOG(INFO) << "BasedOnCC: " << type << " cycles=" << *cycles << " index=" << index
              << " checksum=" << sum;
    return index;
}

}  // namespace

int main(int argc, char** argv) {
    android::base::InitLogging(argv, android::base::LogdLogger(android::base::SYSTEM));
    bool once = argc > 1 && strcmp(argv[1], "--once") == 0;

    auto root = LoadConfig();
    if (!root) {
        LOG(ERROR) << "No battery anti-aging config";
        return 1;
    }

    int index = -1;
    for (;;) {
        ApplyLowSoh(*root);
        index = ApplyBasedOnCC(*root, index);
        if (once) return 0;
        sleep(kPollSeconds);
    }
}
