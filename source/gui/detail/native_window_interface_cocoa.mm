/*
 *	Native Window Interface — Cocoa (macOS) Backend
 *	Nana C++ Library
 *	Implements real NSWindow/NSView-based window management
 */
#if defined(NANA_COCOA)
#include <nana/gui/detail/native_window_interface.hpp>
#include <nana/gui/screen.hpp>
#include <nana/gui/detail/bedrock.hpp>
#include <nana/gui/detail/window_manager.hpp>
#include "../../detail/platform_spec_selector.hpp"
#import <Cocoa/Cocoa.h>
#include <map>
#include <mutex>

// ===================================================================
// NanaNSView — Custom NSView
// ===================================================================
@interface NanaNSView : NSView
@property (nonatomic) void* nanaWindow;
@property (nonatomic) void* nanaRootWindow;
- (nana::point)cvtPt:(NSPoint)pt {
    return nana::point((int)pt.x, (int)(self.bounds.size.height - pt.y));
}
- (void)mouseDown:(NSEvent*)e { [self forwardMouse:e type:0]; }
- (void)mouseUp:(NSEvent*)e { [self forwardMouse:e type:1]; }
- (void)rightMouseDown:(NSEvent*)e { [self forwardMouse:e type:2]; }
- (void)rightMouseUp:(NSEvent*)e { [self forwardMouse:e type:3]; }
- (void)mouseMoved:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)mouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)rightMouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)scrollWheel:(NSEvent*)e { [self forwardMouse:e type:5]; }
- (void)forwardMouse:(NSEvent*)e type:(int)t {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return;
    NSPoint loc = [self convertPoint:[e locationInWindow] fromView:nil];
    nana::point pt = [self cvtPt:loc];
    auto* tw = b.wd_manager().find_window((nana::detail::native_window_type)_nanaRootWindow, pt);
    if (!tw) tw = rw;
    nana::arg_mouse arg; arg.window_handle = tw;
    arg.pos.x = (int)loc.x - tw->pos_root.x;
    arg.pos.y = (int)(self.bounds.size.height - loc.y) - tw->pos_root.y;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.left_button=arg.right_button=arg.mid_button=false;
    if(t==0){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::left_button;arg.left_button=true;tw->set_action(nana::mouse_action::pressed);b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==1){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::left_button;tw->set_action(nana::mouse_action::normal);b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));nana::arg_click ca;ca.window_handle=tw;ca.mouse_args=&arg;b.emit(nana::event_code::click,tw,ca,true,b.get_thread_context(tw->thread_id));b.wd_manager().do_lazy_refresh(tw,false);}
    else if(t==2){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::right_button;arg.right_button=true;b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==3){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::right_button;b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==4){arg.evt_code=nana::event_code::mouse_move;b.emit(nana::event_code::mouse_move,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==5){nana::arg_wheel wa;wa.window_handle=tw;wa.evt_code=nana::event_code::mouse_wheel;wa.pos=arg.pos;wa.upwards=([e scrollingDeltaY]>0);wa.distance=120;wa.which=nana::arg_wheel::wheel::vertical;b.emit(nana::event_code::mouse_wheel,tw,wa,true,b.get_thread_context(tw->thread_id));}
    [self setNeedsDisplay:YES];
}
- (void)keyDown:(NSEvent*)e {
    if (!_nanaRootWindow) { [self interpretKeyEvents:@[e]]; return; }
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) { [self interpretKeyEvents:@[e]]; return; }
    auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_press;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_press, fw, arg, true, b.get_thread_context(fw->thread_id));
    b.wd_manager().do_lazy_refresh(fw, false);
    [self interpretKeyEvents:@[e]];
}
- (void)keyUp:(NSEvent*)e {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_release;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_release, fw, arg, true, b.get_thread_context(fw->thread_id));
}
- (void)insertText:(id)str replacementRange:(NSRange)rr {
    if ([str isKindOfClass:[NSString class]] && _nanaRootWindow) {
        auto& b = nana::detail::bedrock::instance();
        auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
        if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
        nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_char;
        arg.key = [(NSString*)str characterAtIndex:0]; arg.ignore = false;
        b.emit(nana::event_code::key_char, fw, arg, true, b.get_thread_context(fw->thread_id));
        b.wd_manager().do_lazy_refresh(fw, false);
    }
}
@end

