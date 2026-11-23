# Porting a PR from block/buzz

Buzz mobile used to live in `mobile/` in [block/buzz](https://github.com/block/buzz). This repository
was extracted from it with its history, so an open block/buzz PR that touches `mobile/` can be moved
here with one command. The commits keep their authors and changes. Paths lose the `mobile/`
prefix, and `#123` references in commit messages and the PR text become `block/buzz#123`.

## Prerequisites

- A clone of this repository, with a clean working tree, and a remote pointing at
  `block/buzz-mobile`.
- A clone of block/buzz. The script only reads it, to avoid downloading history again. By default
  it looks for `../buzz` next to this clone; otherwise set `BUZZ_REPO` or pass `--source`.
- git 2.31 or newer.
- [git-filter-repo](https://github.com/newren/git-filter-repo) (`brew install git-filter-repo` or
  `pip install git-filter-repo`), the [GitHub CLI](https://cli.github.com) signed in (`gh auth status`),
  and `python3`.

## Port a PR

From this repository's root:

```sh
scripts/port-from-buzz.sh <block/buzz PR number>
```

It fetches the PR, rewrites its commits with the filter that extracts this repository from
block/buzz ([`scripts/buzz-filter-repo.args`](scripts/buzz-filter-repo.args)), creates a branch named
like the PR's with them rebased onto `main`, pushes it (here if you can push, otherwise to your
fork, which it creates if needed), and opens a PR here with the original title, description and
draft state, plus a link back to the original. You stay on the branch you were on. Then close the
block/buzz PR, linking the new one.

The push skips the repository's pre-push hook, which would run the ported code's own checks. CI
runs them on the new PR.

To check the result before pushing anything:

```sh
scripts/port-from-buzz.sh --dry-run <number>   # creates the local branch, prints the PR text
scripts/port-from-buzz.sh --resume <number>    # pushes it and opens the PR
```

Use `--branch <name>` if a branch with the PR's branch name already exists here.

## What doesn't come along

- **Changes outside `mobile/`.** Only the paths this repository carries are kept (`mobile/`, the
  mobile scripts and docs, and a few shared test fixtures). The script lists every changed file it
  left behind and notes them in the new PR. Land those in block/buzz separately if they're still
  needed.
- **Merge commits.** The port is a linear series of the PR's own commits. If you merged `main` into
  the branch and resolved conflicts in the merge, check the result.
- **Reviews and comments.** They stay on the block/buzz PR; the new PR links to it.

## If the rebase conflicts

The script stops with the rebase in progress on the new branch. Resolve the conflicts, `git add`
them, `git rebase --continue`, then publish with `scripts/port-from-buzz.sh --resume <number>`. To
give up, run `git rebase --abort`, switch back to your previous branch and delete the new one; the
script prints the exact commands.

## Before you publish

This repository is public. Check that the PR's commits and description don't mention anything that
shouldn't be public before running without `--dry-run`, and edit the description afterwards if
needed.
