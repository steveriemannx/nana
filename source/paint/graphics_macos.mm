// CoreGraphics Cocoa drawing backend — complete implementation
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>
#include <nana/paint/graphics.hpp>
#include <nana/paint/detail/native_paint_interface.hpp>
#include "../detail/platform_abstraction.hpp"
#include "../detail/platform_spec_selector.hpp"
#include <algorithm>
#if defined(NANA_MACOS)
namespace nana { namespace paint {

static CGContextRef C(drawable_type d){return d?(CGContextRef)d->context:nullptr;}

// === font ===
struct font::impl_type{std::shared_ptr<font_interface> rf;};
font::font():impl_(new impl_type){impl_->rf=platform_abstraction::default_font(nullptr);}
font::font(drawable_type d):impl_(new impl_type){impl_->rf=d->font;}
font::font(const font&o):impl_(new impl_type){if(o.impl_)impl_->rf=o.impl_->rf;}
font::font(const std::string&s,double d,const font_style&fs):impl_(new impl_type){impl_->rf=platform_abstraction::make_font(s,d,fs);}
font::font(double d,const path_type&t,const font_style&fs):impl_(new impl_type){impl_->rf=platform_abstraction::make_font_from_ttf(t,d,fs);}
font::~font(){delete impl_;}
bool font::empty()const{return!impl_||!impl_->rf;}
void font::set_default()const{platform_abstraction::default_font(impl_->rf);}
std::string font::name()const{return impl_&&impl_->rf?impl_->rf->family():"";}
double font::size(bool)const{return impl_&&impl_->rf?impl_->rf->size():10.0;}
bool font::bold()const{return impl_&&impl_->rf&&impl_->rf->style().weight>=700;}
unsigned font::weight()const{return impl_&&impl_->rf?impl_->rf->style().weight:400u;}
bool font::italic()const{return impl_&&impl_->rf&&impl_->rf->style().italic;}
bool font::underline()const{return impl_&&impl_->rf&&impl_->rf->style().underline;}
bool font::strikeout()const{return impl_&&impl_->rf&&impl_->rf->style().strike_out;}
native_font_type font::handle()const{return impl_&&impl_->rf?impl_->rf->native_handle():nullptr;}
void font::release(){if(impl_)impl_->rf.reset();}
font&font::operator=(const font&o){if(this!=&o&&o.impl_)impl_->rf=o.impl_->rf;return*this;}
bool font::operator==(const font&o)const{return impl_->rf==o.impl_->rf;}
bool font::operator!=(const font&o)const{return!operator==(o);}

// === graphics ===
struct graphics::implementation{std::shared_ptr<::nana::detail::drawable_impl_type> pd;::nana::size sz;};
graphics::graphics():impl_(new implementation){}
graphics::graphics(const ::nana::size&s):impl_(new implementation){make(s);}
graphics::graphics(const graphics&o):impl_(new implementation){impl_->sz=o.impl_->sz;if(o.impl_->pd){make(o.impl_->sz);if(impl_->pd&&o.impl_->pd->pixmap){CGImageRef im=CGBitmapContextCreateImage((CGContextRef)o.impl_->pd->pixmap);if(im){CGContextDrawImage((CGContextRef)impl_->pd->pixmap,CGRectMake(0,0,impl_->sz.width,impl_->sz.height),im);CGImageRelease(im);}}}}
graphics&graphics::operator=(const graphics&o){if(this!=&o){impl_->sz=o.impl_->sz;impl_->pd=o.impl_->pd;}return*this;}
graphics::graphics(graphics&&o):impl_(std::move(o.impl_)){}
graphics&graphics::operator=(graphics&&o){if(this!=&o)impl_=std::move(o.impl_);return*this;}
graphics::~graphics(){}
bool graphics::changed()const{return impl_->pd&&impl_->pd->pixmap;}
bool graphics::empty()const{return!impl_->pd||!impl_->pd->pixmap;}
graphics::operator bool()const noexcept{return!empty();}
drawable_type graphics::handle()const{return impl_->pd.get();}
const void* graphics::pixmap()const{return impl_->pd&&impl_->pd->pixmap?impl_->pd->pixmap:nullptr;}
::nana::size graphics::size()const{return impl_->sz;}
unsigned graphics::width()const{return impl_->sz.width;}
unsigned graphics::height()const{return impl_->sz.height;}

void graphics::make(const ::nana::size&s){if(s.empty())return;impl_->sz=s;CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();size_t bpr=s.width*4;void*data=calloc(1,bpr*s.height);CGContextRef c=CGBitmapContextCreate(data,s.width,s.height,8,bpr,cs,kCGImageAlphaPremultipliedFirst|kCGBitmapByteOrder32Little);CGColorSpaceRelease(cs);if(!c){free(data);return;}auto*d=new ::nana::detail::drawable_impl_type();d->pixmap=(void*)c;d->context=(void*)c;d->string.tab_length=4;d->font=platform_abstraction::default_font(nullptr);CGContextTranslateCTM(c,0,(CGFloat)s.height);CGContextScaleCTM(c,1.0,-1.0);CGContextSetTextMatrix(c,CGAffineTransformMake(1,0,0,-1,0,0));CGContextSetRGBFillColor(c,1,1,1,1);CGContextFillRect(c,CGRectMake(0,0,s.width,s.height));impl_->pd=std::shared_ptr<::nana::detail::drawable_impl_type>(d,[](::nana::detail::drawable_impl_type*p){if(p){delete p;}});}
void graphics::resize(const ::nana::size&s){make(s);}
void graphics::flush(){}
void graphics::release(){impl_->pd.reset();}
void graphics::swap(graphics&o)noexcept{std::swap(impl_,o.impl_);}
void graphics::setsta(){}
::nana::color graphics::palette(bool)const{return ::nana::color{0,0,0};}
graphics&graphics::palette(bool f,const ::nana::color&c){if(impl_->pd){if(f)impl_->pd->set_text_color(c);else impl_->pd->set_color(c);}return*this;}
void graphics::typeface(const font&f){if(impl_->pd)impl_->pd->font=f.impl_->rf;}
font graphics::typeface()const{return impl_->pd?font(impl_->pd.get()):font{};}

void graphics::rectangle(bool solid){rectangle(::nana::rectangle{size()},solid);}
void graphics::rectangle(const ::nana::rectangle&r,bool solid){CGContextRef c=C(impl_->pd.get());if(!c)return;CGRect cr=CGRectMake(r.x,r.y,r.width,r.height);if(solid)CGContextFillRect(c,cr);else CGContextStrokeRect(c,cr);}
void graphics::rectangle(const ::nana::rectangle&r,bool solid,const ::nana::color&clr){palette(true,clr);rectangle(r,solid);}
void graphics::rectangle(bool solid,const ::nana::color&clr){palette(true,clr);rectangle(::nana::rectangle{size()},solid);}
void graphics::line(const ::nana::point&p1,const ::nana::point&p2){CGContextRef c=C(impl_->pd.get());if(!c)return;CGContextMoveToPoint(c,p1.x,p1.y);CGContextAddLineToPoint(c,p2.x,p2.y);CGContextStrokePath(c);}
void graphics::line(const ::nana::point&p1,const ::nana::point&p2,const ::nana::color&clr){palette(true,clr);line(p1,p2);}
void graphics::line_begin(int x,int y){if(impl_->pd)impl_->pd->line_begin_pos={x,y};}
void graphics::line_to(const ::nana::point&pos){CGContextRef c=C(impl_->pd.get());if(!c)return;auto&beg=impl_->pd->line_begin_pos;CGContextMoveToPoint(c,beg.x,beg.y);CGContextAddLineToPoint(c,pos.x,pos.y);CGContextStrokePath(c);beg=pos;}
void graphics::line_to(const ::nana::point&pos,const ::nana::color&clr){impl_->pd->set_color(clr);line_to(pos);}
void graphics::set_pixel(int x,int y){set_pixel(x,y,::nana::color(0,0,0));}
void graphics::set_pixel(int x,int y,const ::nana::color&clr){CGContextRef c=C(impl_->pd.get());if(!c)return;CGContextSetRGBFillColor(c,clr.r()/255.0,clr.g()/255.0,clr.b()/255.0,1);CGContextFillRect(c,CGRectMake(x,y,1,1));}

void graphics::round_rectangle(const ::nana::rectangle&r,unsigned ra,unsigned,const ::nana::color&bg,bool,const ::nana::color&){CGContextRef c=C(impl_->pd.get());if(!c)return;CGFloat ch=(CGFloat)CGBitmapContextGetHeight(c);CGFloat w=r.width,ht=r.height,rad=ra;CGFloat cgy=ch-r.y-ht;CGMutablePathRef p=CGPathCreateMutable();CGPathMoveToPoint(p,NULL,r.x+rad,cgy);CGPathAddLineToPoint(p,NULL,r.x+w-rad,cgy);CGPathAddArcToPoint(p,NULL,r.x+w,cgy,r.x+w,cgy+rad,rad);CGPathAddLineToPoint(p,NULL,r.x+w,cgy+ht-rad);CGPathAddArcToPoint(p,NULL,r.x+w,cgy+ht,r.x+w-rad,cgy+ht,rad);CGPathAddLineToPoint(p,NULL,r.x+rad,cgy+ht);CGPathAddArcToPoint(p,NULL,r.x,cgy+ht,r.x,cgy+ht-rad,rad);CGPathAddLineToPoint(p,NULL,r.x,cgy+rad);CGPathAddArcToPoint(p,NULL,r.x,cgy,r.x+rad,cgy,rad);CGPathCloseSubpath(p);CGContextAddPath(c,p);CGContextSetRGBFillColor(c,bg.r()/255.0,bg.g()/255.0,bg.b()/255.0,1);CGContextFillPath(c);CGPathRelease(p);}
void graphics::frame_rectangle(const ::nana::rectangle&r,const ::nana::color& l,const ::nana::color& t,const ::nana::color& rt,const ::nana::color& b){palette(true,l);line(::nana::point((int)r.x,(int)r.y),::nana::point((int)(r.x+r.width-1),(int)r.y));palette(true,t);line(::nana::point((int)(r.x+r.width-1),(int)r.y),::nana::point((int)(r.x+r.width-1),(int)(r.y+r.height-1)));palette(true,rt);line(::nana::point((int)(r.x+r.width-1),(int)(r.y+r.height-1)),::nana::point((int)r.x,(int)(r.y+r.height-1)));palette(true,b);line(::nana::point((int)r.x,(int)(r.y+r.height-1)),::nana::point((int)r.x,(int)r.y));}
void graphics::gradual_rectangle(const ::nana::rectangle&r,const ::nana::color&from,const ::nana::color&to,bool vert){
    CGContextRef c=C(impl_->pd.get());if(!c)return;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGFloat comps[]={from.r()/255.0f,from.g()/255.0f,from.b()/255.0f,1.0f,to.r()/255.0f,to.g()/255.0f,to.b()/255.0f,1.0f};
    CGGradientRef grad=CGGradientCreateWithColorComponents(cs,comps,NULL,2);
    CGColorSpaceRelease(cs);
    if(!grad)return;
    CGFloat ch=(CGFloat)CGBitmapContextGetHeight(c);
    CGContextDrawLinearGradient(c,grad,CGPointMake((CGFloat)r.x,ch-(CGFloat)r.y-(CGFloat)r.height),CGPointMake((CGFloat)r.x,ch-(CGFloat)r.y),0);
    CGGradientRelease(grad);
  }
void graphics::frame_rectangle(const ::nana::rectangle& r,const ::nana::color& clr,unsigned gap){palette(false,clr);if(r.width>gap*2){::nana::point left{r.x+static_cast<int>(gap),r.y},right_{r.right()-static_cast<int>(gap)-1,r.y};line(left,right_);left.y=right_.y=r.bottom()-1;line(left,right_);}if(r.height>gap*2){::nana::point top{r.x,r.y+static_cast<int>(gap)},bottom_{r.x,r.bottom()-static_cast<int>(gap)-1};line(top,bottom_);top.x=bottom_.x=r.right()-1;line(top,bottom_);}}
void graphics::rgb_to_wb(){CGContextRef c=C(impl_->pd.get());if(!c)return;unsigned char*data=(unsigned char*)CGBitmapContextGetData(c);size_t w=CGBitmapContextGetWidth(c);size_t h=CGBitmapContextGetHeight(c);size_t bpr=CGBitmapContextGetBytesPerRow(c);float tr[256],tg[256],tb[256];for(int i=0;i<256;++i){tr[i]=static_cast<float>(i*0.3f);tg[i]=static_cast<float>(i*0.59f);tb[i]=static_cast<float>(i*0.11f);}for(size_t y=0;y<h;++y){unsigned char*row=data+y*bpr;for(size_t x=0;x<w;++x){size_t off=x*4;unsigned char gray=static_cast<unsigned char>(tr[row[off+2]]+tg[row[off+1]]+tb[row[off]]+0.5f);row[off]=gray;row[off+1]=gray;row[off+2]=gray;}}}

void graphics::string(const ::nana::point&p,std::string_view s){if(impl_->pd){auto ws=nana::to_wstring(std::string(s));detail::draw_string(impl_->pd.get(),p,ws.c_str(),ws.size());}}
void graphics::string(const ::nana::point&p,std::wstring_view s){if(impl_->pd)detail::draw_string(impl_->pd.get(),p,s.data(),s.size());}
void graphics::string(const ::nana::point&p,std::string_view s,const ::nana::color&clr){palette(true,clr);string(p,s);}
void graphics::string(const ::nana::point&p,std::wstring_view s,const ::nana::color&clr){palette(true,clr);string(p,s);}
unsigned graphics::bidi_string(const ::nana::point&p,std::string_view s){string(p,s);return 0;}
unsigned graphics::bidi_string(const ::nana::point&p,std::wstring_view s){string(p,s);return 0;}

nana::size graphics::text_extent_size(std::string_view t)const{return impl_->pd ? detail::text_extent_size(impl_->pd.get(),t.data(),t.size()) : nana::size{};}
nana::size graphics::text_extent_size(std::wstring_view t)const{return impl_->pd ? detail::text_extent_size(impl_->pd.get(),t.data(),t.size()) : nana::size{};}
nana::size graphics::bidi_extent_size(std::string_view t)const{return text_extent_size(t);}
nana::size graphics::bidi_extent_size(std::wstring_view t)const{return text_extent_size(t);}
bool graphics::text_metrics(unsigned&a,unsigned&d,unsigned&l)const{a=10;d=2;l=0;if(impl_->pd&&impl_->pd->font){CTFontRef f=(CTFontRef)impl_->pd->font->native_handle();if(f){a=(unsigned)CTFontGetAscent(f);d=(unsigned)CTFontGetDescent(f);l=(unsigned)CTFontGetLeading(f);}}return true;}

void graphics::paste(native_window_type wd,int x,int y,unsigned w,unsigned h,int dx,int dy)const{
    if(!impl_->pd||!C(impl_->pd.get())||!wd)return;
    NSView* view=(__bridge NSView*)(void*)wd;if(!view)return;
    NSBitmapImageRep* rep=[view bitmapImageRepForCachingDisplayInRect:NSMakeRect((CGFloat)x,(CGFloat)y,(CGFloat)w,(CGFloat)h)];
    if(!rep)return;[view cacheDisplayInRect:NSMakeRect((CGFloat)x,(CGFloat)y,(CGFloat)w,(CGFloat)h) toBitmapImageRep:rep];
    CGImageRef im=[rep CGImage];if(!im)return;
    CGContextRef ctx=C(impl_->pd.get());CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx,0,(CGFloat)dy+(CGFloat)h);CGContextScaleCTM(ctx,1.0,-1.0);
    CGContextDrawImage(ctx,CGRectMake((CGFloat)dx,0,(CGFloat)w,(CGFloat)h),im);CGContextRestoreGState(ctx);
  }
void graphics::paste(drawable_type dt,int x,int y)const{
    if(!impl_->pd||!C(impl_->pd.get())||!dt||!dt->pixmap)return;
    CGImageRef im=CGBitmapContextCreateImage((CGContextRef)dt->pixmap);if(!im)return;
    size_t dw=CGBitmapContextGetWidth((CGContextRef)dt->pixmap);
    size_t dh=CGBitmapContextGetHeight((CGContextRef)dt->pixmap);
    CGContextRef ctx=C(impl_->pd.get());CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx,0,(CGFloat)(y+dh));CGContextScaleCTM(ctx,1.0,-1.0);
    CGContextDrawImage(ctx,CGRectMake((CGFloat)x,0,(CGFloat)dw,(CGFloat)dh),im);
    CGContextRestoreGState(ctx);CGImageRelease(im);
  }
