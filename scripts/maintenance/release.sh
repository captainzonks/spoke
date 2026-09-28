#!/usr/bin/env bash
# ==============================================================================
# SPOKE - RELEASE
# ==============================================================================
# Description: Cut a semver release of the hub or any module repo (ADR-029):
#              `prepare` opens a release PR, `publish` tags the merged result
# Author: Matt Barham
# Created: 2026-09-27
# Modified: 2026-09-27
# Version: 1.1.0
# Host: Your Server
# ==============================================================================
# Type: Shell Script (Bash)
# Component: Spoke release tooling
# Usage:
#   release.sh prepare [--dry-run] [--since REV] <repo_dir> [major|minor|patch|X.Y.Z]
#   release.sh publish <repo_dir>
#
#   prepare  Computes the next version (git-cliff from conventional commits,
#            or the bump / exact version given), then on a release/vX.Y.Z
#            branch: writes the CHANGELOG.md entry, syncs version files,
#            makes a signed commit, pushes and opens a PR.
#            --dry-run  print the version and changelog entry; no branch,
#                       commit, tag or PR
#            --since    first release only: build the entry from REV..HEAD
#                       instead of writing a baseline entry
#   publish  After the release PR is merged: finds the release commit on
#            main, creates a signed annotated tag on it, pushes the tag and
#            creates the GitHub release from the CHANGELOG entry.
#
# Version files kept in step with the release, when present:
#   In the repo root and each immediate subdirectory (one crate or app per
#   service directory is common):
#   - Cargo.toml     [workspace.package] or [package] version (+ Cargo.lock);
#                    members using version.workspace = true are left alone
#   - pyproject.toml [project] or [tool.poetry] version
#   - package.json   top-level version (+ package-lock.json, via npm)
#   In the repo root only:
#   - stack.yml    module.version
#   - .env.example the keys named in a `# @release-version: KEY1 KEY2 ...`
#                  comment, e.g. tags of images the repo builds itself
# ==============================================================================
# Requirements:
#   - git (commit.gpgsign / tag signing key configured), gh (authenticated),
#     git-cliff 2.x, cargo for Rust repos, npm for repos with package-lock.json
# Documentation:
#   - https://semver.org/spec/v2.0.0.html
#   - https://keepachangelog.com/en/1.1.0/
#   - https://git-cliff.org/docs/usage/bump-version
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIFF_CONFIG="${CLIFF_CONFIG:-${SCRIPT_DIR}/../../cliff.toml}"
MAIN_BRANCH="main"
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
VERSION_MARKER="@release-version"
TODAY="$(date +%Y-%m-%d)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

TMP_DIR=""
REPO_DIR=""
OPEN_BRANCH=""

# On any exit while prepare has a release branch checked out (die, a failed
# command, Ctrl-C), say how to get back to a state prepare can retry from.
cleanup() {
    [[ -n "${TMP_DIR}" ]] && rm -rf "${TMP_DIR}"
    if [[ -n "${OPEN_BRANCH}" ]]; then
        printf "${YELLOW}prepare stopped with %s checked out in %s.${NC}\n" "${OPEN_BRANCH}" "${REPO_DIR}" >&2
        if git -C "${REPO_DIR}" ls-remote --exit-code --heads origin "${OPEN_BRANCH}" >/dev/null 2>&1; then
            printf "${YELLOW}The branch is already on origin: open the PR by hand, or delete it with\n  git -C %s push origin --delete %s${NC}\n" \
                "${REPO_DIR}" "${OPEN_BRANCH}" >&2
        fi
        printf "${YELLOW}To start over locally:\n  git -C %s switch --force %s && git -C %s branch -D %s${NC}\n" \
            "${REPO_DIR}" "${MAIN_BRANCH}" "${REPO_DIR}" "${OPEN_BRANCH}" >&2
    fi
    return 0
}
trap cleanup EXIT

die() { printf "${RED}ERROR: %s${NC}\n" "$*" >&2; exit 1; }
info() { printf "${BLUE}%s${NC}\n" "$*"; }
ok() { printf "${GREEN}%s${NC}\n" "$*"; }
warn() { printf "${YELLOW}%s${NC}\n" "$*"; }

usage() {
    sed -n '/^# Usage:/,/^# Version files/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
    exit "${1:-0}"
}

