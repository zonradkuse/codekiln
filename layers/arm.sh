# Cross compilers for ARM Linux: aarch64-linux-gnu and arm-linux-gnueabihf (gcc, g++, libc, libstdc++)
# With clang, target the same sysroots:  clang++ --target=aarch64-linux-gnu -fuse-ld=lld ...

as_root() {
  apt-get update
  apt-get install -y --no-install-recommends \
    crossbuild-essential-arm64 crossbuild-essential-armhf
}

as_user() { :; }