void graphics::paste(const ::nana::rectangle&r,graphics&d,int x,int y)const{if(!d.impl_->pd||!C(d.impl_->pd.get()))return;if(!impl_->pd||!impl_->pd->pixmap)return;CGImageRef im=CGBitmapContextCreateImage((CGContextRef)impl_->pd->pixmap);if(im){auto ctx=C(d.impl_->pd.get());CGContextSaveGState(ctx);CGContextTranslateCTM(ctx,0,y+r.height);CGContextScaleCTM(ctx,1.0,-1.0);CGContextDrawImage(ctx,CGRectMake(x,0,r.width,r.height),im);CGContextRestoreGState(ctx);CGImageRelease(im);}}
void graphics::paste(graphics&d,int x,int y)const{if(!impl_->pd||!C(impl_->pd.get()))return;if(!d.impl_->pd||!d.impl_->pd->pixmap)return;CGImageRef im=CGBitmapContextCreateImage((CGContextRef)d.impl_->pd->pixmap);if(im){auto ctx=C(impl_->pd.get());CGContextSaveGState(ctx);CGContextTranslateCTM(ctx,0,y+d.impl_->sz.height);CGContextScaleCTM(ctx,1.0,-1.0);CGContextDrawImage(ctx,CGRectMake(x,0,d.impl_->sz.width,d.impl_->sz.height),im);CGContextRestoreGState(ctx);CGImageRelease(im);}}
void graphics::paste(native_window_type wd,const ::nana::rectangle&r,int x,int y)const{
    if(!impl_->pd||!C(impl_->pd.get())||!wd)return;
    NSView* view=(__bridge NSView*)(void*)wd;if(!view)return;
    NSBitmapImageRep* rep=[view bitmapImageRepForCachingDisplayInRect:NSMakeRect((CGFloat)r.x,(CGFloat)r.y,(CGFloat)r.width,(CGFloat)r.height)];
    if(!rep)return;[view cacheDisplayInRect:NSMakeRect((CGFloat)r.x,(CGFloat)r.y,(CGFloat)r.width,(CGFloat)r.height) toBitmapImageRep:rep];
    CGImageRef im=[rep CGImage];if(!im)return;
    CGContextRef ctx=C(impl_->pd.get());CGContextSaveGState(ctx);
    CGContextTranslateCTM(ctx,0,(CGFloat)(y+r.height));CGContextScaleCTM(ctx,1.0,-1.0);
    CGContextDrawImage(ctx,CGRectMake((CGFloat)x,0,(CGFloat)r.width,(CGFloat)r.height),im);CGContextRestoreGState(ctx);
  }

