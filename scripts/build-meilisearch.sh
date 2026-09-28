#!/bin/bash
# Download and repackage Meilisearch for macOS
#
# Usage: ./scripts/build-meilisearch.sh <version> [arch]
# Example: ./scripts/build-meilisearch.sh 1.11.3 arm64
#
# Meilisearch provides pre-built binaries, so we just download and repackage

set -euo pipefail

VERSION="${1:-1.11.3}"
ARCH="${2:-$(uname -m)}"
OUTPUT_DIR="dist"

echo "📦 Packaging Meilisearch ${VERSION} for ${ARCH}..."

mkdir -p "${OUTPUT_DIR}" cache

# Map architecture names
if [ "$ARCH" = "arm64" ]; then
    MEILI_ARCH="apple-silicon"
elif [ "$ARCH" = "x86_64" ]; then
    MEILI_ARCH="x86_64"
else
    echo "❌ Unsupported architecture: ${ARCH}"
    exit 1
fi

# Download pre-built binary
DOWNLOAD_URL="https://github.com/meilisearch/meilisearch/releases/download/v${VERSION}/meilisearch-macos-${MEILI_ARCH}"
BINARY_FILE="cache/meilisearch-${VERSION}-macos-${MEILI_ARCH}"

if [ ! -f "${BINARY_FILE}" ]; then
    echo "⬇️  Downloading Meilisearch ${VERSION}..."
    curl -fSL "${DOWNLOAD_URL}" -o "${BINARY_FILE}"
fi

# Package
PACKAGE_DIR="package/meilisearch-${VERSION}-macos-${ARCH}"
rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/bin"

# Copy and make executable
cp "${BINARY_FILE}" "${PACKAGE_DIR}/bin/meilisearch"
chmod +x "${PACKAGE_DIR}/bin/meilisearch"

# Strip binary
# Upstream release binaries are already stripped and signed; strip here
# invalidated the signature (the published meilisearch was killed on launch)
# for ~2% smaller downloads. Ship them as-is.
# Smoke test: a binary macOS won't run (bad signature, missing library) must
# fail the build instead of being published. This is how a stripped, unrunnable
# meilisearch shipped before.
for bin in "${PACKAGE_DIR}/bin/meilisearch"; do
    "$bin" --version >/dev/null || { echo "❌ $bin does not run" >&2; exit 1; }
done

# Create tarball
TARBALL_NAME="meilisearch-${VERSION}-macos-${ARCH}.tar.gz"
echo "📦 Creating ${TARBALL_NAME}..."
cd package
tar -czf "../${OUTPUT_DIR}/${TARBALL_NAME}" "meilisearch-${VERSION}-macos-${ARCH}"
cd ..

# Calculate checksum
CHECKSUM=$(shasum -a 256 "${OUTPUT_DIR}/${TARBALL_NAME}" | cut -d' ' -f1)
SIZE=$(stat -f%z "${OUTPUT_DIR}/${TARBALL_NAME}")

echo ""
echo "✅ Meilisearch ${VERSION} packaged successfully!"
echo "   File: ${OUTPUT_DIR}/${TARBALL_NAME}"
echo "   Size: ${SIZE} bytes"
echo "   SHA256: ${CHECKSUM}"
echo ""
echo "Manifest entry:"
echo "\"${VERSION}\": {"
echo "  \"${ARCH}\": {"
echo "    \"url\": \"https://github.com/karajanchang/bitl-service-builds/releases/download/meilisearch-${VERSION}/${TARBALL_NAME}\","
echo "    \"sha256\": \"${CHECKSUM}\","
echo "    \"size\": ${SIZE},"
echo "    \"binaries\": [\"meilisearch\"]"
echo "  }"
echo "}"

