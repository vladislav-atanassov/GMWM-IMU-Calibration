# Built with nRF Connect SDK v3.2.1:
#     west build -b xiao_ble/nrf52840/sense -d C:/gmwm-build/xiao-nrf52840-sense
cmake_minimum_required(VERSION 3.20.0)

# Object paths run about 165 characters past the build folder, and Windows tools fail above 260
set(BUILD_DIR_MAX_LENGTH 90)
string(LENGTH "${CMAKE_BINARY_DIR}" build_dir_length)
if(CMAKE_HOST_WIN32 AND build_dir_length GREATER BUILD_DIR_MAX_LENGTH)
    message(FATAL_ERROR
        "Build folder path is ${build_dir_length} characters:\n"
        "    ${CMAKE_BINARY_DIR}\n"
        "On Windows it must be ${BUILD_DIR_MAX_LENGTH} or fewer, or object file paths pass the 260-character "
        "limit. Build into a short folder instead:\n"
        "    west build -b xiao_ble/nrf52840/sense -d C:/gmwm-build/xiao-nrf52840-sense")
endif()

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(imu_streamer C)

set(FIRMWARE_COMMON_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../common)

target_include_directories(app PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${FIRMWARE_COMMON_DIR}/stream
)

target_sources(app PRIVATE
    src/main.c
    src/Imu/lsm6ds3trc.c
    src/Stream/stream_port.c
    ${FIRMWARE_COMMON_DIR}/stream/stream_packet.c
)
