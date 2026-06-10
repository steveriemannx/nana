/*
 *	Native Paint Interface — Cocoa (CoreGraphics) Backend
 */
#if defined(NANA_COCOA)
#include "../../detail/platform_spec_selector.hpp"
#include <nana/paint/detail/native_paint_interface.hpp>
#include <nana/paint/pixel_buffer.hpp>
#include <nana/gui/layout_utility.hpp>
#import <CoreGraphics/CoreGraphics.h>

namespace nana { namespace paint { namespace detail {

nana::size drawable_size(drawable_type dw) {
    if (!dw || !dw->pixmap) return {};
    CGContextRef ctx = (CGContextRef)dw->pixmap;
    size_t w = (size_t)CGBitmapContextGetWidth(ctx);
    size_t h = (size_t)CGBitmapContextGetHeight(ctx);
    return nana::size((unsigned)w, (unsigned)h);
}

std::unique_ptr<unsigned char[]> alloc_fade_table(double fade_rate) {
    auto ptr = std::make_unique<unsigned char[]>(0x100 * 2);
    unsigned char* d_table = ptr.get();
    unsigned char* s_table = d_table + 0x100;
    double acc = 0;
    for (int i = 0; i < 0x100; i += 4, acc += fade_rate * 4) {
        d_table[0] = (unsigned char)acc;
        s_table[0] = i - d_table[0];
        d_table[1] = (unsigned char)(acc + fade_rate);
        s_table[1] = i + 1 - d_table[1];
        d_table[2] = (unsigned char)(acc + fade_rate * 2);
        s_table[2] = i + 2 - d_table[2];
        d_table[3] = (unsigned char)(acc + fade_rate * 3);
        s_table[3] = i + 3 - d_table[3];
        d_table += 4; s_table += 4;
    }
    return ptr;
}

nana::pixel_color_t fade_color_intermedia(nana::pixel_color_t fg, const unsigned char* ft) {
    ft += 0x100;
    fg.element.red = ft[fg.element.red];
    fg.element.green = ft[fg.element.green];
    fg.element.blue = ft[fg.element.blue];
    return fg;
}

nana::pixel_color_t fade_color_by_intermedia(nana::pixel_color_t bg, nana::pixel_color_t fg_int, const unsigned char* ft) {
    bg.element.red = ft[bg.element.red] + fg_int.element.red;
    bg.element.green = ft[bg.element.green] + fg_int.element.green;
    bg.element.blue = ft[bg.element.blue] + fg_int.element.blue;
    return bg;
}

void blend(drawable_type dw, const rectangle& area, pixel_color_t color, double fade_rate) {
    if (fade_rate <= 0) return;
    if (fade_rate >= 1) fade_rate = 1;
    rectangle r;
    if (!::nana::overlap(rectangle{drawable_size(dw)}, area, r)) return;
    pixel_buffer pixbuf(dw, r.y, r.height);
    for (std::size_t row = 0; row < r.height; ++row) {
        auto i = pixbuf.raw_ptr(row) + r.x;
        auto end = i + r.width;
        for (; i < end; ++i) {
            auto fd = (double)color.element.alpha_channel / 255.0 * fade_rate;
            auto f = 1 - fd;
            unsigned vr = (unsigned)((i->value & 0xFF0000) * f + (color.value & 0xFF0000) * fd) & 0xFF0000;
            unsigned vg = (unsigned)((i->value & 0xFF00) * f + (color.value & 0xFF00) * fd) & 0xFF00;
            unsigned vb = (unsigned)((i->value & 0xFF) * f + (color.value & 0xFF) * fd) & 0xFF;
            i->value = vr | vg | vb;
        }
    }
    pixbuf.paste(rectangle(r.x, 0, r.width, r.height), dw, point{r.x, r.y});
}

nana::size real_text_extent_size(drawable_type dw, const wchar_t* text, std::size_t len) {
    if (!dw || !text || !len) return {};
    // Use CoreText for text measurement
    CFStringRef str = CFStringCreateWithBytes(nullptr, (const UInt8*)text,
        len * sizeof(wchar_t), kCFStringEncodingUTF32LE, false);
    if (!str) return {};
    CTFontRef font = (CTFontRef)(dw->font ? dw->font->native_handle() : nullptr);
    if (!font) font = (CTFontRef)dw->font->native_handle();
    if (!font) { CFRelease(str); return {}; }
    CFAttributedStringRef astr = CFAttributedStringCreate(nullptr, str, nullptr);
    CTLineRef line = CTLineCreateWithAttributedString(astr);
    CGRect bounds = CTLineGetBoundsWithOptions(line, kCTLineBoundsUseGlyphPathBounds);
    CGFloat w = bounds.size.width;
    CGFloat h = CTFontGetAscent(font) + CTFontGetDescent(font);
    CFRelease(line); CFRelease(astr); CFRelease(str);
    return nana::size((unsigned)w, (unsigned)h);
}

nana::size real_text_extent_size(drawable_type dw, const char* text, std::size_t len) {
    if (!dw || !text || !len) return {};
    auto wstr = nana::to_wstring(std::string(text, len));
    return real_text_extent_size(dw, wstr.c_str(), wstr.size());
}

nana::size text_extent_size(drawable_type dw, const char* text, std::size_t len) {
    if (!dw || !text || !len) return {};
    nana::size ext = real_text_extent_size(dw, text, len);
    int tabs = 0;
    for (const char* p = text; p < text + len; ++p) if (*p == '\t') ++tabs;
    if (tabs) ext.width = (int)ext.width - tabs * (int)(dw->string.tab_pixels - dw->string.whitespace_pixels * dw->string.tab_length);
    return ext;
}

nana::size text_extent_size(drawable_type dw, const wchar_t* text, std::size_t len) {
    if (!dw || !text || !len) return {};
    nana::size ext = real_text_extent_size(dw, text, len);
    int tabs = 0;
    for (const wchar_t* p = text; p < text + len; ++p) if (*p == '\t') ++tabs;
    if (tabs) ext.width = (int)ext.width - tabs * (int)(dw->string.tab_pixels - dw->string.whitespace_pixels * dw->string.tab_length);
    return ext;
}

void draw_string(drawable_type dw, const nana::point& pos, const wchar_t* str, std::size_t len) {
    if (!dw || !dw->context || !str || !len) return;
    CGContextRef ctx = (CGContextRef)dw->context;
    CGContextSaveGState(ctx);
    // Flip coordinate system for text
    CGAffineTransform flip = CGAffineTransformMake(1, 0, 0, -1, 0, 0);
    CGContextSetTextMatrix(ctx, flip);

    CFStringRef cfs = CFStringCreateWithBytes(nullptr, (const UInt8*)str,
        len * sizeof(wchar_t), kCFStringEncodingUTF32LE, false);
    if (!cfs) { CGContextRestoreGState(ctx); return; }

    CTFontRef font = (CTFontRef)(dw->font ? dw->font->native_handle() : nullptr);
    if (!font) { CFRelease(cfs); CGContextRestoreGState(ctx); return; }

    CFAttributedStringRef astr = CFAttributedStringCreate(nullptr, cfs, nullptr);
    CTLineRef line = CTLineCreateWithAttributedString(astr);

    CGFloat y = pos.y + CTFontGetAscent(font);
    CGContextSetTextPosition(ctx, pos.x, -y);
    CTLineDraw(line, ctx);

    CFRelease(line); CFRelease(astr); CFRelease(cfs);
    CGContextRestoreGState(ctx);
}

}}} // namespace
#endif
