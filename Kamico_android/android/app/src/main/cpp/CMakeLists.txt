cmake_minimum_required(VERSION 3.22.1)
project(aicolor LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ONNX Runtime 是预编译的 .so，放在 jniLibs/<abi>/，由 Gradle 直接打包；
# 这里只做链接导入，不参与编译。
# 本文件位于 src/main/cpp，jniLibs 与它是兄弟目录，所以只回退一级。
set(AICOLOR_ORT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")
set(AICOLOR_ORT_LIB "${AICOLOR_ORT_DIR}/libonnxruntime.so")

add_library(onnxruntime SHARED IMPORTED)
set_target_properties(onnxruntime PROPERTIES
  IMPORTED_LOCATION "${AICOLOR_ORT_LIB}")

add_library(aicolor SHARED aicolor.c)

target_include_directories(aicolor PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/onnxruntime")

# 模型只支持 arm64-v8a：其他 ABI 编译成桩，返回「架构不支持」而不是崩溃。
if(ANDROID_ABI STREQUAL "arm64-v8a")
  if(EXISTS "${AICOLOR_ORT_LIB}")
    target_compile_definitions(aicolor PRIVATE AICOLOR_WITH_ORT=1)
    target_link_libraries(aicolor onnxruntime log m)
  else()
    message(WARNING "未找到 ${AICOLOR_ORT_LIB}，AI 上色将编译为桩实现")
    target_link_libraries(aicolor m)
  endif()
else()
  message(STATUS "ABI ${ANDROID_ABI} 不支持 AI 上色，编译桩实现")
  target_link_libraries(aicolor m)
endif()

# 只暴露 aicolor_* 符号，其余静态链接进来的符号不导出。
set_target_properties(aicolor PROPERTIES
  C_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON)
