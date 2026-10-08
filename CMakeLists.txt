cmake_minimum_required(VERSION 3.14)
project(ZebradUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

logos_module(
    NAME zebrad_ui
    REP_FILE src/ZebradBackend.rep
    SOURCES
        src/ZebradBackend.h
        src/ZebradBackend.cpp
    INCLUDE_DIRS
        src
)
