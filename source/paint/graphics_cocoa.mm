/*
 *	Graphics Implementation — Cocoa (CoreGraphics) Backend
 */
#if defined(NANA_COCOA)
#include "../detail/platform_spec_selector.hpp"
#include <nana/gui/detail/bedrock.hpp>
#include <nana/paint/graphics.hpp>
#include <nana/paint/detail/native_paint_interface.hpp>
#include <nana/paint/pixel_buffer.hpp>
#include <nana/gui/layout_utility.hpp>
#include <nana/unicode_bidi.hpp>
#include <algorithm>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include "../detail/platform_abstraction.hpp"

namespace nana { namespace paint {

namespace detail {
struct drawable_deleter {
    void operator()(drawable_type p) const {
        if (p) {
            if (p->pixmap) {
                CGContextRelease((CGContextRef)p->pixmap);
                if (p->context && p->context != p->pixmap)
                    CGContextRelease((CGContextRef)p->context);
            }
            delete p;
        }
    }
};
}

// class graphics
struct graphics::impl_type {
    drawable_type drawable;
    nana::size size;
};

graphics::graphics() : impl_(new impl_type) {}
graphics::graphics(const nana::size& sz) : impl_(new impl_type) { make(sz); }
graphics::graphics(const graphics& rhs) : impl_(new impl_type) {
    impl_->size = rhs.impl_->size;
    if (rhs.impl_->drawable) {
        make(rhs.impl_->size);
        if (impl_->drawable && rhs.impl_->drawable) {
            // Copy bitmap data
            void* srcData = CGBitmapContextGetData((CGContextRef)rhs.impl_->drawable->pixmap);
            void* dstData = CGBitmapContextGetData((CGContextRef)impl_->drawable->pixmap);
            if (srcData && dstData) {
                size_t bytes = CGBitmapContextGetBytesPerRow((CGContextRef)impl_->drawable->pixmap) * impl_->size.height;
                memcpy(dstData, srcData, bytes);
            }
        }
    }
}
graphics::~graphics() { delete impl_; }

bool graphics::make(const nana::size& sz) {
    if (sz.empty()) return false;
    impl_->size = sz;

    // Create bitmap context
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bpr = sz.width * 4;
    void* data = calloc(1, bpr * sz.height);
    CGContextRef ctx = CGBitmapContextCreate(data, sz.width, sz.height, 8, bpr, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(data); return false; }

    auto* dw = new detail::drawable_impl_type();
    dw->pixmap = (void*)ctx;
    dw->context = (void*)ctx;
    dw->string.tab_length = 4;
    dw->string.tab_pixels = 0;
    dw->string.whitespace_pixels = 0;

    // Set white background
    CGRect rect = CGRectMake(0, 0, sz.width, sz.height);
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextFillRect(ctx, rect);

    impl_->drawable = std::shared_ptr<detail::drawable_impl_type>(dw, detail::drawable_deleter());
    return true;
}

bool graphics::make(const nana::rectangle& r) {
    if (!make(r.dimension())) return false;
    // TODO: handle offset/origin
    return true;
}

graphics& graphics::operator=(const graphics& rhs) {
    if (this != &rhs) {
        delete impl_;
        impl_ = new impl_type(*rhs.impl_);
    }
    return *this;
}

bool graphics::changed() const {
    return impl_->drawable && impl_->drawable->pixmap;
}

void graphics::flush() {}

drawable_type graphics::handle() const { return impl_->drawable.get(); }

const nana::size& graphics::size() const { return impl_->size; }

void graphics::set_brush(const nana::color& clr) {
    if (impl_->drawable) impl_->drawable->set_color(clr);
}

void graphics::set_pen(const nana::color& clr) {
    if (impl_->drawable) impl_->drawable->set_text_color(clr);
}

void graphics::rectangle(const nana::rectangle& r, bool filled) {
    if (!impl_->drawable || !impl_->drawable->context) return;
    CGContextRef ctx = (CGContextRef)impl_->drawable->context;
    CGRect cr = CGRectMake(r.x, r.y, r.width, r.height);
    if (filled) CGContextFillRect(ctx, cr);
    else CGContextStrokeRect(ctx, cr);
}

void graphics::line(const nana::point& p1, const nana::point& p2) {
    if (!impl_->drawable || !impl_->drawable->context) return;
    CGContextRef ctx = (CGContextRef)impl_->drawable->context;
    CGContextMoveToPoint(ctx, p1.x, p1.y);
    CGContextAddLineToPoint(ctx, p2.x, p2.y);
    CGContextStrokePath(ctx);
}

// More drawing functions follow the same pattern...
void graphics::string(const nana::point& pos, const std::string& text) {
    if (!impl_->drawable) return;
    detail::draw_string(impl_->drawable.get(), pos,
        nana::to_wstring(text).c_str(), nana::to_wstring(text).size());
}

// Simplified implementations below
bool graphics::rounded_rectangle(const nana::rectangle& r, unsigned radius, const nana::color& bg, bool, const nana::color& border, bool, unsigned) {
    if (!impl_->drawable || !impl_->drawable->context) return false;
    CGContextRef ctx = (CGContextRef)impl_->drawable->context;
    CGFloat w = r.width, h = r.height, rad = radius;
    CGContextMoveToPoint(ctx, r.x + rad, r.y);
    CGContextAddLineToPoint(ctx, r.x + w - rad, r.y);
    CGContextAddArcToPoint(ctx, r.x + w, r.y, r.x + w, r.y + rad, rad);
    CGContextAddLineToPoint(ctx, r.x + w, r.y + h - rad);
    CGContextAddArcToPoint(ctx, r.x + w, r.y + h, r.x + w - rad, r.y + h, rad);
    CGContextAddLineToPoint(ctx, r.x + rad, r.y + h);
    CGContextAddArcToPoint(ctx, r.x, r.y + h, r.x, r.y + h - rad, rad);
    CGContextAddLineToPoint(ctx, r.x, r.y + rad);
    CGContextAddArcToPoint(ctx, r.x, r.y, r.x + rad, r.y, rad);
    CGContextClosePath(ctx);
    CGContextSetRGBFillColor(ctx, bg.r()/255.0, bg.g()/255.0, bg.b()/255.0, 1);
    CGContextDrawPath(ctx, kCGPathFillStroke);
    return true;
}

void graphics::paste(graphics& src, int x, int y) {
    if (!impl_->drawable || !impl_->drawable->context || !src.impl_->drawable || !src.impl_->drawable->pixmap) return;
    CGImageRef img = CGBitmapContextCreateImage((CGContextRef)src.impl_->drawable->pixmap);
    if (img) {
        CGRect r = CGRectMake(x, y, src.impl_->size.width, src.impl_->size.height);
        CGContextDrawImage((CGContextRef)impl_->drawable->context, r, img);
        CGImageRelease(img);
    }
}

void graphics::paste(native_window_type wd, const nana::rectangle& src, int x, int y) {
    // Stub: paste to window
}

// Remaining methods with minimal stubs
bool graphics::bitblt(const nana::rectangle& src, native_window_type wd, const nana::point& dst) { return true; }
bool graphics::bitblt(const nana::rectangle& src, graphics& dst, const nana::point& pos) { return true; }
void graphics::blend(const nana::rectangle& src, graphics& dst, const nana::point& pos, double rate) {}
void graphics::blur(const nana::rectangle& r, unsigned radius) {}

font::font() : impl_(new impl_type) {
    impl_->real_font = platform_abstraction::default_font(nullptr);
}
font::font(drawable_type dw) : impl_(new impl_type) { impl_->real_font = dw->font; }
font::font(const font& rhs) : impl_(new impl_type) {
    if (rhs.impl_) impl_->real_font = rhs.impl_->real_font;
}
font::font(const std::string& family, double size, const font_style& fs) : impl_(new impl_type) {
    impl_->real_font = platform_abstraction::make_font(family, size, fs);
}
font::~font() { delete impl_; }
font& font::operator=(const font& rhs) {
    if (this != &rhs && rhs.impl_) impl_->real_font = rhs.impl_->real_font;
    return *this;
}
bool font::operator==(const font& rhs) const { return impl_->real_font == rhs.impl_->real_font; }

}} // namespace
#endif