@implementation NanaNSView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    if (_nanaRootWindow) {
        auto& brock = nana::detail::bedrock::instance();
        auto* rootWidget = brock.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
        if (rootWidget && rootWidget->root_graph) {
            NSGraphicsContext* nsCtx = [NSGraphicsContext currentContext];
            CGContextRef cg = [nsCtx CGContext];
            auto* dw = rootWidget->root_graph->handle();
            if (dw) { dw->context = (void*)cg; dw->pixmap = nullptr; }
            nana::rectangle ua((int)dirtyRect.origin.x,
                (int)(self.bounds.size.height - dirtyRect.origin.y - dirtyRect.size.height),
                (unsigned)dirtyRect.size.width, (unsigned)dirtyRect.size.height);
            rootWidget->drawer.map(rootWidget, true, &ua);
        }
    }
}
- (nana::point)cvtPt:(NSPoint)pt {
    return nana::point((int)pt.x, (int)(self.bounds.size.height - pt.y));
}
- (void)mouseDown:(NSEvent*)e { [self forwardMouse:e type:0]; }
- (void)mouseUp:(NSEvent*)e { [self forwardMouse:e type:1]; }
- (void)rightMouseDown:(NSEvent*)e { [self forwardMouse:e type:2]; }
- (void)rightMouseUp:(NSEvent*)e { [self forwardMouse:e type:3]; }
- (void)mouseMoved:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)mouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)rightMouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)scrollWheel:(NSEvent*)e { [self forwardMouse:e type:5]; }
- (void)forwardMouse:(NSEvent*)e type:(int)t {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return;
    NSPoint loc = [self convertPoint:[e locationInWindow] fromView:nil];
    nana::point pt = [self cvtPt:loc];
    auto* tw = b.wd_manager().find_window((nana::detail::native_window_type)_nanaRootWindow, pt);
    if (!tw) tw = rw;
    nana::arg_mouse arg; arg.window_handle = tw;
    arg.pos.x = (int)loc.x - tw->pos_root.x;
    arg.pos.y = (int)(self.bounds.size.height - loc.y) - tw->pos_root.y;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.left_button=arg.right_button=arg.mid_button=false;
    if(t==0){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::left_button;arg.left_button=true;tw->set_action(nana::mouse_action::pressed);b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==1){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::left_button;tw->set_action(nana::mouse_action::normal);b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));nana::arg_click ca;ca.window_handle=tw;ca.mouse_args=&arg;b.emit(nana::event_code::click,tw,ca,true,b.get_thread_context(tw->thread_id));b.wd_manager().do_lazy_refresh(tw,false);}
    else if(t==2){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::right_button;arg.right_button=true;b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==3){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::right_button;b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==4){arg.evt_code=nana::event_code::mouse_move;b.emit(nana::event_code::mouse_move,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==5){nana::arg_wheel wa;wa.window_handle=tw;wa.evt_code=nana::event_code::mouse_wheel;wa.pos=arg.pos;wa.upwards=([e scrollingDeltaY]>0);wa.distance=120;wa.which=nana::arg_wheel::wheel::vertical;b.emit(nana::event_code::mouse_wheel,tw,wa,true,b.get_thread_context(tw->thread_id));}
    [self setNeedsDisplay:YES];
}
- (void)keyDown:(NSEvent*)e {
    if (!_nanaRootWindow) { [self interpretKeyEvents:@[e]]; return; }
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) { [self interpretKeyEvents:@[e]]; return; }
    auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_press;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_press, fw, arg, true, b.get_thread_context(fw->thread_id));
    b.wd_manager().do_lazy_refresh(fw, false);
    [self interpretKeyEvents:@[e]];
}
- (void)keyUp:(NSEvent*)e {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_release;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_release, fw, arg, true, b.get_thread_context(fw->thread_id));
}
- (void)insertText:(id)str replacementRange:(NSRange)rr {
    if ([str isKindOfClass:[NSString class]] && _nanaRootWindow) {
        auto& b = nana::detail::bedrock::instance();
        auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
        if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
        nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_char;
        arg.key = [(NSString*)str characterAtIndex:0]; arg.ignore = false;
        b.emit(nana::event_code::key_char, fw, arg, true, b.get_thread_context(fw->thread_id));
        b.wd_manager().do_lazy_refresh(fw, false);
    }
}
@end

