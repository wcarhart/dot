#!/bin/sh
# read-only validations for a dot installation
set -eu

# keep diagnostics from triggering Homebrew's automatic update
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1

# shellcheck disable=SC1007
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

status=0
preflight_only=0

pass() { log_line "${color_green}PASS${color_reset}  $*"; }
warn() { log_line "${color_yellow}WARN${color_reset}  $*"; }
fail() { log_line "${color_red}FAIL${color_reset}  $*"; status=1; }

usage() {
    cat <<'EOF'
Usage: doctor.sh [-p] [-h]

Report whether this dot checkout is ready to use. Doctor never installs,
writes configuration, or clones repositories.

Options:
  -p, --preflight  Check only prerequisites only
  -h, --help       Show this help message and exit
EOF
}

while [ "$#" -gt 0 ]; do
    case $1 in
        -p|--preflight)
            preflight_only=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "doctor: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

check_platform() {
    os=$(uname -s 2>/dev/null || true)
    if [ "$os" != "Darwin" ]; then
        fail "macOS only (${os:-unknown})"
        # this is the only check that should exit the script, dot only supports macOS
        exit "$status"
    fi
    pass "macOS"

    arch=$(uname -m)
    if [ "$arch" = "arm64" ]; then
        pass "arch"
    else
        fail "arch $arch"
    fi

    if [ -n "${HOME:-}" ] && [ -d "$HOME" ] && [ -w "$HOME" ]; then
        pass "home"
    else
        fail "home"
    fi
}

check_platform

if [ "$preflight_only" -eq 1 ]; then
    exit "$status"
fi

if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
    exit "$status"
fi

CHECKOUT=$(phys_path "$SCRIPT_DIR/..")

cfg_dot=
cfg_code=
if [ -L "$HOME/.dotrc" ]; then
    warn "dotrc is a symlink"
elif [ -f "$HOME/.dotrc" ]; then
    pass "dotrc"
else
    fail "dotrc"
fi

if [ -f "$HOME/.dotrc" ] || [ -L "$HOME/.dotrc" ]; then
    read_dotrc || true
fi

if [ -z "$cfg_dot" ]; then
    fail "dot directory"
elif [ ! -d "$cfg_dot" ]; then
    fail "dot directory missing $cfg_dot"
else
    cfg_phys=$(phys_path "$cfg_dot")
    if [ "$cfg_phys" = "$CHECKOUT" ]; then
        pass "dot directory"
    else
        fail "dot directory $cfg_phys"
    fi
fi

if [ -n "$cfg_dot" ] && [ -f "$cfg_dot/shell/functions/dot" ] && \
    DOT_DIR="$cfg_dot" /bin/bash -c '. "$DOT_DIR/shell/functions/dot" && dot --help >/dev/null 2>&1'
then
    pass "dot"
else
    fail "dot"
fi

if [ -z "$cfg_code" ]; then
    fail "code directory"
elif [ -d "$cfg_code" ]; then
    pass "code directory"
elif [ -e "$cfg_code" ]; then
    fail "code directory not a directory"
else
    ancestor=$cfg_code
    while [ ! -d "$ancestor" ] && [ "$ancestor" != "/" ] && [ -n "$ancestor" ]; do
        ancestor=$(dirname "$ancestor")
    done
    if [ -d "$ancestor" ] && [ -w "$ancestor" ]; then
        pass "code directory"
    else
        fail "code directory"
    fi
fi

check_link() {
    name=$1
    src=$2
    dest=$3
    if [ ! -f "$src" ]; then
        fail "symlink $name missing source"
        return
    fi
    if [ ! -L "$dest" ]; then
        fail "symlink $name"
        return
    fi
    target=$(readlink "$dest" || true)
    if [ "$target" = "$src" ]; then
        pass "symlink $name"
    else
        fail "symlink $name"
    fi
}

check_link "bashrc" "$CHECKOUT/shell/bashrc" "$HOME/.bashrc"
check_link "bash_profile" "$CHECKOUT/shell/bash_profile" "$HOME/.bash_profile"
check_link "inputrc" "$CHECKOUT/shell/inputrc" "$HOME/.inputrc"
check_link "gitconfig" "$CHECKOUT/gitconfig" "$HOME/.gitconfig"
check_link "vimrc" "$CHECKOUT/vimrc" "$HOME/.vimrc"
check_link "mise" "$CHECKOUT/mise.toml" "$HOME/.config/mise/config.toml"
check_link "ghostty" "$CHECKOUT/ghostty.ini" "$HOME/.config/ghostty/config"
check_link "tmux.conf" "$CHECKOUT/tmux.conf" "$HOME/.tmux.conf"
check_link "editorconfig" "$CHECKOUT/editorconfig" "$HOME/.editorconfig"

sublime_support=$(sublime_support_dir)
check_link "sublime preferences" \
    "$CHECKOUT/sublime/Preferences.sublime-settings" \
    "$sublime_support/Packages/User/Preferences.sublime-settings"
