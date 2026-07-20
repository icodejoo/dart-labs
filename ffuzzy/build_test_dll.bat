@rem Builds ffz.dll at the repo root for local `flutter test` runs on Windows —
@rem the same MSVC invocation Flutter's own CMake plugin build (windows/CMakeLists.txt,
@rem target `ffz`) produces, just without going through the full Flutter/CMake
@rem pipeline. Named `ffz.dll` (no `lib` prefix) to match both the real bundled
@rem plugin artifact and ffuzzy_ffi.dart's default DynamicLibrary.open('ffz.dll') --
@rem test files that pass an explicit path point at this same file.
cd /d "%~dp0"
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
mkdir build 2>nul
cl.exe /std:c11 /utf-8 /W3 /LD /Iinclude src\ffz_alloc.c src\ffz_chars.c src\ffz_class_table.c src\ffz_corpus.c src\ffz_edit.c src\ffz_fuzzy.c src\ffz_match.c src\ffz_pattern.c src\ffz_prefilter.c src\ffz_score.c src\ffz_string.c src\ffz_unicode_tables.c ffi\ffz_ffi.c /Fe:ffz.dll /Fo:build\
if %errorlevel% neq 0 exit /b %errorlevel%
echo BUILD OK
