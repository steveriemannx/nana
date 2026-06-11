/*
 *	Platform Specification for Cocoa/macOS
 *	Nana C++ Library(http://www.nanapro.org)
 *	Copyright(C) 2003-2024 Jinhao(cnjinhao@hotmail.com)
 *
 *	Distributed under the Boost Software License, Version 1.0.
 *
 *	@file: nana/detail/macos/platform_spec.hpp
 *
 *	This file provides the Cocoa backend platform specification for macOS.
 *	Uses forward declarations instead of X11 headers to avoid conflicts
 *	with Cocoa frameworks.
 */

#if defined(NANA_POSIX) && defined(NANA_MACOS)

#ifndef NANA_DETAIL_COCOA_PLATFORM_SPEC_HPP
#define NANA_DETAIL_COCOA_PLATFORM_SPEC_HPP

#include <nana/push_ignore_diagnostic>

// Forward-declare X11-compatible types (no X11 headers needed)
typedef struct _XDisplay Display;
typedef unsigned long XID;
typedef XID Window;
typedef XID Pixmap;
typedef XID Cursor;
typedef XID Colormap;
typedef struct _XIC *XIC;
typedef struct _XIM *XIM;
typedef struct _XGC* GC;

#include <atomic>
#include <thread>
#include <mutex>
#include <memory>
#include <condition_variable>
#include <nana/gui/basis.hpp>
#include <nana/paint/image.hpp>
#include <nana/paint/graphics.hpp>
#include <nana/gui/detail/event_code.hpp>

#include <vector>
#include <map>
#include <functional>
#include "../posix/msg_packet.hpp"
#include "../platform_abstraction_types.hpp"

namespace nana
{
namespace detail
{
	class msg_dispatcher;

	struct drawable_impl_type
	{
		using font_type = ::std::shared_ptr<font_interface>;

		void*	pixmap{nullptr};
		void*	context{nullptr};

		font_type font;
		nana::point	line_begin_pos;

		struct string_spec {
			unsigned tab_length{4};
			unsigned tab_pixels{0};
			unsigned whitespace_pixels{0};
		} string;

		unsigned fgcolor_rgb{ 0xFFFFFFFF };
		unsigned bgcolor_rgb{ 0xFFFFFFFF };

		drawable_impl_type();
		~drawable_impl_type();
		void set_color(const ::nana::color&);
		void set_text_color(const ::nana::color&);
		void update_color();
		void update_text_color();
	private:
		drawable_impl_type(const drawable_impl_type&) = delete;
		drawable_impl_type& operator=(const drawable_impl_type&) = delete;
		unsigned current_color_{ 0xFFFFFF };
	};

	struct atombase_tag
	{
		unsigned long wm_protocols, wm_change_state, wm_delete_window;
		unsigned long net_frame_extents, net_wm_state, net_wm_state_skip_taskbar;
		unsigned long net_wm_state_fullscreen, net_wm_state_maximized_horz, net_wm_state_maximized_vert;
		unsigned long net_wm_state_modal, net_wm_name, net_wm_window_type;
		unsigned long net_wm_window_type_normal, net_wm_window_type_utility, net_wm_window_type_dialog;
		unsigned long motif_wm_hints;
		unsigned long clipboard, text, text_uri_list, utf8_string, targets;
		unsigned long xdnd_aware, xdnd_enter, xdnd_position, xdnd_status;
		unsigned long xdnd_action_copy, xdnd_action_move, xdnd_action_link;
		unsigned long xdnd_drop, xdnd_selection, xdnd_typelist, xdnd_leave, xdnd_finished;
	};

	struct caret_rep;
	class timer_core;
	class timer_runner;

	class platform_scope_guard { public: platform_scope_guard(); ~platform_scope_guard(); };

	class cocoa_dragdrop_interface {
	public: virtual ~cocoa_dragdrop_interface() = default;
		virtual void add_ref() = 0;
		virtual std::size_t release() = 0;
	};

