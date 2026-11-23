#!/usr/bin/env bash
# Ports an open block/buzz pull request that touches mobile/ to this repository.
#
# It rewrites the PR's commits with the same git-filter-repo filter that
# extracted this repository from block/buzz (scripts/buzz-filter-repo.args), so
# paths lose their mobile/ prefix and `#N` references become `block/buzz#N`.
# It rebases them onto this repository's main, pushes the branch, and opens a PR
# here with the original title and description. See PORTING.md.
#
# Usage: scripts/port-from-buzz.sh [options] <block/buzz PR number>
#   --source <dir>   a block/buzz clone to borrow git objects from, only read
#                    (default: $BUZZ_REPO, else ../buzz next to this checkout)
#   --onto <ref>     rebase onto this ref instead of block/buzz-mobile's main
#   --branch <name>  branch name here (default: the PR's branch name)
#   --dry-run        stop after creating the local branch: push nothing, open no PR
#   --resume         push the branch and open the PR after a dry run or after
#                    resolving a rebase conflict
set -euo pipefail

die() { echo "port-from-buzz: $*" >&2; exit 1; }
usage() { sed -n '/^# Usage:/,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit "${1:-1}"; }

source_dir=${BUZZ_REPO:-}
onto=""
branch=""
dry_run=0
resume=0
pr=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source_dir=${2:?--source needs a directory}; shift 2 ;;
    --onto) onto=${2:?--onto needs a ref}; shift 2 ;;
    --branch) branch=${2:?--branch needs a name}; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    --resume) resume=1; shift ;;
    -h|--help) usage 0 ;;
    -*) die "unknown option $1" ;;
    *) [[ -z "$pr" ]] || die "only one PR at a time"; pr=$1; shift ;;
  esac
done
[[ "$pr" =~ ^[0-9]+$ ]] || usage

for tool in git gh python3; do
  command -v "$tool" >/dev/null || die "$tool is required (see PORTING.md)"
done

repo_root=$(git rev-parse --show-toplevel)
args_file="$repo_root/scripts/buzz-filter-repo.args"
[[ -f "$args_file" ]] || die "run this from a block/buzz-mobile checkout ($args_file missing)"
state_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-path port-from-buzz)/$pr"

# The remote that points at block/buzz-mobile.
upstream=""
for remote in $(git -C "$repo_root" remote); do
  if git -C "$repo_root" remote get-url "$remote" | grep -Eq '[:/]block/buzz-mobile(\.git)?/?$'; then
    upstream=$remote; break
  fi
done
[[ -n "$upstream" ]] || die "no remote points at block/buzz-mobile"

