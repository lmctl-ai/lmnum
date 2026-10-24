# Enable the pinned, static mimalloc allocator for a target.
#
# This deliberately uses mimalloc's single-object C build. MI_USE_CXX=OFF keeps
# mimalloc from defining C++ operator new/delete, because memory_budget.cpp owns
# those replacement operators and accounts their allocations. MI_OVERRIDE=ON
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

  add_subdirectory("${CMAKE_SOURCE_DIR}/third_party/mimalloc" "${CMAKE_BINARY_DIR}/mimalloc" EXCLUDE_FROM_ALL)
  if(NOT TARGET mimalloc-obj)
    message(FATAL_ERROR "mimalloc did not provide its static object target")
  endif()
  target_sources("${target}" PRIVATE $<TARGET_OBJECTS:mimalloc-obj>)
endfunction()
