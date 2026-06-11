/*
 *	Platform Specification Implementation for Cocoa/macOS
 *	Nana C++ Library(http://www.nanapro.org)
 *	Copyright(C) 2003-2024 Jinhao(cnjinhao@hotmail.com)
 *
 *	Distributed under the Boost Software License, Version 1.0.
 *	@file: nana/detail/platform_spec_cocoa.mm
 */

// Include Cocoa BEFORE nana headers to avoid thread_t typedef conflict
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

#include "platform_spec_selector.hpp"
#include "platform_abstraction.hpp"
#if defined(NANA_POSIX) && defined(NANA_MACOS)

// Minimal NSApplication delegate for Dock quit (Cmd+Q) support
@interface NanaAppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation NanaAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender { return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender { return NSTerminateNow; }
@end

#include <nana/push_ignore_diagnostic>

#include <clocale>
#include <map>
#include <set>
#include <algorithm>
#include <nana/paint/graphics.hpp>
#include <nana/gui/detail/bedrock.hpp>
#include <nana/gui/detail/window_manager.hpp>
#include <nana/system/platform.hpp>
#include <nana/paint/pixel_buffer.hpp>
#include <errno.h>
#include <sstream>

#include "macos/msg_dispatcher.hpp"
#include "../gui/detail/basic_window.hpp"

namespace nana
{
namespace detail
{
	typedef native_window_type native_window_type;

	// Caret implementation for Cocoa
	struct caret_rep
	{
		native_window_type window;
		bool has_input_method_focus{ false };
		bool visible{ false };
		nana::point pos;
		nana::size	size;
		nana::rectangle rev;
		nana::paint::graphics rev_graph;

		caret_rep(native_window_type wd)
			: window{ wd }
		{}

		bool reinstate()
		{
			if(rev.width && rev.height)
			{
				rev_graph.paste(window, rev, 0, 0);
				rev.width = rev.height = 0;
				return true;
			}
			return false;
		}

		void twinkle()
		{
			if(!visible)
				return;

			if(!reinstate())
			{
				rev_graph.bitblt(rectangle{size}, window, pos);
				rev.width = size.width;
				rev.height = size.height;
				rev.x = pos.x;
				rev.y = pos.y;

				paint::pixel_buffer pxbuf;
				pxbuf.open(rev_graph.handle());

				auto pxsize = pxbuf.size();
				for(int y = 0; y < static_cast<int>(pxsize.height); ++y)
					for(int x = 0; x < static_cast<int>(pxsize.width); ++x)
					{
						auto px = pxbuf.at({x, y});
						px->element.red = ~px->element.red;
						px->element.green = ~px->element.green;
						px->element.blue = ~px->element.blue;
					}
				pxbuf.paste(window, {rev.x, rev.y});
			}
		}
	};

	class timer_runner
	{
		using handler_type = void(*)(const timer_core*);

		struct timer_tag
		{
			const timer_core* handle;
			thread_t	thread_id;
			std::size_t interval;
			std::size_t timestamp;
			handler_type handler;
		};

		struct timer_group
		{
			bool proc_entered{false};
			std::set<const timer_core*> timers;
			std::vector<const timer_core*> delay_deleted;
		};
	public:
		timer_runner()
			: is_proc_handling_(false)
		{}

		void set(const timer_core* handle, std::size_t interval, handler_type handler)
		{
			auto i = holder_.find(handle);
			if(i != holder_.end())
			{
				i->second.interval = interval;
				i->second.handler = handler;
				return;
			}
			auto tid = nana::system::this_thread_id();
			threadmap_[tid].timers.insert(handle);

			timer_tag & tag = holder_[handle];
			tag.handle = handle;
			tag.thread_id = tid;
			tag.interval = interval;
			tag.timestamp = 0;
			tag.handler = handler;
		}

		bool is_proc_handling() const
		{
			return is_proc_handling_;
		}

