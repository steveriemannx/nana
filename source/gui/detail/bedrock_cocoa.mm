/*
 *	A Bedrock Implementation for Cocoa/macOS
 *	Nana C++ Library(http://www.nanapro.org)
 *	Copyright(C) 2003-2024 Jinhao(cnjinhao@hotmail.com)
 *
 *	Distributed under the Boost Software License, Version 1.0.
 *	@file: nana/gui/detail/bedrock_cocoa.mm
 */

#include "../../detail/platform_spec_selector.hpp"
#if defined(NANA_POSIX) && defined(NANA_COCOA)
#include <nana/gui/detail/event_code.hpp>
#include <nana/system/platform.hpp>
#include <nana/gui/detail/native_window_interface.hpp>
#include <nana/gui/layout_utility.hpp>
#include <nana/gui/detail/window_layout.hpp>
#include <nana/gui/detail/element_store.hpp>
#include "inner_fwd_implement.hpp"
#include <errno.h>
#include <algorithm>

#import <Cocoa/Cocoa.h>

#include "bedrock_types.hpp"

namespace nana
{
namespace detail
{
	// Forward declarations of functions in native_window_interface.cpp (Cocoa section)
	void cocoa_apply_exposed_position(native_window_type wd);

	struct bedrock::private_impl
	{
		typedef std::map<unsigned, thread_context> thr_context_container;
		std::recursive_mutex mutex;
		thr_context_container thr_contexts;

		element_store estore;

		struct cache_type
		{
			struct thread_context_cache
			{
				thread_t tid{ 0 };
				thread_context *object{ nullptr };
			} tcontext;
		} cache;
	};

	void timer_proc(thread_t);
	void window_proc_dispatcher(Display*, nana::detail::msg_packet_tag&);
	void window_proc_for_packet(void*, nana::detail::msg_packet_tag&);
	void window_proc_for_nsevent(void*, void* /*NSEvent*/, msg_packet_tag&);

	class accel_key_comparer
	{
	public:
		bool operator()(const accel_key& a, const accel_key& b) const
		{
			auto va = a.case_sensitive ? a.key : std::tolower(a.key);
			auto vb = b.case_sensitive ? b.key : std::tolower(b.key);

			if(va < vb) return true;
			else if(va > vb) return false;

			if (a.case_sensitive != b.case_sensitive) return b.case_sensitive;
			if (a.alt != b.alt) return b.alt;
			if (a.ctrl != b.ctrl) return b.ctrl;
			return ((a.shift != b.shift) && b.shift);
		}
	};

	struct accel_key_value
	{
		std::function<void()> command;
	};

	struct window_platform_assoc
	{
		std::map<accel_key, accel_key_value, accel_key_comparer> accel_commands;
	};

	bedrock bedrock::bedrock_object;

	unsigned long event_window(const void* nsevent)
	{
		// Extract window handle from NSEvent
		NSEvent* evt = (__bridge NSEvent*)nsevent;
		NSWindow* win = [evt window];
		return reinterpret_cast<unsigned long>((__bridge void*)win);
	}

	bedrock::bedrock()
		: pi_data_(new pi_data), impl_(new private_impl)
	{
		nana::detail::platform_spec::instance().msg_set(timer_proc, window_proc_dispatcher);
	}

	bedrock::~bedrock()
	{
		delete pi_data_;
		delete impl_;
	}

	void bedrock::flush_surface(basic_window* wd, bool forced, const rectangle* update_area)
	{
		wd->drawer.map(wd, forced, update_area);
	}

	int bedrock::inc_window(thread_t tid)
	{
		private_impl * impl = instance().impl_;
		std::lock_guard<decltype(impl->mutex)> lock(impl->mutex);

		int & cnt = (impl->thr_contexts[tid ? tid : nana::system::this_thread_id()].window_count);
		return (cnt < 0 ? cnt = 1 : ++cnt);
	}

	bedrock::thread_context* bedrock::open_thread_context(thread_t tid)
	{
		if(0 == tid) tid = nana::system::this_thread_id();

		std::lock_guard<decltype(impl_->mutex)> lock(impl_->mutex);
		if(impl_->cache.tcontext.tid == tid)
			return impl_->cache.tcontext.object;

		bedrock::thread_context* context = nullptr;

		private_impl::thr_context_container::iterator i = impl_->thr_contexts.find(tid);
		if(i == impl_->thr_contexts.end())
			context = &(impl_->thr_contexts[tid]);
		else
			context = &(i->second);

		impl_->cache.tcontext.tid = tid;
		impl_->cache.tcontext.object = context;
		return context;
	}