void graphics::bitblt(int x,int y,const graphics&src){const_cast<graphics*>(this)->paste(const_cast<graphics&>(src),x,y);}
void graphics::bitblt(const ::nana::rectangle&r,native_window_type wd){
    const_cast<graphics*>(this)->paste(wd,r.x,r.y,r.width,r.height,r.x,r.y);
  }
void graphics::bitblt(const ::nana::rectangle&r,native_window_type wd,const point&p){
    const_cast<graphics*>(this)->paste(wd,p.x,p.y,r.width,r.height,r.x,r.y);
  }
void graphics::bitblt(const ::nana::rectangle&r,const graphics&s){
	nana::rectangle local_src(0, 0, r.width, r.height);
	const_cast<graphics&>(s).paste(local_src, *this, r.x, r.y);
}
void graphics::bitblt(const ::nana::rectangle&r,const graphics&s,const point&p){
	// Source uses (0,0)-based coords. Dest uses top-left via paste flip.
	nana::rectangle local_src(0, 0, r.width, r.height);
	const_cast<graphics&>(s).paste(local_src, *this, r.x, r.y);
}
void graphics::stretch(const ::nana::rectangle&src_r,graphics&dst,const ::nana::rectangle&dst_r)const{
    if(!impl_->pd||!impl_->pd->pixmap||!dst.impl_->pd||!dst.impl_->pd->pixmap)return;
    CGImageRef im=CGBitmapContextCreateImage((CGContextRef)impl_->pd->pixmap);if(!im)return;
    CGContextRef ctx=C(dst.impl_->pd.get());CGFloat ch=(CGFloat)CGBitmapContextGetHeight(ctx);
    CGContextSaveGState(ctx);CGContextTranslateCTM(ctx,0,ch-(CGFloat)(dst_r.y+dst_r.height));CGContextScaleCTM(ctx,1.0,-1.0);
    CGContextDrawImage(ctx,CGRectMake((CGFloat)dst_r.x,(CGFloat)dst_r.y,(CGFloat)dst_r.width,(CGFloat)dst_r.height),im);
    CGContextRestoreGState(ctx);CGImageRelease(im);
  }
