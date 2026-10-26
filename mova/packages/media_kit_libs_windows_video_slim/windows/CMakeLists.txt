# This file is a part of media_kit (https://github.com/media-kit/media-kit).
# Modified for mova: uses mova-libmpv's own slimmed libmpv-2.dll instead of
# downloading the upstream media_kit prebuilt archive. ANGLE is likewise
# replaced by a newer build hosted as this repo's release asset (see below).

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
# 下载归档并校验 sha256；已存在且校验通过则跳过，校验失败直接报错，不回退旧文件。
function(download_and_verify url sha256 locationForArchive)
  # 已有归档但 sha256 不符：删除后重新下载。
  if(EXISTS "${locationForArchive}")
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)

    if(NOT sha256 STREQUAL ARCHIVE_SHA256)
      file(REMOVE "${locationForArchive}")
      message(STATUS "SHA256 mismatch. File deleted.")
    endif()
  endif()

  # 归档不存在则下载。
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}" STATUS DOWNLOAD_STATUS)
    list(GET DOWNLOAD_STATUS 0 DOWNLOAD_CODE)

    if(NOT DOWNLOAD_CODE EQUAL 0)
      file(REMOVE "${locationForArchive}")
      message(FATAL_ERROR "Download failed: ${url} (${DOWNLOAD_STATUS}).")
    endif()
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # 校验刚下载文件的 sha256。
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)

    if(sha256 STREQUAL ARCHIVE_SHA256)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      file(REMOVE "${locationForArchive}")
      message(FATAL_ERROR "${locationForArchive} Integrity check failed (expected ${sha256}, got ${ARCHIVE_SHA256}), please try to re-build project again.")
    endif()
  endif()
endfunction()

# ------------------------------------------------------------------------------
# [mova slim] Skip the upstream libmpv 7z download; use the committed artifact
# bundled inside this package's windows/ directory (or fallback to mova/libmpv/
# for backward compatibility).
# ------------------------------------------------------------------------------

# 只读 n9 WHEP 版（mova/libmpv/windows-x86_64-whep）；不再读包内 DLL，n6 旧目录已移除。
# 候选根目录：宿主 app 的 windows/ 相对（example 用法，插件目录是符号链接，不能按包路径推），
# 以及本包相对（包路径为真实路径时）。
set(MOVA_LIBMPV_ROOTS
  "${CMAKE_SOURCE_DIR}/../../libmpv"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../libmpv"
)
set(CUSTOM_LIBMPV_DIR "")
foreach(_sub windows-x86_64-whep)
  foreach(_root ${MOVA_LIBMPV_ROOTS})
    get_filename_component(_cand "${_root}/${_sub}" ABSOLUTE)
    if(NOT CUSTOM_LIBMPV_DIR AND EXISTS "${_cand}/libmpv-2.dll" AND EXISTS "${_cand}/libmpv.dll.a")
      set(CUSTOM_LIBMPV_DIR "${_cand}")
    endif()
  endforeach()
endforeach()
if(NOT CUSTOM_LIBMPV_DIR)
  message(FATAL_ERROR "mova slim libmpv not found (need libmpv-2.dll + libmpv.dll.a in windows-x86_64-whep under ${MOVA_LIBMPV_ROOTS}).")
endif()
set(CUSTOM_LIBMPV_DLL "${CUSTOM_LIBMPV_DIR}/libmpv-2.dll")

message(STATUS "[mova slim] Using ${CUSTOM_LIBMPV_DLL}")

