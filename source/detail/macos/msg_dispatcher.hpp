/*
 *	Message Dispatcher for Cocoa
 *	Nana C++ Library(http://www.nanapro.org)
 *	Copyright(C) 2003-2024 Jinhao(cnjinhao@hotmail.com)
 *
 *	Distributed under the Boost Software License, Version 1.0.
 *	@file: nana/detail/macos/msg_dispatcher.hpp
 */

#ifndef NANA_DETAIL_COCOA_MSG_DISPATCHER_HPP
#define NANA_DETAIL_COCOA_MSG_DISPATCHER_HPP

#include "../posix/msg_packet.hpp"
#include <nana/system/platform.hpp>
#include <list>
#include <set>
#include <map>
#include <mutex>
#include <condition_variable>
#include <memory>
#include <thread>
#include <atomic>

namespace nana
{
namespace detail
{
	class msg_dispatcher
	{
		struct thread_binder
		{
			thread_t tid;
			std::mutex	mutex;
			std::condition_variable	cond;
			std::list<msg_packet_tag>	msg_queue;
			std::set<uintptr_t> windows;  // using unsigned long for window handle (NSView* cast)
		};

	public:
		typedef msg_packet_tag	msg_packet;
		typedef void (*timer_proc_type)(thread_t tid);
		typedef void (*event_proc_type)(void*, msg_packet_tag&);
		typedef int (*event_filter_type)(void* /*NSEvent*/, msg_packet_tag&);

		typedef std::list<msg_packet_tag> msg_queue_type;

		msg_dispatcher(Display* disp)
			: display_(disp)
		{
			proc_.event_proc = 0;
			proc_.timer_proc = 0;
			proc_.filter_proc = 0;
		}

		~msg_dispatcher()
		{
			if(thrd_ && thrd_->joinable())
			{
				is_work_ = false;
				thrd_->join();
			}
		}

		void set(timer_proc_type timer_proc, event_proc_type event_proc, event_filter_type filter)
		{
			proc_.timer_proc = timer_proc;
			proc_.event_proc = event_proc;
			proc_.filter_proc = filter;
		}

		void insert(unsigned long wd)
		{
			auto tid = nana::system::this_thread_id();
			bool start_driver;

			{
				std::lock_guard<decltype(table_.mutex)> lock(table_.mutex);
				start_driver = (0 == table_.thr_table.size());
				thread_binder * thr;

				std::map<thread_t, thread_binder*>::iterator i = table_.thr_table.find(tid);
				if(i == table_.thr_table.end())
				{
					thr = new thread_binder;
					thr->tid = tid;
					table_.thr_table.insert(std::make_pair(tid, thr));
				}
				else
					thr = i->second;

				thr->mutex.lock();
				thr->windows.insert(wd);
				thr->mutex.unlock();

				table_.wnd_table[wd] = thr;
			}

			if(start_driver && proc_.event_proc && proc_.timer_proc)
			{
				if(thrd_)
				{
					is_work_ = false;
					thrd_->join();
				}
				is_work_ = true;
				thrd_ = std::unique_ptr<std::thread>(new std::thread([this](){ this->_m_msg_driver(); }));
			}
		}

		void erase(unsigned long wd)
		{
			std::lock_guard<decltype(table_.mutex)> lock(table_.mutex);

			auto i = table_.wnd_table.find(wd);
			if(i != table_.wnd_table.end())
			{
				thread_binder * const thr = i->second;
				std::lock_guard<decltype(thr->mutex)> lock(thr->mutex);
				for(auto li = thr->msg_queue.begin(); li != thr->msg_queue.end();)
				{
					if(wd == _m_window(*li))
						li = thr->msg_queue.erase(li);
					else
						++li;
				}

				table_.wnd_table.erase(i);
				thr->windows.erase(wd);

				if(thr->windows.size())
				{
					msg_packet_tag msg;
					msg.kind = msg_packet_tag::pkt_family::cleanup;
				table_.wnd_table[reinterpret_cast<uintptr_t>(wd)] = thr;
					thr->msg_queue.push_back(msg);
				}
			}
		}

