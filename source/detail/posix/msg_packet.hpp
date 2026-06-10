#ifndef NANA_DETAIL_MSG_PACKET_HPP
#define NANA_DETAIL_MSG_PACKET_HPP
#if defined(NANA_COCOA)
// Cocoa: forward-declare types to avoid X11/Cocoa header conflict
typedef struct _XDisplay Display;
typedef unsigned long XID;
typedef XID Window;
typedef XID Pixmap;
// Use void* for event data on Cocoa (stores NSEvent* or nullptr)
#else
#include <X11/Xlib.h>
#endif
#include <vector>
#include <nana/deploy.hpp>
#include <nana/filesystem/filesystem.hpp>

namespace nana
{
namespace detail
{
	enum class propagation_chain
	{
		exit,
		stop,
		pass
	};

	struct msg_packet_tag
	{
		enum class pkt_family{xevent, mouse_drop, cleanup};
		pkt_family kind;
		union
		{
#if defined(NANA_COCOA)
			void* xevent_ptr;  // NSEvent* on Cocoa
#else
			XEvent xevent;
#endif

			uintptr_t packet_window;
			struct mouse_drop_tag
			{
				uintptr_t window;
				int x;
				int y;
				std::vector<std::filesystem::path> * files;
			}mouse_drop;
		}u;
	};
}//end namespace detail
}//end namespace nana
#endif
