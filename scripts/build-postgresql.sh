#!/bin/bash
set -e

VERSION=${1:-"16.4"}
ARCH=${2:-"arm64"}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../build/postgresql-$VERSION"
DIST_DIR="$SCRIPT_DIR/../dist"
PREFIX="$BUILD_DIR/install"

echo "🐘 Building PostgreSQL $VERSION for $ARCH..."

# Create directories
mkdir -p "$BUILD_DIR" "$DIST_DIR"
cd "$BUILD_DIR"

# Download source
if [ ! -f "postgresql-$VERSION.tar.bz2" ]; then
    echo "📥 Downloading PostgreSQL $VERSION..."
    curl -LO "https://ftp.postgresql.org/pub/source/v$VERSION/postgresql-$VERSION.tar.bz2"
fi

# Extract
if [ ! -d "postgresql-$VERSION" ]; then
    echo "📦 Extracting..."
    tar xf "postgresql-$VERSION.tar.bz2"
fi

cd "postgresql-$VERSION"

# Find OpenSSL and readline paths
if [ "$ARCH" = "arm64" ]; then
    HOMEBREW_PREFIX="/opt/homebrew"
else
    HOMEBREW_PREFIX="/usr/local"
fi

OPENSSL_PATH="$HOMEBREW_PREFIX/opt/openssl@3"
READLINE_PATH="$HOMEBREW_PREFIX/opt/readline"
ICU_PATH="$HOMEBREW_PREFIX/opt/icu4c"

# Configure
echo "⚙️ Configuring..."
./configure \
    --prefix="$PREFIX" \
    --with-openssl \
    --with-readline \
    --with-icu \
    --with-uuid=e2fs \
    --with-libxml \
    CFLAGS="-arch $ARCH -I$OPENSSL_PATH/include -I$READLINE_PATH/include -I$ICU_PATH/include" \
    LDFLAGS="-arch $ARCH -L$OPENSSL_PATH/lib -L$READLINE_PATH/lib -L$ICU_PATH/lib -Wl,-headerpad_max_install_names" \
    PKG_CONFIG_PATH="$OPENSSL_PATH/lib/pkgconfig:$READLINE_PATH/lib/pkgconfig:$ICU_PATH/lib/pkgconfig"

# Build
echo "🔨 Building..."
make -j$(sysctl -n hw.ncpu)

# Install to prefix
echo "📦 Installing..."
make install

# Create tarball with only essential binaries
echo "📦 Creating distribution tarball..."
cd "$PREFIX"

# Create a minimal dist with just what we need
TARBALL_NAME="postgresql-$VERSION-macos-$ARCH"
mkdir -p "$DIST_DIR/$TARBALL_NAME/bin"
mkdir -p "$DIST_DIR/$TARBALL_NAME/lib"
mkdir -p "$DIST_DIR/$TARBALL_NAME/share"

# Copy essential binaries
for bin in postgres psql pg_ctl initdb createdb dropdb pg_dump pg_restore createuser dropuser pg_isready vacuumdb; do
    if [ -f "bin/$bin" ]; then
        cp "bin/$bin" "$DIST_DIR/$TARBALL_NAME/bin/"
    fi
done

# Copy libraries
cp -r lib/*.dylib "$DIST_DIR/$TARBALL_NAME/lib/" 2>/dev/null || true
cp -r lib/*.a "$DIST_DIR/$TARBALL_NAME/lib/" 2>/dev/null || true

# Copy share files (postgres.bki, timezone, sql, extensions...).
# configure only appends /postgresql to the share dir when the prefix doesn't
# already contain "postgres" -- ours does (build/postgresql-X/install), so the
# files are in share/ itself. The old "share/postgresql/*" copy matched nothing,
# "|| true" hid it, and every release shipped without them: initdb fails with
# 'file ".../share/postgres.bki" does not exist'. Copy whatever pg_config says,
# into the same relative spot (initdb looks in bin/../share), and fail loudly.
SHARE_DIR="$(bin/pg_config --sharedir)"
cp -R "$SHARE_DIR/." "$DIST_DIR/$TARBALL_NAME/share/"
if [ ! -f "$DIST_DIR/$TARBALL_NAME/share/postgres.bki" ]; then
    echo "❌ share/postgres.bki missing from the package (sharedir: $SHARE_DIR)" >&2
    exit 1
fi

# Fix library paths to be relative. The binaries reference bundled libs by
# their absolute install path ($PREFIX/lib/libpq.5.dylib, a path that only
# exists on the CI runner), so adding an rpath alone isn't enough: every such
# reference has to become @rpath/<name>, and each dylib's own id too.
cd "$DIST_DIR/$TARBALL_NAME"
for dylib in lib/*.dylib; do
    install_name_tool -id "@rpath/$(basename "$dylib")" "$dylib"
done
for file in bin/* lib/*.dylib; do
    for ref in $(otool -L "$file" | tail -n +2 | awk '{print $1}' | grep "^$PREFIX/lib/"); do
        install_name_tool -change "$ref" "@rpath/$(basename "$ref")" "$file"
    done
done
for bin in bin/*; do
    install_name_tool -add_rpath @executable_path/../lib "$bin"
done
# Editing load commands invalidates the signature; arm64 kills such binaries.
for file in bin/* lib/*.dylib; do
    codesign --force --sign - "$file"
done
if otool -L bin/* lib/*.dylib | grep -q "$PREFIX"; then
    echo "❌ binaries still reference the build prefix:" >&2
    otool -L bin/* lib/*.dylib | grep "$PREFIX" >&2
    exit 1
fi

# Create tarball
cd "$DIST_DIR"
tar czf "$TARBALL_NAME.tar.gz" "$TARBALL_NAME"
rm -rf "$TARBALL_NAME"

echo "✅ Built: $DIST_DIR/$TARBALL_NAME.tar.gz"
ls -lh "$DIST_DIR/$TARBALL_NAME.tar.gz"
