#!/bin/bash

##
## Case Name: verify-kernel-boot-log
## Preconditions:
##    N/A
## Description:
##    Check kernel boot log, and see if there is any errors
## Case step:
##    1. Disable kernel check point and check kernel log from kernel boot
## Expect result:
##    No error found in kernel boot log
##

set -e

# source from the relative path of current folder
# shellcheck source=case-lib/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")"/../case-lib/lib.sh

main()
{
    printf 'System booted at: '; uptime -s
    journalctl -b | head -n 3

    func_opt_parse_option "$@"
    disable_kernel_check_point

    print_module_params

    wait_is_system_running --system
    [ "$(id -un)" = root ] ||
        wait_is_system_running --user

    ntp_check

    platform=$(sof-dump-status.py -p)
    case "$platform" in
        adl)
            skip_test "internal #99: missing GPU firmware and others on $platform"
            ;;
    esac

    sof-kernel-log-check.sh
}

wait_is_system_running()
{
    local manager="$1" # --user or --system
    local wait_secs=30 ret=0
    local cmd=(systemctl "$manager" --wait is-system-running)

    printf '%s\n' "${cmd[*]}"
    timeout -k 5 "$wait_secs" "${cmd[@]}" || ret=$?

    if [ $ret = 0 ]; then return 0; fi

    if [ $ret = 124 ]; then
        dloge "$0 timed out waiting $wait_secs seconds for ${cmd[*]}"
    fi
    (   set +e; set -x
        systemctl "$manager" --no-pager --failed
        systemctl "$manager" | grep -v active
        systemctl "$manager" is-system-running
        # See https://github.com/thesofproject/sof-test/discussions/964
        DISPLAY=:0 xrandr --listmonitors
    )
    die "Some services are not running correctly"
}

ntp_check()
{
    # Check this device time is NTP Synchronized
    if check_ntp_sync; then
        printf '\nTime Check: NTP Synchronized\n'
    else
        timedatectl show
        # try to disable/enable NTP once, this will trigger ntp sync twice,
        # before stopping ntp and after enabling ntp.
        re_enable_ntp_sync

        if check_ntp_sync; then
            printf '\nTime Check: NTP Synchronized after re-enabling ntp sync\n'
        else
            # If NTP is not synchronized, let this test fail
            die "Time Check: NTP NOT Synchronized"
        fi
    fi
}

main "$@"
