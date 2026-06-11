#include <nana/gui/detail/native_window_interface.hpp>
#include <nana/gui/screen.hpp>
#include <nana/gui/detail/bedrock.hpp>
#include <nana/gui/detail/window_manager.hpp>
#include "../../detail/platform_spec_selector.hpp"
#include "../detail/basic_window.hpp"
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <map>
#include <mutex>

#if defined(NANA_MACOS)

// Forward declare keyboard lookup (implemented in bedrock_cocoa.mm)
namespace nana { namespace detail {
    struct root_misc;
    void cocoa_lookup_chars(const root_misc*, basic_window*, const char*, std::size_t, const arg_keyboard&);
}}

// Map macOS key codes to nana keyboard codes for non-character keys
static wchar_t cocoa_key_to_nana(unsigned short keyCode) {
    switch(keyCode) {
    case 0x24: return nana::keyboard::enter;
    case 0x30: return nana::keyboard::tab;
    case 0x33: return nana::keyboard::backspace;
    case 0x35: return nana::keyboard::escape;
    case 0x75: return nana::keyboard::del;
    case 0x72: return nana::keyboard::os_insert;
    case 0x73: return nana::keyboard::os_pageup;    // home
    case 0x74: return nana::keyboard::os_pagedown;  // page up
    case 0x77: return nana::keyboard::os_pagedown;  // end
    case 0x79: return nana::keyboard::os_pageup;    // page down
    case 0x7E: return nana::keyboard::os_arrow_up;
    case 0x7D: return nana::keyboard::os_arrow_down;
    case 0x7B: return nana::keyboard::os_arrow_left;
    case 0x7C: return nana::keyboard::os_arrow_right;
    case 0x37: case 0x3B: case 0x3A: case 0x3E:
        return nana::keyboard::os_ctrl;
    case 0x38: case 0x3C: return nana::keyboard::os_shift;
    case 0x39: case 0x3D: return nana::keyboard::alt;
    default:   return 0;
    }
}

// Helpers for native controls
static std::map<void*, NSView*> native_controls;
static std::recursive_mutex native_ctrl_mutex;
extern "C" {
void* nana_macos_create_native_button(void*, void*, int, int, unsigned, unsigned, const char*);
void nana_macos_update_native_control(void*, int, int, unsigned, unsigned, const char*);
}

@interface NanaButtonTarget : NSObject
@property (nonatomic) void* basicWindow;
@end
@implementation NanaButtonTarget
- (void)onClick:(id)sender {
    if (_basicWindow) {
        auto* bw = (nana::detail::basic_window*)_basicWindow;
        auto& b = nana::detail::bedrock::instance();
        nana::arg_click arg; arg.window_handle = bw; arg.mouse_args = nullptr;
        b.emit(nana::event_code::click, bw, arg, true, b.get_thread_context(bw->thread_id));
        b.wd_manager().do_lazy_refresh(bw, false);
    }
}
@end

// ============ NanaNSView ============
@interface NanaNSView : NSView <NSTextInputClient>
@property (nonatomic) void* nanaWindow;
@property (nonatomic) void* nanaRootWindow;
// IME marked text storage (prefixed to avoid NSTextInputClient protocol conflict)
@property (nonatomic, copy) NSAttributedString* markedText;
@property (nonatomic) NSRange imeMarkedRange;
@property (nonatomic) NSRange imeSelectedRange;
// Caret (text cursor) state
@property (nonatomic) BOOL caretVisible;
@property (nonatomic) NSPoint caretPos;
@property (nonatomic) NSSize  caretSize;
@property (nonatomic, strong) NSTimer* caretTimer;
@end

