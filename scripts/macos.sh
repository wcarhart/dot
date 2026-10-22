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

# set a global boolean default when it is not already the requested value
ensure_bool_default() {
    key=$1
    value=$2
    case $value in
        true|false) ;;
        *)
            log_err "invalid boolean for $key: $value"
            return 1
            ;;
    esac

    current=$(defaults read -g "$key" 2>/dev/null || true)
    case "$value:$current" in
        true:1|true:true|false:0|false:false)
            log_line "ok $key"
            return 0
            ;;
    esac

    log_line "defaults write -g $key -bool $value"
    if ! defaults write -g "$key" -bool "$value"; then
        log_err "could not set $key"
        return 1
    fi
}

failed=0

# turn off the accent popup so held keys repeat
ensure_bool_default ApplePressAndHoldEnabled false || failed=1
# turn off automatic text replacement
ensure_bool_default WebAutomaticTextReplacementEnabled false || failed=1

exit "$failed"
