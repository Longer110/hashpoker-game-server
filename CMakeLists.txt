cmake_minimum_required(VERSION 3.16)
project(cservice CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(RUNTIME_DIR    ${CMAKE_SOURCE_DIR}/libs/runtime)
set(LUAJIT_RUNTIME ${RUNTIME_DIR})
set(REDIS_RUNTIME  ${RUNTIME_DIR})

option(ENABLE_REDIS_TLS "Enable Redis TLS (hiredis_ssl/OpenSSL)" ON)

file(GLOB_RECURSE CSERVICE_SOURCES CONFIGURE_DEPENDS
        "${CMAKE_SOURCE_DIR}/src/*.cpp")
file(GLOB_RECURSE CSERVICE_HEADERS CONFIGURE_DEPENDS
        "${CMAKE_SOURCE_DIR}/src/*.h" "${CMAKE_SOURCE_DIR}/src/*.hpp")

add_executable(cservice
        ${CSERVICE_SOURCES}
        ${CSERVICE_HEADERS}
        src/modules/kafka.hpp
)

target_include_directories(cservice PRIVATE
        ${CMAKE_SOURCE_DIR}/src
        ${CMAKE_SOURCE_DIR}/src/modules
        ${RUNTIME_DIR}/include
)

# ------- Boost -------
set(Boost_NO_BOOST_CMAKE ON)
if(POLICY CMP0167)
  cmake_policy(SET CMP0167 OLD)
endif()
if(APPLE)
  if(EXISTS "/opt/homebrew/opt/boost@1.85/include/boost")
    set(BOOST_ROOT /opt/homebrew/opt/boost@1.85)
    list(APPEND CMAKE_PREFIX_PATH "/opt/homebrew" "/opt/homebrew/opt/boost@1.85")
  elseif(EXISTS "/opt/homebrew/include/boost")
    set(BOOST_ROOT /opt/homebrew/opt/boost)
    list(APPEND CMAKE_PREFIX_PATH "/opt/homebrew" "/opt/homebrew/opt/boost")
  endif()
  set(CMAKE_OSX_ARCHITECTURES "arm64")
endif()
find_package(Boost 1.70 REQUIRED COMPONENTS system)

# ------- Threads -------
find_package(Threads REQUIRED)

# ------- MySQL client -------
set(MYSQLCLIENT_ROOT "" CACHE PATH "Root of mysql-client installation")
if(APPLE AND NOT MYSQLCLIENT_ROOT)
  execute_process(COMMAND brew --prefix mysql-client
          OUTPUT_VARIABLE HOMEBREW_MYSQL_PREFIX
          OUTPUT_STRIP_TRAILING_WHITESPACE
          ERROR_QUIET)
  if(HOMEBREW_MYSQL_PREFIX)
    set(MYSQLCLIENT_ROOT "${HOMEBREW_MYSQL_PREFIX}")
  endif()
endif()

set(_MYSQL_HINT_INCLUDES "")
set(_MYSQL_HINT_LIBS "")
if(MYSQLCLIENT_ROOT)
  list(APPEND _MYSQL_HINT_INCLUDES
          "${MYSQLCLIENT_ROOT}/include"
          "${MYSQLCLIENT_ROOT}/include/mysql")
  list(APPEND _MYSQL_HINT_LIBS
          "${MYSQLCLIENT_ROOT}/lib")
endif()
list(APPEND _MYSQL_HINT_INCLUDES
        /opt/homebrew/opt/mysql-client/include
        /opt/homebrew/opt/mysql-client/include/mysql
        /usr/local/opt/mysql-client/include
        /usr/local/opt/mysql-client/include/mysql)
list(APPEND _MYSQL_HINT_LIBS
        /opt/homebrew/opt/mysql-client/lib
        /usr/local/opt/mysql-client/lib)

find_path(MYSQL_INCLUDE_DIR NAMES mysql/mysql.h HINTS ${_MYSQL_HINT_INCLUDES} PATH_SUFFIXES mysql)
find_library(MYSQL_LIBRARY   NAMES mysqlclient   HINTS ${_MYSQL_HINT_LIBS})
if(NOT MYSQL_INCLUDE_DIR OR NOT MYSQL_LIBRARY)
  message(FATAL_ERROR
          "未找到 MySQL 头文件或库。\n"
          "请安装/指明 mysql-client。\n"
          "macOS:  brew install mysql-client 并使用 -DMYSQLCLIENT_ROOT=/opt/homebrew/opt/mysql-client\n"
          "尝试包含路径: ${_MYSQL_HINT_INCLUDES}\n"
          "尝试库路径:   ${_MYSQL_HINT_LIBS}\n")
endif()

find_package(OpenSSL QUIET)

add_library(MySQL::Client INTERFACE IMPORTED)
set_target_properties(MySQL::Client PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${MYSQL_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES
        "$<IF:$<BOOL:${OpenSSL_FOUND}>,${MYSQL_LIBRARY};OpenSSL::SSL;OpenSSL::Crypto,${MYSQL_LIBRARY}>"
)

# hiredis
find_library(HIREDIS_LIB NAMES hiredis HINTS "${REDIS_RUNTIME}/lib")
if(NOT HIREDIS_LIB)
  message(FATAL_ERROR "未找到 hiredis 库，请确认 ${REDIS_RUNTIME}/lib 下有 libhiredis.*")
endif()
add_library(hiredis::hiredis UNKNOWN IMPORTED)
set_target_properties(hiredis::hiredis PROPERTIES
        IMPORTED_LOCATION "${HIREDIS_LIB}"
        INTERFACE_INCLUDE_DIRECTORIES "${REDIS_RUNTIME}/include"
)

if(ENABLE_REDIS_TLS)
  find_library(HIREDIS_SSL_LIB NAMES hiredis_ssl HINTS "${REDIS_RUNTIME}/lib")
  if(NOT HIREDIS_SSL_LIB)
    message(FATAL_ERROR "ENABLE_REDIS_TLS=ON，但未找到 hiredis_ssl。请确认 libs/runtime/lib 下有 libhiredis_ssl.*")
  endif()
  if(NOT OpenSSL_FOUND)
    message(FATAL_ERROR "ENABLE_REDIS_TLS=ON，但未找到 OpenSSL（ssl/crypto）。")
  endif()
  add_library(hiredis::hiredis_ssl UNKNOWN IMPORTED)
  set_target_properties(hiredis::hiredis_ssl PROPERTIES
          IMPORTED_LOCATION "${HIREDIS_SSL_LIB}"
          INTERFACE_INCLUDE_DIRECTORIES "${REDIS_RUNTIME}/include"
  )
endif()

if(TARGET Boost::headers)
  target_link_libraries(cservice PRIVATE Boost::headers)
elseif(TARGET Boost::boost)
  target_link_libraries(cservice PRIVATE Boost::boost)
elseif(DEFINED Boost_INCLUDE_DIRS)
  target_include_directories(cservice PRIVATE ${Boost_INCLUDE_DIRS})
endif()

target_link_libraries(cservice
        PRIVATE
        ${LUAJIT_RUNTIME}/lib/libluajit-5.1.a
        hiredis::hiredis
        Boost::system
        Threads::Threads
        MySQL::Client
)

if(ENABLE_REDIS_TLS)
  target_link_libraries(cservice PRIVATE
          hiredis::hiredis_ssl
          OpenSSL::SSL
          OpenSSL::Crypto
  )
endif()

list(APPEND CSERVICE_SOURCES
        ${CMAKE_SOURCE_DIR}/src/modules/kafka_lua.cpp)

add_library(RDKAFKA::rdkafka SHARED IMPORTED)
set_target_properties(RDKAFKA::rdkafka PROPERTIES
        IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/libs/runtime/lib/librdkafka.so"
        INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SOURCE_DIR}/libs/runtime/include"
)


target_link_libraries(cservice PRIVATE RDKAFKA::rdkafka)

if(UNIX AND NOT APPLE)
  target_link_libraries(cservice PRIVATE dl m)
  target_link_options(cservice PRIVATE -rdynamic)
endif()

if(APPLE)
  set(_RPATH "@executable_path/libs/runtime/lib")
else()
  set(_RPATH "\$ORIGIN/libs/runtime/lib")
endif()

set_target_properties(cservice PROPERTIES
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "${_RPATH}"
)