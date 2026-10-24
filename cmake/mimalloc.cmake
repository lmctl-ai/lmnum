# Enable the pinned, static mimalloc allocator for a target.
#
# Use mimalloc's single-object C build. Its C source also emits mangled C++
# allocation aliases, so a marked build copy guards that optional alias block.
# memory_budget.cpp keeps owning/counting every C++ new/delete. MI_OVERRIDE=ON
# supplies the coherent C malloc/free/calloc/realloc/posix_memalign and
# malloc_usable_size entry points through the same allocator.
function(lmnum_enable_mimalloc target)
  if(NOT TARGET "${target}")
    message(FATAL_ERROR "lmnum_enable_mimalloc: unknown target '${target}'")
  endif()
  if(NOT UNIX OR APPLE)
    message(FATAL_ERROR "lmnum_enable_mimalloc is supported only on Linux")
  endif()
  if(NOT EXISTS "${CMAKE_SOURCE_DIR}/third_party/mimalloc/CMakeLists.txt")
    message(FATAL_ERROR "third_party/mimalloc missing: sync the pinned dependency first")
  endif()

  set(MI_OVERRIDE ON CACHE BOOL "mimalloc overrides the C allocation ABI" FORCE)
  set(MI_USE_CXX OFF CACHE STRING "mimalloc is compiled as C" FORCE)
  set(MI_NO_USE_CXX ON CACHE BOOL "mimalloc never compiles as C++" FORCE)
  set(MI_BUILD_SHARED OFF CACHE BOOL "" FORCE)
  set(MI_BUILD_STATIC OFF CACHE BOOL "" FORCE)
  set(MI_BUILD_OBJECT ON CACHE BOOL "" FORCE)
  set(MI_BUILD_TESTS OFF CACHE BOOL "" FORCE)
  set(MI_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(MI_SECURE OFF CACHE STRING "" FORCE)
  set(MI_ALLOW_THP OFF CACHE STRING "" FORCE)

  set(mi_source "${CMAKE_BINARY_DIR}/mimalloc-source")
  file(COPY "${CMAKE_SOURCE_DIR}/third_party/mimalloc/" DESTINATION "${mi_source}" PATTERN ".git" EXCLUDE)
  file(READ "${CMAKE_SOURCE_DIR}/third_party/mimalloc/src/alloc/alloc-override.c" mi_override)
  set(mi_begin "#ifdef __cplusplus\n  // ------------------------------------------------------")
  set(mi_end "#endif // __cplusplus")
  string(FIND "${mi_override}" "${mi_begin}" mi_begin_pos)
  string(FIND "${mi_override}" "${mi_end}" mi_end_pos)
  if(mi_begin_pos EQUAL -1 OR mi_end_pos EQUAL -1)
    message(FATAL_ERROR "mimalloc counted-new patch no longer matches deps.lock")
  endif()
  string(REPLACE "${mi_begin}" "// lmnum build patch: retain the host's counted C++ operators.\n#if !defined(LMNUM_KEEP_COUNTED_NEW)\n${mi_begin}" mi_override "${mi_override}")
  string(REPLACE "${mi_end}" "${mi_end}\n#endif // !LMNUM_KEEP_COUNTED_NEW" mi_override "${mi_override}")
  file(WRITE "${mi_source}/src/alloc/alloc-override.c" "${mi_override}")
  add_subdirectory("${mi_source}" "${CMAKE_BINARY_DIR}/mimalloc" EXCLUDE_FROM_ALL)
  if(NOT TARGET mimalloc-obj)
    message(FATAL_ERROR "mimalloc did not provide its static object target")
  endif()
  target_compile_definitions(mimalloc-obj PRIVATE LMNUM_KEEP_COUNTED_NEW=1)
  target_link_libraries("${target}" PRIVATE mimalloc-obj)
endfunction()
