########### OS

if(WIN32)
    target_compile_definitions(nana PUBLIC WIN32)
    set(CMAKE_DEBUG_POSTFIX "_d")
    if(MSVC)
        option(MSVC_USE_MP "Set to ON to build nana with the /MP option" ON)
        option(MSVC_USE_STATIC_RUNTIME "Set to ON to build nana with the /MT(d) option." ON)
        if(MSVC_USE_MP)
            target_compile_options(nana PUBLIC "/MP")
        endif()
        if(MSVC_USE_STATIC_RUNTIME)
            foreach(flag CMAKE_C_FLAGS CMAKE_C_FLAGS_DEBUG CMAKE_C_FLAGS_RELEASE
                    CMAKE_C_FLAGS_MINSIZEREL CMAKE_C_FLAGS_RELWITHDEBINFO
                    CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE
                    CMAKE_CXX_FLAGS_MINSIZEREL CMAKE_CXX_FLAGS_RELWITHDEBINFO)
                if(${flag} MATCHES "/MD")
                    string(REGEX REPLACE "/MD" "/MT" ${flag} "${${flag}}")
                endif()
            endforeach()
        endif()
    endif()
    if(MINGW)
        if(NANA_CMAKE_ENABLE_MINGW_STD_THREADS_WITH_MEGANZ)
            target_compile_definitions(nana PUBLIC STD_THREAD_NOT_SUPPORTED
                                            PUBLIC NANA_ENABLE_MINGW_STD_THREADS_WITH_MEGANZ)
        endif()
    endif()
endif()

if(APPLE)
    target_compile_definitions(nana PUBLIC APPLE)
    # Link both X11 (for compilation compatibility) and Cocoa (for runtime backend)
    target_include_directories(nana PUBLIC /opt/X11/include/)
    target_link_libraries(nana PRIVATE iconv)
    target_link_libraries(nana PRIVATE
        "-framework Cocoa"
        "-framework CoreGraphics"
        "-framework CoreText"
        "-framework ApplicationServices"
    )
    set(ENABLE_AUDIO OFF)
endif()

if(UNIX)
    find_package(X11 REQUIRED)
    target_link_libraries(nana
            PUBLIC ${X11_LIBRARIES}
            PUBLIC ${X11_Xft_LIB}
            )
    target_include_directories(nana SYSTEM
            PUBLIC ${X11_Xft_INCLUDE_PATH}
            PUBLIC ${X11_INCLUDE_DIR}
            )
    find_package(Freetype)
    if (FREETYPE_FOUND)
        find_package(Fontconfig REQUIRED)
        target_include_directories(nana SYSTEM
                PUBLIC ${FREETYPE_INCLUDE_DIRS}
                PUBLIC ${FONTCONFIG_INCLUDE_DIR}
                )
        target_link_libraries(nana
                PUBLIC ${FREETYPE_LIBRARIES}
                PUBLIC ${FONTCONFIG_LIBRARIES}
                )
    endif(FREETYPE_FOUND)
endif(UNIX)

# Cocoa backend: exclude X11-specific source files, include Cocoa stubs
if(APPLE)
    set(NANA_EXCLUDE_SOURCES
        "${NANA_SOURCE_DIR}/paint/graphics.cpp"
        "${NANA_SOURCE_DIR}/paint/detail/native_paint_interface.cpp"
        "${NANA_SOURCE_DIR}/gui/detail/native_window_interface.cpp"
        "${NANA_SOURCE_DIR}/paint/detail/native_paint_interface.cpp"
        "${NANA_SOURCE_DIR}/paint/graphics.cpp"
    )
    foreach(excl ${NANA_EXCLUDE_SOURCES})
        list(REMOVE_ITEM SOURCES ${excl})
    endforeach()
    # Add Cocoa-specific sources
    target_sources(nana PRIVATE
        "${NANA_SOURCE_DIR}/paint/graphics_cocoa.mm"
        "${NANA_SOURCE_DIR}/paint/detail/native_paint_interface_cocoa.mm"
        "${NANA_SOURCE_DIR}/gui/detail/native_window_interface_cocoa.mm"
    )
endif()
