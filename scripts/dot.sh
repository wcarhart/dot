#!/bin/sh
set -eu

# shellcheck disable=SC1007
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"
DOT_DIR=$(phys_path "$SCRIPT_DIR/..")

usage() {
    cat <<'EOF'
Usage: dot [-h] COMMAND [ARGS...]

Manage dot installation and repository.

Commands:
  status     Show dot status
  repo       Manage dot tracked repositories
  doctor     Validate the current dot installation
  install    Install or update dot
  git        Run git in the dot checkout

Options:
  -h, --help    Show this help message and exit
EOF
}

usage_status() {
    cat <<'EOF'
Usage: dot status [-h]

Show the dot installation metadata and version.

Options:
  -h, --help    Show this help message and exit
EOF
}

usage_repo() {
    cat <<'EOF'
Usage: dot repo [-h] COMMAND [ARGS...]

Manage dot tracked repositories.

Commands:
  add      Register a new tracked repository
  clone    Clone track repositories
  pull     Pull non-feature branch tracked repositories

Options:
  -h, --help    Show this help message and exit
EOF
}

usage_repo_add() {
    cat <<'EOF'
Usage: dot repo add [-h] REPO

Register a new repository to track via dot.

Arguments:
  REPO    The HTTPS or SSH origin of the repository to track

Options:
  -h, --help    Show this help message and exit
EOF
}

usage_repo_clone() {
    cat <<'EOF'
Usage: dot repo clone [-h]

Clone tracked repositories into CODE_DIR.

Options:
  -h, --help    Show this help message and exit
EOF
}

usage_repo_pull() {
    cat <<'EOF'
Usage: dot repo pull [-h]

Pull the latest for each tracked repository. Local repositories on
feature branches are skipped.

Options:
  -h, --help    Show this help message and exit
EOF
}

usage_doctor() {
    cat <<'EOF'
Usage: dot doctor [-p] [-h]

Validate the current dot installation.

Options:
  -p, --preflight    Check prerequisites only
  -h, --help         Show this help message and exit
EOF
}

usage_install() {
    cat <<'EOF'
Usage: dot install [-f] [-b] [-r] [-m] [-h]

Install dot for the current user.

Options:
  -f, --force         Forcefully overwrite mismatched configuration
  -b, --skip-brew     Do not run brew bundle
  -r, --skip-repos    Do not clone repositories
  -m, --skip-mise     Do not run mise install
  -h, --help          Show this help message and exit
EOF
}

usage_git() {
    cat <<'EOF'
Usage: dot git [-h] [ARGS...]

Run git in the dot checkout.

Options:
  -h, --help    Show this help message and exit
  [ARGS...]     Passed through to git
EOF
}

want_help() {
    for arg in "$@"; do
        case $arg in
            -h|--help) return 0 ;;
        esac
    done
    return 1
}

reject_args() {
    usage_name=$1
    shift
    if want_help "$@"; then
        "$usage_name"
        exit 0
    fi
    if [ "$#" -gt 0 ]; then
        printf '%s\n' "dot: unexpected argument: $1" >&2
        "$usage_name" >&2
        exit 2
    fi
}

load_code_dir() {
    if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
        log_err "HOME is not set to a directory"
        exit 1
    fi

    if [ ! -f "$HOME/.dotrc" ]; then
        log_err "$HOME/.dotrc not found, run install.sh first"
        exit 1
    fi

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

    CODE_DIR=$cfg_code
}

