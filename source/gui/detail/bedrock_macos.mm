/*
 *	A Bedrock Implementation for Cocoa/macOS
 *	Nana C++ Library(http://www.nanapro.org)
 *	Copyright(C) 2003-2024 Jinhao(cnjinhao@hotmail.com)
 *
 *	Distributed under the Boost Software License, Version 1.0.
 *	@file: nana/gui/detail/bedrock_cocoa.mm
 */

#include "../../detail/platform_spec_selector.hpp"
#if defined(NANA_POSIX) && defined(NANA_MACOS)
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
	void window_proc_dispatcher(void*, nana::detail::msg_packet_tag&);
	void window_proc_for_packet(void*, nana::detail::msg_packet_tag&);

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

	// Drives nana's hover state for the widget under the cursor. This mirrors the
	// Windows model: leave the previously hovered widget, then enter the new one,
	// and let the caller emit mouse_move afterwards. Without it the hover
	// highlight sticks, because mouse_leave is never produced.
	bool cocoa_mouse_hover(native_window_type root_native, basic_window* wd, const nana::point& pos)
	{
		static auto& brock = bedrock::instance();
		auto* misc = brock.wd_manager().root_runtime(root_native);
		if (!misc)
			return false;

		if (!brock.wd_manager().available(misc->condition.hovered))
			misc->condition.hovered = nullptr;

		if (misc->condition.hovered == wd)
			return false;

		brock.event_msleave(misc->condition.hovered);
		misc->condition.hovered = nullptr;

		if (!wd)
			return true;

		// Windows does not gate mouse_enter on flags.enabled (unlike
		// event_msleave). Keep that asymmetry so hover behaves identically.
		if (mouse_action::pressed != wd->flags.action)
			wd->set_action(mouse_action::hovered);

		arg_mouse arg;
		arg.evt_code = event_code::mouse_enter;
		arg.window_handle = wd;
		arg.pos.x = pos.x - wd->pos_root.x;
		arg.pos.y = pos.y - wd->pos_root.y;
		arg.left_button = arg.right_button = arg.mid_button = false;
		NSUInteger fl = [NSEvent modifierFlags];
		arg.alt = (fl & NSEventModifierFlagOption) != 0;
		arg.ctrl = (fl & NSEventModifierFlagControl) != 0;
		arg.shift = (fl & NSEventModifierFlagShift) != 0;
		brock.emit(event_code::mouse_enter, wd, arg, true, brock.get_thread_context(wd->thread_id));

		misc->condition.hovered = wd;
		return true;
	}

	void cocoa_mouse_leave(native_window_type root_native)
	{
		static auto& brock = bedrock::instance();
		auto* misc = brock.wd_manager().root_runtime(root_native);
		if (!misc)
			return;
		brock.event_msleave(misc->condition.hovered);
		misc->condition.hovered = nullptr;
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

	// Map a macOS virtual key code to a nana keyboard code. Nana's keyboard::os_*
	// constants are the Windows VK codes, so function keys use VK_F1.. (0x70..)
	// to stay consistent with what bedrock_windows.cpp passes through.
	wchar_t cocoa_key_from_keycode(unsigned short keyCode)
	{
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
		// Arrow keys. 0x7A-0x7E are kVK_F1.., not arrows.
		case 0x7B: return keyboard::os_arrow_left;
		case 0x7C: return keyboard::os_arrow_right;
		case 0x7D: return keyboard::os_arrow_down;
		case 0x7E: return keyboard::os_arrow_up;
		// Navigation cluster
		case 0x72: return keyboard::os_insert;   // Help
		case 0x73: return keyboard::os_home;
		case 0x74: return keyboard::os_pageup;
		case 0x75: return keyboard::del;         // forward delete
		case 0x77: return keyboard::os_end;
		case 0x79: return keyboard::os_pagedown;
		// Function keys (VK_F1 == 0x70)
		case 0x7A: return 0x70;  // F1
		case 0x78: return 0x71;  // F2
		case 0x63: return 0x72;  // F3
		case 0x76: return 0x73;  // F4
		case 0x60: return 0x74;  // F5
		case 0x61: return 0x75;  // F6
		case 0x62: return 0x76;  // F7
		case 0x64: return 0x77;  // F8
		case 0x65: return 0x78;  // F9
		case 0x6D: return 0x79;  // F10
		case 0x67: return 0x7A;  // F11
		case 0x6F: return 0x7B;  // F12
		default:   return '\0';
		}
	}

	// Decode the NSFunctionKeyRange characters (0xF700-0xF747) that AppKit puts
	// in an NSEvent's characters for keys that produce no text. This is an
	// independent cross-check of cocoa_key_from_keycode above.
	wchar_t cocoa_key_from_function_char(const char* utf8, std::size_t len)
	{
		if (!utf8 || len == 0) return '\0';
		std::wstring w = nana::to_wstring(std::string(utf8, utf8 + len));
		if (w.empty()) return '\0';
		switch (w[0])
		{
		case NSF1FunctionKey:            return 0x70;
		case NSF2FunctionKey:            return 0x71;
		case NSF3FunctionKey:            return 0x72;
		case NSF4FunctionKey:            return 0x73;
		case NSF5FunctionKey:            return 0x74;
		case NSF6FunctionKey:            return 0x75;
		case NSF7FunctionKey:            return 0x76;
		case NSF8FunctionKey:            return 0x77;
		case NSF9FunctionKey:            return 0x78;
		case NSF10FunctionKey:           return 0x79;
		case NSF11FunctionKey:           return 0x7A;
		case NSF12FunctionKey:           return 0x7B;
		case NSInsertFunctionKey:        return keyboard::os_insert;
		case NSDeleteFunctionKey:        return keyboard::del;
		case NSHomeFunctionKey:          return keyboard::os_home;
		case NSEndFunctionKey:           return keyboard::os_end;
		case NSPageUpFunctionKey:        return keyboard::os_pageup;
		case NSPageDownFunctionKey:      return keyboard::os_pagedown;
		case NSUpArrowFunctionKey:       return keyboard::os_arrow_up;
		case NSDownArrowFunctionKey:     return keyboard::os_arrow_down;
		case NSLeftArrowFunctionKey:     return keyboard::os_arrow_left;
		case NSRightArrowFunctionKey:    return keyboard::os_arrow_right;
		default:                         return '\0';
		}
	}

	bool translate_keyboard_accelerator(root_misc* misc, char os_code, const arg_keyboard& modifiers)
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

	// Satisfy a registered keyboard accelerator (API::register_accel_key /
	// form::keyboard_accelerator) from an NSEvent. Windows uses Ctrl as the
	// accelerator modifier; the macOS convention is Command, so a Cmd+<key>
	// press also matches accelerators registered with ctrl == true.
	bool cocoa_translate_accel(native_window_type root_native, const void* nsevent)
	{
		NSEvent* e = (__bridge NSEvent*)nsevent;
		NSString* s = [e charactersIgnoringModifiers];
		if (!s || [s length] != 1)
			return false;

		static auto& brock = bedrock::instance();
		auto* misc = brock.wd_manager().root_runtime(root_native);
		if (!misc || !misc->wpassoc)
			return false;

		char key = (char)[s characterAtIndex:0];
		NSUInteger fl = [e modifierFlags];
		bool cmd = (fl & NSEventModifierFlagCommand) != 0;

		arg_keyboard mods;
		mods.alt   = (fl & NSEventModifierFlagOption)  != 0;
		mods.ctrl  = (fl & NSEventModifierFlagControl) != 0;
		mods.shift = (fl & NSEventModifierFlagShift)   != 0;

		if (translate_keyboard_accelerator(misc, key, mods))
			return true;

		if (cmd && !mods.ctrl && !mods.alt)
		{
			mods.ctrl = true;
			return translate_keyboard_accelerator(misc, key, mods);
		}
		return false;
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

		// Nothing else ever sets this, so alt-shortkeys (&label) could not fire.
		context.is_alt_pressed = modifiers_status.alt;

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

		// Manual event loop — processes NSEvents and internal messages
		while (context->window_count > 0) {
			@autoreleasepool {
				// Bounded wait. The run loop still services its own sources
				// (NSTimers, dispatch_async on the main queue) while waiting,
				// but we must return periodically so nana's timers can run.
				NSEvent* ev = [NSApp nextEventMatchingMask:NSEventMaskAny
					untilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]
					inMode:NSDefaultRunLoopMode dequeue:YES];
				if (ev) [NSApp sendEvent:ev];
			}

			// bedrock_posix reaches this through msg_dispatcher::dispatch():
			// queue empty -> _m_wait_for_queue() times out -> proc_.timer_proc(tid).
			// There is no such queue here, so call the same entry point directly.
			// Without this nana::timer (and animation/tooltip timeouts) never fire.
			timer_proc(::nana::system::this_thread_id());
		}

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
#endif // NANA_POSIX && NANA_MACOS
