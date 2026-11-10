/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Open replacement for Xiaomi's mi_thermald.
 *
 * Reads the stock rules (odm/etc/thermal-normal.conf, AES-128-CBC with the key
 * and IV "thermalopenssl.h") and the device map (vendor/etc/
 * thermald-devices.conf), then runs the three rule types piano uses:
 *
 *  - virtual: weighted average of thermal zones plus an offset.
 *  - monitor, ss: trip levels with hysteresis; each level has a target.
 *    "reverse" rules trip on falling values (battery level).
 *
 * Devices: map entries drive a cooling device (cur_state) or a sysfs node;
 * "cpuN" caps the frequency of the policy holding CPU N. boost_limit and
 * video_mode are ignored: the first only gates mi_thermald's own boost
 * feature and the stock daemon has no handler for the second. Several rules may
 * drive one device; select_higher picks the winner, CPU caps take the lowest.
 *
 * Until vendor.piano.thermald.active is true the daemon only logs what it
 * would set, so it can run next to mi_thermald and be compared.
 * See docs/XIAOMI_CONFIGS.md.
 */

#define LOG_TAG "piano-thermald"

#include <android-base/file.h>
#include <android-base/logging.h>
#include <android-base/properties.h>
#include <android-base/strings.h>
#include <dirent.h>
#include <openssl/evp.h>
#include <unistd.h>

#include <algorithm>
#include <climits>
#include <cstring>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <vector>

using android::base::GetBoolProperty;
using android::base::GetProperty;
using android::base::ReadFileToString;
using android::base::Split;
using android::base::StartsWith;
using android::base::Trim;
using android::base::WriteStringToFile;

namespace {

constexpr char kKey[] = "thermalopenssl.h";
constexpr char kRules[] = "/odm/etc/thermal-normal.conf";
constexpr char kDevices[] = "/vendor/etc/thermald-devices.conf";
constexpr char kActiveProp[] = "vendor.piano.thermald.active";
constexpr char kProfileProp[] = "sys.piano.thermald.profile";
constexpr char kProfileDir[] = "/odm/etc/";
constexpr char kCpuLimits[] = "/sys/class/thermal/thermal_message/cpu_limits";
constexpr int kTickMs = 500;

using Section = std::map<std::string, std::vector<std::string>>;

std::optional<std::string> ReadMaybeEncrypted(const std::string& path) {
    std::string raw;
    if (!ReadFileToString(path, &raw)) return std::nullopt;
    if (!raw.empty() && (raw[0] == '[' || raw[0] == '#')) return raw;

    std::string out(raw.size() + 16, '\0');
    int len = 0, fin = 0;
    auto key = reinterpret_cast<const uint8_t*>(kKey);
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    bool ok = ctx && EVP_DecryptInit_ex(ctx, EVP_aes_128_cbc(), nullptr, key, key) == 1 &&
              EVP_DecryptUpdate(ctx, reinterpret_cast<uint8_t*>(out.data()), &len,
                                reinterpret_cast<const uint8_t*>(raw.data()), raw.size()) == 1 &&
              EVP_DecryptFinal_ex(ctx, reinterpret_cast<uint8_t*>(out.data()) + len, &fin) == 1;
    EVP_CIPHER_CTX_free(ctx);
    if (!ok) return std::nullopt;
    out.resize(len + fin);
    return out;
}

// "[NAME]" followed by "key<ws>values..." lines.
std::vector<std::pair<std::string, Section>> ParseRules(const std::string& text) {
    std::vector<std::pair<std::string, Section>> out;
    for (const auto& raw : Split(text, "\n")) {
        std::string line = Trim(raw);
        if (line.empty() || line[0] == '#') continue;
        if (line.front() == '[' && line.back() == ']') {
            out.push_back({line.substr(1, line.size() - 2), {}});
            continue;
        }
        if (out.empty()) continue;
        std::istringstream ss(line);
        std::string key, v;
        ss >> key;
        while (ss >> v) out.back().second[key].push_back(v);
    }
    return out;
}

// "[" ... "key:value" ... "]" blocks.
std::vector<std::map<std::string, std::string>> ParseDevices(const std::string& text) {
    std::vector<std::map<std::string, std::string>> out;
    bool in = false;
    for (const auto& raw : Split(text, "\n")) {
        std::string line = Trim(raw);
        if (line == "[") {
            out.push_back({});
            in = true;
        } else if (line == "]") {
            in = false;
        } else if (in) {
            auto pos = line.find(':');
            if (pos != std::string::npos) out.back()[line.substr(0, pos)] = line.substr(pos + 1);
        }
    }
    return out;
}

long ToLong(const std::string& s, long def = 0) {
    char* end = nullptr;
    long v = strtol(s.c_str(), &end, 10);
    return (end && *end == '\0') ? v : def;
}

std::optional<long> ReadLong(const std::string& path) {
    std::string s;
    if (!ReadFileToString(path, &s)) return std::nullopt;
    s = Trim(s);
    char* end = nullptr;
    long v = strtol(s.c_str(), &end, 10);
    if (end == s.c_str()) return std::nullopt;
    return v;
}

// type -> /sys/class/<cls>/<entry>, for thermal_zone* and cooling_device*.
std::map<std::string, std::string> ScanByType(const char* prefix) {
    std::map<std::string, std::string> out;
    DIR* d = opendir("/sys/class/thermal");
    if (!d) return out;
    while (dirent* e = readdir(d)) {
        if (!StartsWith(e->d_name, prefix)) continue;
        std::string dir = std::string("/sys/class/thermal/") + e->d_name;
        std::string type;
        if (ReadFileToString(dir + "/type", &type)) out.emplace(Trim(type), dir);
    }
    closedir(d);
    return out;
}

struct Device {
    std::string name;
    std::string path;  // file written with the target
    std::string prefix;  // written before the target, for cpu_limits
    long def = 0;
    bool select_higher = true;
    bool known = false;
};

struct Rule {
    std::string name;
    std::string algo;
    std::string sensor;
    std::vector<std::string> devices;
    std::vector<long> trig, clr;
    std::vector<std::vector<long>> targets;  // per level, per device
    bool reverse = false;
    int polling_ms = 2000;
    int level = -1;
    int elapsed_ms = 1 << 20;  // due on the first tick
};

struct Virtual {
    std::string name;
    std::vector<std::string> sensors;
    std::vector<long> weights;
    long weight_sum = 1;
    long compensation = 0;
};

class Daemon {
  public:
    bool Load();
    void Tick();

