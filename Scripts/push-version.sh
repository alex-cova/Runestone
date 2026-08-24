#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Push a new package version to origin.

Updates VERSION, creates a "Bump to X.Y.Z." commit, tags the release, and pushes
the branch and tag to origin. Runs swift test before releasing unless skipped.

Usage:
  ./scripts/push-version.sh [OPTIONS] [VERSION]

Arguments:
  VERSION    Explicit semver (e.g. 1.0.11). Defaults to a patch bump from VERSION.

Options:
  --patch       Bump the patch component (default when VERSION is omitted)
  --minor       Bump the minor component
  --major       Bump the major component
  --skip-tests  Do not run swift test before releasing
  --no-push     Commit and tag locally without pushing
  --dry-run     Print actions without changing git state
  -h, --help    Show this help message

Examples:
  ./scripts/push-version.sh              # 1.0.10 -> 1.0.11
  ./scripts/push-version.sh 1.1.0        # release 1.1.0
  ./scripts/push-version.sh --minor      # 1.0.10 -> 1.1.0
  ./scripts/push-version.sh --dry-run
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

version_is_valid() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

version_gt() {
    local left="$1"
    local right="$2"
    IFS=. read -r left_major left_minor left_patch <<< "$left"
    IFS=. read -r right_major right_minor right_patch <<< "$right"

    if (( left_major > right_major )); then
        return 0
    fi
    if (( left_major < right_major )); then
        return 1
    fi
    if (( left_minor > right_minor )); then
        return 0
    fi
    if (( left_minor < right_minor )); then
        return 1
    fi
    (( left_patch > right_patch ))
}

bump_version() {
    local current="$1"
    local kind="$2"
    IFS=. read -r major minor patch <<< "$current"

    case "$kind" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            die "unknown bump kind: $kind"
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}

SKIP_TESTS=false
DRY_RUN=false
NO_PUSH=false
BUMP_KIND="patch"
EXPLICIT_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-push)
            NO_PUSH=true
            shift
            ;;
        --patch)
            BUMP_KIND="patch"
            shift
            ;;
        --minor)
            BUMP_KIND="minor"
            shift
            ;;
        --major)
            BUMP_KIND="major"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1 (try --help)"
            ;;
        *)
            if version_is_valid "$1"; then
                EXPLICIT_VERSION="$1"
                shift
            else
                die "invalid version: $1 (expected MAJOR.MINOR.PATCH)"
            fi
            ;;
    esac
done

if [[ $# -gt 0 ]]; then
    die "unexpected arguments: $*"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

VERSION_FILE="$ROOT/VERSION"
[[ -f "$VERSION_FILE" ]] || die "missing VERSION file at repository root"

CURRENT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
version_is_valid "$CURRENT_VERSION" || die "invalid current version in VERSION: $CURRENT_VERSION"

if [[ -n "$EXPLICIT_VERSION" ]]; then
    NEW_VERSION="$EXPLICIT_VERSION"
else
    NEW_VERSION="$(bump_version "$CURRENT_VERSION" "$BUMP_KIND")"
fi

version_is_valid "$NEW_VERSION" || die "invalid release version: $NEW_VERSION"

if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    die "new version matches current version ($CURRENT_VERSION)"
fi

if ! version_gt "$NEW_VERSION" "$CURRENT_VERSION"; then
    die "new version $NEW_VERSION must be greater than current version $CURRENT_VERSION"
fi

if git rev-parse -q --verify "refs/tags/$NEW_VERSION" >/dev/null; then
    die "tag $NEW_VERSION already exists"
fi

if [[ "$DRY_RUN" == false && -n "$(git status --porcelain)" ]]; then
    die "working tree is not clean; commit or stash changes before releasing"
fi

BRANCH="$(git branch --show-current)"
if [[ "$BRANCH" != "main" ]]; then
    echo "warning: current branch is '$BRANCH', not 'main'" >&2
fi

if ! git remote get-url origin >/dev/null 2>&1; then
    die "remote 'origin' is not configured"
fi

echo "Releasing $CURRENT_VERSION -> $NEW_VERSION"

if [[ "$SKIP_TESTS" == false ]]; then
    echo "Running tests..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] swift test"
    else
        swift test
    fi
else
    echo "Skipping tests (--skip-tests)"
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] printf '%s' '$NEW_VERSION' > VERSION"
else
    printf '%s\n' "$NEW_VERSION" > "$VERSION_FILE"
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] git add VERSION"
    echo "[dry-run] git commit -m \"Bump to $NEW_VERSION.\""
    echo "[dry-run] git tag -a \"$NEW_VERSION\" -m \"$NEW_VERSION\""
    if [[ "$NO_PUSH" == false ]]; then
        echo "[dry-run] git push origin HEAD"
        echo "[dry-run] git push origin \"$NEW_VERSION\""
    fi
else
    git add VERSION
    git commit -m "Bump to $NEW_VERSION."
    git tag -a "$NEW_VERSION" -m "$NEW_VERSION"

    if [[ "$NO_PUSH" == false ]]; then
        git push origin HEAD
        git push origin "$NEW_VERSION"
    else
        echo "Created local commit and tag (--no-push); push manually when ready."
    fi
fi

echo "Done. Released $NEW_VERSION."