	bedrock::thread_context* bedrock::get_thread_context(thread_t tid)
	{
		if(0 == tid) tid = nana::system::this_thread_id();

		std::lock_guard<decltype(impl_->mutex)> lock(impl_->mutex);
		if(impl_->cache.tcontext.tid == tid)
			return impl_->cache.tcontext.object;

		private_impl::thr_context_container::iterator i = impl_->thr_contexts.find(tid);
		if(i != impl_->thr_contexts.end())
		{
			impl_->cache.tcontext.tid = tid;
			return (impl_->cache.tcontext.object = &(i->second));
		}

		impl_->cache.tcontext.tid = 0;
		return 0;
	}

	void bedrock::remove_thread_context(thread_t tid)
	{
		if(0 == tid) tid = nana::system::this_thread_id();

		std::lock_guard<decltype(impl_->mutex)> lock(impl_->mutex);

		if(impl_->cache.tcontext.tid == tid)
		{
			impl_->cache.tcontext.tid = 0;
			impl_->cache.tcontext.object = nullptr;
		}

		impl_->thr_contexts.erase(tid);
	}

	bedrock& bedrock::instance()
	{
		return bedrock_object;
	}

	void bedrock::get_key_state(arg_keyboard& arg)
	{
		// Use NSEvent modifierFlags for current key state
		NSUInteger flags = [NSEvent modifierFlags];
		arg.alt = (flags & NSEventModifierFlagOption) != 0;
		arg.ctrl = (flags & NSEventModifierFlagControl) != 0;
		arg.shift = (flags & NSEventModifierFlagShift) != 0;
	}

	void bedrock::delete_platform_assoc(window_platform_assoc* passoc)
	{
		delete passoc;
	}

	void bedrock::keyboard_accelerator(native_window_type wd, const accel_key& ackey, const std::function<void()>& fn)
	{
		auto misc = wd_manager().root_runtime(wd);
		if (nullptr == misc)
			return;

		if (!misc->wpassoc)
			misc->wpassoc = new window_platform_assoc;

		misc->wpassoc->accel_commands[ackey].command = fn;
	}

	element_store& bedrock::get_element_store() const
	{
		return impl_->estore;
	}

	void bedrock::map_through_widgets(basic_window*, native_drawable_type)
	{
		// No implementation for Cocoa
	}

	void assign_arg(arg_mouse& arg, basic_window* wd, unsigned msg, const void* nsevent)
	{
		NSEvent* evt = (__bridge NSEvent*)nsevent;
		arg.window_handle = wd;
		arg.button = ::nana::mouse::any_button;

		NSPoint loc = [evt locationInWindow];
		NSUInteger flags = [NSEvent modifierFlags];

		switch([evt type])
		{
		case NSEventTypeLeftMouseDown:
		case NSEventTypeRightMouseDown:
		case NSEventTypeOtherMouseDown:
			arg.evt_code = event_code::mouse_down;
			arg.pos.x = static_cast<int>(loc.x) - wd->pos_root.x;
			arg.pos.y = static_cast<int>(loc.y) - wd->pos_root.y;
			switch([evt buttonNumber])
			{
			case 0: arg.button = ::nana::mouse::left_button; break;
			case 1: arg.button = ::nana::mouse::right_button; break;
			case 2: arg.button = ::nana::mouse::middle_button; break;
			}
			break;
		case NSEventTypeLeftMouseUp:
		case NSEventTypeRightMouseUp:
		case NSEventTypeOtherMouseUp:
			arg.evt_code = event_code::mouse_up;
			arg.pos.x = static_cast<int>(loc.x) - wd->pos_root.x;
			arg.pos.y = static_cast<int>(loc.y) - wd->pos_root.y;
			break;
		case NSEventTypeMouseMoved:
		case NSEventTypeLeftMouseDragged:
		case NSEventTypeRightMouseDragged:
			arg.evt_code = event_code::mouse_move;
			arg.pos.x = static_cast<int>(loc.x) - wd->pos_root.x;
			arg.pos.y = static_cast<int>(loc.y) - wd->pos_root.y;
			break;
		case NSEventTypeMouseEntered:
			arg.evt_code = event_code::mouse_enter;
			arg.pos.x = static_cast<int>(loc.x) - wd->pos_root.x;
			arg.pos.y = static_cast<int>(loc.y) - wd->pos_root.y;
			break;
		default:
			break;
		}

		arg.left_button = ([evt type] == NSEventTypeLeftMouseDown || [evt type] == NSEventTypeLeftMouseDragged);
		arg.right_button = ([evt type] == NSEventTypeRightMouseDown || [evt type] == NSEventTypeRightMouseDragged);
		arg.mid_button = ([evt buttonNumber] == 2);
		arg.alt = ((flags & NSEventModifierFlagOption) != 0);
		arg.shift = ((flags & NSEventModifierFlagShift) != 0);
		arg.ctrl = ((flags & NSEventModifierFlagControl) != 0);
	}