		bool kill(const timer_core* handle)
		{
			auto i = holder_.find(handle);
			if(i != holder_.end())
			{
				auto tid = i->second.thread_id;
				auto ig = threadmap_.find(tid);
				if(ig != threadmap_.end())
				{
					auto & group = ig->second;
					if(!group.proc_entered)
					{
						group.timers.erase(handle);
						if(group.timers.empty())
							threadmap_.erase(ig);
					}
					else
						group.delay_deleted.push_back(handle);
				}
				holder_.erase(i);
			}
			return holder_.empty();
		}

		void timer_proc(thread_t tid)
		{
			is_proc_handling_ = true;
			auto i = threadmap_.find(tid);
			if(i != threadmap_.end())
			{
				auto & group = i->second;
				group.proc_entered = true;
				unsigned ticks = nana::system::timestamp();
				for(auto timer_id : group.timers)
				{
					auto & tag = holder_[timer_id];
					if(tag.timestamp)
					{
						if(ticks >= tag.timestamp + tag.interval)
						{
							tag.timestamp = ticks;
							try { tag.handler(tag.handle); }catch(...){}
						}
					}
					else
						tag.timestamp = ticks;
				}
				group.proc_entered = false;
				for(auto tmr: group.delay_deleted)
					group.timers.erase(tmr);
			}
			is_proc_handling_ = false;
		}
	private:
		bool is_proc_handling_;
		std::map<thread_t, timer_group> threadmap_;
		std::map<const timer_core*, timer_tag> holder_;
	};

	drawable_impl_type::drawable_impl_type()
	{
		string.tab_length = 4;
		string.tab_pixels = 0;
		string.whitespace_pixels = 0;
	}

	drawable_impl_type::~drawable_impl_type()
	{
		// pixmap and context are the same CGContextRef in Cocoa backend.
		if(pixmap) {
			CGContextRelease(reinterpret_cast<CGContextRef>(pixmap));
			pixmap = nullptr;
			context = nullptr;
		} else if(context) {
			CGContextRelease(reinterpret_cast<CGContextRef>(context));
			context = nullptr;
		}
	}

	void drawable_impl_type::set_color(const ::nana::color& clr)
	{
		bgcolor_rgb = (clr.px_color().value & 0xFFFFFF);
		update_color();
	}

	void drawable_impl_type::set_text_color(const ::nana::color& clr)
	{
		fgcolor_rgb = (clr.px_color().value & 0xFFFFFF);
		update_text_color();
	}

	void drawable_impl_type::update_color()
	{
		if (bgcolor_rgb != current_color_)
		{
			current_color_ = bgcolor_rgb;
			if(context)
			{
				CGFloat r = ((bgcolor_rgb >> 16) & 0xFF) / 255.0;
				CGFloat g = ((bgcolor_rgb >> 8) & 0xFF) / 255.0;
				CGFloat b = (bgcolor_rgb & 0xFF) / 255.0;
				CGContextSetRGBFillColor(reinterpret_cast<CGContextRef>(context), r, g, b, 1.0);
				CGContextSetRGBStrokeColor(reinterpret_cast<CGContextRef>(context), r, g, b, 1.0);
			}
		}
	}

	void drawable_impl_type::update_text_color()
	{
		if (fgcolor_rgb != current_color_)
		{
			current_color_ = fgcolor_rgb;
			if(context)
			{
				CGFloat r = ((fgcolor_rgb >> 16) & 0xFF) / 255.0;
				CGFloat g = ((fgcolor_rgb >> 8) & 0xFF) / 255.0;
				CGFloat b = (fgcolor_rgb & 0xFF) / 255.0;
				CGContextSetRGBFillColor(reinterpret_cast<CGContextRef>(context), r, g, b, 1.0);
				CGContextSetRGBStrokeColor(reinterpret_cast<CGContextRef>(context), r, g, b, 1.0);
			}
		}
	}

	platform_scope_guard::platform_scope_guard()
	{
		platform_spec::instance().lock_xlib();
	}

	platform_scope_guard::~platform_scope_guard()
	{
		platform_spec::instance().unlock_xlib();
	}

	platform_spec::timer_runner_tag::timer_runner_tag()
		: runner(nullptr), delete_declared(false)
	{}

