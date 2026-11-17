cmake_minimum_required(VERSION 3.28.0)
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(moist_node LANGUAGES C)
target_sources(app PRIVATE src/main.c src/thread_demo.c)