	void assign_arg(arg_focus& arg, basic_window* wd, native_window_type recv, bool getting)
	{
		arg.window_handle = wd;
		arg.receiver = recv;
		arg.getting = getting;
		arg.focus_reason = arg_focus::reason::general;
	}

	void assign_arg(arg_wheel& arg, basic_window* wd, const void* nsevent)
	{
		NSEvent* evt = (__bridge NSEvent*)nsevent;
		arg.evt_code = event_code::mouse_wheel;
		arg.window_handle = wd;

		NSPoint loc = [evt locationInWindow];
		arg.pos.x = static_cast<int>(loc.x) - wd->pos_root.x;
		arg.pos.y = static_cast<int>(loc.y) - wd->pos_root.y;

		arg.upwards = ([evt scrollingDeltaY] > 0);
		arg.left_button = arg.mid_button = arg.right_button = false;
		arg.shift = arg.ctrl = false;
		arg.distance = 120;
		arg.which = arg_wheel::wheel::vertical;
	}

	void timer_proc(thread_t tid)
	{
		nana::detail::platform_spec::instance().timer_proc(tid);
	}

	void window_proc_dispatcher(void* display, nana::detail::msg_packet_tag& msg)
	{
		switch(msg.kind)
		{
		case nana::detail::msg_packet_tag::pkt_family::xevent:
			// Process NSEvent-based message
			break;
		case nana::detail::msg_packet_tag::pkt_family::mouse_drop:
			window_proc_for_packet(display, msg);
			break;
		default: break;
		}
	}

	void window_proc_for_packet(void*, nana::detail::msg_packet_tag& msg)
	{
		static auto& brock = detail::bedrock::instance();
		auto native_window = reinterpret_cast<native_window_type>(msg.u.packet_window);
		auto root_runtime = brock.wd_manager().root_runtime(native_window);

		if(root_runtime)
		{
			auto msgwd = root_runtime->window;

			switch(msg.kind)
			{
			case nana::detail::msg_packet_tag::pkt_family::mouse_drop:
				msgwd = brock.wd_manager().find_window(native_window, {msg.u.mouse_drop.x, msg.u.mouse_drop.y});
				if(msgwd)
				{
					arg_dropfiles arg;
					arg.window_handle = msgwd;
					arg.files.swap(*msg.u.mouse_drop.files);
					delete msg.u.mouse_drop.files;
					arg.pos.x = msg.u.mouse_drop.x - msgwd->pos_root.x;
					arg.pos.y = msg.u.mouse_drop.y - msgwd->pos_root.y;
					msgwd->annex.events_ptr->mouse_dropfiles.emit(arg, msgwd);
					brock.wd_manager().do_lazy_refresh(msgwd, false);
				}
				break;
			default:
				throw std::runtime_error("Nana.GUI.Bedrock: Undefined message packet");
			}
		}
	}

	template<typename Arg>
	void draw_invoker(void(::nana::detail::drawer::*event_ptr)(const Arg&, const bool), basic_window* wd, const Arg& arg, bedrock::thread_context* thrd)
	{
		if(bedrock::instance().wd_manager().available(wd) == false)
			return;
		basic_window * pre_wd;
		if(thrd)
		{
			pre_wd = thrd->event_window;
			thrd->event_window = wd;
		}

		if(wd->other.upd_state == basic_window::update_state::none)
			wd->other.upd_state = basic_window::update_state::lazy;

		(wd->drawer.*event_ptr)(arg, false);
		if(thrd) thrd->event_window = pre_wd;
	}

