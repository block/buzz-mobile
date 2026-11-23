# Contributing to Buzz Mobile

Thank you for your interest in contributing. This repository holds the Buzz
Flutter mobile app for iOS and Android. The relay, CLI and agent harness live
in [block/buzz](https://github.com/block/buzz), and the desktop and web app in
[block/buzz-app](https://github.com/block/buzz-app).

If you believe you found a security vulnerability, do not open a public issue.
Follow the [Buzz security policy](https://github.com/block/buzz/blob/main/SECURITY.md)
to submit a private vulnerability report instead.

This project follows the
[Buzz Code of Conduct](https://github.com/block/buzz/blob/main/CODE_OF_CONDUCT.md).

## Before you open a PR

Search [open PRs](https://github.com/block/buzz-mobile/pulls) and
[Buzz issues](https://github.com/block/buzz/issues) for duplicates first, and
link the closest one in your PR description (or say "none found"). This
repository doesn't take issues yet: report mobile bugs and propose changes in
[block/buzz issues](https://github.com/block/buzz/issues). For anything beyond
a small fix, open an issue first so a maintainer can agree on the approach
before you build it.

AI-assisted PRs are welcome. You don't need to disclose the tools you used, but
you own and must have reviewed the final code.

[VISION_MOBILE.md](VISION_MOBILE.md) describes the intended behavior and
architecture, and [CONTEXT.md](CONTEXT.md) defines the domain terms. Read the
parts relevant to your change before starting.

### Sign your commits

```bash
git commit -s
```

Every commit needs a Developer Certificate of Origin (DCO) sign-off. The `-s`
flag appends a `Signed-off-by` trailer that certifies you wrote the change and
can contribute it under the project license. The **DCO Check** blocks a PR
without it.

To fix commits you already pushed:

```bash
git rebase --signoff main
git push --force-with-lease
```

`bin/lefthook install` sets up this repository's Git hooks, including a
`commit-msg` hook that adds the sign-off for `git commit` and `git merge`.
`git rebase` and `git cherry-pick` still need `--signoff` and `-s`.

## Development setup

This repository pins its toolchain (Flutter, `just`, `lefthook`) with
[Hermit](https://cashapp.github.io/hermit/). Activate it once per shell:

```bash
. ./bin/activate-hermit
just mobile-install
```

See the [README](README.md#setup) for platform setup, the iOS toolchain, build
settings and running the app.

## Checks and tests

```bash
just check        # format check and analysis
just mobile-test  # Flutter and package tests
just mobile-fix   # format, then analyze
```

CI runs these plus Android and iOS builds and native tests. The **Mobile**
check must pass before a PR can merge.

## Making a pull request

We squash-merge, so your PR title becomes the commit subject on `main`. Use
[Conventional Commits](https://www.conventionalcommits.org/), for example
`fix(timeline): keep the scroll position after sending`. The type prefix
(`feat`, `fix`, `perf`, `docs`, `refactor`, `test`, `chore`) is required.

A good PR is:

1. **Focused**: one logical change. Split a bug fix and a refactor into two PRs.
2. **Tested**: new behavior has tests, and bug fixes include a regression test.
   If a test is impractical, explain why in the description.
3. **Clear**: the description explains the problem, the approach and its
   trade-offs, and how you verified it.
4. **Visual**: any UI change includes before and after screenshots, or a short
   recording for an interaction. We can't build every branch locally, and
   screenshots let us review UI changes quickly.

PRs we're unlikely to merge without a prior issue: large refactors or
dependency swaps, cosmetic renames or style-only churn, entirely new features,
and unrelated changes bundled into a fix.

After you open a PR, maintainers triage it on a best-effort cadence. Address
review comments by pushing new commits rather than force-pushing during review.
Once approved, a maintainer squash-merges it.

## License

Buzz is licensed under the **Apache License, Version 2.0**. See
[LICENSE](LICENSE). By submitting a pull request, you agree that your
contribution is licensed under the Apache 2.0 license and that you have the
right to submit it.
