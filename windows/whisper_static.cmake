# App-owned project hook, scoped to whisper.cpp and its descendants. fllama's
# native assets are prebuilt and never see these compiler/linker settings.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build Whisper privately" FORCE)
set(GGML_STATIC ON CACHE BOOL "Static Whisper dependencies" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "Never load llama's ggml backends" FORCE)
set(GGML_CPU ON CACHE BOOL "Built-in CPU backend" FORCE)
set(GGML_CPU_ALL_VARIANTS OFF CACHE BOOL "Single built-in CPU backend" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "Portable Windows binaries" FORCE)
# Fixed x86-64-v3 target; never inherit the build machine's instruction set.
foreach(_instruction SSE42 AVX AVX2 BMI2 FMA F16C)
  set(GGML_${_instruction} ON CACHE BOOL "Whisper x86-64-v3 CPU" FORCE)
endforeach()
foreach(_instruction AVX_VNNI AVX512 AVX512_VBMI AVX512_VNNI AVX512_BF16 AMX_TILE AMX_INT8 AMX_BF16)
  set(GGML_${_instruction} OFF CACHE BOOL "Portable Whisper CPU" FORCE)
endforeach()
