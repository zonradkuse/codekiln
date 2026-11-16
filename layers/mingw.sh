# Windows cross compilers: mingw-w64 for x86_64 and i686 (POSIX threads, so std::thread works)
# With clang:  clang++ --target=x86_64-w64-mingw32 -fuse-ld=lld ...

as_root() {
  apt-get update
  apt-get install -y --no-install-recommends mingw-w64
  # Debian/Ubuntu default to the win32 thread model; switch to posix.
  for arch in x86_64 i686; do
    for tool in gcc g++; do
      update-alternatives --set "${arch}-w64-mingw32-${tool}" "/usr/bin/${arch}-w64-mingw32-${tool}-posix" || true
    done
  done
}

as_user() { :; }
