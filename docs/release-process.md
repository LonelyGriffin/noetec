# Release process

How Noetec versions and tags releases. The changelog lives in
[CHANGELOG.md](../CHANGELOG.md) (Keep a Changelog format); this file describes
the mechanics of cutting a release from it.

## When to release

- Noetec is **pre-alpha**: releases are frequent, low-ceremony checkpoints of
  working state, not polished product drops. Cut a release when `main` is in a
  state worth preserving — typically after a milestone lands (editor
  capability, sync engine, platform support, …).
- In pre-alpha, **never skip** a version just because "nothing big changed";
  the changelog is the progress signal for the project.
- No release from a red or untested state: the branch must pass
  `flutter analyze` and `flutter test` before it is tagged.

## Versioning

Semantic versioning, `MAJOR.MINOR.PATCH`, from `version:` in `pubspec.yaml`:

| Bump | When |
|---|---|
| MAJOR | Breaking changes to user-visible behavior or data/file formats (post-1.0 discipline; in pre-alpha, file-format changes are normal and noted in the changelog) |
| MINOR | New features, new capabilities |
| PATCH | Bug fixes, small improvements, docs |

Pre-alpha versions are `0.x.y` — anything may change at any time.

## Steps

A release is a small PR on the release branch plus a tag and a GitHub Release.

1. **Prepare the branch.** From the tip of `main`, create a release branch:
   `release/vX.Y.Z`.
2. **Fill in the changelog.** In `CHANGELOG.md`, move the `[Unreleased]`
   entries under a new version heading `## [X.Y.Z] - YYYY-MM-DD` (ISO 8601
   date of the tag, not of the last commit), then add a fresh empty
   `## [Unreleased]` section on top.
3. **Bump the version.** Set `version: X.Y.Z` in `pubspec.yaml`.
4. **Verify.** Run the full suite: `flutter analyze` and `flutter test` must
   be green.
5. **PR and merge.** Open the PR (`release/vX.Y.Z` → `main`) with the
   changelog and version bump as the payload. The release PR is reviewed and
   merged like any other — only the maintainer merges, on GitHub.
6. **Tag.** Once merged, tag the merge commit on `main`:
   `git tag vX.Y.Z -m "Release vX.Y.Z" && git push origin vX.Y.Z`.
   Tag format is the lowercase `v` prefix + the exact `pubspec.yaml` version
   (`v0.2.0`), never bare `0.2.0`.
7. **GitHub Release.** Create the release for the tag
   (`gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <notes>`):
   the release notes are the changelog section for that version verbatim
   (entries + headings, minus the version heading line). Mark it pre-release
   while the project is pre-alpha.
8. **Close the loop.** Confirm `pubspec.yaml` version, git tag, and the
   changelog heading all carry the same `X.Y.Z`.

## Rules of thumb

- The changelog is the source of truth for *what changed*; the tag is the
  source of truth for *which commit is the release*. If they disagree, the
  changelog wins and the tag/notes are corrected.
- Never edit a released version's section; corrections go into a new version
  (a `patch` release if needed).
- The `[Unreleased]` section is where all new PRs land: when your work
  adds, changes, or fixes something user-visible, add a line to
  `CHANGELOG.md` in the same PR. The release itself is then mostly mechanical.
- Agents never push tags to `main`-protected history and never merge; the tag
  push and release creation are maintainer actions (or an explicitly
  delegated agent action with a fresh GitHub token, per the project's
  git/GitHub workflow).
