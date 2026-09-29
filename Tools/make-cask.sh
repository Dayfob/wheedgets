#!/bin/zsh
# Prints the Homebrew cask for a release. Used by the release workflow to
# update Dayfob/homebrew-tap; handy locally too:
#
#   ./Tools/make-cask.sh 0.1.0 <sha256> [notarized] > Casks/wheedgets.rb
set -euo pipefail

VERSION="$1"
SHA256="$2"
NOTARIZED="${3:-}"

cat <<EOF
cask "wheedgets" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/Dayfob/wheedgets/releases/download/v#{version}/Wheedgets-#{version}.zip"
  name "Wheedgets"
  desc "Fidget widgets for the menu bar: drums, a spinner and keyboard sounds"
  homepage "https://github.com/Dayfob/wheedgets"

  depends_on macos: :sonoma

  app "Wheedgets.app"

  uninstall quit: "dev.wheedgets.Wheedgets"

  zap trash: [
    "~/Library/Application Support/dev.wheedgets.Wheedgets",
    "~/Library/Preferences/dev.wheedgets.Wheedgets.plist",
  ]
EOF

if [[ "$NOTARIZED" != "notarized" ]]; then
  cat <<'EOF'

  caveats <<~EOS
    Wheedgets isn't notarized by Apple yet, so macOS may refuse to open it
    the first time. Open System Settings → Privacy & Security, scroll down
    and click "Open Anyway" next to Wheedgets.
  EOS
EOF
fi

echo "end"
