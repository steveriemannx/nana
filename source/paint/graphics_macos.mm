// CoreGraphics Cocoa drawing backend — complete implementation
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <ImageIO/ImageIO.h>
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
void graphics::gradual_rectangle(const ::nana::rectangle&,const ::nana::color&,const ::nana::color&,bool){}
void graphics::frame_rectangle(const ::nana::rectangle& r,const ::nana::color& clr,unsigned gap){palette(false,clr);if(r.width>gap*2){::nana::point left{r.x+static_cast<int>(gap),r.y},right_{r.right()-static_cast<int>(gap)-1,r.y};line(left,right_);left.y=right_.y=r.bottom()-1;line(left,right_);}if(r.height>gap*2){::nana::point top{r.x,r.y+static_cast<int>(gap)},bottom_{r.x,r.bottom()-static_cast<int>(gap)-1};line(top,bottom_);top.x=bottom_.x=r.right()-1;line(top,bottom_);}}
void graphics::rgb_to_wb(){CGContextRef c=C(impl_->pd.get());if(!c)return;unsigned char*data=(unsigned char*)CGBitmapContextGetData(c);size_t w=CGBitmapContextGetWidth(c);size_t h=CGBitmapContextGetHeight(c);size_t bpr=CGBitmapContextGetBytesPerRow(c);float tr[256],tg[256],tb[256];for(int i=0;i<256;++i){tr[i]=static_cast<float>(i*0.3f);tg[i]=static_cast<float>(i*0.59f);tb[i]=static_cast<float>(i*0.11f);}for(size_t y=0;y<h;++y){unsigned char*row=data+y*bpr;for(size_t x=0;x<w;++x){size_t off=x*4;unsigned char gray=static_cast<unsigned char>(tr[row[off+2]]+tg[row[off+1]]+tb[row[off]]+0.5f);row[off]=gray;row[off+1]=gray;row[off+2]=gray;}}}

void graphics::string(const ::nana::point&p,std::string_view s){if(impl_->pd){auto ws=nana::to_wstring(std::string(s));detail::draw_string(impl_->pd.get(),p,ws.c_str(),ws.size());}}
void graphics::string(const ::nana::point&p,std::wstring_view s){if(impl_->pd)detail::draw_string(impl_->pd.get(),p,s.data(),s.size());}
void graphics::string(const ::nana::point&p,std::string_view s,const ::nana::color&clr){palette(false,clr);string(p,s);}
void graphics::string(const ::nana::point&p,std::wstring_view s,const ::nana::color&clr){palette(false,clr);string(p,s);}
unsigned graphics::bidi_string(const ::nana::point&p,std::string_view s){string(p,s);return 0;}
unsigned graphics::bidi_string(const ::nana::point&p,std::wstring_view s){string(p,s);return 0;}

nana::size graphics::text_extent_size(std::string_view t)const{return impl_->pd ? detail::text_extent_size(impl_->pd.get(),t.data(),t.size()) : nana::size{};}
nana::size graphics::text_extent_size(std::wstring_view t)const{return impl_->pd ? detail::text_extent_size(impl_->pd.get(),t.data(),t.size()) : nana::size{};}
nana::size graphics::bidi_extent_size(std::string_view t)const{return text_extent_size(t);}
nana::size graphics::bidi_extent_size(std::wstring_view t)const{return text_extent_size(t);}
bool graphics::text_metrics(unsigned&a,unsigned&d,unsigned&l)const{a=10;d=2;l=0;if(impl_->pd&&impl_->pd->font){CTFontRef f=(CTFontRef)impl_->pd->font->native_handle();if(f){a=(unsigned)CTFontGetAscent(f);d=(unsigned)CTFontGetDescent(f);l=(unsigned)CTFontGetLeading(f);}}return true;}

void graphics::paste(native_window_type,int,int,unsigned,unsigned,int,int)const{}
void graphics::paste(drawable_type,int,int)const{}
void graphics::paste(const ::nana::rectangle&r,graphics&d,int x,int y)const{if(!d.impl_->pd||!C(d.impl_->pd.get()))return;if(!impl_->pd||!impl_->pd->pixmap)return;CGImageRef im=CGBitmapContextCreateImage((CGContextRef)impl_->pd->pixmap);if(im){auto ctx=C(d.impl_->pd.get());CGContextSaveGState(ctx);CGContextTranslateCTM(ctx,0,y+r.height);CGContextScaleCTM(ctx,1.0,-1.0);CGContextDrawImage(ctx,CGRectMake(x,0,r.width,r.height),im);CGContextRestoreGState(ctx);CGImageRelease(im);}}
void graphics::paste(graphics&d,int x,int y)const{if(!impl_->pd||!C(impl_->pd.get()))return;if(!d.impl_->pd||!d.impl_->pd->pixmap)return;CGImageRef im=CGBitmapContextCreateImage((CGContextRef)d.impl_->pd->pixmap);if(im){auto ctx=C(impl_->pd.get());CGContextSaveGState(ctx);CGContextTranslateCTM(ctx,0,y+d.impl_->sz.height);CGContextScaleCTM(ctx,1.0,-1.0);CGContextDrawImage(ctx,CGRectMake(x,0,d.impl_->sz.width,d.impl_->sz.height),im);CGContextRestoreGState(ctx);CGImageRelease(im);}}
void graphics::paste(native_window_type,const ::nana::rectangle&,int,int)const{}

void graphics::bitblt(int x,int y,const graphics&src){const_cast<graphics*>(this)->paste(const_cast<graphics&>(src),x,y);}
void graphics::bitblt(const ::nana::rectangle&,native_window_type){}
void graphics::bitblt(const ::nana::rectangle&,native_window_type,const point&){}
void graphics::bitblt(const ::nana::rectangle&r,const graphics&s){
	nana::rectangle local_src(0, 0, r.width, r.height);
	const_cast<graphics&>(s).paste(local_src, *this, r.x, r.y);
}
void graphics::bitblt(const ::nana::rectangle&r,const graphics&s,const point&p){
	// Source uses (0,0)-based coords. Dest uses top-left via paste flip.
	nana::rectangle local_src(0, 0, r.width, r.height);
	const_cast<graphics&>(s).paste(local_src, *this, r.x, r.y);
}
void graphics::stretch(const ::nana::rectangle&,graphics&,const ::nana::rectangle&)const{}
void graphics::stretch(graphics&,const ::nana::rectangle&)const{}
void graphics::blend(const ::nana::rectangle&,const ::nana::color&,double){}
void graphics::blend(const ::nana::rectangle&,const graphics&,const point&,double){}
void graphics::blur(const ::nana::rectangle&,std::size_t){}

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

std::unique_ptr<unsigned[]> graphics::glyph_pixels(std::wstring_view)const{return nullptr;}
}} // namespace

namespace nana { namespace detail {
font_style::font_style(unsigned w,bool i,bool u,bool s):weight(w),italic(i),underline(u),strike_out(s){}
}}
#endif