void graphics::stretch(graphics&dst,const ::nana::rectangle&r)const{
    stretch(::nana::rectangle{size()},dst,r);
  }
void graphics::blend(const ::nana::rectangle&r,const ::nana::color&clr,double alpha){
    CGContextRef c=C(impl_->pd.get());if(!c)return;
    CGContextSaveGState(c);CGContextSetRGBFillColor(c,(CGFloat)clr.r()/255.0,(CGFloat)clr.g()/255.0,(CGFloat)clr.b()/255.0,(CGFloat)alpha);
    CGContextFillRect(c,CGRectMake((CGFloat)r.x,(CGFloat)r.y,(CGFloat)r.width,(CGFloat)r.height));CGContextRestoreGState(c);
  }
void graphics::blend(const ::nana::rectangle&r,const graphics&src,const point&,double alpha){
    if(!impl_->pd||!impl_->pd->pixmap||!src.impl_->pd||!src.impl_->pd->pixmap)return;
    CGImageRef im=CGBitmapContextCreateImage((CGContextRef)src.impl_->pd->pixmap);if(!im)return;
    CGContextRef ctx=C(impl_->pd.get());CGFloat ch=(CGFloat)CGBitmapContextGetHeight(ctx);
    CGContextSaveGState(ctx);CGContextSetAlpha(ctx,(CGFloat)alpha);
    CGContextTranslateCTM(ctx,0,ch-(CGFloat)(r.y+r.height));CGContextScaleCTM(ctx,1.0,-1.0);
    CGContextDrawImage(ctx,CGRectMake((CGFloat)r.x,(CGFloat)r.y,(CGFloat)r.width,(CGFloat)r.height),im);
    CGContextRestoreGState(ctx);CGImageRelease(im);
  }
