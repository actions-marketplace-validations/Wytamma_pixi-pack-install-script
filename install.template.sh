#!/usr/bin/env sh
set -eu

# ------------------------
# 1. Define default values
# ------------------------
GH_USER="{{GH_USER}}"
PROJECT="{{PROJECT}}"
ENTRYPOINT="{{ENTRYPOINT}}"

BIN_DIR="$HOME/.local/bin"
ENVS_DIR="$HOME/.local/envs"

VERSION=""
NAME=""

UNINSTALL="false"
FORCE="false"

usage() {
  cat <<EOF
Usage: $0 [options]

  [--gh-user GH_USER]         GitHub user (default: $GH_USER)
  [--project PROJECT]         Project name (default: $PROJECT)
  [--entrypoint ENTRYPOINT]   Program to extract from the environment (default: $ENTRYPOINT)
  [--name NAME]               Name of executable (default: $ENTRYPOINT)
  [--version VERSION]         Version to install (default: latest from GitHub)
  [--bin-dir BIN_DIR]         Directory to place symlink (default: $BIN_DIR)
  [--envs-dir ENVS_DIR]       Directory where environments are stored (default: $ENVS_DIR)
  [--uninstall]               Remove the environment directory and symlink
  [--force]                   Force overwriting or removal without prompting
  [--help]                    Show this usage message
EOF
  exit 1
}

# --------------------------------
# 2. Parse CLI arguments if given
# --------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --gh-user)      GH_USER="$2";      shift 2 ;;
    --project)      PROJECT="$2";      shift 2 ;;
    --entrypoint)   ENTRYPOINT="$2";   shift 2 ;;
    --name)         NAME="$2";         shift 2 ;;
    --version)      VERSION="$2";      shift 2 ;;
    --bin-dir)      BIN_DIR="$2";      shift 2 ;;
    --envs-dir)     ENVS_DIR="$2";     shift 2 ;;
    --uninstall)    UNINSTALL="true";  shift 1 ;;
    --force)        FORCE="true";      shift 1 ;;
    -h|--help)      usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Decide on the name for the symlink/executable
[ -z "$NAME" ] && NAME="$ENTRYPOINT"

BIN="$BIN_DIR/$NAME"
ENV_DIR="$ENVS_DIR/$PROJECT"

# -----------------------
# 3. Handle --uninstall
# -----------------------
if [ "$UNINSTALL" = "true" ]; then
  # Remove environment directory
  if [ -d "$ENV_DIR" ]; then
    rm -rf "$ENV_DIR"
    echo "Removed environment directory: $ENV_DIR"
  else
    [ "$FORCE" = "true" ] || echo "Environment directory not found: $ENV_DIR"
  fi

  # Remove symlink or file
  if [ -e "$BIN" ] || [ -L "$BIN" ]; then
    if [ -L "$BIN" ]; then
      TARGET="$(readlink "$BIN")"
      EXPECTED_TARGET="$ENV_DIR/$NAME"
      if [ "$TARGET" != "$EXPECTED_TARGET" ] && [ "$FORCE" != "true" ]; then
        echo "Symlink $BIN points to $TARGET, not $EXPECTED_TARGET. Use --force to remove anyway."
        exit 1
      fi
    fi
    rm -f "$BIN"
    echo "Removed $BIN"
  else
    [ "$FORCE" = "true" ] || echo "Symlink/executable not found: $BIN"
  fi

  echo "Uninstall complete!"
  exit 0
fi

# ----------------------------------------
# 4. Install (default action)
# ----------------------------------------
# Existing BIN?
if [ -e "$BIN" ] || [ -L "$BIN" ]; then
  if [ "$FORCE" = "true" ]; then
    rm -rf "$BIN"
    echo "Removed existing $BIN (forced overwrite)"
  else
    echo "Error: $BIN already exists. Use --name to choose a different name or --force to overwrite."
    exit 1
  fi
fi

mkdir -p "$BIN_DIR" "$ENV_DIR"

# ---------- remainder of original install logic (unchanged) ----------
get_version_from_github() {
  wget -qO - "https://api.github.com/repos/${GH_USER}/${PROJECT}/releases/latest" \
    | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

[ -z "$VERSION" ] && VERSION=$(get_version_from_github)
[ -n "$VERSION" ] || { echo "Failed to get the latest version from GitHub."; exit 1; }

# Ensure VERSION starts with 'v'
case "$VERSION" in
  v*) ;;
  *) VERSION="v$VERSION" ;;
esac

echo "Version: $VERSION"

get_operating_system() {
  case "$(uname -s)" in
    Darwin) echo "osx" ;;
    Linux)  echo "linux" ;;
    *)      echo "Unsupported OS"; exit 1 ;;
  esac
}
OS=$(get_operating_system); echo "Operating system: $OS"

get_architecture() {
  case "$(uname -m)" in
    x86_64)  echo "64" ;;
    arm64)   echo "arm64" ;;
    aarch64) echo "aarch64" ;;
    *)       echo "Unsupported architecture"; exit 1 ;;
  esac
}
ARCH=$(get_architecture); echo "Architecture: $ARCH"

URL="https://github.com/${GH_USER}/${PROJECT}/releases/download/${VERSION}/${PROJECT}-${VERSION}-${OS}-${ARCH}.sh"
FILE="${ENV_DIR}/${PROJECT}-${VERSION}-${OS}-${ARCH}.sh"

echo "Downloading installer from $URL"
wget --output-document="$FILE" "$URL"
[ -s "$FILE" ] || { echo "Failed to download installer"; exit 1; }

echo "Running installer"
chmod +x "$FILE"
"$FILE" --output-directory "$ENV_DIR"

[ -f "${ENV_DIR}/activate.sh" ] || { echo "Failed to create the environment."; exit 1; }

cp "${ENV_DIR}/activate.sh" "${ENV_DIR}/${NAME}"
echo "$ENTRYPOINT \$@" >> "${ENV_DIR}/${NAME}"
chmod +x "${ENV_DIR}/${NAME}"

echo "Creating symlink to ${ENV_DIR}/${NAME} in $BIN_DIR"
ln -s "${ENV_DIR}/${NAME}" "$BIN"

if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  echo "Warning: $BIN_DIR is not in your PATH. Add it, e.g.:"
  echo "  export PATH=\$PATH:$BIN_DIR"
fi

rm -f "$FILE" && echo "Removed installer: $FILE"
echo "Installation complete!"
