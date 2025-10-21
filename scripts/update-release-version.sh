#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Determine version (prefer Package.swift semver, fallback to git describe)
PACKAGE_VERSION="$(sed -n 's/.*version:\s*"\([^"]*\)".*/\1/p' Package.swift | head -n 1)"
if [[ -z "$PACKAGE_VERSION" ]]; then
  if VERSION_FROM_GIT=$(git describe --tags --dirty --always 2>/dev/null); then
    PACKAGE_VERSION="$VERSION_FROM_GIT"
  else
    PACKAGE_VERSION="0.0.0-test"
  fi
fi

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_DIR="Sources/AISDKProviderUtils/Versioning/Generated"
  OUTPUT_FILE="$OUTPUT_DIR/SDKReleaseVersion.generated.swift"
else
  OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
fi
mkdir -p "$OUTPUT_DIR"

cat > "$OUTPUT_FILE" <<SWIFT
private let _sdkReleaseVersionInitializer: Void = {
    SDKReleaseVersion.provider = { "$PACKAGE_VERSION" }
    return ()
}()
SWIFT

printf 'Generated release version: %s -> %s\n' "$PACKAGE_VERSION" "$OUTPUT_FILE"
