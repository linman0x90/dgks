#!/usr/bin/env bash
# Release dG KillShot: tag main, publish the GitHub release, wait for the CurseForge build
# and check the package it made.
#
#   tools/release.sh 12.0.011 notes.md     full release
#   tools/release.sh --check 12.0.011      only wait for and check the CurseForge package
#
# notes.md is the release body in Markdown, without the "# dG KillShot x" title line (the
# release title is set to that). The tag push starts the CurseForge build through its webhook.
set -euo pipefail

PROJECT_ID=14980
WAIT_SECONDS=600

die() { echo "release: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

check_only=0
if [ "${1:-}" = "--check" ]; then check_only=1; shift; fi
version="${1:-}"
notes="${2:-}"
[ -n "$version" ] || die "usage: tools/release.sh [--check] <version> [notes.md]"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version should look like 12.0.011, got '$version'"

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

gh="$(command -v gh || true)"
[ -n "$gh" ] || gh="/c/Program Files/GitHub CLI/gh.exe"
[ -x "$gh" ] || die "GitHub CLI not found"
py="$(command -v python || command -v python3 || true)"
[ -n "$py" ] || die "python not found"

if [ "$check_only" = 0 ]; then
	[ -n "$notes" ] || die "release notes file required"
	[ -f "$notes" ] || die "notes file not found: $notes"

	step "Preflight"
	branch="$(git rev-parse --abbrev-ref HEAD)"
	[ "$branch" = "main" ] || die "on branch '$branch', not main"
	[ -z "$(git status --porcelain)" ] || die "working tree has uncommitted changes"
	git fetch -q --tags origin
	[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "local main differs from origin/main (pull or push first)"
	! git rev-parse -q --verify "refs/tags/$version" >/dev/null || die "tag $version already exists"
	prev="$(git describe --tags --abbrev=0 2>/dev/null || true)"
	if [ -n "$prev" ]; then
		[ -n "$(git log --oneline "$prev..HEAD")" ] || die "no commits since $prev"
		echo "Commits since $prev:"
		git log --oneline --no-merges "$prev..HEAD" | sed 's/^/  /'
	fi

	step "Tests"
	"$py" tests/run_all.py | tail -n 3

	step "Tag $version"
	# Lightweight tags, like the earlier releases
	git tag "$version" HEAD
	git push -q origin "$version"
	echo "Pushed tag $version at $(git rev-parse --short HEAD)"

	step "GitHub release"
	body="$(mktemp)"
	# Drop a UTF-8 BOM, which GitHub would show as a stray character
	sed '1s/^\xEF\xBB\xBF//' "$notes" > "$body"
	"$gh" release create "$version" --verify-tag --title "dG KillShot $version" --notes-file "$body"
	rm -f "$body"
fi

step "CurseForge build"
api="https://www.curseforge.com/api/v1/mods/$PROJECT_ID/files?pageIndex=0&pageSize=10&sort=dateCreated&sortDescending=true"
file_id=""
deadline=$((SECONDS + WAIT_SECONDS))
while :; do
	file_id="$(curl -s -A "Mozilla/5.0" "$api" | "$py" -I -c '
import sys, json
try:
    data = json.load(sys.stdin).get("data", [])
except Exception:
    data = []
for f in data:
    if f.get("displayName") == sys.argv[1]:
        print(f["id"], f.get("dateCreated"))
        break
' "$version" || true)"
	[ -n "$file_id" ] && break
	[ "$SECONDS" -lt "$deadline" ] || die "no CurseForge file for $version after $((WAIT_SECONDS / 60)) minutes; check the project's webhook and build log on CurseForge"
	sleep 20
done
created="${file_id#* }"
file_id="${file_id%% *}"
echo "CurseForge file $file_id, created $created"

step "Package check"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
zip="$work/dgks-$version.zip"
curl -sL -A "Mozilla/5.0" -o "$zip" "https://www.curseforge.com/api/v1/mods/$PROJECT_ID/files/$file_id/download"
"$py" -I - "$zip" "$version" <<'EOF'
import re, sys, zipfile

path, version = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(path)
names = z.namelist()
problems = []

def has_dir(d):
    return [n for n in names if n.startswith(f"dgks/{d}/")]

for d in ("tests", "tools", ".claude", ".vscode"):
    if has_dir(d):
        problems.append(f"package contains {d}/ ({len(has_dir(d))} files)")

toc = z.read("dgks/dgks.toc").decode("utf-8", "replace")
m = re.search(r"## Version:\s*(\S+)", toc)
if not m or m.group(1) != version:
    problems.append(f"dgks.toc version is {m.group(1) if m else 'missing'}, expected {version}")

uncommented = [n for n in names if n.endswith(".lua") and not n.startswith("dgks/libs/")
               and re.search(r"^\s*--@debug@", z.read(n).decode("utf-8", "replace"), re.M)]
if uncommented:
    problems.append("debug blocks left active in " + ", ".join(uncommented))

libs = sorted({n.split("/")[2] for n in names if n.lower().startswith("dgks/libs/") and n.count("/") >= 3})
print(f"{len(names)} files, toc version {m.group(1) if m else '?'}")
print(f"{len(libs)} libraries: {', '.join(libs)}")
if problems:
    print("PROBLEMS:")
    for p in problems:
        print("  - " + p)
    sys.exit(1)
print("OK: no tests or tools folders, version matches, debug code commented out")
EOF
echo
if [ "$check_only" = 1 ]; then echo "Package for $version checked."; else echo "Released $version."; fi
echo "The downloaded package has been deleted."