// ===================================================================
// NanaNSWindowDelegate
// ===================================================================
@interface NanaNSWindowDelegate : NSObject <NSWindowDelegate>
@property (nonatomic) void* nanaRoot;
- (nana::point)cvtPt:(NSPoint)pt {
    return nana::point((int)pt.x, (int)(self.bounds.size.height - pt.y));
}
- (void)mouseDown:(NSEvent*)e { [self forwardMouse:e type:0]; }
- (void)mouseUp:(NSEvent*)e { [self forwardMouse:e type:1]; }
- (void)rightMouseDown:(NSEvent*)e { [self forwardMouse:e type:2]; }
- (void)rightMouseUp:(NSEvent*)e { [self forwardMouse:e type:3]; }
- (void)mouseMoved:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)mouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)rightMouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)scrollWheel:(NSEvent*)e { [self forwardMouse:e type:5]; }
- (void)forwardMouse:(NSEvent*)e type:(int)t {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return;
    NSPoint loc = [self convertPoint:[e locationInWindow] fromView:nil];
    nana::point pt = [self cvtPt:loc];
    auto* tw = b.wd_manager().find_window((nana::detail::native_window_type)_nanaRootWindow, pt);
    if (!tw) tw = rw;
    nana::arg_mouse arg; arg.window_handle = tw;
    arg.pos.x = (int)loc.x - tw->pos_root.x;
    arg.pos.y = (int)(self.bounds.size.height - loc.y) - tw->pos_root.y;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.left_button=arg.right_button=arg.mid_button=false;
    if(t==0){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::left_button;arg.left_button=true;tw->set_action(nana::mouse_action::pressed);b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==1){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::left_button;tw->set_action(nana::mouse_action::normal);b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));nana::arg_click ca;ca.window_handle=tw;ca.mouse_args=&arg;b.emit(nana::event_code::click,tw,ca,true,b.get_thread_context(tw->thread_id));b.wd_manager().do_lazy_refresh(tw,false);}
    else if(t==2){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::right_button;arg.right_button=true;b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==3){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::right_button;b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==4){arg.evt_code=nana::event_code::mouse_move;b.emit(nana::event_code::mouse_move,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==5){nana::arg_wheel wa;wa.window_handle=tw;wa.evt_code=nana::event_code::mouse_wheel;wa.pos=arg.pos;wa.upwards=([e scrollingDeltaY]>0);wa.distance=120;wa.which=nana::arg_wheel::wheel::vertical;b.emit(nana::event_code::mouse_wheel,tw,wa,true,b.get_thread_context(tw->thread_id));}
    [self setNeedsDisplay:YES];
}
- (void)keyDown:(NSEvent*)e {
    if (!_nanaRootWindow) { [self interpretKeyEvents:@[e]]; return; }
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) { [self interpretKeyEvents:@[e]]; return; }
    auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_press;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_press, fw, arg, true, b.get_thread_context(fw->thread_id));
    b.wd_manager().do_lazy_refresh(fw, false);
    [self interpretKeyEvents:@[e]];
}
- (void)keyUp:(NSEvent*)e {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_release;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_release, fw, arg, true, b.get_thread_context(fw->thread_id));
}
- (void)insertText:(id)str replacementRange:(NSRange)rr {
    if ([str isKindOfClass:[NSString class]] && _nanaRootWindow) {
        auto& b = nana::detail::bedrock::instance();
        auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
        if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
        nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_char;
        arg.key = [(NSString*)str characterAtIndex:0]; arg.ignore = false;
        b.emit(nana::event_code::key_char, fw, arg, true, b.get_thread_context(fw->thread_id));
        b.wd_manager().do_lazy_refresh(fw, false);
    }
}
@end

