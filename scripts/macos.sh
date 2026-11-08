#!/bin/sh
# macOS defaults for a dot installation
set -eu

# shellcheck disable=SC1007
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<'EOF'
Usage: macos.sh [-h]

Apply macOS defaults for a dot installation.

Options:
  -h, --help  Show this help message and exit
EOF
}

if [ "$#" -gt 0 ]; then
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "macos: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
fi

# set a defaults value when it is not already the requested value
# domain -g is the global domain; type is bool or int
# sets wrote_default=1 when a write happens
ensure_default() {
    domain=$1
    type=$2
    key=$3
    value=$4
    wrote_default=0

    case $type in
        bool)
            case $value in
                true|false) ;;
                *)
                    log_err "invalid boolean for $key: $value"
                    return 1
                    ;;
            esac
            ;;
        int)
            case $value in
                ''|*[!0-9-]*|-|-*[!0-9]*)
                    log_err "invalid integer for $key: $value"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_err "invalid defaults type for $key: $type"
            return 1
            ;;
    esac

    if [ "$domain" = -g ]; then
        current=$(defaults read -g "$key" 2>/dev/null || true)
    else
        current=$(defaults read "$domain" "$key" 2>/dev/null || true)
    fi

    case $type in
        bool)
            case "$value:$current" in
                true:1|true:true|false:0|false:false)
                    log_line "ok $key"
                    return 0
                    ;;
            esac
            ;;
        int)
            if [ "$current" = "$value" ]; then
                log_line "ok $key"
                return 0
            fi
            ;;
    esac

    if [ "$domain" = -g ]; then
        log_line "defaults write -g $key -$type $value"
        if ! defaults write -g "$key" "-$type" "$value"; then
            log_err "could not set $key"
            return 1
        fi
    else
        log_line "defaults write $domain $key -$type $value"
        if ! defaults write "$domain" "$key" "-$type" "$value"; then
            log_err "could not set $key"
            return 1
        fi
    fi
    wrote_default=1
}

# set a global boolean default when it is not already the requested value
ensure_bool_default() {
    ensure_default -g bool "$1" "$2"
}

failed=0

# turn off the accent popup so held keys repeat
ensure_bool_default ApplePressAndHoldEnabled false || failed=1
# turn off automatic text replacement
ensure_bool_default WebAutomaticTextReplacementEnabled false || failed=1
# turn off inserting a period when pressing space twice
ensure_bool_default NSAutomaticPeriodSubstitutionEnabled false || failed=1

clock_changed=0

# menu bar clock: always show the date
ensure_default com.apple.menuextra.clock int ShowDate 1 || failed=1
if [ "$wrote_default" -eq 1 ]; then
    clock_changed=1
fi
# show the day of the week
ensure_default com.apple.menuextra.clock bool ShowDayOfWeek true || failed=1
if [ "$wrote_default" -eq 1 ]; then
    clock_changed=1
fi
# show AM/PM
ensure_default com.apple.menuextra.clock bool ShowAMPM true || failed=1
if [ "$wrote_default" -eq 1 ]; then
    clock_changed=1
fi
# display the time with seconds
ensure_default com.apple.menuextra.clock bool ShowSeconds true || failed=1
if [ "$wrote_default" -eq 1 ]; then
    clock_changed=1
fi

if [ "$clock_changed" -eq 1 ]; then
    log_line "killall SystemUIServer"
    if ! killall SystemUIServer; then
        log_err "could not restart SystemUIServer"
        failed=1
    fi
fi

exit "$failed"