	static wchar_t os_code_from_keycode(unsigned short keyCode)
	{
		// Map macOS key codes to nana keyboard codes
		switch(keyCode)
		{
		case 0x00: return 'a';
		case 0x01: return 's';
		case 0x02: return 'd';
		case 0x03: return 'f';
		case 0x07: return 'x';
		case 0x08: return 'c';
		case 0x09: return 'v';
		case 0x0B: return 'b';
		case 0x0D: return 'w';
		case 0x0E: return 'e';
		case 0x0F: return 'r';
		case 0x11: return 't';
		case 0x12: return '1';
		case 0x13: return '2';
		case 0x14: return '3';
		case 0x15: return '4';
		case 0x16: return '6';
		case 0x17: return '5';
		case 0x18: return '=';
		case 0x19: return '9';
		case 0x1A: return '7';
		case 0x1B: return '-';
		case 0x1C: return '8';
		case 0x1D: return '0';
		case 0x1E: return ']';
		case 0x1F: return 'o';
		case 0x20: return 'u';
		case 0x21: return '[';
		case 0x22: return 'i';
		case 0x23: return 'p';
		case 0x24: return keyboard::enter;
		case 0x25: return 'l';
		case 0x26: return 'j';
		case 0x27: return '\'';
		case 0x28: return 'k';
		case 0x29: return ';';
		case 0x2A: return '\\';
		case 0x2B: return ',';
		case 0x2C: return '/';
		case 0x2D: return 'n';
		case 0x2E: return 'm';
		case 0x2F: return '.';
		case 0x30: return keyboard::tab;
		case 0x31: return ' ';
		case 0x32: return '`';
		case 0x33: return keyboard::backspace;
		case 0x35: return keyboard::escape;
		case 0x37: return keyboard::os_ctrl;  // left command
		case 0x38: return keyboard::os_shift;
		case 0x39: return keyboard::alt;      // option
		case 0x3A: return keyboard::os_ctrl;  // left control
		case 0x3B: return keyboard::os_ctrl;  // right command
		case 0x3C: return keyboard::os_shift; // right shift
		case 0x3D: return keyboard::alt;      // right option
		case 0x3E: return keyboard::os_ctrl;  // right control
		case 0x7A: return keyboard::os_arrow_left;   // F1 = left (mapped)
		case 0x7B: return keyboard::os_arrow_right;  // F2 = right
		case 0x7D: return keyboard::os_arrow_down;   // F3 = down
		case 0x7E: return keyboard::os_arrow_up;     // F4 = up
		case 0x72: return keyboard::os_insert;
		case 0x73: return keyboard::os_pageup;  // home
		case 0x74: return keyboard::os_pagedown; // page up
		case 0x75: return keyboard::del;
		case 0x77: return keyboard::os_pagedown; // end
		case 0x79: return keyboard::os_pageup;   // page down
		case 0x7F: return keyboard::os_pagedown; // page down
		default:   return '\0';
		}
	}

	static bool translate_keyboard_accelerator(root_misc* misc, char os_code, const arg_keyboard& modifiers)
	{
		if(!misc->wpassoc)
			return false;

		auto lower_oc = std::tolower(os_code);
		std::function<void()> command;

		for(auto & accel : misc->wpassoc->accel_commands)
		{
			if(accel.first.key != (accel.first.case_sensitive ? os_code : lower_oc))
				continue;

			if(accel.first.alt == modifiers.alt && accel.first.ctrl == modifiers.ctrl && accel.first.shift == modifiers.shift)
			{
				command = accel.second.command;
				break;
			}
		}

		if(!command)
			return false;

		command();
		return true;
	}

