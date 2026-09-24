#!/bin/sh
# Installs the dobase command-line tool on macOS or Linux:
#
#   curl -fsSL https://raw.githubusercontent.com/smgdkngt/dobase/main/cli/install.sh | sh
#
# DOBASE_VERSION picks a release (default: the latest), DOBASE_INSTALL_DIR
# where the program goes (default: ~/.local/bin).
set -eu

repo="smgdkngt/dobase"
version="${DOBASE_VERSION:-latest}"
install_dir="${DOBASE_INSTALL_DIR:-$HOME/.local/bin}"

fail() {
  echo "dobase: $*" >&2
  exit 1
}

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) target="aarch64-apple-darwin" ;;
  Darwin-x86_64) target="x86_64-apple-darwin" ;;
  Linux-x86_64 | Linux-amd64) target="x86_64-unknown-linux-musl" ;;
  Linux-aarch64 | Linux-arm64) target="aarch64-unknown-linux-musl" ;;
  *) fail "there is no build for $(uname -s) $(uname -m). Download one from https://github.com/$repo/releases" ;;
esac

if [ "$version" = "latest" ]; then
  base="https://github.com/$repo/releases/latest/download"
else
  base="https://github.com/$repo/releases/download/$version"
fi
archive="dobase-$target.tar.gz"

if command -v curl > /dev/null; then
  fetch() { curl -fsSL "$1" -o "$2"; }
elif command -v wget > /dev/null; then
  fetch() { wget -q "$1" -O "$2"; }
else
  fail "needs curl or wget to download."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $archive ($version)..."
fetch "$base/$archive" "$tmp/$archive" || fail "could not download $base/$archive"
fetch "$base/$archive.sha256" "$tmp/$archive.sha256" || fail "could not download the checksum for $archive"

expected="$(cut -d ' ' -f 1 < "$tmp/$archive.sha256")"
if command -v sha256sum > /dev/null; then
  actual="$(sha256sum "$tmp/$archive" | cut -d ' ' -f 1)"
else
  actual="$(shasum -a 256 "$tmp/$archive" | cut -d ' ' -f 1)"
fi
[ "$expected" = "$actual" ] || fail "the download doesn't match its checksum. Try again later."

tar -xzf "$tmp/$archive" -C "$tmp"
mkdir -p "$install_dir"
install -m 755 "$tmp/dobase" "$install_dir/dobase"
echo "Installed $("$install_dir/dobase" --version) to $install_dir/dobase"

case ":$PATH:" in
  *":$install_dir:"*) ;;
  *)
    echo
    echo "$install_dir is not on your PATH. Add this line to your shell's profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"$install_dir:\$PATH\""
    ;;
esac

echo
echo "Next, sign in with a token from Profile → API:"
echo "  dobase login https://your-dobase.example.com"