  private:
    std::optional<long> ReadSensor(const std::string& name, int depth = 0);
    Device& GetDevice(const std::string& name);
    void Apply();
    void CheckProfile();

    std::vector<Rule> normal_rules_;
    std::string profile_;
    std::map<std::string, std::string> zones_ = ScanByType("thermal_zone");
    std::map<std::string, std::string> coolers_ = ScanByType("cooling_device");
    std::map<std::string, std::map<std::string, std::string>> device_map_;
    std::map<std::string, Device> devices_;
    std::map<std::string, std::string> simulated_;  // sensor -> path
    std::map<std::string, Virtual> virtuals_;
    std::vector<Rule> rules_;
    std::map<std::string, long> applied_;
    std::set<std::string> warned_;
    bool active_ = false;
};

std::optional<Rule> MakeRule(const std::string& name, Section& s, const std::string& algo) {
    Rule r{.name = name, .algo = algo};
    if (s["sensor"].empty() || s["device"].empty()) return std::nullopt;
    r.sensor = s["sensor"][0];
    r.devices = Split(s["device"][0], "+");
    for (auto& t : s["trig"]) r.trig.push_back(ToLong(t));
    for (auto& t : s["clr"]) r.clr.push_back(ToLong(t));
    for (auto& t : s["target"]) {
        std::vector<long> per;
        for (auto& p : Split(t, "+")) per.push_back(ToLong(p));
        r.targets.push_back(per);
    }
    r.reverse = !s["reverse"].empty() && s["reverse"][0] == "1";
    if (!s["polling"].empty()) r.polling_ms = std::max(250L, ToLong(s["polling"][0]));
    if (r.trig.size() != r.clr.size() || r.trig.size() != r.targets.size()) {
        LOG(WARNING) << name << ": trig/clr/target sizes differ, skipped";
        return std::nullopt;
    }
    return r;
}

// Sensors always come from thermal-normal; a profile only swaps the rules.
bool Daemon::Load() {
    auto rules = ReadMaybeEncrypted(kRules);
    auto devices = ReadMaybeEncrypted(kDevices);
    if (!rules || !devices) {
        LOG(ERROR) << "Cannot read " << (!rules ? kRules : kDevices);
        return false;
    }
    for (auto& d : ParseDevices(*devices)) device_map_[d["name"]] = d;

    for (auto& [name, s] : ParseRules(*rules)) {
        std::string algo = s["algo_type"].empty() ? "" : s["algo_type"][0];
        if (algo == "simulated" && !s["path"].empty()) {
            simulated_[name] = s["path"][0];
        } else if (algo == "virtual") {
            Virtual v{.name = name, .sensors = s["sensors"]};
            for (auto& w : s["weight"]) v.weights.push_back(ToLong(w));
            if (!s["weight_sum"].empty()) v.weight_sum = std::max(1L, ToLong(s["weight_sum"][0]));
            if (!s["compensation"].empty()) v.compensation = ToLong(s["compensation"][0]);
            virtuals_[name] = v;
        } else if (algo == "monitor" || algo == "ss") {
            if (auto r = MakeRule(name, s, algo)) normal_rules_.push_back(*r);
        }
    }
    rules_ = normal_rules_;
    LOG(INFO) << "Loaded " << rules_.size() << " rules, " << virtuals_.size()
              << " virtual sensors, " << device_map_.size() << " mapped devices";
    return true;
}

// sys.piano.thermald.profile=<name> runs odm/etc/thermal-<name>.conf,
// for example tgame for games. Empty or "normal" goes back to the default.
void Daemon::CheckProfile() {
    std::string want = GetProperty(kProfileProp, "");
    if (want == "normal") want.clear();
    if (want == profile_) return;

    std::vector<Rule> rules;
    if (want.empty()) {
        rules = normal_rules_;
    } else if (want.find_first_of("/.") != std::string::npos) {
        LOG(ERROR) << "Bad profile name " << want;
        return;
    } else {
        auto text = ReadMaybeEncrypted(std::string(kProfileDir) + "thermal-" + want + ".conf");
        if (!text) {
            LOG(ERROR) << "No thermal profile " << want;
            return;
        }
        for (auto& [name, s] : ParseRules(*text)) {
            std::string algo = s["algo_type"].empty() ? "" : s["algo_type"][0];
            if (algo == "monitor" || algo == "ss")
                if (auto r = MakeRule(name, s, algo)) rules.push_back(*r);
        }
        if (rules.empty()) {
            LOG(ERROR) << "Thermal profile " << want << " has no rules";
            return;
        }
    }
    LOG(INFO) << "Profile " << (profile_.empty() ? "normal" : profile_) << " -> "
              << (want.empty() ? "normal" : want) << ", " << rules.size() << " rules";
    profile_ = want;
    rules_ = rules;
    applied_.clear();
}

std::optional<long> Daemon::ReadSensor(const std::string& name, int depth) {
    if (depth > 4) return std::nullopt;
    if (auto it = virtuals_.find(name); it != virtuals_.end()) {
        const Virtual& v = it->second;
        long sum = 0;
        for (size_t i = 0; i < v.sensors.size() && i < v.weights.size(); i++) {
            auto t = ReadSensor(v.sensors[i], depth + 1);
            if (!t) return std::nullopt;
            sum += *t * v.weights[i];
        }
        return sum / v.weight_sum + v.compensation;
    }
    if (auto it = simulated_.find(name); it != simulated_.end()) return ReadLong(it->second);
    if (auto it = zones_.find(name); it != zones_.end()) return ReadLong(it->second + "/temp");
    if (warned_.insert("sensor:" + name).second) LOG(WARNING) << "No sensor " << name;
    return std::nullopt;
}

Device& Daemon::GetDevice(const std::string& name) {
    auto it = devices_.find(name);
    if (it != devices_.end()) return it->second;

    Device d{.name = name};
    if (auto m = device_map_.find(name); m != device_map_.end()) {
        auto& e = m->second;
        d.def = ToLong(e["def_target"]);
        d.select_higher = e["select_higher"] != "0";
        if (!e["path"].empty()) {
            d.path = e["path"];
        } else if (auto c = coolers_.find(e["cooling_name"]); c != coolers_.end()) {
            d.path = c->second + "/cur_state";
        }
    } else if (StartsWith(name, "cpu") && name.find_first_not_of("0123456789", 3) == std::string::npos) {
        // Frequency cap on the policy that holds this CPU. Xiaomi's mi_thermal
        // driver takes "cpuN <kHz>" and holds it as a kernel QoS request, which
        // the power HAL cannot overwrite; fall back to the cpufreq node.
        std::string dir = "/sys/devices/system/cpu/" + name + "/cpufreq/";
        if (access(kCpuLimits, W_OK) == 0) {
            d.path = kCpuLimits;
            d.prefix = name + " ";
        } else {
            d.path = dir + "scaling_max_freq";
        }
        d.def = ReadLong(dir + "cpuinfo_max_freq").value_or(0);
        d.select_higher = false;
    }
    d.known = !d.path.empty() && access(d.path.c_str(), F_OK) == 0;
    if (!d.known) LOG(WARNING) << "Device " << name << " has no node here, ignored";
    return devices_.emplace(name, d).first->second;
}

void Daemon::Tick() {
    CheckProfile();
    bool changed = applied_.empty();
    for (Rule& r : rules_) {
        r.elapsed_ms += kTickMs;
        if (r.elapsed_ms < r.polling_ms) continue;
        r.elapsed_ms = 0;

        auto v = ReadSensor(r.sensor);
        if (!v) continue;
        auto above = [&](long a, long b) { return r.reverse ? a <= b : a >= b; };
        auto below = [&](long a, long b) { return r.reverse ? a > b : a < b; };

        int level = r.level;
        while (level + 1 < (int)r.trig.size() && above(*v, r.trig[level + 1])) level++;
        while (level >= 0 && below(*v, r.clr[level])) level--;
        if (level != r.level) {
            LOG(INFO) << r.name << ": " << r.sensor << "=" << *v << " level " << r.level << " -> "
                      << level;
            r.level = level;
            changed = true;
        }
    }
    // Switching between shadow and active mode re-applies every device.
    bool active = GetBoolProperty(kActiveProp, false);
    if (active != active_) {
        active_ = active;
        applied_.clear();
        changed = true;
    }
    if (changed || applied_.empty()) Apply();
}

void Daemon::Apply() {
    // Collect every rule's request per device, then pick the winner.
    std::map<std::string, std::vector<long>> requests;
    for (const Rule& r : rules_) {
        for (size_t i = 0; i < r.devices.size(); i++) {
            requests[r.devices[i]];  // keep idle devices so they return to default
            if (r.level < 0) continue;
            const auto& t = r.targets[r.level];
            requests[r.devices[i]].push_back(t.size() > i ? t[i] : t.back());
        }
    }

    bool active = active_;
    for (auto& [name, reqs] : requests) {
        Device& d = GetDevice(name);
        if (!d.known) continue;
        long value = d.def;
        if (!reqs.empty())
            value = d.select_higher ? *std::max_element(reqs.begin(), reqs.end())
                                    : *std::min_element(reqs.begin(), reqs.end());
        if (auto it = applied_.find(name); it != applied_.end() && it->second == value) continue;
        applied_[name] = value;
        LOG(INFO) << (active ? "set " : "would set ") << name << " = " << value;
        if (active && !WriteStringToFile(d.prefix + std::to_string(value), d.path))
            PLOG(ERROR) << "write " << d.path;
    }
}

}  // namespace

int main(int, char** argv) {
    android::base::InitLogging(argv, android::base::LogdLogger(android::base::SYSTEM));
    Daemon daemon;
    if (!daemon.Load()) return 1;
    for (;;) {
        daemon.Tick();
        usleep(kTickMs * 1000);
    }
}
