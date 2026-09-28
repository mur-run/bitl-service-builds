#!/bin/bash
# Download and repackage MinIO for macOS
#
# Usage: ./scripts/build-minio.sh <version> [arch]
# Example: ./scripts/build-minio.sh 2024.11.07 arm64
#
# MinIO provides pre-built binaries, so we just download and repackage

set -euo pipefail

VERSION="${1:-2024.11.07}"
ARCH="${2:-$(uname -m)}"
OUTPUT_DIR="dist"

echo "📦 Packaging MinIO ${VERSION} for ${ARCH}..."

mkdir -p "${OUTPUT_DIR}" cache

# Convert version format (2024.11.07 -> RELEASE.2024-11-07T00-52-28Z format or just use latest)
# MinIO uses specific release tags like RELEASE.2024-11-07T00-52-28Z
# We'll download from dl.min.io which uses the simple format

# Map architecture names
if [ "$ARCH" = "arm64" ]; then
    MINIO_ARCH="arm64"
elif [ "$ARCH" = "x86_64" ]; then
    MINIO_ARCH="amd64"
else
    echo "❌ Unsupported architecture: ${ARCH}"
    exit 1
fi

# Download pre-built binaries
# MinIO server
MINIO_URL="https://dl.min.io/server/minio/release/darwin-${MINIO_ARCH}/minio"
MINIO_FILE="cache/minio-${VERSION}-darwin-${MINIO_ARCH}"

# MinIO client (mc)
MC_URL="https://dl.min.io/client/mc/release/darwin-${MINIO_ARCH}/mc"
MC_FILE="cache/mc-${VERSION}-darwin-${MINIO_ARCH}"

if [ ! -f "${MINIO_FILE}" ]; then
    echo "⬇️  Downloading MinIO server..."
    curl -fSL "${MINIO_URL}" -o "${MINIO_FILE}"
fi

if [ ! -f "${MC_FILE}" ]; then
    echo "⬇️  Downloading MinIO client (mc)..."
    curl -fSL "${MC_URL}" -o "${MC_FILE}"
fi

# Package
PACKAGE_DIR="package/minio-${VERSION}-macos-${ARCH}"
rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/bin"

# Copy and make executable
cp "${MINIO_FILE}" "${PACKAGE_DIR}/bin/minio"
cp "${MC_FILE}" "${PACKAGE_DIR}/bin/mc"
chmod +x "${PACKAGE_DIR}/bin/minio" "${PACKAGE_DIR}/bin/mc"

# Strip binaries (may not work on signed binaries)
# Upstream release binaries are already stripped and signed; strip here
# invalidated the signature (the published meilisearch was killed on launch)
# for ~2% smaller downloads. Ship them as-is.
# Smoke test: a binary macOS won't run (bad signature, missing library) must
# fail the build instead of being published. This is how a stripped, unrunnable
# meilisearch shipped before.
for bin in "${PACKAGE_DIR}/bin/minio" "${PACKAGE_DIR}/bin/mc"; do
    "$bin" --version >/dev/null || { echo "❌ $bin does not run" >&2; exit 1; }
done

# Create tarball
TARBALL_NAME="minio-${VERSION}-macos-${ARCH}.tar.gz"
echo "📦 Creating ${TARBALL_NAME}..."
cd package
tar -czf "../${OUTPUT_DIR}/${TARBALL_NAME}" "minio-${VERSION}-macos-${ARCH}"
cd ..

# Calculate checksum
CHECKSUM=$(shasum -a 256 "${OUTPUT_DIR}/${TARBALL_NAME}" | cut -d' ' -f1)
SIZE=$(stat -f%z "${OUTPUT_DIR}/${TARBALL_NAME}")

echo ""
echo "✅ MinIO ${VERSION} packaged successfully!"
echo "   File: ${OUTPUT_DIR}/${TARBALL_NAME}"
echo "   Size: ${SIZE} bytes"
echo "   SHA256: ${CHECKSUM}"
echo ""
echo "Manifest entry:"
echo "\"${VERSION}\": {"
echo "  \"${ARCH}\": {"
echo "    \"url\": \"https://github.com/karajanchang/bitl-service-builds/releases/download/minio-${VERSION}/${TARBALL_NAME}\","
echo "    \"sha256\": \"${CHECKSUM}\","
echo "    \"size\": ${SIZE},"
echo "    \"binaries\": [\"minio\", \"mc\"]"
echo "  }"
echo "}"