require_tools() {
    local tool
    for tool in git gh git-cliff awk; do
        command -v "${tool}" >/dev/null 2>&1 || die "${tool} is required but not installed"
    done
    [[ -f "${CLIFF_CONFIG}" ]] || die "git-cliff config not found at ${CLIFF_CONFIG}"
}

#------------------------------------------------------------------------------
# Repo state and versions
#------------------------------------------------------------------------------

# Require a clean checkout of main, level with origin/main, tags fetched.
# A fetch that would move an existing local tag fails here: tags are immutable.
sync_main() {
    local repo="$1" branch
    [[ -d "${repo}/.git" ]] || die "${repo} is not a git repository"
    [[ -z "$(git -C "${repo}" status --porcelain --untracked-files=no)" ]] \
        || die "${repo} has uncommitted changes"
    branch="$(git -C "${repo}" branch --show-current)"
    [[ "${branch}" == "${MAIN_BRANCH}" ]] || die "${repo} is on '${branch}', not ${MAIN_BRANCH}"
    git -C "${repo}" fetch --quiet --tags origin
    git -C "${repo}" merge --quiet --ff-only "origin/${MAIN_BRANCH}" \
        || die "local ${MAIN_BRANCH} has diverged from origin/${MAIN_BRANCH}"
}

last_tag() {
    git -C "$1" describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true
}

# True when $1 is a strictly higher version than $2.
version_gt() {
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

bump_part() {
    local version="$1" part="$2" major minor patch
    IFS=. read -r major minor patch <<<"${version}"
    case "${part}" in
        major) printf '%s.0.0' "$((major + 1))" ;;
        minor) printf '%s.%s.0' "${major}" "$((minor + 1))" ;;
        patch) printf '%s.%s.%s' "${major}" "${minor}" "$((patch + 1))" ;;
    esac
}

# Resolve the release version from an explicit X.Y.Z, a bump keyword, or
# (no argument) git-cliff's reading of the commits since the last tag.
next_version() {
    local repo="$1" request="$2" last="$3" last_v="${3#v}" version
    if [[ "${request}" =~ ${SEMVER_RE} ]]; then
        version="${request}"
    elif [[ "${request}" =~ ^(major|minor|patch)$ ]]; then
        [[ -n "${last}" ]] || die "no previous tag to bump; give an exact version for the first release"
        version="$(bump_part "${last_v}" "${request}")"
    elif [[ -z "${request}" ]]; then
        [[ -n "${last}" ]] || die "no previous tag; give an exact version for the first release"
        version="$(cd "${repo}" && git-cliff --config "${CLIFF_CONFIG}" --bumped-version 2>/dev/null)"
        version="${version#v}"
        [[ "${version}" != "${last_v}" ]] || die "no feat/fix/breaking commits since ${last}; nothing to release"
    else
        die "invalid version or bump '${request}' (expected major, minor, patch or X.Y.Z)"
    fi
    [[ "${version}" =~ ${SEMVER_RE} ]] || die "computed version '${version}' is not X.Y.Z"
    if [[ -n "${last}" ]] && ! version_gt "${version}" "${last_v}"; then
        die "${version} is not higher than the last release ${last_v}"
    fi
    printf '%s' "${version}"
}

#------------------------------------------------------------------------------
# CHANGELOG.md
#------------------------------------------------------------------------------

# Write the new release's section to stdout.
changelog_section() {
    local repo="$1" version="$2" last="$3" since="$4" range section
    if [[ -n "${last}" ]]; then
        range="${last}..HEAD"
    elif [[ -n "${since}" ]]; then
        range="${since}..HEAD"
    else
        printf '## [%s] - %s\n\n### Baseline\n\n' "${version}" "${TODAY}"
        printf -- '- First versioned release (hub ADR-029). Earlier history is in the git log.\n'
        return 0
    fi
    section="$(cd "${repo}" && git-cliff --config "${CLIFF_CONFIG}" --tag "v${version}" \
        --strip all "${range}" 2>/dev/null)"
    [[ -n "${section}" ]] || section="## [${version}] - ${TODAY}"
    # git-cliff dates the entry in UTC; use the same local date as everywhere else
    printf '%s\n' "${section}" | sed -E "1s/^(## \[[^]]+\]) - [0-9]{4}-[0-9]{2}-[0-9]{2}$/\1 - ${TODAY}/"
    if ! grep -q '^- ' <<<"${section}"; then
        printf '\n### Changed\n\n- Maintenance only; no user-visible changes.\n'
    fi
}

