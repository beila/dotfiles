# shellcheck shell=bash
# Repository-history support for sync_repo.
#
# The caller provides the Git transport, logging, configuration, and lock
# phases. This module owns the history data format and remote cache.

REPO_HISTORY_REF_NAME=_repo-history
REPO_HISTORY_SELF_REF=refs/repo-history/self
REPO_HISTORY_DEFAULT_EXCLUDE='(?i)(passw|secret|token|api[_-]?key|authorization:|bearer\s|private[_-]?key)'
REPO_HISTORY_FILE=""
REPO_HISTORY_REMOTE_DIR=""
REPO_HISTORY_EXCLUDE=""
REPO_HISTORY_USER_NAME=""
REPO_HISTORY_USER_EMAIL=""

# Find the history file with the same rule as _repo_history_resolve.
prepare_repo_history() {
    [ -n "$SNAPSHOT_URL" ] || return 0
    [ "$(jj config get sync.repo-history 2>/dev/null)" = "false" ] && return 0
    if ! command -v perl >/dev/null 2>&1; then
        log WARN "SKIP repo-history: perl not found"
        return 0
    fi
    local root marker pointer="" repo_dir="" state_dir
    root=$(jj --ignore-working-copy root 2>/dev/null) || return 0
    marker="$root/.jj/repo"
    if [ -d "$marker" ]; then
        repo_dir=$(realpath -- "$marker" 2>/dev/null)
    elif [ -f "$marker" ]; then
        IFS= read -r pointer <"$marker" || true
        case "$pointer" in
            "") return 0 ;;
            /*) ;;
            *) pointer="$root/.jj/$pointer" ;;
        esac
        repo_dir=$(realpath -- "$pointer" 2>/dev/null)
    fi
    [ -n "$repo_dir" ] || return 0
    state_dir=${REPO_HISTORY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/zsh/repo-history}
    REPO_HISTORY_FILE="$state_dir/repos${repo_dir%/.jj/repo}.history"
    REPO_HISTORY_REMOTE_DIR="${REPO_HISTORY_FILE%.history}.remote"
    # An empty value disables the filter. An unset value uses the default.
    REPO_HISTORY_EXCLUDE=$(jj config get sync.repo-history-exclude 2>/dev/null) ||
        REPO_HISTORY_EXCLUDE=$REPO_HISTORY_DEFAULT_EXCLUDE
    # Read the identity before the network phase.
    REPO_HISTORY_USER_NAME=$(jj config get user.name 2>/dev/null) || REPO_HISTORY_USER_NAME=sync_repo
    REPO_HISTORY_USER_EMAIL=$(jj config get user.email 2>/dev/null) || REPO_HISTORY_USER_EMAIL=sync_repo@localhost
}

# Write complete records from standard input to standard output.
repo_history_export_filter() {
    perl -e '
        my $re = shift;
        $re = qr/$re/ if length $re;
        local $/ = "\0";
        my @fields;
        while (my $field = <STDIN>) {
            last unless $field =~ /\0\z/;
            push @fields, $field;
            next if @fields < 4;
            my $command = substr($fields[3], 0, -1);
            print @fields unless ref $re && $command =~ $re;
            @fields = ();
        }
    ' "$REPO_HISTORY_EXCLUDE"
}

# Append complete records that are absent from the local file.
repo_history_append_missing() {
    perl -e '
        my $path = shift;
        local $/ = "\0";
        my (%seen, @fields);
        if (open my $in, "<", $path) {
            while (my $field = <$in>) {
                last unless $field =~ /\0\z/;
                push @fields, $field;
                next if @fields < 4;
                $seen{join "", @fields} = 1;
                @fields = ();
            }
        }
        @fields = ();
        open my $out, ">>", $path or die "$path: $!\n";
        while (my $field = <STDIN>) {
            last unless $field =~ /\0\z/;
            push @fields, $field;
            next if @fields < 4;
            my $record = join "", @fields;
            @fields = ();
            next if $seen{$record}++;
            defined syswrite($out, $record) or die "$path: $!\n";
        }
    ' "$1"
}

repo_history_mkdir() {
    (umask 077 && mkdir -p -- "$1")
}

# Restore this host's records when the local reference is missing or stale.
restore_own_repo_history() {
    local branch=$1 remote_tip=$2 self_tip=$3
    transfer_cmd "fetch repo-history ${MACHINE_NAME}" \
        "$GIT" --git-dir="$GIT_DIR" fetch --no-tags --no-write-fetch-head \
        --no-auto-maintenance "$SNAPSHOT_URL" "$branch" || return 1
    if ! "$GIT" --git-dir="$GIT_DIR" cat-file -e "${remote_tip}:history" 2>/dev/null; then
        log ERROR "REPO-HISTORY-RESTORE-FAIL: ${remote_tip} has no history blob; push skipped"
        return 1
    fi
    repo_history_mkdir "${REPO_HISTORY_FILE%/*}" || return 1
    if ! "$GIT" --git-dir="$GIT_DIR" cat-file blob "${remote_tip}:history" |
        repo_history_append_missing "$REPO_HISTORY_FILE"; then
        log ERROR "REPO-HISTORY-RESTORE-FAIL: merge into $REPO_HISTORY_FILE failed; push skipped"
        return 1
    fi
    if [ -n "$self_tip" ]; then
        log WARN "REPO-HISTORY-DIVERGED: remote ${remote_tip} is not local ${self_tip}; records merged (is MACHINE_NAME '${MACHINE_NAME}' used by two hosts?)"
    else
        log INFO "REPO-HISTORY-RESTORED from ${remote_tip}"
    fi
}

push_repo_history() {
    [ -n "$REPO_HISTORY_FILE" ] && [ "$SNAPSHOT_REMOTE_REFS_READY" = "1" ] || return 0
    local branch="refs/heads/${MACHINE_NAME}/${REPO_HISTORY_REF_NAME}"
    local remote_tip=${SNAPSHOT_REMOTE_COMMITS["$branch"]:-}
    local self_tip export_file blob tree commit parent
    self_tip=$("$GIT" --git-dir="$GIT_DIR" rev-parse -q --verify "${REPO_HISTORY_SELF_REF}^{commit}" 2>/dev/null || true)
    if [ -n "$remote_tip" ] && [ "$remote_tip" != "$self_tip" ]; then
        restore_own_repo_history "$branch" "$remote_tip" "$self_tip" || return 0
    fi
    [ -f "$REPO_HISTORY_FILE" ] || return 0

    export_file=$(mktemp "/tmp/sync_repo_history.XXXXXX") || return 0
    if ! repo_history_export_filter <"$REPO_HISTORY_FILE" >"$export_file"; then
        log ERROR "BAD-CONFIG sync.repo-history-exclude='${REPO_HISTORY_EXCLUDE}' is not a valid Perl regex; repo-history push skipped"
        rm -f "$export_file"
        return 0
    fi
    blob=$("$GIT" --git-dir="$GIT_DIR" hash-object -w --stdin <"$export_file")
    rm -f "$export_file"
    [ -n "$blob" ] || return 0
    if [ -n "$remote_tip" ] &&
        [ "$("$GIT" --git-dir="$GIT_DIR" rev-parse -q --verify "${remote_tip}:history" 2>/dev/null)" = "$blob" ]; then
        log DEBUG "SKIP repo-history: unchanged"
        return 0
    fi

    parent=${remote_tip:-$self_tip}
    tree=$(printf '100644 blob %s\thistory\n' "$blob" | "$GIT" --git-dir="$GIT_DIR" mktree) || return 0
    commit=$(
        GIT_AUTHOR_NAME=$REPO_HISTORY_USER_NAME GIT_AUTHOR_EMAIL=$REPO_HISTORY_USER_EMAIL \
        GIT_COMMITTER_NAME=$REPO_HISTORY_USER_NAME GIT_COMMITTER_EMAIL=$REPO_HISTORY_USER_EMAIL \
        "$GIT" --git-dir="$GIT_DIR" commit-tree "$tree" ${parent:+-p "$parent"} \
            -m "repo-history: ${MACHINE_NAME}"
    ) || return 0

    transfer_cmd "push repo-history ${MACHINE_NAME}" \
        env GIT_ALTERNATE_OBJECT_DIRECTORIES="$GIT_DIR/objects" \
        "$GIT" --git-dir="$PUSH_GIT_DIR" push "$SNAPSHOT_URL" "${commit}:${branch}" || return 0
    "$GIT" --git-dir="$GIT_DIR" update-ref "$REPO_HISTORY_SELF_REF" "$commit"
    SNAPSHOT_REMOTE_COMMITS["$branch"]=$commit
    log INFO "PUSH-OK repo-history ${MACHINE_NAME}"
}

# Copy each other host's history into the local read-only cache.
fetch_repo_history() {
    [ -n "$REPO_HISTORY_FILE" ] && [ "$SNAPSHOT_REMOTE_REFS_READY" = "1" ] || return 0
    local ref host tip tip_file cache tmp file
    local -A hosts=()
    for ref in "${!SNAPSHOT_REMOTE_COMMITS[@]}"; do
        case "$ref" in
            refs/heads/*/"$REPO_HISTORY_REF_NAME") ;;
            *) continue ;;
        esac
        host=${ref#refs/heads/}
        host=${host%/"$REPO_HISTORY_REF_NAME"}
        case "$host" in
            "$MACHINE_NAME" | "" | .* | */*) continue ;;
        esac
        hosts["$host"]=1
        tip=${SNAPSHOT_REMOTE_COMMITS["$ref"]}
        cache="$REPO_HISTORY_REMOTE_DIR/${host}.history"
        tip_file="$REPO_HISTORY_REMOTE_DIR/${host}.tip"
        if [ -f "$cache" ] && [ "$(cat "$tip_file" 2>/dev/null)" = "$tip" ]; then
            continue
        fi
        transfer_cmd "fetch repo-history ${host}" \
            "$GIT" --git-dir="$GIT_DIR" fetch --no-tags --no-write-fetch-head \
            --no-auto-maintenance "$SNAPSHOT_URL" "$ref" || continue
        if ! "$GIT" --git-dir="$GIT_DIR" cat-file -e "${tip}:history" 2>/dev/null; then
            log WARN "SKIP repo-history ${host}: ${tip} has no history blob"
            continue
        fi
        repo_history_mkdir "$REPO_HISTORY_REMOTE_DIR" || return 0
        tmp=$(mktemp "$REPO_HISTORY_REMOTE_DIR/.${host}.XXXXXX") || continue
        if "$GIT" --git-dir="$GIT_DIR" cat-file blob "${tip}:history" >"$tmp" &&
            mv -f -- "$tmp" "$cache"; then
            printf '%s\n' "$tip" >"$tip_file"
            log INFO "FETCH-OK repo-history ${host}"
        else
            rm -f -- "$tmp"
        fi
    done

    [ -d "$REPO_HISTORY_REMOTE_DIR" ] || return 0
    for file in "$REPO_HISTORY_REMOTE_DIR"/*.history; do
        [ -e "$file" ] || continue
        host=${file##*/}
        host=${host%.history}
        [ -n "${hosts["$host"]:-}" ] && continue
        rm -f -- "$file" "$REPO_HISTORY_REMOTE_DIR/${host}.tip"
        log INFO "REMOVED repo-history ${host}: remote ref is gone"
    done
}
