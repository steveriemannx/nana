/*
 *	Platform Abstraction — CoreText (Cocoa) Backend
 */
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include "platform_abstraction.hpp"
#include "macos/platform_spec.hpp"
#include <nana/deploy.hpp>
#include "../paint/truetype.hpp"
#include <set>
#include <map>

#if defined(NANA_MACOS)
namespace nana {

// Simplified platform_runtime for Cocoa (no Xft fallback manager)
struct platform_runtime { std::shared_ptr<font_interface> font; };
namespace { platform_runtime* storage; }
static platform_runtime& platform_storage() { return *storage; }

// internal_font with CTFontRef
class internal_font : public font_interface {
    std::string family_; double size_; font_style style_;
    native_font_type handle_; std::filesystem::path ttf_;
public:
    internal_font(const std::filesystem::path& ttf, const std::string& fam,
                  double sz, const font_style& fs, paint::native_font_type h)
        : family_(fam), size_(sz), style_(fs), handle_(h), ttf_(ttf) {}
    ~internal_font() { if (handle_) CFRelease((CTFontRef)handle_); }
    const std::string& family() const override { return family_; }
    double size() const override { return size_; }
    const font_style& style() const override { return style_; }
    paint::native_font_type native_handle() const override { return handle_; }
};

void platform_abstraction::initialize() { if (!storage) storage = new platform_runtime; }
void platform_abstraction::shutdown() { delete storage; storage = nullptr; }
double platform_abstraction::font_default_pt() { return 12.0; }
void platform_abstraction::font_languages(const std::string&) {}
unsigned platform_abstraction::screen_dpi(bool) {
    CGDirectDisplayID d = CGMainDisplayID();
    CGSize mm = CGDisplayScreenSize(d);
    return (unsigned)(CGDisplayPixelsWide(d) / (mm.width / 25.4) + 0.5);
}

::std::shared_ptr<platform_abstraction::font>
platform_abstraction::default_font(const ::std::shared_ptr<font>& nf) {
    auto& r = platform_storage();
    if (nf) { auto f = r.font; r.font = nf; return f; }
    if (!r.font) r.font = make_font({}, 0, {});
    return r.font;
}

::std::shared_ptr<platform_abstraction::font>
platform_abstraction::make_font(const std::string& family, double size_pt, const font::font_style& fs) {
    NSString* name = nil;
    if (!family.empty()) name = [NSString stringWithUTF8String:family.c_str()];
    if (!name) name = @"Helvetica";

    CTFontSymbolicTraits traits = 0;
    if (fs.weight >= 700) traits |= kCTFontBoldTrait;
    if (fs.italic) traits |= kCTFontItalicTrait;

    CGFloat sz = size_pt ?: 12.0;
    CTFontDescriptorRef desc = CTFontDescriptorCreateWithNameAndSize((__bridge CFStringRef)name, sz);
    if (desc && traits) {
        CTFontDescriptorRef bd = CTFontDescriptorCreateCopyWithSymbolicTraits(desc, traits, traits);
        if (bd) { CFRelease(desc); desc = bd; }
    }
    CTFontRef fd = desc ? CTFontCreateWithFontDescriptor(desc, sz, nullptr) : nullptr;
    if (desc) CFRelease(desc);
    if (!fd) fd = CTFontCreateWithName((__bridge CFStringRef)name, sz, nullptr);
    if (!fd) return {};

    return std::make_shared<internal_font>(
        std::filesystem::path{}, family.empty() ? "Helvetica" : family,
        size_pt, fs, reinterpret_cast<paint::native_font_type>((void*)fd));
}

::std::shared_ptr<platform_abstraction::font>
platform_abstraction::make_font_from_ttf(const path_type& ttf, double size_pt, const font::font_style& fs) {
    ::nana::spec::truetype truetype{ttf};
    if (truetype.font_family().empty()) return nullptr;
    font_resource(true, ttf);
    return make_font(truetype.font_family(), size_pt, fs);
}

void platform_abstraction::font_resource(bool, const path_type&) {
    // CoreText handles font registration automatically via CTFontManager
}

} // namespace nana
#endif
