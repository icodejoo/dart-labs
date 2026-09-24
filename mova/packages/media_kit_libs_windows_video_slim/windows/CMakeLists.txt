# This file is a part of media_kit (https://github.com/media-kit/media-kit).
# Modified for mova: uses mova-libmpv's own slimmed libmpv-2.dll instead of
# downloading the upstream media_kit prebuilt archive. ANGLE download logic
# is unchanged (unrelated to libmpv).

cmake_minimum_required(VERSION 3.14)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatiblity
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify MD5 of the newly downloaded file.
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  # Check if the directory exists
  if(EXISTS "${dir}")
    # Check if the directory is not empty
    file(GLOB dir_contents "${dir}/*")

    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# ------------------------------------------------------------------------------
# [mova slim] Skip the upstream libmpv 7z download; point straight at
# mova-libmpv's own CI-built, committed artifact.
# ------------------------------------------------------------------------------

# Deliberately NOT computed from CMAKE_CURRENT_SOURCE_DIR: Flutter reaches
# this package via a symlink (windows/flutter/ephemeral/.plugin_symlinks/
# media_kit_libs_windows_video/windows -> mova/packages/..._slim/windows),
# and on Windows CMake's ABSOLUTE/REALPATH resolution does NOT dereference
# it (verified: "../../.." from CMAKE_CURRENT_SOURCE_DIR walks up through
# .plugin_symlinks/ephemeral instead of packages/mova, even after
# get_filename_component(... REALPATH)). CMAKE_SOURCE_DIR is the top-level
# example/windows project dir, which is never itself a symlink, so anchor
# there instead: mova/example/windows -> up 2 -> mova/, matching the dist
# path .github/workflows/build-mova-libmpv.yml's windows job writes to
# (mova/tools/ffmpeg-slim/dist/windows-x86_64/libmpv-2.dll).
get_filename_component(
  CUSTOM_LIBMPV_DIR
  "${CMAKE_SOURCE_DIR}/../../tools/ffmpeg-slim/dist/windows-x86_64"
  ABSOLUTE
)

# Defensive: the committed filename is libmpv-2.dll (meson's mingw soversion
# naming), but tolerate a plain libmpv.dll too rather than silently pointing
# at nothing if that ever changes.
if(EXISTS "${CUSTOM_LIBMPV_DIR}/libmpv-2.dll")
  set(CUSTOM_LIBMPV_DLL "${CUSTOM_LIBMPV_DIR}/libmpv-2.dll")
elseif(EXISTS "${CUSTOM_LIBMPV_DIR}/libmpv.dll")
  set(CUSTOM_LIBMPV_DLL "${CUSTOM_LIBMPV_DIR}/libmpv.dll")
else()
  message(FATAL_ERROR "mova slim libmpv not found under ${CUSTOM_LIBMPV_DIR} (expected libmpv-2.dll or libmpv.dll) — check mova-libmpv CI has committed dist/windows-x86_64/ and git-lfs pulled it locally.")
endif()

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
#   - windows-devlib/libmpv.dll.a — generated once via `gendef` + `dlltool`
#     against dist/windows-x86_64/libmpv-2.dll's export table (regenerate
#     if that DLL is rebuilt with a different symbol set).
#   - mpv-headers/*.h — mpv's public libmpv/*.h at the exact commit pinned
#     in build-mova-libmpv.yml's windows job (78d43740f52db817d98bcf24fb30a76ab6fa13ff),
#     so the ABI these headers declare matches the shipped DLL.
set(MOVA_LIBMPV_DEVLIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../windows-devlib")
set(MOVA_LIBMPV_HEADERS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../mpv-headers")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

file(MAKE_DIRECTORY "${LIBMPV_SRC}/include")
file(COPY "${CUSTOM_LIBMPV_DLL}" DESTINATION "${LIBMPV_SRC}")
file(COPY "${MOVA_LIBMPV_DEVLIB_DIR}/libmpv.dll.a" DESTINATION "${LIBMPV_SRC}")
file(COPY "${MOVA_LIBMPV_HEADERS_DIR}/" DESTINATION "${LIBMPV_SRC}/include")
# media_kit_video links "${LIBMPV_SRC}/libmpv.dll.a" but bundles/copies the
# runtime DLL by whatever name the bundled_libraries list below gives it —
# our DLL is named libmpv-2.dll (not libmpv.dll like the upstream archive),
# which is fine since nothing hardcodes that filename except this file.

message(STATUS "[mova slim] Populated ${LIBMPV_SRC} for media_kit_video's link step")

# ------------------------------------------------------------------------------
# ANGLE archive containing the pre-built shared libraries & headers.
# Unrelated to libmpv — kept as the upstream download, unchanged.
# ------------------------------------------------------------------------------
set(ANGLE "ANGLE.7z")

set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z")
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")

set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

download_and_verify(
  ${ANGLE_URL}
  ${ANGLE_MD5}
  ${ANGLE_ARCHIVE}
)

check_directory_exists_and_not_empty(${ANGLE_SRC} ANGLE_SRC_VALID)

if(NOT ANGLE_SRC_VALID)
  message(STATUS "Extracting ${ANGLE}...")
  make_directory("${ANGLE_SRC}")
  add_custom_target("${PROJECT_NAME}_ANGLE_EXTRACT" ALL)
  add_custom_command(
    TARGET "${PROJECT_NAME}_ANGLE_EXTRACT"
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "\"${ANGLE_ARCHIVE}\""
    WORKING_DIRECTORY "${ANGLE_SRC}"
  )
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
set(
  media_kit_libs_windows_video_bundled_libraries
  "${CUSTOM_LIBMPV_DLL}"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
