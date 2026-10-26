# Builds the ffz shared library (matcher + FFI shim [+ crash handler]) for
# Flutter ffiPlugin use (Android / Windows / Linux desktop) or any CMake consumer.
#
# 构建配置自动决定调试、性能分析与发布模式，适配 Flutter 的对应配置：
#   * debug/profile -> LOCATABLE: -O1 -g, symbols kept (no strip, no hidden
#     visibility), asserts on, the in-process crash handler compiled in. Native
#     errors AND hard crashes are pinpointed in-process (Windows: file:line via
#     PDB; POSIX: func+offset via dladdr).
#   * release       -> COMPRESSED: -Os/-O2, NDEBUG, hidden visibility, stripped
#     with a split .debug sidecar (GCC/Clang) / .pdb (MSVC). The crash handler
#     is NOT compiled here, so the release lib stays ~32 KB (arm64).
#
# Why the handler is release-OFF by default: it forces .eh_frame unwind tables
# across the whole library (so _Unwind_Backtrace can walk the stack), which
# inflates the stripped arm64 .so from ~32 KB to ~58 KB. Release crashes are
# instead diagnosed from the OS tombstone + the shipped .debug/.pdb sidecar.
# To put the in-process handler back into release (the ~58 KB path), configure
# with -DFFZ_CRASH_IN_RELEASE=ON and ship the sidecar.
cmake_minimum_required(VERSION 3.14)
project(ffz LANGUAGES C)

option(FFZ_CRASH_IN_RELEASE
  "Compile the in-process crash handler into release builds (+~26 KB unwind tables; ship the .debug/.pdb sidecar to symbolize)." OFF)

set(FFZ_SRCS
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_alloc.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_chars.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_class_table.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_corpus.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_edit.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_fuzzy.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_match.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_pattern.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_prefilter.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_score.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_string.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/ffz_unicode_tables.c"
  "${CMAKE_CURRENT_SOURCE_DIR}/ffi/ffz_ffi.c"
)

# 按实际构建配置选择断言、崩溃处理和符号保留，兼容多配置生成器。
set(FFZ_LOCATABLE "$<OR:$<CONFIG:Debug>,$<CONFIG:Profile>,$<CONFIG:RelWithDebInfo>>")
set(FFZ_CRASH "$<OR:${FFZ_LOCATABLE},$<BOOL:${FFZ_CRASH_IN_RELEASE}>>")
list(APPEND FFZ_SRCS "$<${FFZ_CRASH}:${CMAKE_CURRENT_SOURCE_DIR}/ffi/ffz_crash.c>")

add_library(ffz SHARED ${FFZ_SRCS})
target_include_directories(ffz PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_features(ffz PRIVATE c_std_11)

# ffz_corpus.c parallel scan uses pthreads on POSIX. glibc>=2.34 folds libpthread
# into libc, but musl / old glibc / non-glibc need it linked explicitly. No-op on
# Win32 (the corpus uses CreateThread there). Threads::Threads adds -pthread.
find_package(Threads REQUIRED)
target_link_libraries(ffz PRIVATE Threads::Threads)

target_compile_definitions(ffz PRIVATE
  $<$<NOT:${FFZ_LOCATABLE}>:NDEBUG>
  $<${FFZ_CRASH}:FFZ_HAVE_CRASH_HANDLER>)
# CMake 默认可能给带符号的优化配置定义断言关闭宏，这里恢复可定位配置的断言。
if(MSVC)
  target_compile_options(ffz PRIVATE $<${FFZ_LOCATABLE}:/UNDEBUG> /utf-8)
else()
  target_compile_options(ffz PRIVATE
    $<${FFZ_LOCATABLE}:-UNDEBUG>
    $<$<NOT:${FFZ_LOCATABLE}>:-fvisibility=hidden>
    "$<${FFZ_CRASH}:-funwind-tables;-fno-omit-frame-pointer>")
endif()
if(WIN32)
  target_link_libraries(ffz PRIVATE $<${FFZ_CRASH}:dbghelp>)
elseif(ANDROID)
  target_link_libraries(ffz PRIVATE "$<${FFZ_CRASH}:log;dl>")
endif()

# Optimization tier: Debug = low-opt for stepping; Profile (and RelWithDebInfo)
# = full -O2 AND symbols kept (optimized but still locatable — Flutter profile
# is a performance build); Release = size-optimized + stripped.
if(MSVC)
  target_compile_options(ffz PRIVATE /Zi)              # always emit a PDB sidecar
  target_link_options(ffz PRIVATE /DEBUG /OPT:REF /OPT:ICF)
  # 按实际配置选择优化等级，避免多配置调试构建混用互斥的运行时检查和优化选项。
  target_compile_options(ffz PRIVATE
    $<$<CONFIG:Debug>:/Od>
    $<$<NOT:$<CONFIG:Debug>>:/O2>)            # profile + release
else()
  # -g always: in locatable builds it stays in the .so; in release it is split
  # to the .debug sidecar and then stripped (so the sidecar is non-empty).
  target_compile_options(ffz PRIVATE -g -ffunction-sections -fdata-sections)
  target_compile_options(ffz PRIVATE
    $<$<CONFIG:Debug>:-O1>
    $<$<AND:${FFZ_LOCATABLE},$<NOT:$<CONFIG:Debug>>>:-O2>
    $<$<NOT:${FFZ_LOCATABLE}>:-Os>)
  if(NOT APPLE)
    target_link_options(ffz PRIVATE -Wl,--gc-sections)
  endif()
  # release (non-Apple): split debug info to a sidecar, then strip the shipped
  # library and link it back via gnu-debuglink. Apple keeps symbols in a .dSYM
  # produced by Xcode, so nothing to do there.
  if(NOT APPLE AND CMAKE_OBJCOPY AND CMAKE_STRIP)
    add_custom_command(TARGET ffz POST_BUILD
      COMMAND "${CMAKE_COMMAND}"
        "-DFFZ_CONFIG=$<CONFIG>" "-DFFZ_FILE=$<TARGET_FILE:ffz>"
        "-DFFZ_OBJCOPY=${CMAKE_OBJCOPY}" "-DFFZ_STRIP=${CMAKE_STRIP}"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/ffz_symbols.cmake"
      VERBATIM)
  endif()
endif()

# Flutter ffiPlugin: expose the built artifact for bundling.
set(ffz_bundled_libraries "$<TARGET_FILE:ffz>" PARENT_SCOPE)

# 显式启用本地测试，不影响 Flutter 插件的默认构建。
option(FFZ_BUILD_TESTS "Build native regression and allocation tests" OFF)
if(FFZ_BUILD_TESTS)
  enable_testing()
  set(FFZ_TEST_SRCS ${FFZ_SRCS})
  list(FILTER FFZ_TEST_SRCS EXCLUDE REGEX "ffz_crash")
  foreach(FFZ_TEST IN ITEMS test_ffz test_leak)
    add_executable(${FFZ_TEST} ${FFZ_TEST_SRCS} "test/${FFZ_TEST}.c")
    target_include_directories(${FFZ_TEST} PRIVATE include)
    target_compile_features(${FFZ_TEST} PRIVATE c_std_11)
    target_compile_definitions(${FFZ_TEST} PRIVATE FFZ_TRACK_ALLOC)
    target_link_libraries(${FFZ_TEST} PRIVATE Threads::Threads)
    if(MSVC)
      target_compile_options(${FFZ_TEST} PRIVATE /utf-8 /W3)
    endif()
    add_test(NAME ${FFZ_TEST} COMMAND ${FFZ_TEST})
  endforeach()
endif()
