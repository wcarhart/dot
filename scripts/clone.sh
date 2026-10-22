#!/bin/sh
# clone repositories listed in $DOT_DIR/repos.txt
set -eu

# shellcheck disable=SC1007
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
    cat <<'EOF'
Usage: clone.sh [-h]

Read repos.txt under DOT_DIR from ~/.dotrc and clone missing repositories
into CODE_DIR. Existing checkouts are left in place. Clone does not pull,
fetch, reset, or clean.

Options:
  -h, --help  Show this help message and exit
EOF
}

while [ "$#" -gt 0 ]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "clone: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

manifest_is_empty() {
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(trim_line "$line")
        if manifest_skip "$line"; then
            continue
        fi
        return 1
    done < "$DOT_DIR/repos.txt"
    return 0
}

print_repo_hint() {
    repos_disp=$(display_path "$DOT_DIR/repos.txt")
    clone_disp=$(display_path "$DOT_DIR/scripts/clone.sh")

    if manifest_is_empty; then
        log_line "Add Git remotes to $repos_disp, then run $clone_disp"
    else
        log_line "Installed all repositories listed in $repos_disp"
    fi
}

log_step clone
trap 'log_step_done' EXIT

# validate installation
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
    log_err "HOME is not set to a directory"
    exit 1
fi

if [ ! -f "$HOME/.dotrc" ]; then
    log_err "$HOME/.dotrc not found, run install.sh first"
    exit 1
fi

# read repository configuration
cfg_dot=
cfg_code=
dotrc_rc=0
read_dotrc || dotrc_rc=$?
case $dotrc_rc in
    0) ;;
    2)
        log_err "could not read $HOME/.dotrc"
        exit 1
        ;;
    *)
        # shellcheck disable=SC2088
        log_err "~/.dotrc must set DOT_DIR and CODE_DIR"
        exit 1
        ;;
esac

if [ -z "$cfg_code" ]; then
    # shellcheck disable=SC2088
    log_err "~/.dotrc must set DOT_DIR and CODE_DIR"
    exit 1
fi

DOT_DIR=$cfg_dot
CODE_DIR=$cfg_code

if [ ! -d "$DOT_DIR" ]; then
    log_err "DOT_DIR is not a directory: $DOT_DIR"
    exit 1
fi
DOT_DIR=$(phys_path "$DOT_DIR")

repos="$DOT_DIR/repos.txt"
if [ ! -f "$repos" ]; then
    log_err "$repos not found"
    exit 1
fi

if ! mkdir -p -- "$CODE_DIR"; then
    log_err "cannot create $CODE_DIR"
    exit 1
fi
CODE_DIR=$(phys_path "$CODE_DIR")

# validate repository manifest
failed=0
pending=
seen_names=
# command substitution would strip this newline and break exact-name matching
nl='
'

while IFS= read -r line || [ -n "$line" ]; do
    line=$(trim_line "$line")
    if manifest_skip "$line"; then
        continue
    fi

    if ! name=$(repo_name "$line"); then
        log_err "invalid repository URL: $line"
        failed=1
        continue
    fi

    dest="$CODE_DIR/$name"
    case $dest in
        "$CODE_DIR"/*) ;;
        *)
            log_err "refusing to clone outside $CODE_DIR ($dest)"
            failed=1
            continue
            ;;
    esac

    case "$nl$seen_names" in
        *"$nl$name$nl"*)
            continue
            ;;
    esac
    seen_names="$seen_names$name$nl"

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if is_repo_root "$dest"; then
            origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
            if [ "$origin" != "$line" ]; then
                log_warn "$name origin is '${origin:-missing}', manifest has '$line'"
            else
                log_line "skip: $dest"
            fi
        else
            log_err "$dest exists and is not a git checkout"
            failed=1
        fi
        continue
    fi

    pending="${pending}${line}
"
done < "$repos"

if [ "$failed" -ne 0 ]; then
    exit 1
fi

rest=$pending
while [ -n "$rest" ]; do
    line=${rest%%
*}
    case $rest in
        *'
'*)
        rest=${rest#*
}
        ;;
    *)
        rest=
        ;;
    esac
    [ -n "$line" ] || continue
    name=$(repo_name "$line")
    dest="$CODE_DIR/$name"
    log_cloning "$name"
    if ! GIT_TERMINAL_PROMPT=0 git clone -- "$line" "$dest"; then
        log_err "git clone failed for $line"
        failed=1
    fi
done

if [ "$failed" -eq 0 ]; then
    print_repo_hint
fi
exit "$failed"