@implementation NanaNSWindowDelegate
- (BOOL)windowShouldClose:(NSWindow*)sender {
    if (_nanaRoot) {
        auto& brock = nana::detail::bedrock::instance();
        auto* rw = brock.wd_manager().root((nana::detail::native_window_type)_nanaRoot);
        if (rw) {
            nana::arg_unload arg; arg.window_handle = rw; arg.cancel = false;
            brock.emit(nana::event_code::unload, rw, arg, true, brock.get_thread_context(rw->thread_id));
            if (!arg.cancel) nana::detail::native_interface::close_window((nana::detail::native_window_type)_nanaRoot);
            return NO;
        }
    }
    return YES;
}
- (void)windowDidResize:(NSNotification*)n {
    if (!_nanaRoot) return;
    NSWindow* win = [n object];
    NSRect frame = [win contentRectForFrameRect:[win frame]];
    auto& brock = nana::detail::bedrock::instance();
    auto* rw = brock.wd_manager().root((nana::detail::native_window_type)_nanaRoot);
    if (rw) brock.wd_manager().size(rw, nana::size((unsigned)frame.size.width, (unsigned)frame.size.height), true, true);
    [[win contentView] setNeedsDisplay:YES];
}
- (void)windowDidBecomeKey:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRoot); if (rw) b.event_focus_changed(rw, (nana::detail::native_window_type)_nanaRoot, true); }
}
- (void)windowDidResignKey:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRoot); if (rw) b.event_focus_changed(rw, nullptr, false); }
}
- (void)windowDidMiniaturize:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRoot); if (rw) b.event_expose(rw, false); }
}
- (void)windowDidDeminiaturize:(NSNotification*)n {
    if (_nanaRoot) { auto& b = nana::detail::bedrock::instance(); auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRoot); if (rw) b.event_expose(rw, true); }
}
- (nana::point)cvtPt:(NSPoint)pt {
    return nana::point((int)pt.x, (int)(self.bounds.size.height - pt.y));
}
- (void)mouseDown:(NSEvent*)e { [self forwardMouse:e type:0]; }
- (void)mouseUp:(NSEvent*)e { [self forwardMouse:e type:1]; }
- (void)rightMouseDown:(NSEvent*)e { [self forwardMouse:e type:2]; }
- (void)rightMouseUp:(NSEvent*)e { [self forwardMouse:e type:3]; }
- (void)mouseMoved:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)mouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)rightMouseDragged:(NSEvent*)e { [self forwardMouse:e type:4]; }
- (void)scrollWheel:(NSEvent*)e { [self forwardMouse:e type:5]; }
- (void)forwardMouse:(NSEvent*)e type:(int)t {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return;
    NSPoint loc = [self convertPoint:[e locationInWindow] fromView:nil];
    nana::point pt = [self cvtPt:loc];
    auto* tw = b.wd_manager().find_window((nana::detail::native_window_type)_nanaRootWindow, pt);
    if (!tw) tw = rw;
    nana::arg_mouse arg; arg.window_handle = tw;
    arg.pos.x = (int)loc.x - tw->pos_root.x;
    arg.pos.y = (int)(self.bounds.size.height - loc.y) - tw->pos_root.y;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.left_button=arg.right_button=arg.mid_button=false;
    if(t==0){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::left_button;arg.left_button=true;tw->set_action(nana::mouse_action::pressed);b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==1){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::left_button;tw->set_action(nana::mouse_action::normal);b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));nana::arg_click ca;ca.window_handle=tw;ca.mouse_args=&arg;b.emit(nana::event_code::click,tw,ca,true,b.get_thread_context(tw->thread_id));b.wd_manager().do_lazy_refresh(tw,false);}
    else if(t==2){arg.evt_code=nana::event_code::mouse_down;arg.button=nana::mouse::right_button;arg.right_button=true;b.emit(nana::event_code::mouse_down,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==3){arg.evt_code=nana::event_code::mouse_up;arg.button=nana::mouse::right_button;b.emit(nana::event_code::mouse_up,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==4){arg.evt_code=nana::event_code::mouse_move;b.emit(nana::event_code::mouse_move,tw,arg,true,b.get_thread_context(tw->thread_id));}
    else if(t==5){nana::arg_wheel wa;wa.window_handle=tw;wa.evt_code=nana::event_code::mouse_wheel;wa.pos=arg.pos;wa.upwards=([e scrollingDeltaY]>0);wa.distance=120;wa.which=nana::arg_wheel::wheel::vertical;b.emit(nana::event_code::mouse_wheel,tw,wa,true,b.get_thread_context(tw->thread_id));}
    [self setNeedsDisplay:YES];
}
- (void)keyDown:(NSEvent*)e {
    if (!_nanaRootWindow) { [self interpretKeyEvents:@[e]]; return; }
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) { [self interpretKeyEvents:@[e]]; return; }
    auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_press;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_press, fw, arg, true, b.get_thread_context(fw->thread_id));
    b.wd_manager().do_lazy_refresh(fw, false);
    [self interpretKeyEvents:@[e]];
}
- (void)keyUp:(NSEvent*)e {
    if (!_nanaRootWindow) return;
    auto& b = nana::detail::bedrock::instance();
    auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
    if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
    nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_release;
    arg.key = [[e characters] length]>0 ? [[e characters] characterAtIndex:0] : 0;
    NSUInteger fl = [NSEvent modifierFlags];
    arg.alt=(fl&NSEventModifierFlagOption)!=0; arg.ctrl=(fl&NSEventModifierFlagControl)!=0; arg.shift=(fl&NSEventModifierFlagShift)!=0;
    arg.ignore = false;
    b.emit(nana::event_code::key_release, fw, arg, true, b.get_thread_context(fw->thread_id));
}
- (void)insertText:(id)str replacementRange:(NSRange)rr {
    if ([str isKindOfClass:[NSString class]] && _nanaRootWindow) {
        auto& b = nana::detail::bedrock::instance();
        auto* rw = b.wd_manager().root((nana::detail::native_window_type)_nanaRootWindow);
        if (!rw) return; auto* fw = b.focus(); if (!fw) fw = rw;
        nana::arg_keyboard arg; arg.window_handle = fw; arg.evt_code = nana::event_code::key_char;
        arg.key = [(NSString*)str characterAtIndex:0]; arg.ignore = false;
        b.emit(nana::event_code::key_char, fw, arg, true, b.get_thread_context(fw->thread_id));
        b.wd_manager().do_lazy_refresh(fw, false);
    }
}
@end