check_link "sublime package control" \
    "$CHECKOUT/sublime/Package Control.sublime-settings" \
    "$sublime_support/Packages/User/Package Control.sublime-settings"
if [ -f "$sublime_support/Installed Packages/Package Control.sublime-package" ]; then
    pass "sublime package-control"
else
    fail "sublime package-control"
fi

if [ -f "$CHECKOUT/shell/inputrc" ]; then
    pass "inputrc"
else
    fail "inputrc"
fi

for rel in \
    shell/bashrc \
    shell/bash_profile \
    shell/aliases.bash
do
    if /bin/bash -n "$CHECKOUT/$rel"; then
        pass "syntax $rel"
    else
        fail "syntax $rel"
    fi
done

for fn in "$CHECKOUT/shell/functions"/*; do
    [ -f "$fn" ] || continue
    rel=${fn#"$CHECKOUT/"}
    if /bin/bash -n "$fn"; then
        pass "syntax $rel"
    else
        fail "syntax $rel"
    fi
done

prefix=
if prefix=$(brew_prefix); then
    pass "homebrew"
else
    fail "homebrew"
    prefix=
fi

if [ -n "$prefix" ] && [ -x "$prefix/bin/bash" ]; then
    # shellcheck disable=SC2016
    ver=$("$prefix/bin/bash" -c 'printf "%d.%d\n" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null || true)
    major=${ver%%.*}
    minor=${ver#*.}
    minor=${minor%%.*}
    if [ -n "$major" ] && [ -n "$minor" ] && {
        [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 2 ]; }
    }; then
        pass "bash"
    else
        fail "bash ${ver:-unknown}"
    fi
    if [ "${SHELL:-}" = "$prefix/bin/bash" ]; then
        pass "login-shell"
    else
        warn "login-shell ${SHELL:-unknown}"
    fi
else
    fail "bash"
    warn "login-shell ${SHELL:-unknown}"
fi

formulae=
casks=
if [ -n "$prefix" ]; then
    brew_cmd=$(brew_bin 2>/dev/null || true)
    if [ -n "$brew_cmd" ]; then
        formulae=$("$brew_cmd" list --formula 2>/dev/null || true)
        casks=$("$brew_cmd" list --cask 2>/dev/null || true)
    fi
fi

if [ -f "$CHECKOUT/Brewfile" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        name=$(printf '%s\n' "$line" | sed -n 's/^[[:space:]]*brew[[:space:]]*"\([^"]*\)".*/\1/p')
        kind=formula
        if [ -z "$name" ]; then
            name=$(printf '%s\n' "$line" | sed -n 's/^[[:space:]]*cask[[:space:]]*"\([^"]*\)".*/\1/p')
            kind=cask
        fi
        [ -n "$name" ] || continue
        if [ "$kind" = "cask" ]; then
            list=$casks
        else
            list=$formulae
        fi
        if printf '%s\n' "$list" | grep -Fxq -- "$name"; then
            pass "package $name"
        else
            fail "package $name"
        fi
    done < "$CHECKOUT/Brewfile"
else
    fail "package Brewfile"
fi

if command -v git >/dev/null 2>&1; then
    pass "git"
else
    fail "git"
fi

git_prompt=
completion=
if [ -n "$prefix" ]; then
    for candidate in \
        "$prefix/etc/bash_completion.d/git-prompt.sh" \
        "$prefix/opt/git/etc/bash_completion.d/git-prompt.sh"
    do
        if [ -r "$candidate" ]; then
            git_prompt=$candidate
            break
        fi
    done
    for candidate in \
        "$prefix/etc/profile.d/bash_completion.sh" \
        "$prefix/opt/bash-completion@2/etc/profile.d/bash_completion.sh"
    do
        if [ -r "$candidate" ]; then
            completion=$candidate
            break
        fi
    done
fi

if [ -n "$git_prompt" ]; then
    pass "git-prompt"
else
    fail "git-prompt"
fi

if [ -n "$completion" ]; then
    pass "bash-completion"
else
    fail "bash-completion"
fi

repos="$CHECKOUT/repos.txt"
if [ ! -r "$repos" ]; then
    fail "repos manifest"
else
    pass "repos manifest"
    code_phys=
    if [ -n "$cfg_code" ] && [ -d "$cfg_code" ]; then
        code_phys=$(phys_path "$cfg_code")
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(trim_line "$line")
        if manifest_skip "$line"; then
            continue
        fi
        if ! name=$(repo_name "$line"); then
            warn "repo invalid $line"
            continue
        fi
        if [ -z "$cfg_code" ]; then
            warn "repo $name not checked"
            continue
        fi
        if [ -n "$code_phys" ]; then
            dest="$code_phys/$name"
        else
            dest="$cfg_code/$name"
        fi
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
            warn "repo $name missing"
            continue
        fi
        if ! is_repo_root "$dest"; then
            warn "repo $name not a git checkout"
            continue
        fi
        origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
        if [ "$origin" != "$line" ]; then
            warn "repo $name origin"
        else
            pass "repo $name"
        fi
    done < "$repos"
fi

exit "$status"
