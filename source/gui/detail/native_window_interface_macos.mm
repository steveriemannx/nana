#include <nana/gui/detail/native_window_interface.hpp>
#include <nana/gui/screen.hpp>
#include <nana/gui/detail/bedrock.hpp>
#include <nana/gui/detail/window_manager.hpp>
#include "../../detail/platform_spec_selector.hpp"
#include "../detail/basic_window.hpp"
#import <Cocoa/Cocoa.h>
#include <map>
#include <mutex>

#if defined(NANA_MACOS)

// Forward declare keyboard lookup and hover tracking (implemented in bedrock_macos.mm)
namespace nana { namespace detail {
    struct root_misc;
    void cocoa_lookup_chars(const root_misc*, basic_window*, const char*, std::size_t, const arg_keyboard&);
    bool cocoa_mouse_hover(native_window_type, basic_window*, const nana::point&);
    void cocoa_mouse_leave(native_window_type);
    wchar_t cocoa_key_from_keycode(unsigned short keyCode);
    wchar_t cocoa_key_from_function_char(const char* utf8, std::size_t len);
    bool cocoa_translate_accel(native_window_type, const void* nsevent);
}}

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
// Modifier state of the previous flagsChanged: event, for detecting which
// modifier was pressed or released.
@property (nonatomic) NSUInteger lastModifierFlags;
@property (nonatomic) BOOL hasLastModifierFlags;
// Private helpers, declared here so they can be used before their definitions.
- (void)forwardMouse:(NSEvent*)e type:(int)t;
- (nana::point)cvtPt:(NSPoint)pt;
- (BOOL)updateHoverAt:(NSPoint)loc;
- (void)sendKeyEvent:(wchar_t)key pressed:(BOOL)down;
- (wchar_t)nanaKeyForEvent:(NSEvent*)event;
- (void)resetModifierState;
@end

@implementation NanaNSView
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return YES; }

// Without this, AppKit swallows the click that reactivates an inactive window
// (the default is to only activate). Clicking a nana widget while another nana
// popup, e.g. a combobox drop-down, is the key window would then do nothing.
- (BOOL)acceptsFirstMouse:(NSEvent*)event { (void)event; return YES; }

// Start from a clean modifier baseline so the first flagsChanged: after gaining
// focus reports a real transition instead of being discarded.
- (BOOL)becomeFirstResponder {
    [self resetModifierState];
    return [super becomeFirstResponder];
}

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

// AppKit clears the tracking areas before calling this, so re-establish ours.
// Without a tracking area the view receives neither mouseMoved: nor the
// enter/exit events, which leaves widget hover state stuck.
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea* ta in [self trackingAreas])
        [self removeTrackingArea:ta];
    NSTrackingArea* area = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                      NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:area];
    [area release];
}

// Resolve the widget under a view-space point and drive nana's hover state.
// Returns YES when the hovered widget changed.
- (BOOL)updateHoverAt:(NSPoint)loc {
    if (!_nanaRootWindow) return NO;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRootWindow);
    if (!rw) return NO;
    nana::point pt = [self cvtPt:loc];
    auto* tw = b.wd_manager().find_window((nana::native_window_type)_nanaRootWindow, pt);
    return nana::detail::cocoa_mouse_hover((nana::native_window_type)_nanaRootWindow, tw ? tw : rw, pt) ? YES : NO;
}