@implementation NanaNSView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    if (!_nanaRootWindow) return;
    auto& brock = nana::detail::bedrock::instance();
    auto* rw = brock.wd_manager().root((nana::native_window_type)_nanaRootWindow);
    if (!rw || !rw->root_graph) return;
    auto* dw = rw->root_graph->handle();
    if (!dw || !dw->pixmap) return;
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGImageRef img = CGBitmapContextCreateImage((CGContextRef)dw->pixmap);
    if (img) { CGContextSaveGState(ctx); CGContextTranslateCTM(ctx, 0, self.bounds.size.height); CGContextScaleCTM(ctx, 1.0, -1.0); CGContextDrawImage(ctx, self.bounds, img); CGContextRestoreGState(ctx); CGImageRelease(img); }

    // Draw blinking caret (text cursor)
    // The flipped NSView context already has Y=0 at top, matching nana coords.
    if (_caretVisible && _caretSize.width > 0 && _caretSize.height > 0) {
        CGContextSaveGState(ctx);
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
        CGContextFillRect(ctx, CGRectMake(_caretPos.x, _caretPos.y, _caretSize.width, _caretSize.height));
        CGContextRestoreGState(ctx);
    }
}

- (nana::point)cvtPt:(NSPoint)pt { return nana::point((int)pt.x, (int)pt.y); }

- (void)mouseDown:(NSEvent*)e {
    [self.window makeKeyWindow];
    [self forwardMouse:e type:0];
}
- (void)mouseUp:(NSEvent*)e { [self forwardMouse:e type:1]; }
- (void)mouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)mouseMoved:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)rightMouseDown:(NSEvent*)e { [self forwardMouse:e type:2]; }
- (void)rightMouseUp:(NSEvent*)e { [self forwardMouse:e type:3]; }
- (void)scrollWheel:(NSEvent*)e { [self forwardMouse:e type:5]; }

- (void)forwardMouse:(NSEvent*)e type:(int)t {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRootWindow);
    if (!rw) return;
    NSPoint loc = [self convertPoint:[e locationInWindow] fromView:nil];
    nana::point pt = [self cvtPt:loc];
    auto* tw = b.wd_manager().find_window((nana::native_window_type)_nanaRootWindow, pt);
    if (!tw) tw = rw;
    nana::arg_mouse arg; arg.window_handle = tw;
    arg.pos.x = (int)loc.x - tw->pos_root.x;
    arg.pos.y = (int)loc.y - tw->pos_root.y;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.left_button=arg.right_button=arg.mid_button=false;
    if(t==0){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::left_button;arg.left_button=true;tw->set_action(nana::mouse_action::pressed);b.wd_manager().set_focus(tw,false,nana::arg_focus::reason::mouse_press);b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==1){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::left_button;tw->set_action(nana::mouse_action::normal);b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));nana::arg_click ca;ca.window_handle=tw;ca.mouse_args=&arg;b.emit(nana::event_code::click,tw,ca,true,b.get_thread_context(tw->thread_id));}
    else if(t==2){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::right_button;arg.right_button=true;b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==3){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::right_button;b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==4){arg.evt_code=nana::event_code::mouse_move;b.emit(nana::event_code::mouse_move,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==5){nana::arg_wheel wa;wa.window_handle=tw;wa.evt_code=nana::event_code::mouse_wheel;wa.pos=arg.pos;wa.upwards=([e scrollingDeltaY]>0);wa.distance=120;wa.which=nana::arg_wheel::wheel::vertical;b.emit(nana::event_code::mouse_wheel,tw,wa,true,b.get_thread_context(tw->thread_id));}
    // Defer refresh to next runloop iteration so all event handlers
    // (label _m_caption, etc.) have completed before we repaint.
    auto* root_native = _nanaRootWindow;
    auto* view = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        auto& bb = nana::detail::bedrock::instance();
        auto* rr = bb.wd_manager().root((nana::native_window_type)root_native);
        if (rr) {
            bb.wd_manager().do_lazy_refresh(rr, true, true);
            [view setNeedsDisplay:YES];
        }
    });
}

- (void)keyDown:(NSEvent *)event {
    // Use macOS input system: handles IME, special keys, and regular characters
    [self interpretKeyEvents:@[event]];
}

