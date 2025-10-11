#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$(realpath "$0")")"

refresh_gnu_config() {
  for d in "$@"; do
    curl -sL -o "$d/config.sub"  https://git.savannah.gnu.org/cgit/config.git/plain/config.sub
    curl -sL -o "$d/config.guess" https://git.savannah.gnu.org/cgit/config.git/plain/config.guess
    chmod +x "$d/config.sub" "$d/config.guess"
  done
}

download_dependencies() {
  echo "Downloading dependencies..."
  if command -v gtar >/dev/null 2>&1; then tar_exec="gtar"; else tar_exec="tar"; fi

  curl -L -# -o sox.tar.gz 'https://downloads.sourceforge.net/project/sox/sox/14.4.2/sox-14.4.2.tar.gz'
  mkdir -p sox-src && $tar_exec -x -z -C sox-src --strip-components 1 -f sox.tar.gz

  curl -L -# -o libsndfile.tar.xz 'https://github.com/libsndfile/libsndfile/releases/download/1.2.2/libsndfile-1.2.2.tar.xz'
  mkdir -p sox-src/libsndfile && $tar_exec -x -J -C sox-src/libsndfile --strip-components 1 -f libsndfile.tar.xz

  curl -L -# -o libmad.tar.gz 'https://downloads.sourceforge.net/project/mad/libmad/0.15.1b/libmad-0.15.1b.tar.gz'
  mkdir -p sox-src/libmad && $tar_exec -x -z -C sox-src/libmad --strip-components 1 -f libmad.tar.gz

  rm -f sox.tar.gz libsndfile.tar.xz libmad.tar.gz
}

build_arch() {
  local arch="$1" host_triple build_dir cflags ldflags
  echo "Building for $arch..."

  case "$arch" in
    x86_64) host_triple="x86_64-pc-linux-gnu" ;;
    *) echo "Unsupported arch for this script: $arch" >&2; exit 1 ;;
  esac

  cflags=""    # native x64, no special -march needed
  ldflags=""

  build_dir="sox-build/linux-$arch"
  mkdir -p "$build_dir"

  # libsndfile (static)
  pushd sox-src/libsndfile
    make distclean || true; rm -f config.cache
    ./configure \
      --build="$(./config.guess)" \
      --host="$host_triple" \
      --prefix="$(pwd)/../../$build_dir" \
      --enable-static --disable-shared --disable-external-libs \
      CFLAGS="$cflags" LDFLAGS="$ldflags"
    make -j"$(nproc)"; make install
  popd

  # libmad (static)
  pushd sox-src/libmad
    refresh_gnu_config "."
    make distclean || true; rm -f config.cache
    ./configure \
      --build="$(./config.guess)" \
      --host="$host_triple" \
      --disable-shared --enable-static \
      --prefix="$(pwd)/../../$build_dir" \
      CFLAGS="$cflags" LDFLAGS="$ldflags"
    make -j"$(nproc)"; make install
  popd

  # SoX (static)
  pushd sox-src
    make distclean || true; rm -f config.cache
    export PKG_CONFIG_PATH="$(pwd)/../$build_dir/lib/pkgconfig"
    ./configure \
      --build="$(./config.guess)" \
      --host="$host_triple" \
      --prefix="$(pwd)/../$build_dir" \
      --enable-static --disable-shared \
      --with-mad \
      --with-alsa \
      --with-pulseaudio \
      --without-lame --without-id3tag \
      --without-magic --without-png \
      --without-twolame \
      --without-ladspa --without-opus \
      --without-flac --without-wavpack \
      --without-ao \
      CFLAGS="-I$(pwd)/../$build_dir/include -Wno-incompatible-function-pointer-types $cflags" \
      LDFLAGS="-L$(pwd)/../$build_dir/lib $ldflags"
    make -j"$(nproc)"; make install
  popd

  echo "Done. Binaries in $build_dir/bin"
}

[ -d sox-src ] || download_dependencies
rm -rf sox-build || true
build_arch "x86_64"
