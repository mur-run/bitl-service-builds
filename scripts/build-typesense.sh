#!/bin/bash
# Download and repackage Typesense for macOS
#
# Usage: ./scripts/build-typesense.sh <version> [arch]
# Example: ./scripts/build-typesense.sh 27.1 arm64
#
# Typesense provides pre-built binaries, so we just download and repackage

set -euo pipefail

VERSION="${1:-27.1}"
ARCH="${2:-$(uname -m)}"
OUTPUT_DIR="dist"
BUILD_DIR="build/typesense-${VERSION}"

echo "📦 Packaging Typesense ${VERSION} for ${ARCH}..."

mkdir -p "${OUTPUT_DIR}" cache "${BUILD_DIR}"

# Map architecture names
if [ "$ARCH" = "arm64" ]; then
    TS_ARCH="arm64"
elif [ "$ARCH" = "x86_64" ]; then
    TS_ARCH="amd64"
else
    echo "❌ Unsupported architecture: ${ARCH}"
    exit 1
fi

# Download pre-built tarball
DOWNLOAD_URL="https://dl.typesense.org/releases/${VERSION}/typesense-server-${VERSION}-darwin-${TS_ARCH}.tar.gz"
TARBALL_FILE="cache/typesense-server-${VERSION}-darwin-${TS_ARCH}.tar.gz"

if [ ! -f "${TARBALL_FILE}" ]; then
    echo "⬇️  Downloading Typesense ${VERSION}..."
    curl -fSL "${DOWNLOAD_URL}" -o "${TARBALL_FILE}"
fi

# Extract
echo "📦 Extracting..."
tar -xzf "${TARBALL_FILE}" -C "${BUILD_DIR}"

# Package
PACKAGE_DIR="package/typesense-${VERSION}-macos-${ARCH}"
rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/bin"

# Find and copy the binary
if [ -f "${BUILD_DIR}/typesense-server" ]; then
    cp "${BUILD_DIR}/typesense-server" "${PACKAGE_DIR}/bin/"
elif [ -f "${BUILD_DIR}/typesense-server-${VERSION}-darwin-${TS_ARCH}/typesense-server" ]; then
    cp "${BUILD_DIR}/typesense-server-${VERSION}-darwin-${TS_ARCH}/typesense-server" "${PACKAGE_DIR}/bin/"
else
    echo "❌ typesense-server binary not found"
    ls -la "${BUILD_DIR}"
    exit 1
fi

chmod +x "${PACKAGE_DIR}/bin/typesense-server"

# Strip binary (may not work on signed binaries)
# Upstream release binaries are already stripped and signed; strip here
# invalidated the signature (the published meilisearch was killed on launch)
# for ~2% smaller downloads. Ship them as-is.
# Smoke test: a binary macOS won't run (bad signature, missing library) must
# fail the build instead of being published. This is how a stripped, unrunnable
# meilisearch shipped before.
for bin in "${PACKAGE_DIR}/bin/typesense-server"; do
    "$bin" --version >/dev/null || { echo "❌ $bin does not run" >&2; exit 1; }
done

# Create tarball
TARBALL_NAME="typesense-${VERSION}-macos-${ARCH}.tar.gz"
echo "📦 Creating ${TARBALL_NAME}..."
cd package
tar -czf "../${OUTPUT_DIR}/${TARBALL_NAME}" "typesense-${VERSION}-macos-${ARCH}"
cd ..

# Calculate checksum
CHECKSUM=$(shasum -a 256 "${OUTPUT_DIR}/${TARBALL_NAME}" | cut -d' ' -f1)
SIZE=$(stat -f%z "${OUTPUT_DIR}/${TARBALL_NAME}")

echo ""
echo "✅ Typesense ${VERSION} packaged successfully!"
echo "   File: ${OUTPUT_DIR}/${TARBALL_NAME}"
echo "   Size: ${SIZE} bytes"
echo "   SHA256: ${CHECKSUM}"
echo ""
echo "Manifest entry:"
echo "\"${VERSION}\": {"
echo "  \"${ARCH}\": {"
echo "    \"url\": \"https://github.com/karajanchang/bitl-service-builds/releases/download/typesense-${VERSION}/${TARBALL_NAME}\","
echo "    \"sha256\": \"${CHECKSUM}\","
echo "    \"size\": ${SIZE},"
echo "    \"binaries\": [\"typesense-server\"]"
echo "  }"
echo "}"