	class platform_spec
	{
		typedef platform_spec self_type;
		struct window_context_t { native_window_type owner; std::vector<native_window_type>* owned; };
	public:
		int error_code{0};
		typedef void (*timer_proc_type)(thread_t tid);
		typedef void (*event_proc_type)(void*, msg_packet_tag&);
		typedef ::nana::event_code event_code;
		typedef ::nana::native_window_type native_window_type;

		platform_spec(const platform_spec&) = delete;
		platform_spec& operator=(const platform_spec&) = delete;
		platform_spec();
		~platform_spec();

		Display* open_display();
		void close_display();
		void lock_xlib();
		void unlock_xlib();

		unsigned long root_window();
		int screen_depth();
		unsigned long screen_colormap();

		static self_type& instance();
		const atombase_tag& atombase() const;

		void make_owner(native_window_type owner, native_window_type wd);
		bool umake_owner(native_window_type child);
		native_window_type get_owner(native_window_type) const;
		void remove(native_window_type);

		void write_keystate(const void* nsEvent);
		void read_keystate(void* nsEvent);

		void* caret_input_context(native_window_type) const;
		void caret_open(native_window_type, const ::nana::size&);
		void caret_close(native_window_type);
		void caret_pos(native_window_type, const ::nana::point&);
		void caret_visible(native_window_type, bool);
		bool caret_update(native_window_type, nana::paint::graphics&, bool);
		void set_error_handler();
		int rev_error_handler();

		unsigned long grab(unsigned long);
		void set_timer(const timer_core*, std::size_t interval, void (*)(const timer_core*));
		void kill_timer(const timer_core*);
		void timer_proc(thread_t tid);

		void msg_insert(native_window_type);
		void msg_set(timer_proc_type, event_proc_type);
		void msg_dispatch(native_window_type modal);
		void msg_dispatch(std::function<propagation_chain(const msg_packet_tag&)>);

		void* request_selection(native_window_type, unsigned long, size_t&);
		void write_selection(native_window_type, unsigned long, const void*, size_t);

		const nana::paint::graphics& keep_window_icon(native_window_type, const nana::paint::image&);

		bool register_dragdrop(native_window_type, cocoa_dragdrop_interface*);
		std::size_t dragdrop_target(native_window_type, bool, std::size_t);
		cocoa_dragdrop_interface* remove_dragdrop(native_window_type);
	private:
		void _m_caret_routine();

		Display* display_{nullptr};
		unsigned long colormap_{0};
		atombase_tag atombase_{};
		void* key_state_{nullptr};
		unsigned long grab_{0};
		std::recursive_mutex xlib_locker_;

		struct caret_holder_tag {
			std::atomic<bool> exit_thread{false};
			std::unique_ptr<std::thread> thr;
			std::map<native_window_type, caret_rep*> carets;
		} caret_holder_;

		std::map<native_window_type, window_context_t> wincontext_;
		std::map<native_window_type, nana::paint::graphics> iconbase_;

		struct timer_runner_tag {
			timer_runner* runner{nullptr};
			std::recursive_mutex mutex;
			bool delete_declared{false};
			timer_runner_tag();
		} timer_;

		struct selection_tag {
			struct item_t {
				unsigned long type; unsigned long requestor;
				void* buffer; size_t bufsize;
				std::mutex cond_mutex; std::condition_variable cond;
			};
			std::vector<item_t*> items;
			struct content_tag { std::string* utf8_string{nullptr}; } content;
		} selection_;

		struct xdnd_tag {
			unsigned long good_type{0}; int timestamp{0}; unsigned long wd_src{0};
			nana::point pos;
			std::map<native_window_type, cocoa_dragdrop_interface*> dragdrop;
			std::map<native_window_type, std::size_t> targets;
		} xdnd_;

		msg_dispatcher* msg_dispatcher_{nullptr};
	};

}//end namespace detail
}//end namespace nana

#include <nana/pop_ignore_diagnostic>
#endif
#endif
