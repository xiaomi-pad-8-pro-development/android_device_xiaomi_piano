#!/vendor/bin/sh
# The ADSP charger firmware only allows fast charging after Xiaomi's private
# charger handshake sets pd_verifed. Third-party PPS chargers can't pass it and
# stay at about 18 W. Marking the charger as verified helps on some chargers
# and does nothing on others, so try it once per plug-in: measure the charge
# current, set pd_verifed, measure again after 30 s, and keep forcing it only
# if the current clearly went up. Unplugging resets the trial.
# Turn off with: setprop persist.vendor.piano.free_pps 0

B=/sys/class/qcom-battery
P=/sys/class/power_supply/battery
TAG=piano-free-pps

# Charge current in mA, positive while charging (current_now is negative then).
ma() {
    c=$(cat $P/current_now 2>/dev/null)
    echo $(( -${c:-0} / 1000 ))
}

state=idle
while [ "$(getprop persist.vendor.piano.free_pps)" != 0 ]; do
    case "$(cat $B/usb_real_type 2>/dev/null)" in
    *PD*)
        case $state in
        idle)
            cap=$(cat $P/capacity 2>/dev/null)
            if [ "${cap:-100}" -ge 80 ]; then
                state=skip
                log -t $TAG "battery ${cap}%, no trial"
            else
                sleep 10
                before=$(ma)
                echo 1 > $B/pd_verifed
                sleep 30
                after=$(ma)
                if [ "$after" -ge 2000 ] && [ "$after" -ge $(( before * 13 / 10 )) ]; then
                    state=keep
                    log -t $TAG "trial ${before} mA -> ${after} mA, keeping"
                else
                    state=skip
                    log -t $TAG "trial ${before} mA -> ${after} mA, giving up"
                fi
            fi
            ;;
        keep)
            [ "$(cat $B/pd_verifed 2>/dev/null)" = 1 ] || echo 1 > $B/pd_verifed
            ;;
        esac
        ;;
    *)
        [ "$(cat /sys/class/power_supply/usb/online 2>/dev/null)" = 1 ] || state=idle
        ;;
    esac
    sleep 2
done