# https and ssh origins, with a path of at least owner/repo
# repo_name assigns the global name URL, so run it in a subshell
valid_repo_url() {
    remote_url=$1
    case $remote_url in
        *[[:space:]]*|*[![:print:]]*)
            return 1
            ;;
    esac
    case $remote_url in
        https://*@*)
            return 1
            ;;
        git@*:*/*|https://*/*/*|ssh://git@*/*/*)
            ;;
        *)
            return 1
            ;;
    esac
    (repo_name "$remote_url" >/dev/null)
}

# append one manifest line, keeping a trailing newline
append_manifest_line() {
    file=$1
    line=$2
    if [ -s "$file" ]; then
        last=$(tail -c 1 "$file"; printf x)
        nl='
'
        case $last in
            *"$nl"x) ;;
            *) printf '\n' >> "$file" ;;
        esac
    fi
    printf '%s\n' "$line" >> "$file"
}

cmd_status() {
    reject_args usage_status "$@"
    load_code_dir
    if ! git -C "$DOT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
        log_err "DOT_DIR is not a git checkout: $DOT_DIR"
        exit 1
    fi
    porcelain=$(git -C "$DOT_DIR" status --porcelain)
    version=$(git -C "$DOT_DIR" rev-parse --short HEAD)
    # color_* are assigned in lib.sh
    # shellcheck disable=SC2154
    if [ -n "$porcelain" ]; then
        state="${color_red}dirty${color_reset}"
    else
        state="${color_green}clean${color_reset}"
    fi
    printf '%-13s %s\n' "Dot dir:" "$DOT_DIR"
    printf '%-13s %s\n' "Dot code dir:" "$CODE_DIR"
    printf '%-13s %s\n' "Repo:" "$state"
    printf '%-13s %s\n' "Version:" "$version"
}

cmd_repo_add() {
    if want_help "$@"; then
        usage_repo_add
        exit 0
    fi
    if [ "$#" -eq 0 ]; then
        printf '%s\n' "dot: missing repository" >&2
        usage_repo_add >&2
        exit 2
    fi
    if [ "$#" -gt 1 ]; then
        printf '%s\n' "dot: unexpected argument: $2" >&2
        usage_repo_add >&2
        exit 2
    fi

    remote=$1
    case $remote in
        -*)
            printf '%s\n' "dot: unexpected argument: $remote" >&2
            usage_repo_add >&2
            exit 2
            ;;
    esac
    if ! valid_repo_url "$remote"; then
        log_err "invalid repository URL: $remote"
        exit 1
    fi

    repos="$DOT_DIR/repos.txt"
    if [ ! -f "$repos" ]; then
        log_err "$repos not found"
        exit 1
    fi

    name=$(repo_name "$remote")
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(trim_line "$line")
        if manifest_skip "$line"; then
            continue
        fi
        if [ "$line" = "$remote" ]; then
            log_err "repository already listed: $remote"
            exit 1
        fi
        if existing=$(repo_name "$line"); then
            if [ "$existing" = "$name" ]; then
                log_err "repository name already used: $name"
                exit 1
            fi
        fi
    done < "$repos"

    append_manifest_line "$repos" "$remote"
    log_line "added $remote"
}

cmd_repo_clone() {
    if want_help "$@"; then
        usage_repo_clone
        exit 0
    fi
    exec "$SCRIPT_DIR/clone.sh" "$@"
}

cmd_repo_pull() {
    reject_args usage_repo_pull "$@"
    load_code_dir

    repos="$DOT_DIR/repos.txt"
    if [ ! -f "$repos" ]; then
        log_err "$repos not found"
        exit 1
    fi

    failed=0
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
        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
            log_warn "$name is not checked out"
            continue
        fi
        if ! is_repo_root "$dest"; then
            log_warn "$name is not a git checkout"
            continue
        fi

        branch=$(git -C "$dest" rev-parse --abbrev-ref HEAD 2>/dev/null) || {
            log_err "could not read the branch for $name"
            failed=1
            continue
        }
        case $branch in
            main|master) ;;
            *)
                log_line "skip: $name ($branch)"
                continue
                ;;
        esac

        log_line "pull: $name"
        if ! git -C "$dest" pull; then
            log_err "git pull failed for $name"
            failed=1
        fi
    done < "$repos"

    exit "$failed"
}

cmd_repo() {
    if [ "$#" -eq 0 ]; then
        usage_repo
        exit 0
    fi
    case $1 in
        -h|--help)
            usage_repo
            exit 0
            ;;
        add)
            shift
            cmd_repo_add "$@"
            ;;
        clone)
            shift
            cmd_repo_clone "$@"
            ;;
        pull)
            shift
            cmd_repo_pull "$@"
            ;;
        *)
            printf '%s\n' "dot: unknown command: $1" >&2
            usage_repo >&2
            exit 2
            ;;
    esac
}

cmd_doctor() {
    if want_help "$@"; then
        usage_doctor
        exit 0
    fi
    exec "$SCRIPT_DIR/doctor.sh" "$@"
}

cmd_install() {
    if want_help "$@"; then
        usage_install
        exit 0
    fi
    exec "$SCRIPT_DIR/install.sh" "$@"
}

cmd_git() {
    if [ "$#" -eq 0 ]; then
        usage_git
        exit 0
    fi
    case $1 in
        -h|--help)
            usage_git
            exit 0
            ;;
    esac
    cd "$DOT_DIR" || exit 1
    exec git "$@"
}

if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi

case $1 in
    -h|--help)
        usage
        exit 0
        ;;
    status)
        shift
        cmd_status "$@"
        ;;
    repo)
        shift
        cmd_repo "$@"
        ;;
    doctor)
        shift
        cmd_doctor "$@"
        ;;
    install)
        shift
        cmd_install "$@"
        ;;
    git)
        shift
        cmd_git "$@"
        ;;
    *)
        printf '%s\n' "dot: unknown command: $1" >&2
        usage >&2
        exit 2
        ;;
esac