void graphics::blur(const ::nana::rectangle&r,std::size_t radius){
    if(!impl_->pd||!impl_->pd->pixmap||radius<1)return;
    unsigned char* data=(unsigned char*)CGBitmapContextGetData((CGContextRef)impl_->pd->pixmap);if(!data)return;
    size_t w=CGBitmapContextGetWidth((CGContextRef)impl_->pd->pixmap);
    size_t h=CGBitmapContextGetHeight((CGContextRef)impl_->pd->pixmap);
    size_t bpr=CGBitmapContextGetBytesPerRow((CGContextRef)impl_->pd->pixmap);
    int rx=(int)r.x,ry=(int)r.y,rw=(int)r.width,rh=(int)r.height;
    if(rx<0)rx=0;if(ry<0)ry=0;if(rx+rw>(int)w)rw=(int)w-rx;if(ry+rh>(int)h)rh=(int)h-ry;
    if(rw<1||rh<1)return;
    size_t rad=radius>20?20:radius;
    std::vector<unsigned char> buf(rw*rh*4),tmp(rw*rh*4);
    for(int y=0;y<rh;++y)for(int x=0;x<rw;++x){
        size_t off=((size_t)(ry+y))*bpr+((size_t)(rx+x))*4;
        tmp[y*rw*4+x*4]=data[off];tmp[y*rw*4+x*4+1]=data[off+1];tmp[y*rw*4+x*4+2]=data[off+2];
    }
    for(int y=0;y<rh;++y)for(int x=0;x<rw;++x){
        unsigned sr=0,sg=0,sb=0,count=0;
        for(int dy=(int)(y>rad?y-rad:0);dy<=y+(int)rad&&dy<rh;++dy)
        for(int dx=(int)(x>rad?x-rad:0);dx<=x+(int)rad&&dx<rw;++dx){
            size_t soff=dy*rw*4+dx*4;sr+=tmp[soff+2];sg+=tmp[soff+1];sb+=tmp[soff];++count;
        }
        if(count){size_t off=y*rw*4+x*4;buf[off]=(unsigned char)(sb/count);buf[off+1]=(unsigned char)(sg/count);buf[off+2]=(unsigned char)(sr/count);}
    }
    for(int y=0;y<rh;++y)for(int x=0;x<rw;++x){
        size_t doff=((size_t)(ry+y))*bpr+((size_t)(rx+x))*4;size_t soff=y*rw*4+x*4;
        data[doff]=buf[soff];data[doff+1]=buf[soff+1];data[doff+2]=buf[soff+2];
    }
  }

