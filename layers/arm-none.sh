# Bare-metal ARM toolchain (Cortex-M/R): arm-none-eabi gcc, binutils, newlib, gdb-multiarch
# With clang:  clang --target=arm-none-eabi --sysroot=/usr/lib/arm-none-eabi ...

as_root() {
  apt-get update
  apt-get install -y --no-install-recommends \
    gcc-arm-none-eabi binutils-arm-none-eabi \
    libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib \
    gdb-multiarch
}

as_user() { :; }
