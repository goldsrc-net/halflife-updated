# Cross-compilation toolchain for Linux i386 from a 64-bit host.
# Usage: cmake -B build-i386 -DCMAKE_TOOLCHAIN_FILE=cmake/LinuxToolchain.cmake
#
# Don't hardcode a specific gcc version — probe for what's available
# (mirrors LinuxToolchain-aarch64.cmake's pattern). The goldsrc-net
# buildchain runs this in a debian:buster-based container (gcc-8);
# debian:12-based hosts have gcc-11/12.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR i386)

# Allow override via env; otherwise probe newest gcc → older → unversioned.
if (DEFINED ENV{I386_GCC})
	set(CMAKE_C_COMPILER   $ENV{I386_GCC})
	set(CMAKE_CXX_COMPILER $ENV{I386_GXX})
elseif (EXISTS /usr/bin/gcc-11)
	set(CMAKE_C_COMPILER   gcc-11)
	set(CMAKE_CXX_COMPILER g++-11)
elseif (EXISTS /usr/bin/gcc-10)
	set(CMAKE_C_COMPILER   gcc-10)
	set(CMAKE_CXX_COMPILER g++-10)
elseif (EXISTS /usr/bin/gcc-9)
	set(CMAKE_C_COMPILER   gcc-9)
	set(CMAKE_CXX_COMPILER g++-9)
elseif (EXISTS /usr/bin/gcc-8)
	set(CMAKE_C_COMPILER   gcc-8)
	set(CMAKE_CXX_COMPILER g++-8)
else()
	set(CMAKE_C_COMPILER   gcc)
	set(CMAKE_CXX_COMPILER g++)
endif()

set(CMAKE_C_FLAGS   -m32)
set(CMAKE_CXX_FLAGS "-m32 -static-libgcc -static-libstdc++ -D_GLIBCXX_USE_CXX11_ABI=0")