port() {
  git filter-repo --version >/dev/null 2>&1 || die "git-filter-repo is required (see PORTING.md)"
  [[ -z "$(git -C "$repo_root" status --porcelain)" ]] || die "commit or stash your changes first"
  [[ -n "$source_dir" ]] || source_dir="$repo_root/../buzz"
  local source_objects
  source_objects="$(git -C "$source_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/objects" \
    || die "no block/buzz clone at $source_dir (clone it, or pass --source)"
  [[ -d "$source_objects" ]] || die "no git objects at $source_objects"

  local pr_json
  pr_json=$(gh pr view "$pr" --repo block/buzz --json title,body,isDraft,headRefName,state,url,baseRefName)
  field() {
    python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(str(v).lower() if isinstance(v,bool) else (v or ""))' \
      "$1" <<<"$pr_json"
  }
  [[ "$(field state)" == OPEN ]] || die "block/buzz#$pr is $(field state), not open"
  [[ "$(field baseRefName)" == main ]] || die "block/buzz#$pr targets $(field baseRefName); only PRs into main can be ported"
  [[ -n "$branch" ]] || branch=$(field headRefName)
  git check-ref-format --branch "$branch" >/dev/null 2>&1 && [[ "$branch" != -* ]] \
    || die "'$branch' can't be used as a branch name here (pass --branch)"
  ! git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" \
    || die "branch $branch already exists here (delete it, or pass --branch)"

  local onto_commit
  if [[ -n "$onto" ]]; then
    onto_commit=$(git -C "$repo_root" rev-parse --verify --quiet "$onto^{commit}") || die "unknown ref $onto"
  else
    git -C "$repo_root" fetch --quiet "$upstream" main
    onto_commit=$(git -C "$repo_root" rev-parse FETCH_HEAD)
    onto="$upstream main"
  fi

  # Filter in a scratch repository that borrows the clone's objects, so the
  # clone is untouched and only objects it lacks are downloaded.
  work=$(mktemp -d "${TMPDIR:-/tmp}/port-from-buzz.XXXXXX")
  trap 'rm -rf "$work"' EXIT
  local scratch=(git --git-dir="$work/repo.git")
  git init --quiet --bare "$work/repo.git"
  echo "$source_objects" >"$work/repo.git/objects/info/alternates"
  echo "Fetching block/buzz#$pr and block/buzz main..."
  "${scratch[@]}" fetch --quiet --no-tags https://github.com/block/buzz.git \
    "+refs/pull/$pr/head:refs/heads/port-head" "+refs/heads/main:refs/heads/port-main"

  local base
  base=$("${scratch[@]}" merge-base port-head port-main)
  "${scratch[@]}" cat-file -e "$base:mobile" 2>/dev/null \
    || die "the PR's merge base with block/buzz main has no mobile/ (was main merged in after mobile moved out?)"
  "${scratch[@]}" update-ref refs/heads/port-base "$base"
  "${scratch[@]}" update-ref -d refs/heads/port-main
  local merges
  "${scratch[@]}" -c core.quotepath=off diff --name-only -z --no-renames "$base" port-head >"$work/changed"
  merges=$("${scratch[@]}" rev-list --merges --count "$base..port-head")

  local filter_args=() line
  while IFS= read -r line; do filter_args+=("$line"); done <"$args_file"
  echo "Rewriting history with the buzz-mobile filter..."
  (cd "$work/repo.git" && git filter-repo --force --quiet "${filter_args[@]}" >/dev/null)

  [[ -n "$("${scratch[@]}" diff --name-only port-base port-head)" ]] \
    || die "block/buzz#$pr changes nothing that moved to buzz-mobile"

  # Changed files the filter leaves behind in block/buzz, judged by the same
  # --path and --path-glob rules filter-repo applies.
  local dropped
  dropped=$(python3 - "$args_file" "$work/changed" <<'EOF'
import fnmatch, sys
args = open(sys.argv[1]).read().splitlines()
paths, globs = [], []
for flag, value in zip(args, args[1:]):
    if flag == "--path":
        paths.append(value)
    elif flag == "--path-glob":
        globs.append(value)
def kept(p):
    return any(p == k or (k.endswith("/") and p.startswith(k)) or p.startswith(k + "/") for k in paths) \
        or any(fnmatch.fnmatch(p, g) for g in globs)
for p in open(sys.argv[2], "rb").read().decode().split("\0"):
    if p and not kept(p):
        print(p)
EOF
  )

  # The new PR's title and body, with the same #N rewrite as the filter.
  rewrite() { python3 -c 'import re,sys; sys.stdout.write(re.sub(r"(?<![\w/.&-])#(\d{1,5})\b", r"block/buzz#\1", sys.stdin.read()))'; }
  rm -rf "$state_dir"
  mkdir -p "$state_dir"
  printf '%s\n' "$branch" >"$state_dir/branch"
  printf '%s\n' "$onto_commit" >"$state_dir/onto"
  field title | rewrite >"$state_dir/title"
  field isDraft >"$state_dir/draft"
  {
    field body | rewrite
    printf '\n---\nPorted from %s.\n' "$(field url)"
    if [[ -n "$dropped" ]]; then
      printf '\nChanges to these files stayed in block/buzz:\n'
      sed 's/^/- `/; s/$/`/' <<<"$dropped"
    fi
  } >"$state_dir/body.md"

  # Bring the rewritten commits here and replay them onto main.
  git -C "$repo_root" fetch --quiet --no-tags "$work/repo.git" \
    "+refs/heads/port-head:refs/heads/$branch" "+refs/heads/port-base:refs/port-from-buzz/base"
  local previous
  previous=$(git -C "$repo_root" symbolic-ref --quiet --short HEAD || git -C "$repo_root" rev-parse HEAD)
  echo "Rebasing $(git -C "$repo_root" rev-list --count --no-merges "refs/port-from-buzz/base..refs/heads/$branch") commit(s) onto $onto..."
  local rebased=0
  git -C "$repo_root" rebase --quiet --onto "$onto_commit" refs/port-from-buzz/base "$branch" && rebased=1
  git -C "$repo_root" update-ref -d refs/port-from-buzz/base
  if [[ "$rebased" == 0 ]]; then
    cat >&2 <<EOF

port-from-buzz: rebasing onto $onto stopped (see git's message above).
Resolve the conflict and run 'git rebase --continue', then publish with:
  scripts/port-from-buzz.sh --resume $pr
To give up instead: git rebase --abort && git checkout $previous && git branch -D $branch
EOF
    exit 1
  fi
  git -C "$repo_root" checkout --quiet "$previous"

  echo
  echo "Ported block/buzz#$pr to branch $branch:"
  git -C "$repo_root" log --oneline "$onto_commit..refs/heads/$branch"
  if [[ -n "$dropped" ]]; then
    echo
    echo "These changed files stay in block/buzz and are NOT in the port:"
    sed 's/^/  /' <<<"$dropped"
  fi
  [[ "$merges" == 0 ]] \
    || echo "Note: the PR had $merges merge commit(s); the port is linear, so check any conflict resolutions they held."
}

publish() {
  [[ -d "$state_dir" ]] || die "nothing to resume for block/buzz#$pr (run without --resume first)"
  ! git -C "$repo_root" rev-parse --verify --quiet REBASE_HEAD >/dev/null \
    || die "a rebase is still in progress; finish it first"
  branch=$(<"$state_dir/branch")
  git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" || die "branch $branch is gone"
  git -C "$repo_root" merge-base --is-ancestor "$(<"$state_dir/onto")" "refs/heads/$branch" \
    || die "branch $branch isn't based on the main it was ported onto (was the rebase aborted?)"

  # Push to block/buzz-mobile when you can, else to your fork of it.
  local push_remote head_ref
  if [[ "$(gh api repos/block/buzz-mobile --jq .permissions.push)" == true ]]; then
    push_remote=$upstream; head_ref=$branch
  else
    local login fork
    login=$(gh api user --jq .login)
    gh repo fork block/buzz-mobile --clone=false >/dev/null
    local url_field=.clone_url
    [[ "$(gh config get git_protocol 2>/dev/null)" == ssh ]] && url_field=.ssh_url
    local tries=0
    until fork=$(gh api "repos/$login/buzz-mobile" --jq "select(.parent.full_name == \"block/buzz-mobile\") | $url_field" 2>/dev/null) \
        && [[ -n "$fork" ]]; do
      (( ++tries < 10 )) || die "couldn't find your fork $login/buzz-mobile of block/buzz-mobile"
      sleep 3
    done
    push_remote=$fork; head_ref="$login:$branch"
  fi
  # --no-verify: the pre-push hook would run the ported PR's own scripts and tests.
  git -C "$repo_root" push --no-verify "$push_remote" "refs/heads/$branch:refs/heads/$branch"

  local draft=()
  [[ "$(<"$state_dir/draft")" == true ]] && draft=(--draft)
  gh pr create --repo block/buzz-mobile --base main --head "$head_ref" \
    --title "$(<"$state_dir/title")" --body-file "$state_dir/body.md" ${draft[@]+"${draft[@]}"}
  rm -rf "$state_dir"
}

if [[ "$resume" == 1 ]]; then
  publish
  exit 0
fi
port
if [[ "$dry_run" == 1 ]]; then
  echo
  echo "Dry run: nothing pushed. The PR would be titled:"
  sed 's/^/  /' "$state_dir/title"
  echo "Body:"
  sed 's/^/  | /' "$state_dir/body.md"
  echo "To publish it: scripts/port-from-buzz.sh --resume $pr"
  exit 0
fi
publish
