#!/vendor/bin/sh
# The ADSP charger firmware only allows fast charging after Xiaomi's private
# charger handshake sets pd_verifed. Third-party PPS chargers can't pass it and
# stay at about 18 W. Mark a connected PD charger as verified whenever the
# firmware clears the flag, so standard PPS chargers can charge at full rate.
# Turn off with: setprop persist.vendor.piano.free_pps 0

B=/sys/class/qcom-battery
while [ "$(getprop persist.vendor.piano.free_pps)" != 0 ]; do
    case "$(cat $B/usb_real_type 2>/dev/null)" in
    *PD*)
        [ "$(cat $B/pd_verifed 2>/dev/null)" = 1 ] || echo 1 > $B/pd_verifed
        ;;
    esac
    sleep 2
done
