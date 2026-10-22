#!/bin/sh
# install dot for the current user idempotently
set -eu

# shellcheck disable=SC1007
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"
DOT_DIR=$(phys_path "$SCRIPT_DIR/..")

force=0
skip_brew=0
skip_repos=0
skip_mise=0
failed=0
repos_failed=0
install_step_open=0
BACKUP_DIR=

usage() {
    cat <<'EOF'
Usage: install.sh [-f] [-b] [-r] [-m] [-h]

Install dot into the current user's home directory. Does not change the login shell.

Options:
  -f, --force       Forcefully overwrite existing configuration. Existing directories
                    are never modified, and mismatched files are backed up to
                    ~/.dot-backups/<timestamp>/.
  -b, --skip-brew   Do not run brew bundle
  -r, --skip-repos  Do not clone repositories listed in repos.txt
  -m, --skip-mise   Do not run mise install
  -h, --help        Show this help and exit
EOF
}

while [ "$#" -gt 0 ]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -f|--force)
            force=1
            ;;
        -b|--skip-brew)
            skip_brew=1
            ;;
        -r|--skip-repos)
            skip_repos=1
            ;;
        -m|--skip-mise)
            skip_mise=1
            ;;
        --)
            shift
            break
            ;;
        -*)
            printf '%s\n' "install: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            printf '%s\n' "install: unexpected argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$#" -gt 0 ]; then
    printf '%s\n' "install: unexpected argument: $1" >&2
    usage >&2
    exit 2
fi

shell_quote() {
    printf '%s\n' "$1" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/"
}

require_script() {
    path=$1
    if [ -f "$path" ] && [ -x "$path" ]; then
        return 0
    fi
    printf '%s\n' "install: error: missing $(display_path "$path")" >&2
    exit 1
}

ensure_backup_dir() {
    if [ -n "$BACKUP_DIR" ]; then
        return 0
    fi
    stamp=$(date +%Y%m%dT%H%M%S)
    base="$HOME/.dot-backups/$stamp"
    dir=$base
    n=0
    while [ -e "$dir" ]; do
        n=$((n + 1))
        dir="$base-$n"
    done
    mkdir -p -- "$dir" || return 1
    BACKUP_DIR=$dir
}

write_dotrc() {
    code_value=$1
    tmp="$HOME/.dotrc.tmp.$$"
    {
        printf 'DOT_DIR=%s\n' "$(shell_quote "$DOT_DIR")"
        if [ -n "$code_value" ]; then
            printf 'CODE_DIR=%s\n' "$(shell_quote "$code_value")"
        else
            # shellcheck disable=SC2016
            printf '%s\n' 'CODE_DIR="$HOME/code"'
        fi
    } > "$tmp"
    mv -- "$tmp" "$HOME/.dotrc"
}

setup_dotrc() {
    cfg_dot=
    cfg_code=
    if [ ! -e "$HOME/.dotrc" ] && [ ! -L "$HOME/.dotrc" ]; then
        write_dotrc ""
        log_line "wrote $HOME/.dotrc"
        return 0
    fi
    if [ -d "$HOME/.dotrc" ] && [ ! -L "$HOME/.dotrc" ]; then
        log_err "$HOME/.dotrc is a directory"
        return 1
    fi
    if read_dotrc; then
        cfg_phys=$(phys_path "$cfg_dot" 2>/dev/null || true)
        if [ -n "$cfg_phys" ] && [ "$cfg_phys" = "$DOT_DIR" ]; then
            log_line "keeping $HOME/.dotrc"
            return 0
        fi
    fi

    log_err "$HOME/.dotrc belongs to a different installation"
    if [ "$force" -ne 1 ]; then
        log_err "re-run with -f to replace it"
        return 1
    fi

    kept_code=
    if read_dotrc; then
        kept_code=$cfg_code
    fi
    if ! ensure_backup_dir; then
        log_err "could not create a backup directory"
        return 1
    fi
    mv -- "$HOME/.dotrc" "$BACKUP_DIR/.dotrc"
    write_dotrc "$kept_code"
    log_line "replaced $HOME/.dotrc (backup $BACKUP_DIR/.dotrc)"
}

link_one() {
    src=$1
    dest=$2
    # 1 backs up and replaces a mismatched path, the default leaves it in place
    replace=${3:-0}

    if [ ! -f "$src" ]; then
        log_err "missing $src"
        failed=1
        return 0
    fi

    if [ -L "$dest" ]; then
        current=$(readlink "$dest" || true)
        if [ "$current" = "$src" ]; then
            log_line "ok $dest"
            return 0
        fi
    elif [ -d "$dest" ]; then
        log_err "$dest is a directory, refusing to replace it"
        failed=1
        return 0
    elif [ -e "$dest" ]; then
        :
    else
        ln -s -- "$src" "$dest"
        log_line "linked $dest"
        return 0
    fi

    if [ "$force" -ne 1 ] && [ "$replace" -ne 1 ]; then
        log_err "$dest already exists (use -f to replace)"
        failed=1
        return 0
    fi

    if ! ensure_backup_dir; then
        log_err "could not create a backup directory"
        failed=1
        return 0
    fi
    base=$(basename -- "$dest")
    if ! mv -- "$dest" "$BACKUP_DIR/$base"; then
        log_err "could not back up $dest"
        failed=1
        return 0
    fi
    if ! ln -s -- "$src" "$dest"; then
        log_err "could not link $dest"
        failed=1
        return 0
    fi
    log_line "backed up $dest to $BACKUP_DIR/$base"
}