// Helper: get focused window and send text to it
- (void)sendTextToFocused:(const char*)utf8 len:(std::size_t)len modifiers:(NSUInteger)fl {
    if (!_nanaRootWindow || len == 0) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRootWindow);
    if (!rw) return;
    auto* attr_root = rw->other.attribute.root;
    auto* focused = attr_root ? attr_root->focus : nullptr;
    if (!focused) focused = rw;

    nana::arg_keyboard arg;
    arg.alt   = (fl & NSEventModifierFlagOption) != 0;
    arg.ctrl  = (fl & NSEventModifierFlagControl) != 0;
    arg.shift = (fl & NSEventModifierFlagShift) != 0;

    auto misc = b.wd_manager().root_runtime((nana::native_window_type)_nanaRootWindow);
    if (misc) {
        nana::detail::cocoa_lookup_chars(misc, focused, utf8, len, arg);
    }
    b.wd_manager().do_lazy_refresh(rw, true, true);
    [self setNeedsDisplay:YES];
}

// Helper: send key_press for special keys
- (void)sendKeyPress:(wchar_t)key {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRootWindow);
    if (!rw) return;
    auto* attr_root = rw->other.attribute.root;
    auto* focused = attr_root ? attr_root->focus : nullptr;
    if (!focused) focused = rw;

    nana::arg_keyboard arg;
    arg.evt_code = nana::event_code::key_press;
    arg.key = key;
    arg.window_handle = focused;
    auto* ctx = b.get_thread_context(focused->thread_id);
    b.emit(nana::event_code::key_press, focused, arg, true, ctx);
    b.wd_manager().do_lazy_refresh(rw, true, true);
    [self setNeedsDisplay:YES];
}

// NSTextInputClient / interpretKeyEvents callbacks
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    // Called for regular characters AND IME-committed text
    NSString* str = nil;
    if ([string isKindOfClass:[NSAttributedString class]]) {
        str = [(NSAttributedString*)string string];
    } else if ([string isKindOfClass:[NSString class]]) {
        str = (NSString*)string;
    }
    if (str && [str length] > 0) {
        const char* utf8 = [str UTF8String];
        [self sendTextToFocused:utf8 len:strlen(utf8) modifiers:[NSApp currentEvent].modifierFlags];
    }
}

- (void)doCommandBySelector:(SEL)selector {
    // Handle special keys: backspace, arrows, etc.
    if (selector == @selector(deleteBackward:)) {
        [self sendKeyPress:nana::keyboard::backspace];
    } else if (selector == @selector(deleteForward:)) {
        [self sendKeyPress:nana::keyboard::del];
    } else if (selector == @selector(insertTab:)) {
        [self sendKeyPress:nana::keyboard::tab];
    } else if (selector == @selector(insertNewline:) || selector == @selector(insertLineBreak:)) {
        [self sendKeyPress:nana::keyboard::enter];
    } else if (selector == @selector(moveLeft:)) {
        [self sendKeyPress:nana::keyboard::os_arrow_left];
    } else if (selector == @selector(moveRight:)) {
        [self sendKeyPress:nana::keyboard::os_arrow_right];
    } else if (selector == @selector(moveUp:)) {
        [self sendKeyPress:nana::keyboard::os_arrow_up];
    } else if (selector == @selector(moveDown:)) {
        [self sendKeyPress:nana::keyboard::os_arrow_down];
    } else if (selector == @selector(cancelOperation:)) {
        [self sendKeyPress:nana::keyboard::escape];
    } else {
        // Unknown command (punctuation etc.) - try sending as text via insertText path
        NSEvent* evt = [NSApp currentEvent];
        NSString* chars = evt ? [evt characters] : nil;
        if (chars && [chars length] > 0) {
            [self insertText:chars replacementRange:NSMakeRange(NSNotFound, 0)];
        }
    }
}

// NSTextInputClient protocol (minimal implementation for IME support)
- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    // Store marked text state for IME (visual preview only, NOT inserted into document)
    if ([string isKindOfClass:[NSAttributedString class]]) {
        self.markedText = (NSAttributedString*)string;
    } else if ([string isKindOfClass:[NSString class]]) {
        self.markedText = [[NSAttributedString alloc] initWithString:(NSString*)string];
    }
    self.imeMarkedRange = NSMakeRange(0, self.markedText.length);
    self.imeSelectedRange = selectedRange;
    // Marked text is NOT sent to the nana widget — only insertText: commits real text
}