# ------------------------------------------------------------------------------
# [mova slim] media_kit_video's own windows/CMakeLists.txt does NOT read the
# bundled_libraries variable for its *link-time* dependency — it hardcodes
# LIBMPV_SRC="${CMAKE_BINARY_DIR}/libmpv" independently and expects
# libmpv.dll.a (MinGW import lib) + include/*.h (mpv public headers) there.
# That's a private convention between the two upstream packages: the real
# media_kit_libs_windows_video downloads a 7z that already contains all
# three (dll + .dll.a + headers) into that exact path. We don't have an
# equivalent archive, so assemble the same directory shape ourselves from:
#   - libmpv/windows-x86_64-whep/libmpv.dll.a — import lib shipped next to the
#     DLL by the WHEP build, so its export table always matches.
#   - mpv-headers/*.h — mpv v0.41.0's public libmpv/*.h (client API 2.5), the
#     same version the shipped DLL is built from (keep in sync on mpv bumps).
set(MOVA_LIBMPV_HEADERS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../mpv-headers")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

file(MAKE_DIRECTORY "${LIBMPV_SRC}/include")
file(COPY "${CUSTOM_LIBMPV_DLL}" DESTINATION "${LIBMPV_SRC}")
# 导入库与 DLL 同目录取，保证导出表一致。
file(COPY "${CUSTOM_LIBMPV_DIR}/libmpv.dll.a" DESTINATION "${LIBMPV_SRC}")
file(COPY "${MOVA_LIBMPV_HEADERS_DIR}/" DESTINATION "${LIBMPV_SRC}/include")
# media_kit_video links "${LIBMPV_SRC}/libmpv.dll.a" but bundles/copies the
# runtime DLL by whatever name the bundled_libraries list below gives it —
# our DLL is named libmpv-2.dll (not libmpv.dll like the upstream archive),
# which is fine since nothing hardcodes that filename except this file.

message(STATUS "[mova slim] Populated ${LIBMPV_SRC} for media_kit_video's link step")

# ------------------------------------------------------------------------------
# [mova slim] ANGLE：运行时只随包 libEGL.dll、libGLESv2.dll（见文末 bundled_libraries）。
# 下载改为 sha256 校验，解压目录带标记，并提供本地覆盖开关。
# 当前仍指向上游 alexmercerind ANGLE.7z v1.0.1（2022-08）：它在 OpenGL ES 硬件渲染下
# 每分钟泄漏约 9~10 MiB，但 Chromium 117 及以后的 ANGLE 构建在 media_kit_video 2.0.1 下
# 不出画（Chromium 116 及以前能出画但同样泄漏），所以暂时不能换新版。
# 实测数据与结论见 mova-libmpv/doc/notes/2026-10-24-angle-replacement-verify.md。
# 将来换资产：改 ANGLE_URL 与 ANGLE_SHA256，资产需含 include/（EGL、GLES2、KHR）与
# lib/（两个 .dll.lib），因为 media_kit_video 硬编码读取 ${CMAKE_BINARY_DIR}/ANGLE。
# 本地自测开关：设置 CMake 变量或环境变量 MOVA_ANGLE_LOCAL_DIR 指向资产解压后的目录，
# 则跳过下载与校验直接使用；默认关闭。
# ------------------------------------------------------------------------------
set(ANGLE "ANGLE.7z")

set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_SHA256 "cc5911bb15d596fd5a2b362613ad35b7093b427117269a7359054a65746a5f9a")

set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")
set(ANGLE_STAMP "${ANGLE_SRC}/.mova-angle-stamp")

if(NOT DEFINED MOVA_ANGLE_LOCAL_DIR AND DEFINED ENV{MOVA_ANGLE_LOCAL_DIR})
  set(MOVA_ANGLE_LOCAL_DIR "$ENV{MOVA_ANGLE_LOCAL_DIR}")
endif()

if(MOVA_ANGLE_LOCAL_DIR)
  # 本地覆盖：不校验，仅供上传前自测。
  foreach(_f libEGL.dll libGLESv2.dll lib/libEGL.dll.lib lib/libGLESv2.dll.lib include/EGL/egl.h)
    if(NOT EXISTS "${MOVA_ANGLE_LOCAL_DIR}/${_f}")
      message(FATAL_ERROR "MOVA_ANGLE_LOCAL_DIR=${MOVA_ANGLE_LOCAL_DIR} is missing ${_f}.")
    endif()
  endforeach()
  message(WARNING "[mova slim] Using LOCAL ANGLE from ${MOVA_ANGLE_LOCAL_DIR} (no checksum verification).")
  file(REMOVE_RECURSE "${ANGLE_SRC}")
  file(MAKE_DIRECTORY "${ANGLE_SRC}")
  file(COPY "${MOVA_ANGLE_LOCAL_DIR}/" DESTINATION "${ANGLE_SRC}")
  file(WRITE "${ANGLE_STAMP}" "local")