# downloads the Sublime Package Control package to the given destination
download_package_control() {
    dest=$1
    url='https://download.sublimetext.com/Package%20Control.sublime-package'
    dest_dir=$(dirname -- "$dest")

    if ! command -v curl >/dev/null 2>&1; then
        log_err "curl is not available"
        return 1
    fi

    if ! tmp=$(mktemp "$dest_dir/Package Control.sublime-package.XXXXXX"); then
        log_err "could not create a temporary file in $dest_dir"
        return 1
    fi

    if ! curl -q -fsSL -o "$tmp" "$url"; then
        rm -f -- "$tmp"
        log_err "could not download Package Control"
        return 1
    fi

    # sublime-package files are zip archives
    magic=$(dd if="$tmp" bs=2 count=1 2>/dev/null || true)
    if [ ! -s "$tmp" ] || [ "$magic" != "PK" ]; then
        rm -f -- "$tmp"
        log_err "could not download Package Control"
        return 1
    fi

    if ! mv -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        log_err "could not install $dest"
        return 1
    fi
}

# installs the Sublime Package Control package to the given destination
install_package_control() {
    package_path=$1

    if [ -f "$package_path" ]; then
        log_line "ok $package_path"
        return 0
    fi

    if [ -e "$package_path" ] || [ -L "$package_path" ]; then
        if ! ensure_backup_dir; then
            log_err "could not create a backup directory"
            return 1
        fi
        base=$(basename -- "$package_path")
        if ! mv -- "$package_path" "$BACKUP_DIR/$base"; then
            log_err "could not back up $package_path"
            return 1
        fi
        log_line "backed up $package_path to $BACKUP_DIR/$base"
    fi

    if ! download_package_control "$package_path"; then
        return 1
    fi
    log_line "installed $package_path"
}

# sets up Sublime Text
setup_sublime() {
    dot_dir=$1
    support=$(sublime_support_dir)
    installed_dir="$support/Installed Packages"
    user_dir="$support/Packages/User"

    if ! mkdir -p -- "$installed_dir" "$user_dir"; then
        log_err "could not create $support"
        failed=1
        return 0
    fi

    if ! install_package_control "$installed_dir/Package Control.sublime-package"; then
        failed=1
    fi

    # 1 backs up conflicting settings without requiring -f, correct symlink is left alone so Package Control can write through it
    link_one "$dot_dir/sublime/Preferences.sublime-settings" "$user_dir/Preferences.sublime-settings" 1
    link_one "$dot_dir/sublime/Package Control.sublime-settings" "$user_dir/Package Control.sublime-settings" 1
}

use_brew_shellenv() {
    bin=$1
    # shellcheck disable=SC1091
    eval "$("$bin" shellenv)"
    hash -r 2>/dev/null || true
    command -v brew >/dev/null 2>&1
}

ensure_brew() {
    if command -v brew >/dev/null 2>&1; then
        return 0
    fi

    bin=$(brew_bin 2>/dev/null || true)
    if [ -n "$bin" ]; then
        if use_brew_shellenv "$bin"; then
            return 0
        fi
        log_err "Homebrew is installed but brew is not usable"
        return 1
    fi

    log_line "Homebrew is not installed, installing it now..."
    if ! brew_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh); then
        log_err "could not download the Homebrew installer"
        return 1
    fi
    if ! /bin/bash -c "$brew_script"; then
        log_err "Homebrew installation failed"
        return 1
    fi
    bin=$(brew_bin 2>/dev/null || true)
    if [ -z "$bin" ] || ! use_brew_shellenv "$bin"; then
        log_err "Homebrew installed but brew is not on PATH"
        return 1
    fi

    return 0
}

print_logo() {
    cat <<'EOF'
__/\\\\\\\\\\\\__________/\\\\\_______/\\\\\\\\\\\\\\\_        
 _\/\\\////////\\\______/\\\///\\\____\///////\\\/////__       
  _\/\\\______\//\\\___/\\\/__\///\\\________\/\\\_______      
   _\/\\\_______\/\\\__/\\\______\//\\\_______\/\\\_______     
    _\/\\\_______\/\\\_\/\\\_______\/\\\_______\/\\\_______    
     _\/\\\_______\/\\\_\//\\\______/\\\________\/\\\_______   
      _\/\\\_______/\\\___\///\\\__/\\\__________\/\\\_______  
       _\/\\\\\\\\\\\\/______\///\\\\\/___________\/\\\_______ 
        _\////////////__________\/////_____________\///________
EOF
}

