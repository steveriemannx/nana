/*
 *	Native Window Interface — Cocoa Stubs
 *	Nana C++ Library
 *	Provides minimal stubs for Step 1 compilation
 */
#if defined(NANA_COCOA)
#include "native_window_interface_cocoa.hpp"
#include <nana/gui/detail/native_window_interface.hpp>
#include <nana/gui/screen.hpp>
#include <nana/gui/detail/bedrock.hpp>
#include <nana/gui/detail/window_manager.hpp>

namespace nana { namespace detail {

void native_interface::affinity_execute(native_window_type, const std::function<void()>& fn) { if(fn) fn(); }
nana::size native_interface::primary_monitor_size() { return {1920, 1080}; }
rectangle native_interface::screen_area_from_point(const point&) { return {primary_monitor_size()}; }

native_interface::window_result native_interface::create_window(native_window_type, bool, const rectangle& r, const appearance&) {
    window_result res = {reinterpret_cast<native_window_type>(1), r.width, r.height, 0, 0};
    return res;
}
native_window_type native_interface::create_child_window(native_window_type, const rectangle&) { return nullptr; }
void native_interface::enable_dropfiles(native_window_type, bool) {}
void native_interface::enable_window(native_window_type, bool) {}
bool native_interface::window_icon(native_window_type, const paint::image&, const paint::image&) { return false; }
void native_interface::activate_owner(native_window_type) {}
void native_interface::activate_window(native_window_type) {}
void native_interface::close_window(native_window_type) {}
void native_interface::show_window(native_window_type, bool, bool) {}
void native_interface::restore_window(native_window_type) {}
void native_interface::zoom_window(native_window_type, bool) {}
void native_interface::refresh_window(native_window_type) {}
bool native_interface::is_window(native_window_type) { return true; }
bool native_interface::is_window_visible(native_window_type) { return true; }
bool native_interface::is_window_zoomed(native_window_type, bool) { return false; }
nana::point native_interface::window_position(native_window_type) { return {}; }
void native_interface::move_window(native_window_type, int, int) {}
bool native_interface::move_window(native_window_type, const rectangle&) { return true; }
void native_interface::bring_top(native_window_type, bool) {}
void native_interface::set_window_z_order(native_window_type, native_window_type, z_order_action) {}
native_interface::frame_extents native_interface::window_frame_extents(native_window_type) { return {0,0,0,0}; }
bool native_interface::window_size(native_window_type, const size&) { return true; }
void native_interface::get_window_rect(native_window_type, rectangle& r) { r = {}; }
void native_interface::window_caption(native_window_type, const native_string_type&) {}
auto native_interface::window_caption(native_window_type) -> native_string_type { return {}; }
void native_interface::capture_window(native_window_type, bool) {}
nana::point native_interface::cursor_position() { return {}; }
native_window_type native_interface::get_window(native_window_type, window_relationship) { return nullptr; }
native_window_type native_interface::parent_window(native_window_type child, native_window_type, bool returns_previous) { return returns_previous ? nullptr : child; }
void native_interface::caret_create(native_window_type, const ::nana::size&) {}
void native_interface::caret_destroy(native_window_type) {}
void native_interface::caret_pos(native_window_type, const point&) {}
void native_interface::caret_visible(native_window_type, bool) {}
void native_interface::set_focus(native_window_type) {}
native_window_type native_interface::get_focus_window() { return nullptr; }
bool native_interface::calc_screen_point(native_window_type, nana::point&) { return false; }
bool native_interface::calc_window_point(native_window_type, nana::point&) { return false; }
native_window_type native_interface::find_window(int, int) { return nullptr; }
nana::size native_interface::check_track_size(nana::size sz, unsigned, unsigned, bool) { return sz; }

}} // namespace
#endif