new_changelog() {
    local repo="$1" version="$2" author
    # Match the Author used in the repo's other headers; fall back to git.
    author="${RELEASE_AUTHOR:-$(sed -n -E 's/^(# )?Author: //p' "${repo}/README.md" 2>/dev/null | head -n1)}"
    author="${author:-$(git -C "${repo}" config user.name)}"
    cat <<EOF
# Changelog

<!--
==============================================================================
CHANGELOG.md - Release history
==============================================================================
Description: Notable changes in each release, newest first
Author: ${author}
Created: ${TODAY}
Modified: ${TODAY}
Version: ${version}
==============================================================================
Document Type: Changelog
Audience: Operator, Module Developer
Status: Active (living document)
==============================================================================
-->

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html). What
counts as a breaking change for a Spoke module is defined in the Spoke hub's
ADR-029.

EOF
}

# Insert the section above the newest existing entry (or create the file),
# and bump the header's Modified/Version fields.
write_changelog() {
    local repo="$1" version="$2" section_file="$3" file="$1/CHANGELOG.md" out
    [[ -f "${file}" ]] || new_changelog "${repo}" "${version}" >"${file}"
    sed -i -E "1,25{s/^Modified: .*/Modified: ${TODAY}/;s/^Version: .*/Version: ${version}/}" "${file}"
    out="${TMP_DIR}/changelog.new"
    awk -v sec="${section_file}" '
        BEGIN { while ((getline line < sec) > 0) body = body line "\n" }
        !done && /^## \[/ { printf "%s\n", body; done = 1 }
        { print }
        END { if (!done) printf "%s", body }
    ' "${file}" >"${out}"
    mv "${out}" "${file}"
}

# Print the body of one version's entry (without its heading).
changelog_entry() {
    local version="$1"
    awk -v v="${version}" '
        index($0, "## [" v "]") == 1 { on = 1; next }
        on && /^## \[/ { exit }
        on { print }
    '
}

top_changelog_version() {
    sed -n -E 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/p' | head -n1
}

#------------------------------------------------------------------------------
# Version files
#------------------------------------------------------------------------------