	platform_spec::platform_spec()
		: display_(0), colormap_(0), error_code(0), grab_(0)
	{
		// Initialize Cocoa application if needed
		if ([NSApp isRunning] == NO)
		{
			[NSApplication sharedApplication];
			[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

			// Set up a minimal delegate so Dock quit (Cmd+Q) works
			static NanaAppDelegate* appDel = nil;
			if (!appDel) { appDel = [[NanaAppDelegate alloc] init]; }
			[NSApp setDelegate:appDel];
		}

		const char * langstr = getenv("LC_CTYPE");
		if(0 == langstr)
			langstr = getenv("LC_ALL");

		std::string langstr_dup;
		if(langstr)
		{
			langstr_dup = langstr;
			auto dotpos = langstr_dup.find(".");
			if(dotpos != langstr_dup.npos)
			{
				auto beg = langstr_dup.begin() + dotpos + 1;
				std::transform(beg, langstr_dup.end(), beg, toupper);
			}
		}
		else
			langstr_dup = "en_US.UTF-8";
		std::setlocale(LC_CTYPE, langstr_dup.c_str());

		// Store NSApp as the "display" handle
		display_ = (Display*)this;

		msg_dispatcher_ = new msg_dispatcher(display_);

		platform_abstraction::initialize();
	}

	platform_spec::~platform_spec()
	{
		delete msg_dispatcher_;
		platform_abstraction::shutdown();
		close_display();
	}

	Display* platform_spec::open_display()
	{
		return (Display*)display_;
	}

	void platform_spec::close_display()
	{
		display_ = nullptr;
	}

	void platform_spec::lock_xlib()
	{
		xlib_locker_.lock();
	}

	void platform_spec::unlock_xlib()
	{
		xlib_locker_.unlock();
	}

	unsigned long platform_spec::root_window()
	{
		// Return the main window content view or 0
		NSWindow* mainWin = [NSApp mainWindow];
		if (mainWin)
			return reinterpret_cast<unsigned long>((__bridge void*)mainWin);
		return 0;
	}

	int platform_spec::screen_depth()
	{
		// Cocoa uses 24/32 bit color
		return 24;
	}

	unsigned long platform_spec::screen_colormap()
	{
		return colormap_;
	}

	platform_spec& platform_spec::instance()
	{
		static platform_spec object;
		return object;
	}

	const atombase_tag& platform_spec::atombase() const
	{
		return atombase_;
	}

	void platform_spec::make_owner(native_window_type owner, native_window_type wd)
	{
		platform_scope_guard lock;
		wincontext_[wd].owner = owner;

		auto& owner_ctx = wincontext_[owner];
		if(!owner_ctx.owned)
			owner_ctx.owned = new std::vector<native_window_type>;
		owner_ctx.owned->push_back(wd);
	}

	bool platform_spec::umake_owner(native_window_type child)
	{
		platform_scope_guard lock;

		auto i = wincontext_.find(child);
		if(i == wincontext_.end())
			return false;

		if(i->second.owner)
		{
			auto u = wincontext_.find(i->second.owner);
			if(u != wincontext_.end())
			{
				auto * owned = u->second.owned;
				if(owned)
				{
					auto j = std::find(owned->begin(), owned->end(), child);
					if(j != owned->end())
						owned->erase(j);

					if(owned->empty())
					{
						delete owned;
						u->second.owned = nullptr;
						if(nullptr == u->second.owner)
							wincontext_.erase(u);
					}
				}
			}
			i->second.owner = nullptr;
		}

		if(nullptr == i->second.owned)
			wincontext_.erase(i);

		return true;
	}

	native_window_type platform_spec::get_owner(native_window_type wd) const
	{
		platform_scope_guard psg;
		auto i = wincontext_.find(wd);
		return (i != wincontext_.end() ? i->second.owner : nullptr);
	}

	void platform_spec::remove(native_window_type wd)
	{
		msg_dispatcher_->erase(reinterpret_cast<unsigned long>(wd));

		platform_scope_guard lock;
		if(umake_owner(wd))
		{
			auto & wd_manager = detail::bedrock::instance().wd_manager();

			std::vector<native_window_type> owned_children;
			auto i = wincontext_.find(wd);
			if(i != wincontext_.end())
			{
				if(i->second.owned)
				{
					for(auto child : *i->second.owned)
						owned_children.push_back(child);
				}
			}

			set_error_handler();
			for(auto u = owned_children.rbegin(); u != owned_children.rend(); ++u)
				wd_manager.close(wd_manager.root(*u));
			rev_error_handler();

			i = wincontext_.find(wd);
			if(i != wincontext_.end())
			{
				delete i->second.owned;
				wincontext_.erase(i);
			}
		}
		iconbase_.erase(wd);
	}

	void platform_spec::write_keystate(const void* nsEvent)
	{
		key_state_ = const_cast<void*>(nsEvent);
	}

	void platform_spec::read_keystate(void* nsEvent)
	{
		// Copy key state for keyboard modifier tracking
		nsEvent = key_state_;
	}

	void* platform_spec::caret_input_context(native_window_type wd) const
	{
		platform_scope_guard psg;
		auto i = caret_holder_.carets.find(wd);
		if(i != caret_holder_.carets.end())
			return nullptr; // Cocoa handles IME via NSTextInputContext
		return nullptr;
	}

	void platform_spec::caret_open(native_window_type wd, const ::nana::size& caret_sz)
	{
		bool is_start_routine = false;
		platform_scope_guard psg;
		auto & addr = caret_holder_.carets[wd];
		if(nullptr == addr)
		{
			addr = new caret_rep(wd);
			is_start_routine = (caret_holder_.carets.size() == 1);
		}

		addr->visible = false;
		addr->rev_graph.make(caret_sz);
		addr->size = caret_sz;

		if(is_start_routine)
		{
			caret_holder_.exit_thread = false;
			auto fn = [this](){ this->_m_caret_routine(); };
			caret_holder_.thr.reset(new std::thread(fn));
		}
	}

	void platform_spec::caret_close(native_window_type wd)
	{
		bool is_end_routine = false;
		{
			platform_scope_guard psg;

			auto i = caret_holder_.carets.find(wd);
			if(i != caret_holder_.carets.end())
			{
				auto addr = i->second;
				delete i->second;
				caret_holder_.carets.erase(i);
			}

			is_end_routine = (caret_holder_.carets.size() == 0);
		}

		if(is_end_routine && (caret_holder_.thr != nullptr) && (caret_holder_.thr->joinable()))
		{
			caret_holder_.exit_thread = true;
			caret_holder_.thr->join();
			caret_holder_.thr.reset();
		}
	}

	void platform_spec::caret_pos(native_window_type wd, const point& pos)
	{
		platform_scope_guard psg;
		auto i = caret_holder_.carets.find(wd);
		if(i != caret_holder_.carets.end())
		{
			i->second->reinstate();
			i->second->pos = pos;
		}
	}

	void platform_spec::caret_visible(native_window_type wd, bool vis)
	{
		platform_scope_guard psg;
		auto i = caret_holder_.carets.find(wd);
		if(i != caret_holder_.carets.end())
		{
			auto & crt = *i->second;
			if(crt.visible != vis)
			{
				if(vis == false)
					crt.reinstate();
				crt.visible = vis;
			}
		}
	}

	bool platform_spec::caret_update(native_window_type wd, nana::paint::graphics&, bool after_mapping)
	{
		platform_scope_guard psg;
		auto i = caret_holder_.carets.find(wd);
		if(i != caret_holder_.carets.end())
		{
			auto & crt = *i->second;
			if(!after_mapping)
				return crt.reinstate();
			else
				crt.twinkle();
		}
		return false;
	}

	void platform_spec::set_error_handler()
	{
		error_code = 0;
	}

	int platform_spec::rev_error_handler()
	{
		return error_code;
	}

	void platform_spec::_m_caret_routine()
	{
		while(false == caret_holder_.exit_thread)
		{
			if(xlib_locker_.try_lock())
			{
				for(auto i : caret_holder_.carets)
					i.second->twinkle();

				xlib_locker_.unlock();
			}
			for(int i = 0; i < 5 && (false == caret_holder_.exit_thread); ++i)
				nana::system::sleep(100);
		}
	}

	unsigned long platform_spec::grab(unsigned long wd)
	{
		unsigned long r = grab_;
		grab_ = wd;
		return r;
	}

	void platform_spec::set_timer(const timer_core* handle, std::size_t interval, void (*timer_proc)(const timer_core*))
	{
		std::lock_guard<decltype(timer_.mutex)> lock(timer_.mutex);
		if(!timer_.runner)
			timer_.runner = new timer_runner;

		timer_.runner->set(handle, interval, timer_proc);
		timer_.delete_declared = false;
	}

	void platform_spec::kill_timer(const timer_core* handle)
	{
		std::lock_guard<decltype(timer_.mutex)> lock(timer_.mutex);
		if(timer_.runner)
		{
			if(timer_.runner->kill(handle))
			{
				if(timer_.runner->is_proc_handling() == false)
				{
					delete timer_.runner;
					timer_.runner = nullptr;
				}
				else
					timer_.delete_declared = true;
			}
		}
	}

	void platform_spec::timer_proc(thread_t tid)
	{
		std::lock_guard<decltype(timer_.mutex)> lock(timer_.mutex);
		if(timer_.runner)
		{
			timer_.runner->timer_proc(tid);
			if(timer_.delete_declared)
			{
				delete timer_.runner;
				timer_.runner = nullptr;
				timer_.delete_declared = false;
			}
		}
	}

	void platform_spec::msg_insert(native_window_type wd)
	{
		msg_dispatcher_->insert(reinterpret_cast<unsigned long>(wd));
	}

	void platform_spec::msg_set(timer_proc_type tp, event_proc_type ep)
	{
		msg_dispatcher_->set(tp, ep, nullptr);
	}

	void platform_spec::msg_dispatch(native_window_type modal)
	{
		msg_dispatcher_->dispatch(reinterpret_cast<unsigned long>(modal));
	}

	void platform_spec::msg_dispatch(std::function<propagation_chain(const msg_packet_tag&)> msg_filter_fn)
	{
		msg_dispatcher_->dispatch(msg_filter_fn);
	}

	void* platform_spec::request_selection(native_window_type, unsigned long, size_t& size)
	{
		size = 0;
		return nullptr;
	}

	void platform_spec::write_selection(native_window_type, unsigned long, const void*, size_t)
	{
		// Stub - will use NSPasteboard
	}

	const nana::paint::graphics& platform_spec::keep_window_icon(native_window_type wd, const nana::paint::image& img)
	{
		nana::paint::graphics & graph = iconbase_[wd];
		graph.make(img.size());
		img.paste(graph, {});
		return graph;
	}

	bool platform_spec::register_dragdrop(native_window_type wd, cocoa_dragdrop_interface* ddrop)
	{
		platform_scope_guard lock;
		if(0 != xdnd_.dragdrop.count(wd))
			return false;

		xdnd_.dragdrop[wd] = ddrop;
		return true;
	}

	std::size_t platform_spec::dragdrop_target(native_window_type wd, bool insert, std::size_t count)
	{
		std::size_t new_val = 0;
		platform_scope_guard lock;
		if(insert)
		{
			new_val = (xdnd_.targets[wd] += count);
		}
		else
		{
			auto i = xdnd_.targets.find(wd);
			if(i == xdnd_.targets.end())
				return 0;

			new_val = (i->second > count ? i->second - count : 0);
			if(0 == new_val)
				xdnd_.targets.erase(wd);
			else
				i->second = new_val;
		}
		return new_val;
	}

	cocoa_dragdrop_interface* platform_spec::remove_dragdrop(native_window_type wd)
	{
		platform_scope_guard lock;
		auto i = xdnd_.dragdrop.find(wd);
		if(i == xdnd_.dragdrop.end())
			return nullptr;

		auto ddrop = i->second;
		xdnd_.dragdrop.erase(i);
		return ddrop;
	}

}//end namespace detail
}//end namespace nana

#include <nana/pop_ignore_diagnostic>
#endif // NANA_POSIX && NANA_MACOS
