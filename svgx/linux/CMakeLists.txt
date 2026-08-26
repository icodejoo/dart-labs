# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "svgx")
project(${PROJECT_NAME} LANGUAGES CXX)

# svgx ships precompiled Rust binaries (see PRECOMPILED_MIGRATION_PLAN.md):
# consumers need no Rust toolchain, and nothing is compiled here. Flutter's
# generated_plugins.cmake only reads `<plugin>_bundled_libraries` for an FFI
# plugin and copies those files into the bundle — it does not require this
# file to define any CMake target.
#
# svgx 随包分发预编译的 Rust 二进制（见 PRECOMPILED_MIGRATION_PLAN.md）：下游
# 不需要 Rust 工具链，这里也不编译任何东西。
#
# glibc floor: the shipped .so requires at most GLIBC_2.34 (measured with
# `objdump -T`), so it loads on Ubuntu 22.04 / Debian 12 / RHEL 9 and newer.
# musl was evaluated and rejected — a musl-libc .so cannot be dlopen'd into a
# glibc Flutter process; see tool/prebuilt_common.dart for the full findings.
#
# glibc 下限：分发的 .so 最高只需要 GLIBC_2.34（`objdump -T` 实测），可在
# Ubuntu 22.04 / Debian 12 / RHEL 9 及更新的发行版上加载。musl 方案已评估并否决
# ——musl libc 的 .so 无法被 dlopen 进 glibc 的 Flutter 进程，详见
# tool/prebuilt_common.dart。

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(svgx_arch "arm64")
else()
  set(svgx_arch "x64")
endif()

set(svgx_prebuilt "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/linux/${svgx_arch}/libsvgx.so")

# Without this check the failure mode is a silent one: the .so simply never
# gets bundled, and the app dies at runtime inside DynamicLibrary.open with an
# error that points nowhere near the real cause.
#
# 没有这条检查时的失败模式非常隐蔽：.so 静默不被打包，运行期才在
# DynamicLibrary.open 里报一个离根因十万八千里的错。
if(NOT EXISTS "${svgx_prebuilt}")
  message(FATAL_ERROR
    "svgx: prebuilt native library not found at\n"
    "  ${svgx_prebuilt}\n"
    "This package ships precompiled binaries instead of building Rust on your "
    "machine. If you are working from a source checkout, run:\n"
    "  dart run tool/build_prebuilt.dart --group linux\n"
    "See PRECOMPILED_MIGRATION_PLAN.md for details.")
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
set(svgx_bundled_libraries
  "${svgx_prebuilt}"
  PARENT_SCOPE
)
