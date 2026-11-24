#!/bin/sh
# Shared machine role helpers. Callers source lib.sh first.
# shellcheck disable=SC2154

# determine if a given machine role is valid
valid_machine_role() {
    case $1 in
        workstation|server)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# try to load the configured machine role from ~/.dotrc
load_machine_role() {
    role_error=
    role_config_rc=0
    read_dotrc || role_config_rc=$?
    case $role_config_rc in
        0|1|3) ;;
        *)
            role_error="could not read $HOME/.dotrc"
            log_err "$role_error"
            return 1
            ;;
    esac
    if ! valid_machine_role "$cfg_role"; then
        role_error="invalid DOT_MACHINE_ROLE '$cfg_role' (expected workstation or server)"
        log_err "$role_error"
        return 1
    fi
}

# append an authoritative assignment without rewriting arbitrary local
# shell code, resolve existing symlinks so their targets, rather than
# the links, are updated
save_machine_role() (
    role_dest="$HOME/.dotrc"
    role_links=0
    while [ -L "$role_dest" ]; do
        role_links=$((role_links + 1))
        [ "$role_links" -le 40 ] || return 1
        role_link=$(readlink "$role_dest") || return 1
        case $role_link in
            /*)
                role_dest=$role_link
                ;;
            *)
                role_dest="$(dirname "$role_dest")/$role_link"
                ;;
        esac
    done
    [ -f "$role_dest" ] || return 1
    role_tmp=$(mktemp "${role_dest}.XXXXXX") || return 1
    trap 'rm -f "$role_tmp"' EXIT
    cat "$role_dest" > "$role_tmp" || return 1
    printf '\nDOT_MACHINE_ROLE="%s"\n' "$1" >> "$role_tmp" || return 1
    mv -f "$role_tmp" "$role_dest"
)

# read only the AC section, never mistake battery/UPS values for AC values
read_role_power() {
    role_caps=$(pmset -g cap) || { log_err 'could not read power capabilities'; return 1; }
    role_power=$(pmset -g custom) || { log_err 'could not read AC power settings'; return 1; }
}

# check if an AC power setting is supported
role_supported() {
    printf '%s\n' "$role_caps" | awk -v key="$1" '
        /^Capabilities for / { ac=($0 == "Capabilities for AC Power:"); next }
        ac && $1 == key { found=1 }
        END { exit !found }
    '
}

# check the role's power value
role_power_value() {
    printf '%s\n' "$role_power" | awk -v key="$1" '
        /^[^ \t].*:/ { ac=($0 == "AC Power:"); next }
        ac && $1 == key { print $2; exit }
    '
}

# check if the power value is valid
valid_power_value() {
    case $2 in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    case $1 in
        sleep)
            return 0
            ;;
        autorestart)
            [ "$2" = 0 ] || [ "$2" = 1 ]
            ;;
        *)
            return 1
            ;;
    esac
}

# determine the server profile's target value for a power setting
role_target_value() {
    case $1 in
        sleep)
            printf '0\n'
            ;;
        autorestart)
            printf '1\n'
            ;;
    esac
}

# snapshot is validated data, never sourced as shell code
validate_role_snapshot() {
    [ ! -L "$1" ] && [ -f "$1" ] && awk '
        NF != 2 { exit 1 }
        $1 != "sleep" && $1 != "autorestart" { exit 1 }
        $2 !~ /^[0-9]+$/ { exit 1 }
        $1 == "autorestart" && $2 != "0" && $2 != "1" { exit 1 }
        seen[$1]++ { exit 1 }
    ' "$1"
}

# resolve label for machine role
machine_role_label() {
    if [ "$cfg_role_source" = default ]; then
        printf '%s (default)\n' "$cfg_role"
    else
        printf '%s\n' "$cfg_role"
    fi
}

# workstations have no prescribed AC values, only a pending restoration
# is a mismatch
# unsupported settings do not impose a requirement on either role
# shellcheck disable=SC2034 # returned to CLI/doctor through shared variables
collect_role_profile() {
    read_role_power || return 1
    role_profile=consistent
    role_sleep=unsupported
    role_autorestart=unsupported
    for role_key in sleep autorestart; do
        role_supported "$role_key" || continue
        role_value=$(role_power_value "$role_key")
        if ! valid_power_value "$role_key" "$role_value"; then
            log_err "AC $role_key: unreadable"
            return 1
        fi
        case $role_key in
            sleep) role_sleep=$role_value ;;
            autorestart) role_autorestart=$role_value ;;
        esac
        if [ "$cfg_role" = server ] && [ "$role_value" != "$(role_target_value "$role_key")" ]; then
            role_profile=mismatched
        fi
    done
    if [ "$cfg_role" = workstation ] && { [ -e "$HOME/.dot/server-power" ] || [ -L "$HOME/.dot/server-power" ]; }; then
        role_profile=mismatched
    fi
}

# show the power settings for the current role
log_current_role_power() (
    read_role_power || return 1
    for role_key in sleep autorestart; do
        if role_supported "$role_key"; then
            role_value=$(role_power_value "$role_key")
            valid_power_value "$role_key" "$role_value" || { log_err "AC $role_key: unreadable"; return 1; }
            log_line "AC $role_key: $role_value"
        else
            log_warn "AC $role_key: unsupported"
        fi
    done
)

# serialize power writes and baseline updates, subshell keeps traps/variables local
apply_role_power() (
    role_selected=$1
    role_state="$HOME/.dot/server-power"
    if [ "$role_selected" = workstation ] && [ ! -e "$role_state" ] && [ ! -L "$role_state" ]; then
        log_current_role_power
        return $?
    fi
    mkdir -p "$HOME/.dot" || return 1
    if ! mkdir "$HOME/.dot/role.lock"; then
        log_err 'another role operation is active (role.lock); retry after it finishes'
        return 1
    fi
    role_tmp=
    trap 'rm -f "${role_tmp:-}"; rmdir "$HOME/.dot/role.lock"' EXIT
    if [ -e "$role_state" ] || [ -L "$role_state" ]; then
        validate_role_snapshot "$role_state" || { log_err 'invalid server power baseline'; return 1; }
    fi
    read_role_power || return 1
    role_tmp=$(mktemp "$HOME/.dot/server-power.XXXXXX") || return 1
    if [ -f "$role_state" ]; then
        cat "$role_state" > "$role_tmp" || return 1
    fi
    # validate every supported value and commit the baseline before any sudo/write
    for role_key in sleep autorestart; do
        if ! role_supported "$role_key"; then
            log_warn "AC $role_key: unsupported"
            if [ "$role_selected" = workstation ] && awk -v key="$role_key" '$1 == key { found=1 } END { exit !found }' "$role_tmp"; then
                log_err "cannot restore unsupported AC $role_key; baseline retained"
                return 1
            fi
            continue
        fi
        role_value=$(role_power_value "$role_key")
        valid_power_value "$role_key" "$role_value" || { log_err "AC $role_key: unreadable"; return 1; }
        if [ "$role_selected" = server ] && ! awk -v key="$role_key" '$1 == key { found=1 } END { exit !found }' "$role_tmp"; then
            printf '%s %s\n' "$role_key" "$role_value" >> "$role_tmp" || return 1
        fi
    done
    if [ "$role_selected" = server ]; then
        mv -f "$role_tmp" "$role_state" || return 1
    fi
    set --
    for role_key in sleep autorestart; do
        role_supported "$role_key" || continue
        role_value=$(role_power_value "$role_key")
        role_expected=$(role_target_value "$role_key")
        if [ "$role_selected" = workstation ]; then
            role_original=$(awk -v key="$role_key" '$1 == key { print $2 }' "$role_state")
            [ -n "$role_original" ] || continue
            if [ "$role_value" != "$role_expected" ]; then
                log_line "AC $role_key: preserving current value $role_value (original $role_original)"
                continue
            fi
            role_expected=$role_original
        fi
        if [ "$role_value" = "$role_expected" ]; then
            log_line "AC $role_key: $role_value"
        else
            log_line "AC $role_key: $role_value → $role_expected"
            set -- "$@" "$role_key" "$role_expected"
        fi
    done
    if [ "$#" -gt 0 ]; then
        if ! sudo pmset -c "$@"; then
            log_err 'could not apply AC power settings; baseline retained for retry'
            return 1
        fi
        read_role_power || return 1
        while [ "$#" -gt 0 ]; do
            if [ "$(role_power_value "$1")" != "$2" ]; then
                log_err "AC $1 verification failed; baseline retained for retry"
                return 1
            fi
            shift 2
        done
    fi
    if [ "$role_selected" = workstation ]; then
        rm -f "$role_state" || return 1
        log_line 'Workstation power restoration complete; manual edits preserved'
    fi
)