# The repo root and its immediate subdirectories.
manifest_dirs() {
    local repo="$1" dir
    printf '%s\n' "${repo}"
    for dir in "${repo}"/*/; do
        [[ -d "${dir}" ]] || continue
        dir="${dir%/}"
        case "$(basename "${dir}")" in target|node_modules) continue ;; esac
        printf '%s\n' "${dir}"
    done
}

# Rewrite the first `version =` line inside one of the named TOML tables.
set_toml_version() {
    local file="$1" version="$2" tables="$3" out="${TMP_DIR}/toml.new"
    awk -v v="${version}" -v tables="${tables}" '
        BEGIN { n = split(tables, t, " "); for (k = 1; k <= n; k++) want["[" t[k] "]"] = 1 }
        /^\[/ {
            header = $0
            sub(/\r$/, "", header)
            sub(/[[:space:]]*#.*$/, "", header)
            sub(/[[:space:]]+$/, "", header)
            in_tbl = (header in want)
        }
        in_tbl && !done && /^version[[:space:]]*=/ { print "version = \"" v "\""; done = 1; next }
        { print }
    ' "${file}" >"${out}"
    cat "${out}" >"${file}"
}

bump_cargo() {
    local dir="$1" version="$2"
    [[ -f "${dir}/Cargo.toml" ]] || return 0
    set_toml_version "${dir}/Cargo.toml" "${version}" "workspace.package package"
    [[ -f "${dir}/Cargo.lock" ]] || return 0
    command -v cargo >/dev/null 2>&1 || die "cargo is required to refresh ${dir}/Cargo.lock"
    (cd "${dir}" && cargo update --workspace --offline --quiet) \
        || die "cargo update --workspace failed in ${dir}; Cargo.lock not refreshed"
}

bump_pyproject() {
    local dir="$1" version="$2"
    [[ -f "${dir}/pyproject.toml" ]] || return 0
    set_toml_version "${dir}/pyproject.toml" "${version}" "project tool.poetry"
}

bump_package_json() {
    local dir="$1" version="$2"
    [[ -f "${dir}/package.json" ]] || return 0
    grep -qE '^  "version":' "${dir}/package.json" || return 0
    if [[ -f "${dir}/package-lock.json" ]]; then
        command -v npm >/dev/null 2>&1 || die "npm is required to update ${dir}/package-lock.json"
        (cd "${dir}" && npm version "${version}" --no-git-tag-version --allow-same-version \
            --ignore-scripts >/dev/null) || die "npm version failed in ${dir}"
    else
        sed -i -E "0,/^  \"version\": \"[^\"]*\"/s//  \"version\": \"${version}\"/" "${dir}/package.json"
    fi
}

bump_manifests() {
    local repo="$1" version="$2" dir
    while IFS= read -r dir; do
        bump_cargo "${dir}" "${version}"
        bump_pyproject "${dir}" "${version}"
        bump_package_json "${dir}" "${version}"
    done < <(manifest_dirs "${repo}")
}

bump_stack_yml() {
    local repo="$1" version="$2" out="${TMP_DIR}/stack.new"
    [[ -f "${repo}/stack.yml" ]] || return 0
    awk -v v="${version}" '
        /^[^[:space:]#]/ { in_mod = ($0 ~ /^module:/) }
        in_mod && !done && /^  version:/ { print "  version: \"" v "\""; done = 1; next }
        { print }
    ' "${repo}/stack.yml" >"${out}"
    cat "${out}" >"${repo}/stack.yml"
}

# Set every key listed on a "# @release-version: KEY ..." line to the version.
bump_env_example() {
    local repo="$1" version="$2" out="${TMP_DIR}/env.new"
    [[ -f "${repo}/.env.example" ]] || return 0
    awk -v v="${version}" -v marker="${VERSION_MARKER}:" '
        FNR == NR {
            if ($0 ~ /^[[:space:]]*#/ && (i = index($0, marker)) > 0) {
                n = split(substr($0, i + length(marker)), names, /[[:space:],]+/)
                for (k = 1; k <= n; k++) if (names[k] != "") keys[names[k]] = 1
            }
            next
        }
        /^[A-Za-z_][A-Za-z0-9_]*=/ {
            name = substr($0, 1, index($0, "=") - 1)
            if (name in keys) { print name "=" v; next }
        }
        { print }
    ' "${repo}/.env.example" "${repo}/.env.example" >"${out}"
    cat "${out}" >"${repo}/.env.example"
}

# Refuse a release that would lower any version field it rewrites, e.g. a
# stack.yml that already declares a higher version than the one requested.
check_no_downgrade() {
    local repo="$1" version="$2" old
    while IFS= read -r old; do
        if version_gt "${old}" "${version}"; then
            die "a version field already says ${old}, higher than ${version}; release ${old} or later"
        fi
    done < <(git -C "${repo}" diff -U0 | grep -E '^-[^-]' \
        | grep -oE '(^|[^0-9.])[0-9]+\.[0-9]+\.[0-9]+([^0-9.]|$)' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
}

#------------------------------------------------------------------------------
# Commands
#------------------------------------------------------------------------------

cmd_prepare() {
    local dry_run=false since="" repo request last version tag branch section_file
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --since) [[ $# -ge 2 ]] || die "--since needs a revision"; since="$2"; shift 2 ;;
            -h|--help) usage 0 ;;
            -*) die "unknown option $1" ;;
            *) break ;;
        esac
    done
    [[ $# -ge 1 && $# -le 2 ]] || usage 1
    repo="$(cd "$1" && pwd)"
    request="${2:-}"

    sync_main "${repo}"
    last="$(last_tag "${repo}")"
    [[ -z "${since}" || -z "${last}" ]] || die "--since is only for a repo's first release"
    version="$(next_version "${repo}" "${request}" "${last}")"
    tag="v${version}"
    branch="release/${tag}"
    TMP_DIR="$(mktemp -d)"
    section_file="${TMP_DIR}/section.md"
    changelog_section "${repo}" "${version}" "${last}" "${since}" >"${section_file}"

    info "$(basename "${repo}"): ${last:-no previous release} -> ${tag}"
    cat "${section_file}"
    if [[ "${dry_run}" == true ]]; then
        warn "Dry run: no branch, commit, tag or PR created."
        return 0
    fi

    git -C "${repo}" rev-parse -q --verify "refs/tags/${tag}" >/dev/null && die "tag ${tag} already exists"
    if git -C "${repo}" ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1; then
        die "branch ${branch} already exists on origin"
    fi
    git -C "${repo}" switch --quiet -c "${branch}"
    REPO_DIR="${repo}"
    OPEN_BRANCH="${branch}"

    write_changelog "${repo}" "${version}" "${section_file}"
    bump_manifests "${repo}" "${version}"
    bump_stack_yml "${repo}" "${version}"
    bump_env_example "${repo}" "${version}"
    check_no_downgrade "${repo}" "${version}"

    git -C "${repo}" add CHANGELOG.md
    git -C "${repo}" add -u
    info "Files in the release commit:"
    git -C "${repo}" diff --cached --stat
    git -C "${repo}" commit --quiet -S -m "chore(release): ${tag}"
    git -C "${repo}" push --quiet -u origin "${branch}"

    # shellcheck disable=SC2016  # backticks are Markdown in the PR body
    printf '%s\n\n---\nAfter every check is green and this is merged, run `release.sh publish` on the repo to tag and publish %s.\n' \
        "$(changelog_entry "${version}" <"${repo}/CHANGELOG.md")" "${tag}" >"${TMP_DIR}/pr_body.md"
    (cd "${repo}" && gh pr create --base "${MAIN_BRANCH}" --head "${branch}" \
        --title "chore(release): ${tag}" --body-file "${TMP_DIR}/pr_body.md")
    git -C "${repo}" switch --quiet "${MAIN_BRANCH}"
    OPEN_BRANCH=""
    ok "Release PR for ${tag} opened. Merge it when green, then: release.sh publish ${repo}"
}

cmd_publish() {
    [[ $# -eq 1 ]] || usage 1
    local repo version tag commit notes_file
    repo="$(cd "$1" && pwd)"

    sync_main "${repo}"
    [[ -f "${repo}/CHANGELOG.md" ]] || die "no CHANGELOG.md; run prepare first"
    version="$(top_changelog_version <"${repo}/CHANGELOG.md")"
    [[ "${version}" =~ ${SEMVER_RE} ]] || die "could not read a version from CHANGELOG.md"
    tag="v${version}"
    git -C "${repo}" rev-parse -q --verify "refs/tags/${tag}" >/dev/null && die "${tag} is already tagged"

    # Squash-merge subject: "chore(release): vX.Y.Z (#N)"
    commit="$(git -C "${repo}" log --format=%H -n1 -E \
        --grep="^chore\\(release\\): ${tag//./\\.}( \\(#[0-9]+\\))?$" "${MAIN_BRANCH}")"
    [[ -n "${commit}" ]] || die "no 'chore(release): ${tag}' commit on ${MAIN_BRANCH}; merge the release PR first"
    [[ "$(git -C "${repo}" show "${commit}:CHANGELOG.md" | top_changelog_version)" == "${version}" ]] \
        || die "CHANGELOG.md at ${commit:0:7} does not list ${version} first"

    TMP_DIR="$(mktemp -d)"
    notes_file="${TMP_DIR}/notes.md"
    git -C "${repo}" show "${commit}:CHANGELOG.md" | changelog_entry "${version}" >"${notes_file}"

    git -C "${repo}" tag -s -m "${tag}" "${tag}" "${commit}"
    git -C "${repo}" push --quiet origin "refs/tags/${tag}"
    (cd "${repo}" && gh release create "${tag}" --verify-tag --title "${tag}" --notes-file "${notes_file}")
    ok "Published ${tag} at ${commit:0:7}"
}

main() {
    [[ $# -ge 1 ]] || usage 1
    local cmd="$1"
    shift
    case "${cmd}" in
        prepare) require_tools; cmd_prepare "$@" ;;
        publish) require_tools; cmd_publish "$@" ;;
        -h|--help|help) usage 0 ;;
        *) die "unknown command '${cmd}'" ;;
    esac
}

main "$@"
