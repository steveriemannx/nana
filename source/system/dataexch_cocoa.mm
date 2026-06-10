/*
 *	Data Exchange — Cocoa (NSPasteboard) Backend
 */
#if defined(NANA_COCOA)
#include <nana/system/dataexch.hpp>
#include <nana/traits.hpp>
#import <Cocoa/Cocoa.h>
#include <vector>
#include <cstring>

namespace nana { namespace system {

void dataexch::set(const std::string& text, native_window_type) {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[NSString stringWithUTF8String:text.c_str()] forType:NSPasteboardTypeString];
}

void dataexch::set(const std::wstring& text, native_window_type) {
    std::string utf8 = to_utf8(text);
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString:[NSString stringWithUTF8String:utf8.c_str()] forType:NSPasteboardTypeString];
}

void dataexch::get(std::string& text) {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSString* str = [pb stringForType:NSPasteboardTypeString];
    if (str) text = [str UTF8String] ?: "";
}

void dataexch::get(std::wstring& text) {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSString* str = [pb stringForType:NSPasteboardTypeString];
    if (str) {
        std::string utf8 = [str UTF8String] ?: "";
        text = nana::to_wstring(utf8);
    }
}

void dataexch::_m_set(unsigned fmt, const void* data, std::size_t bytes, native_window_type) {
    // Internal set implementation
    if (fmt == format::text && data) {
        NSPasteboard* pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        NSString* str = [[NSString alloc] initWithBytes:data length:bytes encoding:NSUTF8StringEncoding];
        if (str) {
            [pb setString:str forType:NSPasteboardTypeString];
            [str release];
        }
    }
}

}} // namespace
#endif
