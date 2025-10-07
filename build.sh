#!/bin/sh
set -euxo pipefail

# Change to script directory
cd $(dirname $(realpath $0))

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

    # Cleanup
    rm -f sox.tar.gz libsndfile.tar.xz
}

build_arch() {
    arch=$1
    echo "Building for $arch..."
    
    # Setup build directories
    build_dir="sox-build/$arch"
    mkdir -p "$build_dir"
    
    # Build libsndfile first
    echo "Building libsndfile for $arch..."
    cd sox-src/libsndfile
    make distclean || true
    CFLAGS="-arch $arch" ./configure --prefix=$(pwd)/../../$build_dir --enable-static --disable-shared --disable-external-libs
    make
    make install
    cd ../..
    
    # Now build sox
    echo "Building sox for $arch..."
    cd sox-src
    make distclean || true
    PKG_CONFIG_PATH="$(pwd)/../$build_dir/lib/pkgconfig" \
    CFLAGS="-arch $arch -I$(pwd)/../$build_dir/include -Wno-incompatible-function-pointer-types" \
    LDFLAGS="-L$(pwd)/../$build_dir/lib" \
    ./configure --prefix=$(pwd)/../$build_dir \
        --enable-static --disable-shared \
        --without-magic --without-png \
        --without-lame --without-twolame \
        --without-mad --without-id3tag \
        --without-ladspa --without-opus \
        --without-flac --without-wavpack \
        --without-ao
    make
    make install
    cd ..
}

# Detect platform
platform=$(uname -s)

if [ "$platform" = "Darwin" ]; then
    echo "Building for macOS (Universal Binary)..."

    # Backwards compatibility target
    export MACOSX_DEPLOYMENT_TARGET=13.0
    export SDKROOT=$(xcrun --sdk macosx --show-sdk-path)

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
