#!/usr/bin/env bash
#
# Point the project at a bundle identifier you own.
#
# The repository ships with the placeholder com.marty0427.PocketPass. Free provisioning
# (signing with a plain Apple ID, no paid programme) refuses to build if that identifier is
# already registered to somebody else's team, so pick one that is certainly yours.
#
# Usage:
#   Scripts/set-bundle-id.sh com.yourname.PocketPass
#
# The test bundles get the same identifier with Tests and UITests appended, which is the
# convention Xcode itself follows.
set -euo pipefail

NEW_ID="${1:-}"

if [ -z "$NEW_ID" ]; then
  echo "usage: Scripts/set-bundle-id.sh com.yourname.PocketPass" >&2
  exit 64
fi

if ! printf '%s' "$NEW_ID" | grep -Eq '^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$'; then
  echo "“$NEW_ID” is not a valid bundle identifier." >&2
  echo "Use reverse DNS: letters, digits, hyphens and dots, e.g. com.yourname.PocketPass" >&2
  exit 64
fi

cd "$(dirname "$0")/.."

python3 - "$NEW_ID" <<'PY'
import pathlib
import re
import sys

new_id = sys.argv[1]
project = pathlib.Path("PocketPass.xcodeproj/project.pbxproj")
source = project.read_text()

def rewrite(match: "re.Match[str]") -> str:
    current = match.group(1).strip()
    # Keep whichever bundle this line belongs to; matching on the current value means the
    # script still works after someone has already changed the identifier once.
    if current.endswith("UITests"):
        suffix = "UITests"
    elif current.endswith("Tests"):
        suffix = "Tests"
    else:
        suffix = ""
    return f"PRODUCT_BUNDLE_IDENTIFIER = {new_id}{suffix};"

updated, count = re.subn(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", rewrite, source)

if count == 0:
    sys.exit("No PRODUCT_BUNDLE_IDENTIFIER settings found — is the project file intact?")

project.write_text(updated)
print(f"Updated {count} bundle identifiers:")
for value in sorted(set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", updated))):
    print(f"  {value}")
PY

echo
echo "Next: open PocketPass.xcodeproj, and under Signing & Capabilities pick your team."
