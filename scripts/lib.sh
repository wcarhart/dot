#!/bin/sh
# shared helpers for scripts

# get the physical path of a directory
phys_path() {
    # shellcheck disable=SC1007
    CDPATH= cd -- "$1" && pwd -P
}

# shorten a path under $HOME to ~
display_path() {
    p=$1
    home=${HOME-}
    if [ -n "$home" ]; then
        case $p in
            "$home")
                printf '%s\n' '~'
                return
                ;;
            "$home"/*)
                # shellcheck disable=SC2088
                printf '~/%s\n' "${p#"$home"/}"
                return
                ;;
        esac
    fi
    printf '%s\n' "$p"
}

# sublime text 4 user data directory on macos
sublime_support_dir() {
    printf '%s\n' "$HOME/Library/Application Support/Sublime Text"
}

# trim whitespace from the beginning and end of a line
trim_line() {
    printf '%s' "$1" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# determine if a line is a manifest entry
manifest_skip() {
    case "$1" in
        ''|'#'*) return 0 ;;
        *) return 1 ;;
    esac
}

# directory name for a remote URL
repo_name() {
    url=$1
    url=${url%/}
    case $url in
        *.git) url=${url%.git} ;;
    esac
    url=${url%/}
    case $url in
        *://*)
            name=${url##*/}
            ;;
        *:*)
            rest=${url#*:}
            name=${rest##*/}
            ;;
        *)
            name=${url##*/}
            ;;
    esac
    case $name in
        ''|'.'|'..'|-*|*'/'*)
            return 1
            ;;
    esac
    case $name in
        *[!A-Za-z0-9._+-]*)
            return 1
            ;;
    esac
    printf '%s\n' "$name"
}

# determine if a directory is the root of a git repository
is_repo_root() {
    dir=$1
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
    top_phys=$(phys_path "$top") || return 1
    dir_phys=$(phys_path "$dir") || return 1
    [ "$top_phys" = "$dir_phys" ]
}

# Read ~/.dotrc into cfg_dot and cfg_code
# 0  DOT_DIR is set (CODE_DIR may be empty)
# 1  file is missing
# 2  file cannot be sourced
# 3  file sourced, but DOT_DIR is empty (cfg_code is still set)
read_dotrc() {
    cfg_dot=
    cfg_code=
    if [ ! -f "$HOME/.dotrc" ] && [ ! -L "$HOME/.dotrc" ]; then
        return 1
    fi
    dotrc_out=$(
        set +e
        set +u
        # shellcheck disable=SC1090,SC1091
        . "$HOME/.dotrc" || exit 1
        printf 'DOT=%s\n' "${DOT_DIR-}"
        printf 'CODE=%s\n' "${CODE_DIR-}"
    ) || return 2
    cfg_dot=$(printf '%s\n' "$dotrc_out" | sed -n 's/^DOT=//p' | head -n 1)
    # shellcheck disable=SC2034
    cfg_code=$(printf '%s\n' "$dotrc_out" | sed -n 's/^CODE=//p' | head -n 1)
    [ -n "$cfg_dot" ] || return 3
    return 0
}

# get the path to the brew binary
brew_bin() {
    bin=$(command -v brew 2>/dev/null || true)
    if [ -z "$bin" ] && [ -x /opt/homebrew/bin/brew ]; then
        bin=/opt/homebrew/bin/brew
    fi
    if [ -z "$bin" ]; then
        return 1
    fi
    printf '%s\n' "$bin"
}

# get the prefix of the brew binary
brew_prefix() {
    bin=$(brew_bin) || return 1
    case $bin in
        /opt/homebrew/bin/brew)
            printf '%s\n' /opt/homebrew
            ;;
        /usr/local/bin/brew)
            printf '%s\n' /usr/local
            ;;
        *)
            "$bin" --prefix
            ;;
    esac
}

# fail if the Homebrew prefix is not owned or writable by the current user
# runs in a subshell so its variables do not leak into the caller
check_brew_permissions() {
    (
        prefix=$(brew_prefix 2>/dev/null) || {
            log_err "could not determine Homebrew prefix"
            return 1
        }

        owner=$(stat -f '%Su' "$prefix" 2>/dev/null) || {
            log_err "could not determine owner of $prefix"
            return 1
        }

        current_user=$(id -un)

        if [ "$owner" != "$current_user" ]; then
            log_err "Homebrew at $prefix is owned by '$owner', not '$current_user'"
            log_err "Fix Homebrew ownership before running dot"
            log_err "You can do this via: sudo chown -R $current_user $prefix"
            return 1
        fi

        for dir in \
            "$prefix" \
            "$prefix/bin" \
            "$prefix/Cellar" \
            "$prefix/Caskroom" \
            "$prefix/etc" \
            "$prefix/opt" \
            "$prefix/share" \
            "$prefix/var/homebrew"
        do
            if [ -d "$dir" ] && [ ! -w "$dir" ]; then
                log_err "Homebrew directory is not writable: $dir"
                return 1
            fi
        done

        return 0
    )
}

# colors when stdout is a terminal, plain text for pipes and logs
color_magenta=
color_red=
color_yellow=
color_green=
color_reset=
if [ -t 1 ]; then
    color_magenta=$(printf '\033[35m')
    color_red=$(printf '\033[31m')
    color_yellow=$(printf '\033[33m')
    # shellcheck disable=SC2034 # read by scripts that source this file
    color_green=$(printf '\033[32m')
    color_reset=$(printf '\033[0m')
fi

step_label=
step_started_at=

# format an elapsed time in seconds as "59s", "2m", or "4m 23s"
format_elapsed() {
    elapsed=$1
    mins=$((elapsed / 60))
    secs=$((elapsed % 60))
    if [ "$mins" -eq 0 ]; then
        printf '%ss' "$secs"
    elif [ "$secs" -eq 0 ]; then
        printf '%sm' "$mins"
    else
        printf '%sm %ss' "$mins" "$secs"
    fi
}

# log a step in the installation process
log_step() {
    step_label=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
    step_started_at=$(date +%s)
    printf '%s• %s •%s\n' "$color_magenta" "$step_label" "$color_reset"
}

# log how long the current step took
log_step_done() {
    now=$(date +%s)
    elapsed=$((now - step_started_at))
    dur=$(format_elapsed "$elapsed")
    printf '%s• %s complete in %s •%s\n' "$color_magenta" "$step_label" "$dur" "$color_reset"
}

# log a line to stdout
log_line() {
    printf '  %s\n' "$*"
}

# log an error to stderr
log_err() {
    printf '  %s %s\n' "${color_red}error${color_reset}:" "$*" >&2
}

# log a warning to stderr
log_warn() {
    printf '  %s %s\n' "${color_yellow}warn${color_reset}:" "$*" >&2
}

# log a cloning step
log_cloning() {
    printf '  Cloning %s%s%s...\n' "$color_magenta" "$1" "$color_reset"
}