void graphics::save_as_file(const char* file_utf8) const noexcept{
	if(!impl_->pd||!impl_->pd->pixmap)return;
	CGImageRef im=CGBitmapContextCreateImage((CGContextRef)impl_->pd->pixmap);
	if(!im)return;
	CFStringRef path=CFStringCreateWithCString(NULL,file_utf8,kCFStringEncodingUTF8);
	CFURLRef url=CFURLCreateWithFileSystemPath(NULL,path,kCFURLPOSIXPathStyle,false);
	CFRelease(path);
	if(url){CGImageDestinationRef dest=CGImageDestinationCreateWithURL(url,CFSTR("public.png"),1,NULL);CFRelease(url);
		if(dest){CGImageDestinationAddImage(dest,im,NULL);CGImageDestinationFinalize(dest);CFRelease(dest);}}
	CGImageRelease(im);
}

// === draw ===
paint::draw::draw(paint::graphics& g) : graph_(g) {}
void paint::draw::corner(const rectangle& r, unsigned px) {
	if(px==1){graph_.set_pixel(r.x,r.y);graph_.set_pixel(r.right()-1,r.y);graph_.set_pixel(r.x,r.bottom()-1);graph_.set_pixel(r.right()-1,r.bottom()-1);return;}
	if(px>1){graph_.line(r.position(),point(r.x+px,r.y));graph_.line(r.position(),point(r.x,r.y+px));int rt=r.right()-1;graph_.line(point(rt,r.y),point(rt-px,r.y));graph_.line(point(rt,r.y),point(rt,r.y-px));int bt=r.bottom()-1;graph_.line(point(r.x,bt),point(r.x+px,bt));graph_.line(point(r.x,bt),point(r.x,bt-px));graph_.line(point(rt,bt),point(rt-px,bt));graph_.line(point(rt,bt),point(rt,bt-px));}
}

