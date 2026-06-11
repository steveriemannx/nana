#include <nana/system/dataexch.hpp>
#include <nana/paint/graphics.hpp>
#include "../detail/platform_spec_selector.hpp"
#import <Cocoa/Cocoa.h>

#if defined(NANA_MACOS)

namespace nana { namespace system {

void dataexch::set(const std::string& text, native_window_type) {
	[[NSPasteboard generalPasteboard] clearContents];
	[[NSPasteboard generalPasteboard] setString:[NSString stringWithUTF8String:text.c_str()]
	                                    forType:NSPasteboardTypeString];
}

void dataexch::set(const std::wstring& text, native_window_type) {
	set(to_utf8(text), nullptr);
}

void dataexch::get(std::string& text) {
	NSString* s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
	if (s) text = [s UTF8String] ?: "";
	else text.clear();
}

void dataexch::get(std::wstring& text) {
	std::string t; get(t); text = to_wstring(t);
}

std::wstring dataexch::wget() {
	std::wstring t; get(t); return t;
}

bool dataexch::_m_set(format fmt, const void* buf, std::size_t size, native_window_type) {
	if (fmt == format::text && buf) {
		[[NSPasteboard generalPasteboard] clearContents];
		NSString* str = [[NSString alloc] initWithBytes:buf length:size encoding:NSUTF8StringEncoding];
		if (str) {
			[[NSPasteboard generalPasteboard] setString:str forType:NSPasteboardTypeString];
			[str release];
		}
		return true;
	}
	return false;
}

void* dataexch::_m_get(format fmt, size_t& size) {
	if (fmt == format::text) {
		NSString* s = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
		if (s) {
			const char* utf8 = [s UTF8String];
			if (utf8) {
				size = strlen(utf8) + 1;
				char* buf = new char[size];
				memcpy(buf, utf8, size);
				return buf;
			}
		}
	}
	return nullptr;
}

}} // namespace
#endif
