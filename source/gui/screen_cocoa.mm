/*
 *	Screen + Filebox + Msgbox — Cocoa stubs
 */
#if defined(NANA_COCOA)
#include <nana/gui/screen.hpp>
#include <nana/gui/filebox.hpp>
#include <nana/gui/msgbox.hpp>
#import <Cocoa/Cocoa.h>

namespace nana {

// === Screen ===
void screen::reload() {
    for (auto& d : displays_) { /* NSScreen array is dynamic */ }
}
std::size_t screen::count() const { return [[NSScreen screens] count]; }
std::vector<screen::display> screen::enum_display() const {
    std::vector<display> result;
    NSArray* screens = [NSScreen screens];
    for (NSScreen* s in screens) {
        display d;
        NSRect f = [s frame], vf = [s visibleFrame];
        d.area = rectangle((int)f.origin.x, (int)(f.size.height - f.origin.y - f.size.height),
                           (unsigned)f.size.width, (unsigned)f.size.height);
        d.workarea = rectangle((int)vf.origin.x, (int)(vf.size.height - vf.origin.y - vf.size.height),
                               (unsigned)vf.size.width, (unsigned)vf.size.height);
        result.push_back(d);
    }
    return result;
}

// === Filebox (stub) ===
filebox::filebox(bool is_open) : open_(is_open) {}
filebox::filebox(window, const nana::rectangle&, bool) : open_(true) {}
filebox::~filebox() {}
void filebox::init_path(const std::string&) {}
void filebox::init_file(const std::string&) {}
void filebox::add_filter(const std::string&, const std::string&) {}
std::string filebox::path() const { return {}; }
std::string filebox::file() const { return {}; }
bool filebox::show() {
    @autoreleasepool {
        if (open_) {
            NSOpenPanel* panel = [NSOpenPanel openPanel];
            [panel setCanChooseFiles:YES];
            [panel setCanChooseDirectories:NO];
            if ([panel runModal] == NSModalResponseOK && [[panel URLs] count] > 0)
                return true;
        } else {
            NSSavePanel* panel = [NSSavePanel savePanel];
            if ([panel runModal] == NSModalResponseOK && [panel URL])
                return true;
        }
    }
    return false;
}
filebox& filebox::operator()(const std::string&) { return *this; }

// === Msgbox (stub) ===
msgbox::msgbox(const std::string& title) : title_(title) {}
msgbox::msgbox(window, const std::string& title, buttons_t btns) : title_(title), buttons_(btns) {}
msgbox& msgbox::operator<<(const std::string& text) { text_ = text; return *this; }
void msgbox::icon(msgbox::icon_t) {}
msgbox::buttons_t msgbox::operator()() {
    // Not supported in stub — just return ok
    return {msgbox::ok};
}

} // namespace
#endif
