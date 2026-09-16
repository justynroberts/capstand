#!/usr/bin/env bash
# The only thing in this repository that ships anything — and what the app's
# self-updater consumes: a notarised Capstand-<version>.dmg on a GitHub release
# of justynroberts/capstand, tagged v<version>.
#
# Built here, not in CI, because signing and notarising need the Developer ID
# certificate and the notarytool keychain profile on this machine.
#
#   scripts/release.sh 0.2.0
#   scripts/release.sh 0.2.0 --dry-run          # everything except tag and publish
#   scripts/release.sh 0.2.0 --notes NOTES.md   # release body; otherwise generated
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

VERSION="" ; DRY_RUN=0 ; NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --notes)   shift; NOTES="$1" ;;
    *) [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && VERSION="$1" ;;
  esac
  shift
done

red()   { printf '\033[31m%s\033[0m' "$1"; }
green() { printf '\033[32m%s\033[0m' "$1"; }
dim()   { printf '\033[2m%s\033[0m'  "$1"; }
step()  { printf '\n%s %s\n' "$(green ▸)" "$1"; }
die()   { printf '\n%s %s\n' "$(red ✗)" "$1" >&2; [ $# -gt 1 ] && printf '%s\n' "$(dim "  $2")" >&2; exit 1; }

[ -n "$VERSION" ] || die "no version given" "scripts/release.sh 0.2.0 [--dry-run] [--notes file]"
[ -z "$NOTES" ] || [ -f "$NOTES" ] || die "notes file not found: $NOTES"

PROFILE="${NOTARY_KEYCHAIN_PROFILE:-notarytool}"
APP="Capstand.app"
DIST="dist"
DMG="$DIST/Capstand-$VERSION.dmg"

# ---- refuse before building anything ---------------------------------------

step "Checking the tree is clean"
[ -z "$(git status --porcelain)" ] || \
  die "the working tree has uncommitted changes" \
      "a release must correspond to a commit, or nobody can tell what shipped"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || printf '%s\n' "$(dim "  on $BRANCH, not main — continuing, but this is unusual")"

step "Checking the version is new"
git fetch --tags --quiet origin
git tag --list | grep -qx "v$VERSION" && die "v$VERSION already exists as a tag" "pick a later version"

step "Checking the signing identity is present"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')"
[ -n "$IDENTITY" ] || \
  die "no Developer ID certificate in the keychain" \
      "without it the build is ad-hoc signed and the updater will refuse it"

step "Checking notarytool credentials"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || \
  die "notarytool refused the keychain profile '$PROFILE'" \
      "xcrun notarytool store-credentials \"$PROFILE\" --apple-id <id> --team-id <team>  (or: the developer agreement needs accepting)"

# ---- build and prove it launches ---------------------------------------------

step "Setting the version to $VERSION"
# A dry run leaves the tree exactly as it found it, or the next run refuses.
[ "$DRY_RUN" = "1" ] && trap 'git checkout -- scripts/bundle.sh docs/index.html 2>/dev/null || true' EXIT
sed -i '' -E "s|^VERSION=\"[^\"]*\"|VERSION=\"$VERSION\"|" scripts/bundle.sh
grep -q "^VERSION=\"$VERSION\"" scripts/bundle.sh || die "could not set VERSION in scripts/bundle.sh"

# The Pages site links straight to this release's disk image, so the download
# works with no JavaScript and no API call.
sed -i '' -E \
  -e "s|releases/download/v[0-9.]+/Capstand-[0-9.]+\.dmg|releases/download/v$VERSION/Capstand-$VERSION.dmg|g" \
  -e "s|(class=\"dl-ver\">)[0-9.]+|\1$VERSION|g" docs/index.html
grep -q "Capstand-$VERSION.dmg" docs/index.html || die "could not set the download link in docs/index.html"

step "Building and signing"
swift build -c release --arch arm64 --arch x86_64 2>&1 | tail -1
./scripts/bundle.sh release | sed 's/^/  /'

# Intel Macs get the same download, so the app must carry both slices.
step "Checking the binary is universal"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Capstand")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || die "the app is not universal: $ARCHS"
echo "  $ARCHS"

# SwiftPM resource lookups can fall back to this checkout's .build and pass
# every local test while crashing elsewhere. Run a copy with .build hidden.
# A copy, because launching a bundle tags it and stapler then cannot write to it.
step "Launching a copy of the built app with .build hidden"
SMOKE="$(mktemp -d)"
ditto "$APP" "$SMOKE/$APP"
mv .build .build.release-smoke
REPORTED="$("$SMOKE/$APP/Contents/MacOS/Capstand" --version 2>&1 || true)"
mv .build.release-smoke .build
rm -rf "$SMOKE"
[ "$REPORTED" = "$VERSION" ] || die "the built app reports '$REPORTED', expected $VERSION"
echo "  launches without .build and reports $VERSION"

rm -rf "$DIST" && mkdir -p "$DIST"

# The app and the disk image each need their own ticket.
step "Notarising the app"
ditto -c -k --keepParent "$APP" "$DIST/Capstand-$VERSION.zip"
xcrun notarytool submit "$DIST/Capstand-$VERSION.zip" --keychain-profile "$PROFILE" --wait 2>&1 | sed 's/^/  /' | tee "$DIST/notary-app.log"
grep -q "status: Accepted" "$DIST/notary-app.log" || \
  die "Apple did not accept the app" "xcrun notarytool log <id> --keychain-profile $PROFILE"
xcrun stapler staple "$APP" >/dev/null || die "could not staple the app"
rm "$DIST/Capstand-$VERSION.zip"

step "Building the disk image"
for v in /Volumes/Capstand*; do
  [ -d "$v" ] && hdiutil detach "$v" -force -quiet 2>/dev/null && echo "  detached stale $v"
done
true
STAGING="$DIST/staging"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP"
ln -s /Applications "$STAGING/Applications"
# Versioned volume name: macOS refuses writes under a /Volumes path an app was
# once launched from, and it lets two versions mount side by side.
hdiutil create -volname "Capstand $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null || \
  die "hdiutil could not build the disk image" "run it without >/dev/null to see why"
rm -rf "$STAGING"

# sign → notarise → staple. Signing after stapling destroys the ticket.
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

step "Notarising the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | sed 's/^/  /' | tee "$DIST/notary-dmg.log"
grep -q "status: Accepted" "$DIST/notary-dmg.log" || \
  die "Apple did not accept the disk image" "xcrun notarytool log <id> --keychain-profile $PROFILE"
xcrun stapler staple "$DMG" >/dev/null || die "could not staple the disk image"

# ---- verify the artifacts, not the intention -------------------------------

step "Verifying what a download will see"
ASSESSMENT=$(spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 || true)
case "$ASSESSMENT" in
  *"Notarized Developer ID"*) echo "  $(basename "$DMG") — Gatekeeper accepts it" ;;
  *) die "Gatekeeper does not accept $(basename "$DMG")" "$ASSESSMENT" ;;
esac

MNT=$(hdiutil attach -nobrowse -readonly "$DMG" | grep Volumes | awk -F'\t' '{print $NF}')
ASSESSMENT=$(spctl -a -vvv -t exec "$MNT/$APP" 2>&1 || true)
STAPLED=$(xcrun stapler validate "$MNT/$APP" 2>&1 | tail -1)
hdiutil detach "$MNT" -quiet
case "$ASSESSMENT" in
  *"Notarized Developer ID"*) echo "  $APP inside it — Gatekeeper accepts it" ;;
  *) die "Gatekeeper does not accept the app inside the image" "$ASSESSMENT" ;;
esac
case "$STAPLED" in
  *"worked"*) echo "  $APP inside it — ticket stapled" ;;
  *) die "the app inside the image has no stapled ticket" "$STAPLED" ;;
esac

if [ "$DRY_RUN" = "1" ]; then
  printf '\n%s %s is built and verified. Nothing was tagged or published.\n  %s\n\n' \
    "$(green ✓)" "$VERSION" "$(dim "artifact: $DMG; tree left untouched")"
  exit 0
fi

# ---- only now does any of it become visible --------------------------------

step "Committing, tagging and publishing"
if [ -n "$(git status --porcelain)" ]; then
  git add scripts/bundle.sh docs/index.html
  git commit -q -m "Release $VERSION"
fi
git push -q origin "$BRANCH"
git tag -a "v$VERSION" -m "Capstand $VERSION"
git push -q origin "v$VERSION"

NOTES_ARG=(--generate-notes)
[ -n "$NOTES" ] && NOTES_ARG=(--notes-file "$NOTES")

gh release create "v$VERSION" "$DMG" --title "Capstand $VERSION" "${NOTES_ARG[@]}"

printf '\n%s Capstand %s published.\n\n' "$(green ✓)" "$VERSION"