std::unique_ptr<unsigned[]> graphics::glyph_pixels(std::wstring_view text)const{
	auto result=std::make_unique<unsigned[]>(text.empty()?1:text.size());
	if(!impl_->pd||!impl_->pd->font||text.empty()){
		if(text.empty()) result[0]=0;
		else for(size_t i=0;i<text.size();++i) result[i]=0;
		return result;
	}
	CTFontRef font=(CTFontRef)impl_->pd->font->native_handle();
	if(!font){for(size_t i=0;i<text.size();++i)result[i]=0;return result;}
	// Convert UTF-32 wchar_t to UTF-16
	std::vector<UniChar> utf16;utf16.reserve(text.size()*2);
	std::vector<std::size_t> cmap(text.size()+1);
	for(std::size_t i=0;i<text.size();++i){
		cmap[i]=utf16.size();
		wchar_t wc=text[i];
		if(wc<=0xFFFF) utf16.push_back((UniChar)wc);
		else{wc-=0x10000;utf16.push_back((UniChar)(0xD800|(wc>>10)));utf16.push_back((UniChar)(0xDC00|(wc&0x3FF)));}
	}
	cmap[text.size()]=utf16.size();
	std::vector<CGGlyph> glyphs(utf16.size());
	bool anyGlyphs=false;
	for(size_t i=0;i<utf16.size();++i){
		CGGlyph g;
		if(CTFontGetGlyphsForCharacters(font,&utf16[i],&g,1)){glyphs[i]=g;if(g)anyGlyphs=true;}
		else glyphs[i]=0;
	}
	std::vector<CGSize> advances(utf16.size(),CGSize{0,0});
	if(anyGlyphs) CTFontGetAdvancesForGlyphs(font,kCTFontOrientationDefault,glyphs.data(),advances.data(),utf16.size());
	for(std::size_t i=0;i<text.size();++i){
		double adv=0;
		for(std::size_t j=cmap[i];j<cmap[i+1];++j) adv+=advances[j].width;
		result[i]=(unsigned)std::max(0.0,std::ceil(adv));
	}
	return result;
}
#ifndef _nana_std_has_string_view
bool graphics::glyph_pixels(const wchar_t*str,std::size_t length,unsigned*pxbuf)const{
	if(!impl_->pd||!impl_->pd->font||!str||!length||!pxbuf) return false;
	auto pixels=glyph_pixels(std::wstring_view(str,length));
	if(!pixels) return false;
	for(std::size_t i=0;i<length;++i) pxbuf[i]=pixels[i];
	return true;
}
::nana::size graphics::glyph_extent_size(const wchar_t*text,std::size_t length,std::size_t begin,std::size_t end)const{
	return glyph_extent_size(std::wstring_view(text,length),begin,end);
}
::nana::size graphics::glyph_extent_size(const std::wstring&text,std::size_t length,std::size_t begin,std::size_t end)const{
	return glyph_extent_size(std::wstring_view(text.data(),length),begin,end);
}
#endif
#ifdef _nana_std_has_string_view
::nana::size graphics::glyph_extent_size(std::wstring_view text,std::size_t begin,std::size_t end)const{
	if(!impl_->pd||!impl_->pd->font||begin>=end||end>text.size()) return {};
	auto px=glyph_pixels(text);
	unsigned w=0;
	for(std::size_t i=begin;i<end;++i) w+=px[i];
	unsigned h=(unsigned)impl_->pd->font->size();
	return {w,h};
}
#endif
}} // namespace

namespace nana { namespace detail {
font_style::font_style(unsigned w,bool i,bool u,bool s):weight(w),italic(i),underline(u),strike_out(s){}
}}
#endif