- (void)mouseEntered:(NSEvent*)e {
    [self updateHoverAt:[self convertPoint:[e locationInWindow] fromView:nil]];
}
- (void)mouseExited:(NSEvent*)e {
    nana::detail::cocoa_mouse_leave((nana::native_window_type)_nanaRootWindow);
}

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
    BOOL hover_changed = NO;
    // A double click *replaces* mouse_down, matching WM_LBUTTONDBLCLK on Windows
    // and the POSIX backend: the first press of the pair already delivered a
    // normal mouse_down, so widgets see down, up, dbl_click, up.
    if(t==0){bool dbl=([e clickCount]>=2)&&tw->flags.dbl_click;arg.evt_code=dbl?nana::event_code::dbl_click:nana::event_code::mouse_down;arg.button=nana::mouse::left_button;arg.left_button=true;tw->set_action(nana::mouse_action::pressed);b.wd_manager().set_focus(tw,false,nana::arg_focus::reason::mouse_press);b.emit(arg.evt_code,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==1){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::left_button;tw->set_action(nana::mouse_action::normal);b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));nana::arg_click ca;ca.window_handle=tw;ca.mouse_args=&arg;b.emit(nana::event_code::click,tw,ca,true,b.get_thread_context(tw->thread_id));}
    else if(t==2){bool dbl=([e clickCount]>=2)&&tw->flags.dbl_click;arg.evt_code=dbl?nana::event_code::dbl_click:nana::event_code::mouse_down;arg.button=nana::mouse::right_button;arg.right_button=true;b.emit(arg.evt_code,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==3){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::right_button;b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==4){hover_changed=[self updateHoverAt:loc];arg.evt_code=nana::event_code::mouse_move;b.emit(nana::event_code::mouse_move,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==5){nana::arg_wheel wa;wa.window_handle=tw;wa.evt_code=nana::event_code::mouse_wheel;wa.pos=arg.pos;wa.upwards=([e scrollingDeltaY]>0);wa.distance=120;wa.which=nana::arg_wheel::wheel::vertical;b.emit(nana::event_code::mouse_wheel,tw,wa,true,b.get_thread_context(tw->thread_id));}
    // A plain mouse_move repaints only the widget itself (bedrock::emit does
    // that already). Repainting the whole widget tree on every move event is
    // needlessly expensive, so defer that to when the hovered widget changed.
    if(t==4 && !hover_changed) return;
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
    if (!_nanaRootWindow) { [super keyDown:event]; return; }

    // Accelerators first, matching bedrock_posix.cpp.
    if (nana::detail::cocoa_translate_accel((nana::native_window_type)_nanaRootWindow, (__bridge void*)event))
        return;

    // key_press for every key, mirroring WM_KEYDOWN. Safe alongside the
    // key_char emitted below: text_editor::respond_key ignores printable keys,
    // text insertion is driven by key_char.
    wchar_t key = [self nanaKeyForEvent:event];
    if (key) [self sendKeyEvent:key pressed:YES];

    // IME and key_char, unchanged.
    [self interpretKeyEvents:@[event]];
}

- (void)keyUp:(NSEvent *)event {
    wchar_t key = [self nanaKeyForEvent:event];
    if (key) [self sendKeyEvent:key pressed:NO];
    else [super keyUp:event];
}

// A modifier-only change never reaches keyDown:, so report the press/release of
// Shift/Ctrl/Option/Command from here.
- (void)flagsChanged:(NSEvent*)event {
    NSUInteger now = [event modifierFlags];
    if (!_hasLastModifierFlags) {
        // First event after gaining focus: record the state, report nothing.
        _lastModifierFlags = now;
        _hasLastModifierFlags = YES;
        return;
    }
    NSUInteger prev = _lastModifierFlags;
    _lastModifierFlags = now;

    const struct { NSUInteger mask; wchar_t key; } tbl[] = {
        { NSEventModifierFlagShift,   nana::keyboard::os_shift },
        { NSEventModifierFlagControl, nana::keyboard::os_ctrl  },
        { NSEventModifierFlagOption,  nana::keyboard::alt      },
        { NSEventModifierFlagCommand, nana::keyboard::os_ctrl  }, // Command -> nana's ctrl-modifier code
    };
    for (const auto& m : tbl) {
        bool was = (prev & m.mask) != 0;
        bool is  = (now  & m.mask) != 0;
        if (is && !was) [self sendKeyEvent:m.key pressed:YES];
        else if (!is && was) [self sendKeyEvent:m.key pressed:NO];
    }
}

// Seed the modifier baseline from the current state, so the next flagsChanged:
// reports a real transition.
- (void)resetModifierState {
    _lastModifierFlags = [NSEvent modifierFlags];
    _hasLastModifierFlags = YES;
}

// Translate an NSEvent to a nana key, preferring the virtual key code and
// falling back to the NSFunctionKeyRange characters.
- (wchar_t)nanaKeyForEvent:(NSEvent*)event {
    wchar_t key = nana::detail::cocoa_key_from_keycode([event keyCode]);
    if (!key) {
        const char* u = [[event charactersIgnoringModifiers] UTF8String];
        if (u) key = nana::detail::cocoa_key_from_function_char(u, ::strlen(u));
    }
    return key;
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

// Helper: emit key_press or key_release for the focused widget
- (void)sendKeyEvent:(wchar_t)key pressed:(BOOL)down {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRootWindow);
    if (!rw) return;
    auto* attr_root = rw->other.attribute.root;
    auto* focused = attr_root ? attr_root->focus : nullptr;
    if (!focused) focused = rw;

    NSUInteger fl = [NSEvent modifierFlags];
    nana::arg_keyboard arg;
    arg.evt_code = down ? nana::event_code::key_press : nana::event_code::key_release;
    arg.key = key;
    arg.window_handle = focused;
    arg.ignore = false;
    arg.alt   = (fl & NSEventModifierFlagOption) != 0;
    arg.ctrl  = (fl & NSEventModifierFlagControl) != 0;
    arg.shift = (fl & NSEventModifierFlagShift) != 0;
    auto* ctx = b.get_thread_context(focused->thread_id);
    b.emit(arg.evt_code, focused, arg, true, ctx);
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

// interpretKeyEvents: routes keys that produce no text here. key_press is now
// emitted from keyDown: as the single source (mirroring WM_KEYDOWN preceding
// WM_CHAR), so for the no-text keys below there is nothing left to do.
- (void)doCommandBySelector:(SEL)selector {
    if (selector == @selector(deleteBackward:)
        || selector == @selector(deleteForward:)
        || selector == @selector(insertTab:)
        || selector == @selector(insertBacktab:)
        || selector == @selector(insertNewline:)
        || selector == @selector(insertLineBreak:)
        || selector == @selector(moveLeft:)
        || selector == @selector(moveRight:)
        || selector == @selector(moveUp:)
        || selector == @selector(moveDown:)
        || selector == @selector(cancelOperation:))
        return;

    // Unknown command - try sending as text via insertText path
    NSEvent* evt = [NSApp currentEvent];
    NSString* chars = evt ? [evt characters] : nil;
    if (!chars || [chars length] == 0)
        return;

    // Never forward a key that produces no text: control characters (backspace
    // is 0x7F, return 0x0D, escape 0x1B, ...) and the NSFunctionKeyRange
    // (arrows, function keys, home/end/page). key_press already covered them.
    unichar c = [chars characterAtIndex:0];
    if (c < 0x20 || c == 0x7F || (c >= 0xF700 && c <= 0xF747))
        return;

    [self insertText:chars replacementRange:NSMakeRange(NSNotFound, 0)];
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

// NSDraggingDestination for file drop support
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard* pb = [sender draggingPasteboard];
    if ([pb.types containsObject:NSPasteboardTypeFileURL])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender { return [self draggingEntered:sender]; }
- (void)draggingExited:(id<NSDraggingInfo>)sender {}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender { return YES; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    if (!_nanaRootWindow) return NO;
    NSPasteboard* pb = [sender draggingPasteboard];
    NSArray* urls = [pb readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls || [urls count] == 0) return NO;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRootWindow);
    if (!rw) return NO;
    NSPoint loc = [self convertPoint:[sender draggingLocation] fromView:nil];
    nana::point pt((int)loc.x, (int)loc.y);
    auto* tw = b.wd_manager().find_window((nana::native_window_type)_nanaRootWindow, pt);
    if (!tw) tw = rw;
    std::vector<std::filesystem::path> files;
    for (NSURL* url in urls) {
        if ([url isFileURL]) {
            const char* path = [[url path] UTF8String];
            if (path) files.emplace_back(path);
        }
    }
    if (!files.empty()) {
        nana::arg_dropfiles arg;
        arg.window_handle = tw;
        arg.pos.x = (int)loc.x - tw->pos_root.x;
        arg.pos.y = (int)loc.y - tw->pos_root.y;
        arg.files.swap(files);
        tw->annex.events_ptr->mouse_dropfiles.emit(arg, tw);
        b.wd_manager().do_lazy_refresh(tw, false);
        [self setNeedsDisplay:YES];
        return YES;
    }
    return NO;
}
- (void)concludeDragOperation:(id<NSDraggingInfo>)sender {}

@end

// ============ NanaNSWindow ============
@interface NanaNSWindow : NSWindow
@end
@implementation NanaNSWindow
// A borderless window refuses key status by default, which would leave nana's
// popups (float_listbox such as a combobox drop-down, menus) unable to receive
// keyboard input. Windows' WS_POPUP windows can take focus, so allow it here.
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }
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
    if (_nanaRoot) {
        // NSTrackingActiveInKeyWindow delivers no mouseExited: when the window
        // stops being key, so clear the hover state explicitly.
        nana::detail::cocoa_mouse_leave((nana::native_window_type)_nanaRoot);
        auto& b = nana::detail::bedrock::instance();
        auto* rw = b.wd_manager().root((nana::native_window_type)_nanaRoot);
        if (rw) b.event_focus_changed(rw, nullptr, false);
    }
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

        // Mirrors the reference implementation in native_window_interface.cpp:
        // `decoration` decides whether the window gets a title bar, `floating`
        // raises it above normal windows, and the rect of a non-nested window is
        // relative to its owner's client area (there it is a ClientToScreen call).
        NSUInteger style = NSWindowStyleMaskBorderless;
        if (app.decoration)
        {
            // A titled NSWindow always draws all three traffic lights; the ones the
            // style mask does not enable come up greyed out. Windows and X11 take
            // `app.minimize` literally (an absent WS_MINIMIZEBOX greys the button
            // out), but on macOS that reads as a broken window, so a decorated
            // window always gets a working yellow button. `app.maximize` is already
            // a no-op here for the same reason: the green button is the platform's
            // zoom control and is governed by NSWindowStyleMaskResizable.
            style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
        }
        if (app.sizable) style |= NSWindowStyleMaskResizable;

        nana::point pt{ r.x, r.y };
        NSScreen* sc = [NSScreen mainScreen];
        if (owner && !nested)
        {
            cocoa_wd* od = gwd(owner);
            if (od && od->win)
            {
                // contentRectForFrameRect: already returns the content rect in
                // absolute screen coordinates, so it must not be offset by the
                // frame origin again.
                NSRect owner_content = [od->win contentRectForFrameRect:[od->win frame]];
                sc = [od->win screen] ?: sc;
                pt.x += static_cast<int>(owner_content.origin.x);
                pt.y += static_cast<int>([sc frame].size.height - owner_content.origin.y - owner_content.size.height);
            }
        }

        CGFloat cy = [sc frame].size.height - pt.y - r.height;
        NSRect cr = NSMakeRect((CGFloat)pt.x, cy, (CGFloat)r.width, (CGFloat)r.height);
        NanaNSWindow* win = [[NanaNSWindow alloc] initWithContentRect:cr styleMask:style backing:NSBackingStoreBuffered defer:NO];
        if (!win) return {nullptr, 0, 0, 0, 0};

        if (app.floating)
            [win setLevel:NSFloatingWindowLevel];

        [win setTitle:@"Nana Window"];
        [win setReleasedWhenClosed:NO];

        NanaNSView* view = [[NanaNSView alloc] initWithFrame:[[win contentView] bounds]];
        [win setContentView:view];
        [view registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
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
        if (!has) {
            // Wake the event loop so it can exit
            [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
                location:NSZeroPoint modifierFlags:0 timestamp:0
                windowNumber:0 context:nil subtype:0 data1:0 data2:0]
                atStart:YES];
            [NSApp terminate:nil];
        }
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
native_interface::frame_extents native_interface::window_frame_extents(native_window_type w) {
	frame_extents fm_extents{0, 0, 0, 0};
	auto* d = gwd(w);
	if (!d || !d->win) return fm_extents;
	NSRect frame = [d->win frame];
	NSRect content = [d->win contentRectForFrameRect:frame];
	fm_extents.bottom = (int)content.origin.y;
	fm_extents.top    = (int)(frame.size.height - (content.origin.y + content.size.height));
	fm_extents.left   = (int)content.origin.x;
	fm_extents.right  = (int)(frame.size.width - (content.origin.x + content.size.width));
	return fm_extents;
}
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
}
auto native_interface::window_caption(native_window_type w) -> native_string_type {
    auto* d = gwd(w);
    if (d && d->win && [d->win title]) return [[d->win title] UTF8String] ?: "";
    return "";
}
void native_interface::capture_window(native_window_type, bool) {}
void native_interface::set_modal(native_window_type wd) {
	cocoa_wd* d = gwd(wd);
	if (!d || !d->win) return;
	native_window_type owner = platform_spec::instance().get_owner(wd);
	if (owner) {
		cocoa_wd* owner_d = gwd(owner);
		if (owner_d && owner_d->win) {
			[owner_d->win beginSheet:d->win completionHandler:nil];
		}
	}
}
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
native_window_type native_interface::get_focus_window() {
	NSWindow* keyWin = [NSApp keyWindow];
	if (!keyWin) return nullptr;
	return reinterpret_cast<native_window_type>((__bridge void*)keyWin);
}
bool native_interface::calc_screen_point(native_window_type w, nana::point& pos) {
	auto* d = gwd(w);
	if (!d || !d->win) return false;
	NSRect content = [d->win contentRectForFrameRect:[d->win frame]];
	NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
	CGFloat screenH = [sc frame].size.height;
	// contentRectForFrameRect: is already absolute, do not add the frame origin.
	CGFloat winX = content.origin.x;
	CGFloat winY = content.origin.y;
	pos.x += (int)winX;
	pos.y += (int)(screenH - winY - content.size.height);
	return true;
}
bool native_interface::calc_window_point(native_window_type w, nana::point& pos) {
	auto* d = gwd(w);
	if (!d || !d->win) return false;
	NSRect content = [d->win contentRectForFrameRect:[d->win frame]];
	NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
	CGFloat screenH = [sc frame].size.height;
	// contentRectForFrameRect: is already absolute, do not add the frame origin.
	CGFloat winX = content.origin.x;
	CGFloat winY = content.origin.y;
	pos.x -= (int)winX;
	pos.y = (int)(screenH - pos.y - winY - content.size.height);
	return true;
}
native_window_type native_interface::find_window(int x, int y) {
	std::lock_guard<std::recursive_mutex> lk(wd_mutex);
	for (auto& kv : wd_map) {
		auto* d = &kv.second;
		if (!d->win || !d->visible) continue;
		NSRect frame = [d->win frame];
		NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
		CGFloat screenH = [sc frame].size.height;
		CGFloat macY = screenH - y - frame.size.height;
		if (x >= frame.origin.x && x < frame.origin.x + frame.size.width &&
			macY >= frame.origin.y && macY < frame.origin.y + frame.size.height)
			return kv.first;
	}
	return nullptr;
}
nana::size native_interface::check_track_size(nana::size sz, unsigned, unsigned, bool) { return sz; }

}} // namespace
#endif