// ===================================================================
// Window data storage
// ===================================================================
namespace {
    struct cocoa_wd {
        NSWindow* win;
        NanaNSView* view;
        NanaNSWindowDelegate* del;
        nana::detail::native_window_type owner;
        bool visible;
    };
    std::recursive_mutex wd_mutex;
    std::map<nana::detail::native_window_type, cocoa_wd> wd_map;

    cocoa_wd* gwd(nana::detail::native_window_type w) {
        auto it = wd_map.find(w); return (it != wd_map.end()) ? &it->second : nullptr;
    }
}

namespace nana { namespace detail {

void native_interface::affinity_execute(native_window_type wd, const std::function<void()>& fn) {
    if (!fn) return;
    cocoa_wd* d = gwd(wd);
    if (d && d->view) { dispatch_async(dispatch_get_main_queue(), ^{ fn(); }); }
    else fn();
}

nana::size native_interface::primary_monitor_size() {
    NSRect f = [[NSScreen mainScreen] frame];
    return nana::size((unsigned)f.size.width, (unsigned)f.size.height);
}

rectangle native_interface::screen_area_from_point(const point& pos) {
    NSArray* screens = [NSScreen screens];
    for (NSScreen* s in screens) {
        NSRect f = [s frame];
        if (pos.x >= f.origin.x && pos.x < f.origin.x+f.size.width &&
            pos.y >= f.origin.y && pos.y < f.origin.y+f.size.height) {
            NSRect vf = [s visibleFrame];
            return rectangle((int)vf.origin.x, (int)(f.size.height - vf.origin.y - vf.size.height),
                             (unsigned)vf.size.width, (unsigned)vf.size.height);
        }
    }
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
        NSRect sf = [sc frame];
        CGFloat cy = sf.size.height - r.y - r.height;

        NSRect cr = NSMakeRect((CGFloat)r.x, cy, (CGFloat)r.width, (CGFloat)r.height);
        NSWindow* win = [[NSWindow alloc] initWithContentRect:cr styleMask:style
            backing:NSBackingStoreBuffered defer:NO];
        if (!win) return {nullptr, 0, 0, 0, 0};

        [win setTitle:@"Nana Window"];
        [win setReleasedWhenClosed:NO];

        NanaNSView* view = [[NanaNSView alloc] initWithFrame:[[win contentView] bounds]];
        [win setContentView:view];
        [view release];

        NanaNSWindowDelegate* del = [[NanaNSWindowDelegate alloc] init];
        [win setDelegate:del];

        if (app.floating) [win setLevel:NSFloatingWindowLevel];
        if (!nested && owner) {
            cocoa_wd* od = gwd(owner);
            if (od && od->win) [od->win addChildWindow:win ordered:NSWindowAbove];
        }

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

native_window_type native_interface::create_child_window(native_window_type parent, const rectangle& r) {
    if (!parent) return nullptr;
    cocoa_wd* pd = gwd(parent);
    if (!pd || !pd->view) return nullptr;
    @autoreleasepool {
        NSView* pv = pd->view;
        NSRect cf = NSMakeRect((CGFloat)r.x, pv.bounds.size.height - r.y - r.height,
                                (CGFloat)r.width, (CGFloat)r.height);
        NanaNSView* cv = [[NanaNSView alloc] initWithFrame:cf];
        [pv addSubview:cv];
        native_window_type h = reinterpret_cast<native_window_type>((__bridge void*)cv);
        cocoa_wd d; d.win = nullptr; d.view = cv; d.del = nullptr; d.owner = parent; d.visible = true;
        wd_map[h] = d;
        cv.nanaWindow = h; cv.nanaRootWindow = pd->del ? parent : nullptr;
        [cv release];
        return h;
    }
}

void native_interface::enable_dropfiles(native_window_type w, bool enb) {
    cocoa_wd* d = gwd(w);
    if (d && d->view) {
        if (enb) [d->view registerForDraggedTypes:@[NSFilenamesPboardType]];
        else [d->view unregisterDraggedTypes];
    }
}
void native_interface::enable_window(native_window_type w, bool enb) {
    cocoa_wd* d = gwd(w);
    if (d && d->win) [d->win setIgnoresMouseEvents:!enb];
}
bool native_interface::window_icon(native_window_type, const paint::image&, const paint::image&) { return false; }
void native_interface::activate_owner(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (d && d->owner) { cocoa_wd* od = gwd(d->owner); if (od && od->win) [od->win makeKeyAndOrderFront:nil]; }
}
void native_interface::activate_window(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (d && d->win) [d->win makeKeyAndOrderFront:nil];
}
void native_interface::close_window(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (!d) return;
    if (d->win) { [d->win setDelegate:nil]; [d->del release]; [d->win close]; [d->win release]; }
    else if (d->view) { [d->view removeFromSuperview]; }
    { std::lock_guard<std::recursive_mutex> lk(wd_mutex); wd_map.erase(w); }
    platform_spec::instance().remove(w);
}
void native_interface::show_window(native_window_type w, bool show, bool active) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return;
    d->visible = show;
    if (show) {
        if (active) [d->win makeKeyAndOrderFront:nil]; else [d->win orderFront:nil];
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
    if (d && d->win) { if (max) [d->win zoom:nil]; else [d->win miniaturize:nil]; }
}
void native_interface::refresh_window(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (d && d->view) [d->view setNeedsDisplay:YES];
}
bool native_interface::is_window(native_window_type w) { return gwd(w) != nullptr; }
bool native_interface::is_window_visible(native_window_type w) {
    cocoa_wd* d = gwd(w); return d ? d->visible : false;
}
bool native_interface::is_window_zoomed(native_window_type w, bool max) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return false;
    return max ? [d->win isZoomed] : [d->win isMiniaturized];
}
nana::point native_interface::window_position(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return {};
    NSRect f = [d->win frame];
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    return {(int)f.origin.x, (int)([sc frame].size.height - f.origin.y - f.size.height)};
}
void native_interface::move_window(native_window_type w, int x, int y) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return;
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    CGFloat cy = [sc frame].size.height - y - [d->win frame].size.height;
    [d->win setFrameOrigin:NSMakePoint((CGFloat)x, cy)];
}
bool native_interface::move_window(native_window_type w, const rectangle& r) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return false;
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    CGFloat cy = [sc frame].size.height - r.y - r.height;
    [d->win setFrame:NSMakeRect((CGFloat)r.x, cy, (CGFloat)r.width, (CGFloat)r.height) display:YES];
    return true;
}
void native_interface::bring_top(native_window_type w, bool act) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return;
    if (act) { [d->win makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
    else [d->win orderFront:nil];
}
void native_interface::set_window_z_order(native_window_type w, native_window_type after, z_order_action act) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return;
    if (!after) {
        switch (act) {
        case z_order_action::bottom: [d->win orderBack:nil]; break;
        case z_order_action::top: case z_order_action::foreground: case z_order_action::topmost:
            [d->win orderFront:nil]; break;
        default: break;
        }
    }
}
native_interface::frame_extents native_interface::window_frame_extents(native_window_type w) {
    frame_extents e = {0,0,0,0};
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return e;
    NSRect f = [d->win frame], c = [d->win contentRectForFrameRect:f];
    e.left = (int)(c.origin.x - f.origin.x);
    e.top = (int)((f.origin.y+f.size.height) - (c.origin.y+c.size.height));
    e.right = (int)((f.origin.x+f.size.width) - (c.origin.x+c.size.width));
    e.bottom = (int)(c.origin.y - f.origin.y);
    return e;
}
bool native_interface::window_size(native_window_type w, const size& sz) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) return false;
    NSRect f = [d->win frame];
    [d->win setFrame:NSMakeRect(f.origin.x, f.origin.y, (CGFloat)sz.width, (CGFloat)sz.height) display:YES];
    return true;
}
void native_interface::get_window_rect(native_window_type w, rectangle& r) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->win) { r = {}; return; }
    NSRect f = [d->win frame];
    NSScreen* sc = [d->win screen] ?: [NSScreen mainScreen];
    r.x = (int)f.origin.x; r.width = (unsigned)f.size.width; r.height = (unsigned)f.size.height;
    r.y = (int)([sc frame].size.height - f.origin.y - f.size.height);
}
void native_interface::window_caption(native_window_type w, const native_string_type& t) {
    cocoa_wd* d = gwd(w);
    if (d && d->win) [d->win setTitle:[NSString stringWithUTF8String:t.c_str()]];
}
auto native_interface::window_caption(native_window_type w) -> native_string_type {
    cocoa_wd* d = gwd(w);
    if (d && d->win && [d->win title]) return [[d->win title] UTF8String] ?: "";
    return "";
}
void native_interface::capture_window(native_window_type, bool) {}
nana::point native_interface::cursor_position() {
    NSPoint loc = [NSEvent mouseLocation];
    NSRect sf = [[NSScreen mainScreen] frame];
    return {(int)loc.x, (int)(sf.size.height - loc.y)};
}
native_window_type native_interface::get_window(native_window_type w, window_relationship rsp) {
    cocoa_wd* d = gwd(w);
    if (!d) return nullptr;
    if (rsp == window_relationship::owner) return d->owner;
    if (rsp == window_relationship::parent || rsp == window_relationship::either_po) {
        if (d->win) {
            NSWindow* p = [d->win parentWindow];
            if (p) { for (auto& kv : wd_map) if (kv.second.win == p) return kv.first; }
        }
        return d->owner;
    }
    return nullptr;
}
native_window_type native_interface::parent_window(native_window_type child, native_window_type np, bool ret_prev) {
    cocoa_wd* cd = gwd(child);
    if (!cd || !cd->view) return nullptr;
    native_window_type prev = nullptr;
    if (np) {
        cocoa_wd* nd = gwd(np);
        if (nd && nd->view) {
            if (ret_prev) {
                NSView* sv = [cd->view superview];
                for (auto& kv : wd_map) if (kv.second.view == sv) { prev = kv.first; break; }
            }
            [nd->view addSubview:cd->view];
        }
    }
    return prev;
}
void native_interface::caret_create(native_window_type w, const ::nana::size& sz) { platform_spec::instance().caret_open(w, sz); }
void native_interface::caret_destroy(native_window_type w) { platform_spec::instance().caret_close(w); }
void native_interface::caret_pos(native_window_type w, const point& pos) { platform_spec::instance().caret_pos(w, pos); }
void native_interface::caret_visible(native_window_type w, bool vis) { platform_spec::instance().caret_visible(w, vis); }
void native_interface::set_focus(native_window_type w) {
    cocoa_wd* d = gwd(w);
    if (d && d->win) [d->win makeFirstResponder:d->view];
}
native_window_type native_interface::get_focus_window() {
    NSWindow* kw = [NSApp keyWindow];
    if (kw) { for (auto& kv : wd_map) if (kv.second.win == kw) return kv.first; }
    return nullptr;
}
bool native_interface::calc_screen_point(native_window_type w, nana::point& pos) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->view || ![d->view window]) return false;
    NSRect vf = [d->view convertRect:d->view.bounds toView:nil];
    NSRect wf = [[d->view window] convertRectToScreen:vf];
    NSScreen* sc = [[d->view window] screen] ?: [NSScreen mainScreen];
    pos.x = (int)(wf.origin.x + pos.x);
    pos.y = (int)([sc frame].size.height - wf.origin.y - pos.y);
    return true;
}
bool native_interface::calc_window_point(native_window_type w, nana::point& pos) {
    cocoa_wd* d = gwd(w);
    if (!d || !d->view || ![d->view window]) return false;
    NSRect sf = [[NSScreen mainScreen] frame];
    NSPoint cp = NSMakePoint((CGFloat)pos.x, sf.size.height - pos.y);
    NSPoint wp = [[d->view window] convertScreenToBase:cp];
    NSPoint vp = [d->view convertPoint:wp fromView:nil];
    pos.x = (int)vp.x; pos.y = (int)(d->view.bounds.size.height - vp.y);
    return true;
}
native_window_type native_interface::find_window(int x, int y) {
    NSRect sf = [[NSScreen mainScreen] frame];
    NSPoint cp = NSMakePoint((CGFloat)x, sf.size.height - y);
    for (auto& kv : wd_map) {
        if (kv.second.view && [kv.second.view window]) {
            NSPoint vp = [kv.second.view convertPoint:cp fromView:nil];
            if ([kv.second.view hitTest:vp]) return kv.first;
        }
    }
    NSInteger wn = [NSWindow windowNumberAtPoint:cp belowWindowWithWindowNumber:0];
    NSWindow* win = [NSApp windowWithWindowNumber:wn];
    if (win) { for (auto& kv : wd_map) if (kv.second.win == win) return kv.first; }
    return nullptr;
}
nana::size native_interface::check_track_size(nana::size sz, unsigned, unsigned, bool) { return sz; }

}} // namespace
#endif
