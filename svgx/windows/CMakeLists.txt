# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "svgx")
project(${PROJECT_NAME} LANGUAGES CXX)

# svgx ships precompiled Rust binaries (see PRECOMPILED_MIGRATION_PLAN.md):
# consumers need no Rust toolchain, and nothing is compiled here. Flutter's
# generated_plugins.cmake only reads `<plugin>_bundled_libraries` for an FFI
# plugin and copies those files next to the runner executable — it does not
# require this file to define any CMake target.
#
# svgx 随包分发预编译的 Rust 二进制（见 PRECOMPILED_MIGRATION_PLAN.md）：下游
# 不需要 Rust 工具链，这里也不编译任何东西。Flutter 的 generated_plugins.cmake
# 对 FFI 插件只读取 `<plugin>_bundled_libraries` 并把这些文件拷到 runner 旁边，
# 不要求本文件定义任何 CMake target。

# Windows-on-ARM consumers get the arm64 slice; everyone else gets x64. The
# previous cargokit source build compiled for whatever the consumer's machine
# was, so keeping arm64 here avoids a silent compatibility regression.
#
# ARM 版 Windows 用 arm64 slice，其余用 x64。此前 cargokit 是在用户机器上按其
# 架构现编的，保留 arm64 才不会造成静默的兼容性回退。
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(ARM64|arm64|aarch64)$")
  set(svgx_arch "arm64")
else()
  set(svgx_arch "x64")
endif()

set(svgx_prebuilt "${CMAKE_CURRENT_SOURCE_DIR}/../prebuilt/windows/${svgx_arch}/svgx.dll")

# Without this check the failure mode is a silent one: the DLL simply never
# gets bundled, and the app dies at runtime inside DynamicLibrary.open with an
# error that points nowhere near the real cause.
#
# 没有这条检查时的失败模式非常隐蔽：DLL 静默不被打包，运行期才在
# DynamicLibrary.open 里报一个离根因十万八千里的错。
if(NOT EXISTS "${svgx_prebuilt}")
  message(FATAL_ERROR
    "svgx: prebuilt native library not found at\n"
    "  ${svgx_prebuilt}\n"
    "This package ships precompiled binaries instead of building Rust on your "
    "machine. If you are working from a source checkout, run:\n"
    "  dart run tool/build_prebuilt.dart --group windows\n"
    "See PRECOMPILED_MIGRATION_PLAN.md for details.")
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
set(svgx_bundled_libraries
  "${svgx_prebuilt}"
  PARENT_SCOPE
)