		void dispatch(unsigned long modal)
		{
			auto tid = nana::system::this_thread_id();
			msg_packet_tag msg;
			int qstate;

			while((qstate = _m_read_queue(tid, msg, modal)))
			{
				if(-1 == qstate)
				{
					if(false == _m_wait_for_queue(tid))
						proc_.timer_proc(tid);
				}
				else
				{
					proc_.event_proc(display_, msg);
				}
			}
		}

		template<typename MsgFilter>
		void dispatch(MsgFilter msg_filter_fn)
		{
			auto tid = nana::system::this_thread_id();
			msg_packet_tag msg;
			int qstate;

			while((qstate = _m_read_queue(tid, msg, 0)))
			{
				if(-1 == qstate)
				{
					if(false == _m_wait_for_queue(tid))
						proc_.timer_proc(tid);
				}
				else
				{
					switch(msg_filter_fn(msg))
					{
					case propagation_chain::exit:
						return;
					case propagation_chain::stop:
						break;
					case propagation_chain::pass:
						proc_.event_proc(display_, msg);
					}
				}
			}
		}
	private:
		void _m_msg_driver()
		{
			while(is_work_)
			{
				// Cocoa: poll for events on main thread; minimal sleep-based driver for now
				// Will be replaced with proper NSApplication run loop integration
				std::this_thread::sleep_for(std::chrono::milliseconds(10));

				// Process any pending messages
				{
					std::lock_guard<decltype(table_.mutex)> lock(table_.mutex);
					// Check if any threads are waiting
					for(auto & thr_pair : table_.thr_table)
					{
						auto * thr = thr_pair.second;
						std::lock_guard<decltype(thr->mutex)> thr_lock(thr->mutex);
						if(!thr->msg_queue.empty())
							thr->cond.notify_one();
					}
				}
			}
		}

		static unsigned long _m_window(const msg_packet_tag& pack)
		{
			switch(pack.kind)
			{
			case msg_packet_tag::pkt_family::xevent:
				return 0; // TODO: extract from NSEvent
			case msg_packet_tag::pkt_family::mouse_drop:
				return reinterpret_cast<unsigned long>(pack.u.mouse_drop.window);
			case msg_packet_tag::pkt_family::cleanup:
				return reinterpret_cast<unsigned long>(pack.u.packet_window);
			default:
				break;
			}
			return 0;
		}

		int _m_read_queue(thread_t tid, msg_packet_tag& msg, unsigned long modal)
		{
			bool stop_driver = false;

			{
				std::lock_guard<decltype(table_.mutex)> lock(table_.mutex);
				auto i = table_.thr_table.find(tid);
				if(i != table_.thr_table.end())
				{
					if(i->second->windows.size())
					{
						msg_queue_type & queue = i->second->msg_queue;
						if(queue.size())
						{
							msg = queue.front();
							queue.pop_front();

							if((modal == reinterpret_cast<unsigned long>(msg.u.packet_window)) && (msg.kind == msg_packet_tag::pkt_family::cleanup))
								return 0;

							return 1;
						}
						else
							return -1;
					}

					delete i->second;
					table_.thr_table.erase(i);
					stop_driver = (table_.thr_table.size() == 0);
				}
			}
			if(stop_driver)
			{
				is_work_ = false;
				thrd_->join();
				thrd_.reset();
			}
			return 0;
		}

		bool _m_wait_for_queue(thread_t tid)
		{
			thread_binder * thr = nullptr;
			{
				std::lock_guard<decltype(table_.mutex)> lock(table_.mutex);
				auto i = table_.thr_table.find(tid);
				if(i != table_.thr_table.end())
				{
					if(i->second->msg_queue.size())
						return true;
					thr = i->second;
				}
			}

			std::unique_lock<decltype(thr->mutex)> lock(thr->mutex);
			return (thr->cond.wait_for(lock, std::chrono::milliseconds(10)) != std::cv_status::timeout);
		}

	private:
		Display* display_;
		std::atomic<bool> is_work_{ false };
		std::unique_ptr<std::thread> thrd_;

		struct table_tag
		{
			std::recursive_mutex mutex;
			std::map<thread_t, thread_binder*> thr_table;
			std::map<unsigned long, thread_binder*> wnd_table;
		} table_;

		struct proc_tag
		{
			timer_proc_type	timer_proc;
			event_proc_type	event_proc;
			event_filter_type filter_proc;
		} proc_;
	};
}//end namespace detail
}//end namespace nana

#endif