	void cocoa_lookup_chars(const root_misc* rruntime, basic_window * msgwd, const char* keybuf, std::size_t keybuf_len, const arg_keyboard& modifiers_status)
	{
		if (!msgwd->flags.enabled)
			return;

		static auto& brock = detail::bedrock::instance();
		auto & wd_manager = brock.wd_manager();
		auto& context = *brock.get_thread_context(msgwd->thread_id);
		auto const native_window = rruntime->window->root;

		auto wstr = nana::to_wstring(std::string{keybuf, keybuf + keybuf_len});
		auto const charbuf = wstr.c_str();
		auto const len = wstr.length();

		for(std::size_t i = 0; i < len; ++i)
		{
			arg_keyboard arg = modifiers_status;
			arg.ignore = false;
			arg.key = charbuf[i];

			if (arg.key == 0xFEFF) continue;

			if ((keyboard::tab == arg.key) && rruntime->condition.ignore_tab)
				continue;

			if(context.is_alt_pressed)
			{
				arg.ctrl = arg.shift = false;
				arg.evt_code = event_code::shortkey;
				brock.shortkey_occurred(true);
				auto shr_wd = wd_manager.find_shortkey(native_window, arg.key);
				if(shr_wd)
				{
					arg.window_handle = shr_wd;
					brock.emit(event_code::shortkey, shr_wd, arg, true, &context);
				}
				continue;
			}

			arg.evt_code = event_code::key_char;
			arg.window_handle = msgwd;
			msgwd->annex.events_ptr->key_char.emit(arg, msgwd);
			if(arg.ignore == false && wd_manager.available(msgwd))
				draw_invoker(&drawer::key_char, msgwd, arg, &context);
		}

		if(brock.shortkey_occurred(false))
			context.is_alt_pressed = false;
	}

	void bedrock::pump_event(window condition_wd, bool is_modal)
	{
		thread_context * context = open_thread_context();
		if(0 == context->window_count)
		{
			remove_thread_context();
			return;
		}

		++(context->event_pump_ref_count);

		auto & lock = wd_manager().internal_lock();
		lock.revert();

		native_window_type owner_native{};
		basic_window * owner = nullptr;
		if(condition_wd && is_modal)
		{
			native_window_type modal = condition_wd->root;
			owner_native = native_interface::get_window(modal, window_relationship::owner);
			if(owner_native)
			{
				native_interface::enable_window(owner_native, false);
				owner = wd_manager().root(owner_native);
				if(owner)
					owner->flags.enabled = false;
			}
		}

		nana::detail::platform_spec::instance().msg_dispatch(condition_wd ? condition_wd->root : 0);

		if(owner_native)
		{
			if(owner)
				owner->flags.enabled = true;
			native_interface::enable_window(owner_native, true);
		}

		auto thread_id = ::nana::system::this_thread_id();
		wd_manager().call_safe_place(thread_id);
		wd_manager().remove_trash_handle(thread_id);

		lock.forward();

		if(0 == --(context->event_pump_ref_count))
		{
			if(0 == condition_wd || 0 == context->window_count)
				remove_thread_context();
		}
	}

	void bedrock::set_cursor(basic_window* wd, nana::cursor cur, thread_context* thrd)
	{
		if (nullptr == thrd)
			thrd = get_thread_context(wd->thread_id);

		if ((cursor::arrow == cur) && !thrd->cursor.native_handle)
			return;

		thrd->cursor.window = wd;
		if ((thrd->cursor.native_handle == wd->root) && (cur == thrd->cursor.predef_cursor))
			return;

		thrd->cursor.native_handle = wd->root;
		thrd->cursor.predef_cursor = cur;

		// Map nana cursor to NSCursor
		if (nana::cursor::arrow == cur)
		{
			[[NSCursor arrowCursor] set];
		}
		else if (nana::cursor::hand == cur)
		{
			[[NSCursor pointingHandCursor] set];
		}
		else if (nana::cursor::iterm == cur)
		{
			[[NSCursor IBeamCursor] set];
		}
		// Additional cursor mappings can be added here
	}

	void bedrock::define_state_cursor(basic_window* wd, nana::cursor cur, thread_context* thrd)
	{
		wd->root_widget->other.attribute.root->state_cursor = cur;
		wd->root_widget->other.attribute.root->state_cursor_window = wd;
		set_cursor(wd, cur, thrd);
	}

	void bedrock::undefine_state_cursor(basic_window * wd, thread_context* thrd)
	{
		if (!wd_manager().available(wd))
			return;

		wd->root_widget->other.attribute.root->state_cursor = nana::cursor::arrow;
		wd->root_widget->other.attribute.root->state_cursor_window = nullptr;

		auto pos = native_interface::cursor_position();
		auto native_handle = native_interface::find_window(pos.x, pos.y);
		if (!native_handle)
			return;

		native_interface::calc_window_point(native_handle, pos);
		auto rev_wd = wd_manager().find_window(native_handle, pos);
		if (rev_wd)
			set_cursor(rev_wd, rev_wd->predef_cursor, thrd);
	}
}//end namespace detail
}//end namespace nana
#endif // NANA_POSIX && NANA_COCOA