else()
  download_and_verify(
    ${ANGLE_URL}
    ${ANGLE_SHA256}
    ${ANGLE_ARCHIVE}
  )

  # 解压目录里的标记与校验值不一致（含换版本、从本地覆盖切回）就清掉重解压，避免误用旧 DLL。
  set(ANGLE_STAMP_OK FALSE)
  if(EXISTS "${ANGLE_STAMP}")
    file(READ "${ANGLE_STAMP}" ANGLE_STAMP_CONTENT)
    if(ANGLE_STAMP_CONTENT STREQUAL ANGLE_SHA256)
      set(ANGLE_STAMP_OK TRUE)
    endif()
  endif()

  if(NOT ANGLE_STAMP_OK)
    message(STATUS "Extracting ${ANGLE}...")
    file(REMOVE_RECURSE "${ANGLE_SRC}")
    file(MAKE_DIRECTORY "${ANGLE_SRC}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E tar xzf "${ANGLE_ARCHIVE}"
      WORKING_DIRECTORY "${ANGLE_SRC}"
      RESULT_VARIABLE ANGLE_EXTRACT_RESULT
    )
    if(NOT ANGLE_EXTRACT_RESULT EQUAL 0
       OR NOT EXISTS "${ANGLE_SRC}/libEGL.dll"
       OR NOT EXISTS "${ANGLE_SRC}/libGLESv2.dll")
      file(REMOVE_RECURSE "${ANGLE_SRC}")
      message(FATAL_ERROR "Failed to extract ANGLE from ${ANGLE_ARCHIVE}.")
    endif()
    file(WRITE "${ANGLE_STAMP}" "${ANGLE_SHA256}")
  endif()
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

# Same variable name/shape the upstream package exports — the parent
# media_kit_video CMakeLists reads this by name to bundle the libraries into
# the app's output directory; renaming it would silently drop our DLL from
# the packaged build.
# [mova slim] Deliberately NOT bundled from ANGLE.7z (saves 10,775,128 bytes):
#   - zlib.dll            (203,264)   nobody imports it; it is a Debug-CRT build anyway.
#   - vk_swiftshader.dll  (4,808,008) Vulkan software ICD; unreachable, there is no
#                                     vk_swiftshader_icd.json and media_kit never asks ANGLE for Vulkan.
#   - vulkan-1.dll        (872,776)   only loaded if ANGLE picks the Vulkan backend (never here).
#   - d3dcompiler_47.dll  (4,891,080) loaded by libGLESv2 at runtime by NAME (not in the import table);
#                                     ANGLE searches the app directory first, then System32.
# Evidence: doc/notes/2026-10-02-windows-angle-shrink.md (mova-libmpv), variant E - with all four
# removed, inline / fullscreen / in-app mini window playback all rendered correctly (real screenshots),
# and the module list showed d3dcompiler_47.dll loaded from C:\Windows\SYSTEM32.
# PREREQUISITE: minimum supported OS is Windows 10 (product decision). Windows 10 ships
# d3dcompiler_47.dll in System32 (measured on build 19045: 4,517,376 bytes, v10.0.19041.3636).
# RISK: on Windows 7/8 or stripped-down OS images that lack it, ANGLE only fails when it first compiles
# a shader, so the symptom is a late black screen rather than a startup error.
# To restore it, add "${ANGLE_SRC}/d3dcompiler_47.dll" back to the list below.
# libEGL.dll / libGLESv2.dll are statically imported by media_kit_video_plugin - they must stay.
set(
  media_kit_libs_windows_video_bundled_libraries
  "${CUSTOM_LIBMPV_DLL}"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  PARENT_SCOPE
)
