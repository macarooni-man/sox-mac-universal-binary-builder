#!/bin/sh
set -euxo pipefail

# Change to script directory
cd "$(dirname "$(realpath "$0")")"

# Download dependencies
download_dependencies() {
    echo "Downloading dependencies..."

    if command -v gtar >/dev/null 2>&1; then
        tar_exec="gtar"
    else
        tar_exec="tar"
    fi

    # Download and extract SoX
    echo "Downloading SoX..."
    curl -L -# -o sox.tar.gz 'https://downloads.sourceforge.net/project/sox/sox/14.4.2/sox-14.4.2.tar.gz'
    mkdir -p sox-src
    $tar_exec -x -z -C sox-src --strip-components 1 -f sox.tar.gz

    # Download and extract libsndfile
    echo "Downloading libsndfile..."
    curl -L -# -o libsndfile.tar.xz 'https://github.com/libsndfile/libsndfile/releases/download/1.2.2/libsndfile-1.2.2.tar.xz'
    mkdir -p sox-src/libsndfile
    $tar_exec -x -J -C sox-src/libsndfile --strip-components 1 -f libsndfile.tar.xz

    # Download and extract mpg123
    echo "Downloading mpg123..."
    curl -L -# -o mpg123.tar.bz2 'https://www.mpg123.de/download/mpg123-1.32.6.tar.bz2'
    mkdir -p sox-src/mpg123
    $tar_exec -x -j -C sox-src/mpg123 --strip-components 1 -f mpg123.tar.bz2

    # Cleanup
    rm -f sox.tar.gz libsndfile.tar.xz mpg123.tar.bz2
}

build_arch() {
    arch="$1"
    echo "Building for $arch..."

    # Map archs
    case "$arch" in
        x86_64) host_triple="x86_64-apple-darwin" ;;
        arm64)  host_triple="aarch64-apple-darwin" ;;
        *) echo "Unsupported arch: $arch"; exit 1 ;;
    esac
    build_triple="$(uname -m)-apple-darwin"

    # Common flags
    cflags="-arch $arch"
    ldflags="-arch $arch"

    # Setup build directories
    build_dir="sox-build/$arch"
    mkdir -p "$build_dir"

    # Build libsndfile (static)
    echo "Building libsndfile for $arch..."
    cd sox-src/libsndfile
    make distclean || true
    rm -f config.cache
    CFLAGS="$cflags" LDFLAGS="$ldflags" \
    ./configure \
        --build="$build_triple" \
        --host="$host_triple" \
        --prefix="$(pwd)/../../$build_dir" \
        --enable-static --disable-shared --disable-external-libs
    make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    make install
    cd ../..

    # Build mpg123 (static)
    echo "Building mpg123 for $arch..."
    cd sox-src/mpg123
    make distclean || true
    rm -f config.cache
    CFLAGS="$cflags" LDFLAGS="$ldflags" \
    ./configure \
        --build="$build_triple" \
        --host="$host_triple" \
        --disable-shared --enable-static \
        --with-default-audio=coreaudio \
        --prefix="$(pwd)/../../$build_dir"
    make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    make install
    cd ../..

    # Build SoX (static) with mpg123 enabled
    echo "Building sox for $arch..."
    cd sox-src
    make distclean || true
    rm -f config.cache

    # Ensure per-arch pkg-config is found first
    export PKG_CONFIG_PATH="$(pwd)/../$build_dir/lib/pkgconfig"

    CFLAGS="$cflags -I$(pwd)/../$build_dir/include -Wno-incompatible-function-pointer-types" \
    LDFLAGS="$ldflags -L$(pwd)/../$build_dir/lib" \
    ./configure \
        --build="$build_triple" \
        --host="$host_triple" \
        --prefix="$(pwd)/../$build_dir" \
        --enable-static --disable-shared \
        --with-mpg123 \
        --without-lame --without-id3tag \
        --without-magic --without-png \
        --without-twolame \
        --without-mad \
        --without-ladspa --without-opus \
        --without-flac --without-wavpack \
        --without-ao
    make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    make install
    cd ..
}

# Detect platform
platform="$(uname -s)"

if [ "$platform" = "Darwin" ]; then
    echo "Building for macOS (Universal Binary)..."

    # Backwards compatibility target (adjust if you need older macOS)
    export MACOSX_DEPLOYMENT_TARGET=13.0
    export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

    echo "Using SDKROOT=$SDKROOT"
    echo "MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"

    # Download dependencies if sox-src doesn't exist
    if [ ! -d "sox-src" ]; then
        download_dependencies
    fi

    # Clean up previous build
    rm -rf sox-build

    # Build for each architecture
    build_arch "x86_64"
    build_arch "arm64"

    # Create universal binary
    echo "Creating universal binary..."
    cd sox-build
    mkdir -p universal/bin

    # Check if both architecture binaries exist
    if [ ! -f "x86_64/bin/sox" ] || [ ! -f "arm64/bin/sox" ]; then
        echo "Error: Missing architecture binaries"
        exit 1
    fi

    echo "Creating universal binaries..."
    for binary in sox soxi play rec; do
        if [ -f "x86_64/bin/$binary" ] && [ -f "arm64/bin/$binary" ]; then
            lipo -create "x86_64/bin/$binary" "arm64/bin/$binary" -output "universal/bin/$binary"
        else
            echo "Warning: Skipping $binary - missing one or both architecture versions"
        fi
    done

    echo "Build complete. Universal binaries are in sox-build/universal/bin/"
    ls -l universal/bin/
else
    echo "Unsupported platform: $platform"
    exit 1
fi