print_shell_hint() {
    prefix=$(brew_prefix 2>/dev/null || true)
    if [ -z "$prefix" ]; then
        return 0
    fi

    bash_path="$prefix/bin/bash"
    if [ -n "${SHELL:-}" ] && [ "$SHELL" = "$bash_path" ]; then
        return 0
    fi

    quoted=$(shell_quote "$bash_path")
    printf '\n%s\n' "To use Homebrew Bash as your login shell, run:"
    if ! grep -Fxq "$bash_path" /etc/shells 2>/dev/null; then
        printf '  %s%s%s\n' "$color_magenta" "echo $quoted | sudo tee -a /etc/shells" "$color_reset"
    fi
    printf '  %s%s%s\n' "$color_magenta" "chsh -s $quoted" "$color_reset"
    printf 'Then open a new terminal, or run: %s%s%s\n' "$color_magenta" "exec $quoted -l" "$color_reset"
}

pipeline_step() {
    printf '%s%s%s' "$color_magenta" "$1" "$color_reset"
}

finish_install_step() {
    if [ "$install_step_open" -eq 1 ]; then
        install_step_open=0
        log_step_done
    fi
}

fail_install() {
    finish_install_step
    printf '%s%s%s\n' "$color_red" "Dot installation failed" "$color_reset"
    exit 1
}

require_script "$DOT_DIR/scripts/clone.sh"
require_script "$DOT_DIR/scripts/doctor.sh"

trap finish_install_step EXIT

printf '%s%s%s\n' "$color_magenta" '••• WELCOME TO DOT •••' "$color_reset"
if [ "$skip_repos" -eq 0 ]; then
    printf 'Running install pipeline: %s > %s > %s > %s\n' \
        "$(pipeline_step doctor)" \
        "$(pipeline_step install)" \
        "$(pipeline_step clone)" \
        "$(pipeline_step doctor)"
else
    printf 'Running install pipeline: %s > %s > %s\n' \
        "$(pipeline_step doctor)" \
        "$(pipeline_step install)" \
        "$(pipeline_step doctor)"
fi

if ! "$DOT_DIR/scripts/doctor.sh" --preflight; then
    log_err "preflight checks failed"
    exit 1
fi

log_step install
install_step_open=1

if ! ensure_brew; then
    fail_install
fi

if ! check_brew_permissions; then
    fail_install
fi

if ! setup_dotrc; then
    fail_install
fi

brew_ok=0
if [ "$skip_brew" -eq 0 ]; then
    log_line "This can take up to 15m, please be patient..."
    log_line "brew bundle --file=$DOT_DIR/Brewfile"
    if brew bundle --file="$DOT_DIR/Brewfile"; then
        brew_ok=1
    else
        log_err "brew bundle failed"
        fail_install
    fi
else
    log_line "skipping brew bundle"
fi

setup_sublime "$DOT_DIR"

link_one "$DOT_DIR/shell/bashrc" "$HOME/.bashrc"
link_one "$DOT_DIR/shell/bash_profile" "$HOME/.bash_profile"
link_one "$DOT_DIR/shell/inputrc" "$HOME/.inputrc"
link_one "$DOT_DIR/gitconfig" "$HOME/.gitconfig"
link_one "$DOT_DIR/vimrc" "$HOME/.vimrc"
link_one "$DOT_DIR/tmux.conf" "$HOME/.tmux.conf"
link_one "$DOT_DIR/editorconfig" "$HOME/.editorconfig"

mise_config_dir="$HOME/.config/mise"
if mkdir -p -- "$mise_config_dir"; then
    link_one "$DOT_DIR/mise.toml" "$mise_config_dir/config.toml"
else
    log_err "could not create $mise_config_dir"
    failed=1
fi

if [ "$skip_brew" -eq 1 ] || [ "$skip_mise" -eq 1 ] || [ "$brew_ok" -ne 1 ]; then
    log_line "skipping mise install"
else
    log_line "mise install"
    if ! command -v mise >/dev/null 2>&1; then
        log_err "mise is not on PATH"
        failed=1
    elif ! mise install; then
        log_err "mise install failed"
        failed=1
    fi
fi

if [ "$skip_repos" -eq 1 ]; then
    log_line "skipping repository clones"
fi
finish_install_step

if [ "$skip_repos" -eq 0 ]; then
    if ! "$DOT_DIR/scripts/clone.sh"; then
        log_err "repository provisioning was not successful"
        repos_failed=1
    fi
fi

if ! "$DOT_DIR/scripts/doctor.sh"; then
    failed=1
fi

if [ "$failed" -ne 0 ]; then
    printf '%s%s%s\n' "$color_red" "Dot installation failed" "$color_reset"
    exit_code=1
elif [ "$repos_failed" -ne 0 ]; then
    printf '%s%s%s\n' "$color_yellow" "Dot installation completed with some issues" "$color_reset"
    print_logo
    exit_code=1
else
    printf '%s%s%s\n' "$color_green" "Dot installation successful" "$color_reset"
    print_logo
    exit_code=0
fi

if [ -n "$BACKUP_DIR" ]; then
    printf '%s\n' "Backups: $BACKUP_DIR"
fi

print_shell_hint

exit "$exit_code"
