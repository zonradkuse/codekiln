# C++ with clang as default compiler: lld, lldb, clangd, clang-format, clang-tidy, CMake, Ninja, ccache
# A layer defines two functions: as_root (system packages) and as_user (per-user tools).

as_root() {
  apt-get update
  apt-get install -y --no-install-recommends \
    clang clangd clang-format clang-tidy lld lldb libc++-dev libc++abi-dev \
    build-essential cmake ninja-build pkg-config ccache gdb
  # Make cc/c++ point at clang so CMake and make pick it up by default.
  # gcc/g++ stay installed and can be selected with CC=gcc CXX=g++.
  update-alternatives --install /usr/bin/cc  cc  /usr/bin/clang   100
  update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++ 100
}

as_user() { :; }
