# Generic riscv-none-elf toolchain file for WCH CH32V / CH32X firmware.
#
# Baked into the image at /opt/embedded/cmake/toolchains/riscv-none-elf.cmake.
# Gives CMake-based WCH projects the same tasks.json / launch.json flow the arm
# leaf has, as an alternative to ch32fun's Makefiles.
#
#   cmake -S . -B build -G Ninja \
#     -DCMAKE_TOOLCHAIN_FILE=/opt/embedded/cmake/toolchains/riscv-none-elf.cmake \
#     -DRISCV_MARCH=rv32ec_zicsr -DRISCV_MABI=ilp32e
#
# Values by part (matching .mcu-profile.json's march/mabi keys):
#
#   Part       Core          RISCV_MARCH         RISCV_MABI
#   CH32V003   QingKe V2A    rv32ec_zicsr        ilp32e     <- 16 registers only
#   CH32V103   QingKe V3     rv32imac_zicsr      ilp32
#   CH32V203   QingKe V4B    rv32imac_zicsr      ilp32
#   CH32V303   QingKe V4F    rv32imafc_zicsr     ilp32f     <- has an FPU
#   CH32X033   QingKe V4C    rv32imac_zicsr      ilp32
#
# RV32EC (the V003) has 16 integer registers instead of 32 and NO hardware
# multiply. `ilp32e` is not ABI-compatible with `ilp32`, so a library built for
# one will not link against the other — this is why march/mabi must be explicit.

# CMake's compiler-ABI check runs in a scratch project that re-includes this file
# but does not inherit -D cache variables; without this it fails with
# "RISCV_MARCH is not set" (seen with CMake 4.4).
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES RISCV_MARCH RISCV_MABI)

set(CMAKE_SYSTEM_NAME      Generic)
set(CMAKE_SYSTEM_PROCESSOR riscv32)

if(NOT DEFINED RISCV_MARCH OR RISCV_MARCH STREQUAL "")
    message(FATAL_ERROR
        "RISCV_MARCH is not set.\n"
        "Pass -DRISCV_MARCH=rv32ec_zicsr (CH32V003) or -DRISCV_MARCH=rv32imac_zicsr "
        "(CH32V203/X033), together with a matching -DRISCV_MABI.\n"
        "Building without -march produces code for the wrong ISA — on RV32EC that "
        "means instructions the core does not implement, which traps at run time.")
endif()

if(NOT DEFINED RISCV_MABI OR RISCV_MABI STREQUAL "")
    message(FATAL_ERROR "RISCV_MABI is not set (ilp32e for RV32EC, ilp32 otherwise).")
endif()

if(RISCV_MARCH MATCHES "rv32e" AND NOT RISCV_MABI STREQUAL "ilp32e")
    message(FATAL_ERROR
        "RISCV_MARCH=${RISCV_MARCH} is an RV32E variant but RISCV_MABI=${RISCV_MABI}. "
        "RV32E has 16 registers and requires ilp32e; mixing them produces a link "
        "error or silently wrong argument passing.")
endif()

set(CMAKE_C_COMPILER   riscv-none-elf-gcc)
set(CMAKE_CXX_COMPILER riscv-none-elf-g++)
set(CMAKE_ASM_COMPILER riscv-none-elf-gcc)
set(CMAKE_AR           riscv-none-elf-ar)
set(CMAKE_RANLIB       riscv-none-elf-ranlib)
set(CMAKE_OBJCOPY      riscv-none-elf-objcopy)
set(CMAKE_OBJDUMP      riscv-none-elf-objdump)
set(CMAKE_SIZE         riscv-none-elf-size)

set(_arch "-march=${RISCV_MARCH} -mabi=${RISCV_MABI} -msmall-data-limit=8 -mno-save-restore")

set(CMAKE_C_FLAGS_INIT          "${_arch}")
set(CMAKE_CXX_FLAGS_INIT        "${_arch}")
set(CMAKE_ASM_FLAGS_INIT        "${_arch} -x assembler-with-cpp")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_arch} -nostartfiles")

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

# ch32fun sources, for projects that want its startup/peripheral layer without
# its Makefile:
#   target_include_directories(firmware PRIVATE ${CH32FUN_DIR})
#   target_sources(firmware PRIVATE ${CH32FUN_DIR}/ch32fun.c)
set(CH32FUN_DIR "$ENV{CH32FUN}/ch32fun" CACHE PATH "ch32fun source directory")