- (void)unmarkText {
    self.markedText = nil;
    self.imeMarkedRange = NSMakeRange(NSNotFound, 0);
}

- (NSRange)selectedRange { return self.imeSelectedRange; }
- (BOOL)hasMarkedText { return self.markedText != nil && self.markedText.length > 0; }
- (NSRange)markedRange { return self.imeMarkedRange; }
- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange { return nil; }
- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    // Return the caret rect in screen coords so IME candidate window appears below cursor
    NSRect caretRect = NSMakeRect(_caretPos.x, _caretPos.y,
                                   _caretSize.width > 0 ? _caretSize.width : 2, _caretSize.height);
    NSRect winRect = [self convertRect:caretRect toView:nil];
    return [self.window convertRectToScreen:winRect];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)point { return NSNotFound; }

@end

// ============ NanaNSWindow ============
@interface NanaNSWindow : NSWindow
@end
@implementation NanaNSWindow
- (void)sendEvent:(NSEvent *)event {
    NSEventType type = event.type;
    if ((type == NSEventTypeLeftMouseDown || type == NSEventTypeRightMouseDown || type == NSEventTypeOtherMouseDown)
        && ![self isKeyWindow]) {
        [self makeKeyAndOrderFront:nil];
    }
    [super sendEvent:event];
}
@end

// ============ NanaNSWindowDelegate ============
@interface NanaNSWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic) void* nanaRoot;
@end
@implementation NanaNSWindowDelegate
- (BOOL)windowShouldClose:(NSWindow*)sender {
    if (_nanaRoot) {
        auto& b = nana::detail::bedrock::instance();
        auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRoot);
        if (rw) {
            nana::arg_unload arg; arg.window_handle = rw; arg.cancel = false;
            b.emit(nana::event_code::unload, rw, arg, true, b.get_thread_context(rw->thread_id));
            if (!arg.cancel) nana::detail::native_interface::close_window((nana::native_window_type)_nanaRoot);
            return NO;
        }
    }
    return YES;
}
- (void)windowDidResize:(NSNotification*)n {
    if (!_nanaRoot) return;
    NSWindow* win = [n object];
    NSRect frame = [win contentRectForFrameRect:[win frame]];
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRoot);
    if (rw) b.wd_manager().size(rw, nana::size((unsigned)frame.size.width, (unsigned)frame.size.height), true, true);
}
- (void)windowDidBecomeKey:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRoot); if (rw) b.event_focus_changed(rw, (nana::native_window_type)_nanaRoot, true); }
}
- (void)windowDidResignKey:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRoot); if (rw) b.event_focus_changed(rw, nullptr, false); }
}
- (void)windowDidMiniaturize:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRoot); if (rw) b.event_expose(rw, false); }
}
- (void)windowDidDeminiaturize:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRoot); if (rw) b.event_expose(rw, true); }
}
@end

// ============ Window data storage ============
namespace {
    struct cocoa_wd { NSWindow* win; NanaNSView* view; NanaNSWindowDelegate* del; nana::native_window_type owner; bool visible; };
    std::recursive_mutex wd_mutex;
    std::map<nana::native_window_type, cocoa_wd> wd_map;
    cocoa_wd* gwd(nana::native_window_type w) { auto it = wd_map.find(w); return (it != wd_map.end()) ? &it->second : nullptr; }
}

// ============ Native control helpers ============
extern "C" {
void* nana_macos_create_native_button(void* parent_native, void* bwd_ptr, int x, int y, unsigned w, unsigned h, const char* title) {
    cocoa_wd* pd = gwd((nana::native_window_type)parent_native);
    NSView* pv = pd ? pd->view : nil;
    if (!pv) return nullptr;
    NSRect frame = NSMakeRect((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h);
    NSButton* btn = [[NSButton alloc] initWithFrame:frame];
    [btn setTitle:[NSString stringWithUTF8String:title ?: ""]];
    [btn setBezelStyle:NSBezelStyleRounded];
    [btn setButtonType:NSButtonTypeMomentaryPushIn];
    NanaButtonTarget* tgt = [[NanaButtonTarget alloc] init];
    tgt.basicWindow = bwd_ptr;
    [btn setTarget:tgt];
    [btn setAction:@selector(onClick:)];
    objc_setAssociatedObject(btn, (const void*)"_tgt", tgt, OBJC_ASSOCIATION_RETAIN);
    [pv addSubview:btn];
    { std::lock_guard<std::recursive_mutex> lk(native_ctrl_mutex); native_controls[bwd_ptr] = btn; }
    [btn release];
    return (void*)btn;
}
void nana_macos_update_native_control(void* bwd_ptr, int x, int y, unsigned w, unsigned h, const char* title) {
    std::lock_guard<std::recursive_mutex> lk(native_ctrl_mutex);
    auto it = native_controls.find(bwd_ptr);
    if (it == native_controls.end()) return;
    NSView* view = it->second;
    NSRect frame = NSMakeRect((CGFloat)x, (CGFloat)y, (CGFloat)w, (CGFloat)h);
    [view setFrame:frame];
    if (title && [view isKindOfClass:[NSButton class]])
        [(NSButton*)view setTitle:[NSString stringWithUTF8String:title]];
}
} // extern "C"

namespace nana { namespace detail {

void native_interface::affinity_execute(native_window_type wd, const std::function<void()>& fn) {
    if (!fn) return;
    cocoa_wd* d = gwd(wd);
    if (d && d->view) dispatch_async(dispatch_get_main_queue(), ^{ fn(); });
    else fn();
}

nana::size native_interface::primary_monitor_size() {
    NSRect f = [[NSScreen mainScreen] frame];
    return nana::size((unsigned)f.size.width, (unsigned)f.size.height);
}

rectangle native_interface::screen_area_from_point(const point& pos) {
    return rectangle{primary_monitor_size()};
}

native_interface::window_result native_interface::create_window(
    native_window_type owner, bool nested, const rectangle& r, const appearance& app)
{
    @autoreleasepool {
        std::lock_guard<std::recursive_mutex> lk(wd_mutex);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        if (app.sizable) style |= NSWindowStyleMaskResizable;
        if (app.minimize) style |= NSWindowStyleMaskMiniaturizable;

        NSScreen* sc = [NSScreen mainScreen];
        CGFloat cy = [sc frame].size.height - r.y - r.height;
        NSRect cr = NSMakeRect((CGFloat)r.x, cy, (CGFloat)r.width, (CGFloat)r.height);
        NanaNSWindow* win = [[NanaNSWindow alloc] initWithContentRect:cr styleMask:style backing:NSBackingStoreBuffered defer:NO];
        if (!win) return {nullptr, 0, 0, 0, 0};

        [win setTitle:@"Nana Window"];
        [win setReleasedWhenClosed:NO];

        NanaNSView* view = [[NanaNSView alloc] initWithFrame:[[win contentView] bounds]];
        [win setContentView:view];
        [view release];

        NanaNSWindowDelegate* del = [[NanaNSWindowDelegate alloc] init];
        [win setDelegate:del];

        native_window_type h = reinterpret_cast<native_window_type>((__bridge void*)win);
        cocoa_wd d; d.win = win; d.view = view; d.del = del; d.owner = owner; d.visible = false;
        wd_map[h] = d;
        view.nanaWindow = h; view.nanaRootWindow = h;
        del.nanaRoot = h;

        window_result res = {h, r.width, r.height, 0, 0};
        platform_spec::instance().msg_insert(h);
        return res;
    }
}

native_window_type native_interface::create_child_window(native_window_type parent, const rectangle& r) { return nullptr; }

void native_interface::enable_dropfiles(native_window_type w, bool enb) {}
void native_interface::enable_window(native_window_type w, bool enb) {
    cocoa_wd* d = gwd(w);
    if (d && d->win) [d->win setIgnoresMouseEvents:!enb];
}
bool native_interface::window_icon(native_window_type, const paint::image&, const paint::image&) { return false; }
void native_interface::activate_owner(native_window_type w) {}
void native_interface::activate_window(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (d && d->win) [d->win makeKeyAndOrderFront:nil];
}
void native_interface::close_window(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (!d) return;
    bool was_win = (d->win != nullptr);
    if (d->win) {
        [d->win setDelegate:nil];
        [d->del release]; d->del = nil;
        [d->win close];
        [d->win release]; d->win = nil; d->view = nil;
    } else if (d->view) { [d->view removeFromSuperview]; d->view = nil; }
    { std::lock_guard<std::recursive_mutex> lk(wd_mutex); wd_map.erase(w); }
    platform_spec::instance().remove(w);
    if (was_win) {
        bool has = false;
        for (auto& kv : wd_map) if (kv.second.win) { has = true; break; }
        if (!has) [NSApp terminate:nil];
    }
}
void native_interface::show_window(native_window_type w, bool show, bool active) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win || !d->view) return;
    d->visible = show;
    if (show) {
        if (active) {
            [NSApp activateIgnoringOtherApps:YES];
            [d->win makeKeyAndOrderFront:nil];
            [d->win makeMainWindow];
        } else [d->win orderFront:nil];
        auto* rw = bedrock::instance().wd_manager().root(w);
        if (rw) bedrock::instance().event_expose(rw, true);
    } else {
        [d->win orderOut:nil];
        auto* rw = bedrock::instance().wd_manager().root(w);
        if (rw) bedrock::instance().event_expose(rw, false);
    }
}
void native_interface::restore_window(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (d && d->win && [d->win isMiniaturized]) [d->win deminiaturize:nil];
}
void native_interface::zoom_window(native_window_type w, bool max) {
    cocoa_wd* d = gwd(w);
    if (d && d->win) [d->win zoom:nil];
}
void native_interface::refresh_window(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (d && d->view) { [d->view setNeedsDisplay:YES]; return; }
    // Child widget (label, etc.): force a full root refresh
    // do_lazy_refresh with refresh_tree=true repaints all children and composites to root pixmap
    auto* rw = bedrock::instance().wd_manager().root(w);
    if (rw) {
        bedrock::instance().wd_manager().do_lazy_refresh(rw, true, true);
        cocoa_wd* rd = gwd(rw->root);
        if (rd && rd->view) [rd->view setNeedsDisplay:YES];
    }
}
bool native_interface::is_window(native_window_type w) { return gwd(w) != nullptr; }
bool native_interface::is_window_visible(native_window_type w) { auto* d = gwd(w); return d ? d->visible : false; }
bool native_interface::is_window_zoomed(native_window_type w, bool max) {
    auto* d = gwd(w);
    if (!d || !d->win) return false;
    return [d->win isZoomed];
}
nana::point native_interface::window_position(native_window_type w) {
    auto* d = gwd(w);
    if (!d || !d->win) return {};
    NSRect f = [d->win frame];
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    return {(int)f.origin.x, (int)([sc frame].size.height - f.origin.y - f.size.height)};
}
void native_interface::move_window(native_window_type w, int x, int y) {
    auto* d = gwd(w);
    if (!d || !d->win) return;
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    CGFloat cy = [sc frame].size.height - y - [d->win frame].size.height;
    [d->win setFrameOrigin:NSMakePoint((CGFloat)x, cy)];
}
bool native_interface::move_window(native_window_type w, const rectangle& r) {
    auto* d = gwd(w);
    if (!d || !d->win) return false;
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    CGFloat cy = [sc frame].size.height - r.y - r.height;
    [d->win setFrame:NSMakeRect((CGFloat)r.x, cy, (CGFloat)r.width, (CGFloat)r.height) display:YES];
    return true;
}
void native_interface::bring_top(native_window_type w, bool act) {
    auto* d = gwd(w);
    if (!d || !d->win) return;
    if (act) { [d->win makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
    else [d->win orderFront:nil];
}
void native_interface::set_window_z_order(native_window_type w, native_window_type after, z_order_action act) {}
native_interface::frame_extents native_interface::window_frame_extents(native_window_type w) { return {0,0,0,0}; }
bool native_interface::window_size(native_window_type w, const size& sz) {
    auto* d = gwd(w);
    if (!d || !d->win) return false;
    NSRect f = [d->win frame];
    [d->win setFrame:NSMakeRect(f.origin.x, f.origin.y, (CGFloat)sz.width, (CGFloat)sz.height) display:YES];
    return true;
}
void native_interface::get_window_rect(native_window_type w, rectangle& r) {
    auto* d = gwd(w);
    if (!d || !d->win) { r = {}; return; }
    NSRect f = [d->win frame];
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    r.x = (int)f.origin.x; r.width = (unsigned)f.size.width; r.height = (unsigned)f.size.height;
    r.y = (int)([sc frame].size.height - f.origin.y - f.size.height);
}
void native_interface::window_caption(native_window_type w, const native_string_type& t) {
    auto* d = gwd(w);
    if (d && d->win) [d->win setTitle:[NSString stringWithUTF8String:t.c_str()]];
    else {
        auto it = native_controls.find((void*)w);
        if (it != native_controls.end() && [it->second isKindOfClass:[NSButton class]])
            [(NSButton*)it->second setTitle:[NSString stringWithUTF8String:t.c_str()]];
    }
}
auto native_interface::window_caption(native_window_type w) -> native_string_type {
    auto* d = gwd(w);
    if (d && d->win && [d->win title]) return [[d->win title] UTF8String] ?: "";
    auto it = native_controls.find((void*)w);
    if (it != native_controls.end() && [it->second isKindOfClass:[NSButton class]])
        return [[(NSButton*)it->second title] UTF8String] ?: "";
    return "";
}
void native_interface::capture_window(native_window_type, bool) {}
nana::point native_interface::cursor_position() {
    NSPoint loc = [NSEvent mouseLocation];
    NSRect sf = [[NSScreen mainScreen] frame];
    return {(int)loc.x, (int)(sf.size.height - loc.y)};
}
native_window_type native_interface::get_window(native_window_type w, window_relationship rsp) { return nullptr; }
native_window_type native_interface::parent_window(native_window_type child, native_window_type np, bool ret_prev) { return nullptr; }
void native_interface::caret_create(native_window_type w, const ::nana::size& sz) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->view) return;
    NanaNSView* view = (NanaNSView*)d->view;
    view.caretSize = NSMakeSize((CGFloat)sz.width, (CGFloat)sz.height);
    view.caretVisible = YES;
    // Start blinking timer if not already running
    if (!view.caretTimer) {
        view.caretTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer* t){
            view.caretVisible = !view.caretVisible;
            [view setNeedsDisplay:YES];
        }];
    }
}
void native_interface::caret_destroy(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->view) return;
    NanaNSView* view = (NanaNSView*)d->view;
    [view.caretTimer invalidate];
    view.caretTimer = nil;
    view.caretVisible = NO;
    view.caretSize = NSZeroSize;
    [view setNeedsDisplay:YES];
}
void native_interface::caret_pos(native_window_type w, const point& pos) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->view) return;
    NanaNSView* view = (NanaNSView*)d->view;
    view.caretPos = NSMakePoint((CGFloat)pos.x, (CGFloat)pos.y);
    if (view.caretVisible) [view setNeedsDisplay:YES];
}
void native_interface::caret_visible(native_window_type w, bool vis) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->view) return;
    NanaNSView* view = (NanaNSView*)d->view;
    view.caretVisible = vis;
    [view setNeedsDisplay:YES];
}
void native_interface::set_focus(native_window_type w) {
    auto* d = gwd(w);
    if (d && d->win) [d->win makeFirstResponder:d->view];
}
native_window_type native_interface::get_focus_window() { return nullptr; }
bool native_interface::calc_screen_point(native_window_type w, nana::point& pos) { return false; }
bool native_interface::calc_window_point(native_window_type w, nana::point& pos) { return false; }
native_window_type native_interface::find_window(int x, int y) { return nullptr; }
nana::size native_interface::check_track_size(nana::size sz, unsigned, unsigned, bool) { return sz; }

}} // namespace
#endif
