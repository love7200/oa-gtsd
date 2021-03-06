/*-
 * Copyright (c) 2011 Ryota Hayashi
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * $FreeBSD$
 */

#import "HRColorPickerView.h"
#import "HRCgUtil.h"
#import "HRBrightnessCursor.h"
#import "HRColorCursor.h"

@interface HRColorPickerView()
- (void)createCacheImage;
- (void)update;
- (void)updateBrightnessCursor;
- (void)updateColorCursor;
- (void)clearInput;
- (void)setCurrentTouchPointInView:(UITouch *)touch;
- (void)setNeedsDisplay15FPS;
@end

@implementation HRColorPickerView

@synthesize delegate;

+ (HRColorPickerStyle)defaultStyle
{
    HRColorPickerStyle style;
    style.width = 320.0f;
    style.headerHeight = 106.0f;
    style.colorMapTileSize = 15.0f;
    style.colorMapSizeWidth = 20;
    style.colorMapSizeHeight = 20;
    style.brightnessLowerLimit = 0.4f;
    style.saturationUpperLimit = 0.95f;
    return style;
}

// j5136p1 12/08/2014 : Extended the method with size to fit the current view
+ (HRColorPickerStyle)fitScreenStyleWithSize:(CGSize)size
{
    size.height -= 44.f;
    
    HRColorPickerStyle style = [HRColorPickerView defaultStyle];
    style.colorMapSizeHeight = (size.height - style.headerHeight)/style.colorMapTileSize;
    style.colorMapSizeWidth = size.width/style.colorMapTileSize;
    
    style.width = size.width;
    
    float colorMapMargin = (style.width - (style.colorMapSizeWidth*style.colorMapTileSize))/2.f;
    style.headerHeight = size.height - (style.colorMapSizeHeight*style.colorMapTileSize) - colorMapMargin;
    
    return style;
}

+ (HRColorPickerStyle)fullColorStyle
{
    HRColorPickerStyle style = [HRColorPickerView defaultStyle];
    style.brightnessLowerLimit = 0.0f;
    style.saturationUpperLimit = 1.0f;
    return style;
}

// j5136p1 12/08/2014 : Extended the method with size to fit the current view
+ (HRColorPickerStyle)fitScreenFullColorStyleWithSize:(CGSize)size
{
    HRColorPickerStyle style = [HRColorPickerView fitScreenStyleWithSize:size];
    style.brightnessLowerLimit = 0.0f;
    style.saturationUpperLimit = 1.0f;
    return style;
}

+ (CGSize)sizeWithStyle:(HRColorPickerStyle)style
{
    CGSize colorMapSize = CGSizeMake(style.colorMapTileSize * style.colorMapSizeWidth, style.colorMapTileSize * style.colorMapSizeHeight);
    float colorMapMargin = (style.width - colorMapSize.width) / 2.0f;
    return CGSizeMake(style.width, style.headerHeight + colorMapSize.height + colorMapMargin);
}

- (id)initWithFrame:(CGRect)frame defaultColor:(const HRRGBColor)defaultColor
{
    return [self initWithStyle:[HRColorPickerView defaultStyle] defaultColor:defaultColor];
}

- (id)initWithStyle:(HRColorPickerStyle)style defaultColor:(const HRRGBColor)defaultColor{
    CGSize size = [HRColorPickerView sizeWithStyle:style];
    CGRect frame = CGRectMake(0.0f, 0.0f, size.width, size.height);
    
    self = [super initWithFrame:frame];
    if (self) {
        _defaultRgbColor = defaultColor;
        _animating = FALSE;
        
        // RGB??????????????????????????????HSV?????????
        HSVColorFromRGBColor(&_defaultRgbColor, &_currentHsvColor);
        
        // ??????????????????
        CGSize colorMapSize = CGSizeMake(style.colorMapTileSize * style.colorMapSizeWidth, style.colorMapTileSize * style.colorMapSizeHeight);
        float colorMapSpace = (style.width - colorMapSize.width) / 2.0f;
        float headerPartsOriginY = (style.headerHeight - 40.0f)/2.0f;
        _currentColorFrame = CGRectMake(10.0f, headerPartsOriginY, 40.0f, 40.0f);
        _brightnessPickerFrame = CGRectMake(120.0f, headerPartsOriginY, style.width - 120.0f - 10.0f, 40.0f);
        _brightnessPickerTouchFrame = CGRectMake(_brightnessPickerFrame.origin.x - 20.0f,
                                                 headerPartsOriginY,
                                                 _brightnessPickerFrame.size.width + 40.0f,
                                                 _brightnessPickerFrame.size.height);
        _brightnessPickerShadowFrame = CGRectMake(_brightnessPickerFrame.origin.x-5.0f,
                                                  headerPartsOriginY-5.0f,
                                                  _brightnessPickerFrame.size.width+10.0f,
                                                  _brightnessPickerFrame.size.height+10.0f);
        
        _colorMapFrame = CGRectMake(colorMapSpace + 1.0f, style.headerHeight, colorMapSize.width, colorMapSize.height);
        
        _colorMapSideFrame = CGRectMake(_colorMapFrame.origin.x - 1.0f,
                                        _colorMapFrame.origin.y - 1.0f,
                                        _colorMapFrame.size.width,
                                        _colorMapFrame.size.height);
        
        _tileSize = style.colorMapTileSize;
        _brightnessLowerLimit = style.brightnessLowerLimit;
        _saturationUpperLimit = style.saturationUpperLimit;
        
        _brightnessCursor = [[HRBrightnessCursor alloc] initWithPoint:CGPointMake(_brightnessPickerFrame.origin.x, _brightnessPickerFrame.origin.y + _brightnessPickerFrame.size.height/2.0f)];
        
        // ?????????????????????????????????????????????
        _colorCursor = [[HRColorCursor alloc] initWithPoint:CGPointMake(_colorMapFrame.origin.x - ([HRColorCursor cursorSize].width - _tileSize)/2.0f - [HRColorCursor shadowSize]/2.0,
                                                                        _colorMapFrame.origin.y - ([HRColorCursor cursorSize].height - _tileSize)/2.0f - [HRColorCursor shadowSize]/2.0)];
        [self addSubview:_brightnessCursor];
        [self addSubview:_colorCursor];
        
        // ??????????????????
        _isTapStart = FALSE;
        _isTapped = FALSE;
        _wasDragStart = FALSE;
        _isDragStart = FALSE;
        _isDragging = FALSE;
        _isDragEnd = FALSE;
        
        // ???????????????
        [self setBackgroundColor:[UIColor colorWithWhite:0.99f alpha:1.0f]];
        [self setMultipleTouchEnabled:FALSE];
        
        _brightnessPickerShadowImage = nil;
        [self createCacheImage];
        
        [self updateBrightnessCursor];
        [self updateColorCursor];
        
        // ??????????????????????????????
        gettimeofday(&_lastDrawTime, NULL);
        
        _timeInterval15fps.tv_sec = 0.0;
        _timeInterval15fps.tv_usec = 1000000.0/15.0;
        
        _delegateHasSELColorWasChanged = FALSE;
    }
    return self;
}


- (HRRGBColor)RGBColor{
    HRRGBColor rgbColor;
    RGBColorFromHSVColor(&_currentHsvColor, &rgbColor);
    return rgbColor;
}

- (float)BrightnessLowerLimit{
    return _brightnessLowerLimit;
}

- (void)setBrightnessLowerLimit:(float)brightnessUnderLimit{
    _brightnessLowerLimit = brightnessUnderLimit;
    [self updateBrightnessCursor];
}

- (float)SaturationUpperLimit{
    return _brightnessLowerLimit;
}

- (void)setSaturationUpperLimit:(float)saturationUpperLimit{
    _saturationUpperLimit = saturationUpperLimit;
    [self updateColorCursor];
}

/////////////////////////////////////////////////////////////////////////////
//
// ??????????????????
//
/////////////////////////////////////////////////////////////////////////////

- (void)createCacheImage{
    // ??????????????????????????????????????????????????????????????????????????????
    
    if (_brightnessPickerShadowImage != nil) {
        return;
    }
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(_brightnessPickerShadowFrame.size.width,
                                                      _brightnessPickerShadowFrame.size.height),
                                           FALSE,
                                           [[UIScreen mainScreen] scale]);
    CGContextRef brightness_picker_shadow_context = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(brightness_picker_shadow_context, 0, _brightnessPickerShadowFrame.size.height);
    CGContextScaleCTM(brightness_picker_shadow_context, 1.0, -1.0);
    
    HRSetRoundedRectanglePath(brightness_picker_shadow_context, 
                                      CGRectMake(0.0f, 0.0f,
                                                 _brightnessPickerShadowFrame.size.width,
                                                 _brightnessPickerShadowFrame.size.height), 5.0f);
    CGContextSetLineWidth(brightness_picker_shadow_context, 10.0f);
    CGContextSetShadow(brightness_picker_shadow_context, CGSizeMake(0.0f, 0.0f), 10.0f);
    CGContextDrawPath(brightness_picker_shadow_context, kCGPathStroke);
    
    _brightnessPickerShadowImage = CGBitmapContextCreateImage(brightness_picker_shadow_context);
    UIGraphicsEndImageContext();
}

- (void)update{
    // ???????????????????????????????????????????????????
    if (_isDragging || _isDragStart || _isDragEnd || _isTapped) {
        CGPoint touchPosition = _activeTouchPosition;
        if (CGRectContainsPoint(_colorMapFrame,touchPosition)) {
            
            int pixelCountX = _colorMapFrame.size.width/_tileSize;
            int pixelCountY = _colorMapFrame.size.height/_tileSize;
            HRHSVColor newHsv = _currentHsvColor;
            
            CGPoint newPosition = CGPointMake(touchPosition.x - _colorMapFrame.origin.x, touchPosition.y - _colorMapFrame.origin.y);
            
            float pixelX = (int)((newPosition.x)/_tileSize)/(float)pixelCountX; // X(??????)???1.0f=0.0f?????????0.0f~0.95f????????????????????????
            float pixelY = (int)((newPosition.y)/_tileSize)/(float)(pixelCountY-1); // Y(??????)???0.0f~1.0f
            
            HSVColorAt(&newHsv, pixelX, pixelY, _saturationUpperLimit, _currentHsvColor.v);
            
            if (!HRHSVColorEqualToColor(&newHsv,&_currentHsvColor)) {
                _currentHsvColor = newHsv;
                [self setNeedsDisplay15FPS];
            }
            [self updateColorCursor];
        }else if(CGRectContainsPoint(_brightnessPickerTouchFrame,touchPosition)){
            if (CGRectContainsPoint(_brightnessPickerFrame,touchPosition)) {
                // ?????????????????????????????????
                _currentHsvColor.v = (1.0f - ((touchPosition.x - _brightnessPickerFrame.origin.x )/ _brightnessPickerFrame.size.width )) * (1.0f - _brightnessLowerLimit) + _brightnessLowerLimit;
            }else{
                // ??????????????????????????????
                if (touchPosition.x < _brightnessPickerFrame.origin.x) {
                    _currentHsvColor.v = 1.0f;
                }else if((_brightnessPickerFrame.origin.x + _brightnessPickerFrame.size.width) < touchPosition.x){
                    _currentHsvColor.v = _brightnessLowerLimit;
                }
            }
            [self updateBrightnessCursor];
            [self updateColorCursor];
            [self setNeedsDisplay15FPS];
        }
    }
    [self clearInput];
}

- (void)updateBrightnessCursor{
    // ??????????????????????????????
    float brightnessCursorX = (1.0f - (_currentHsvColor.v - _brightnessLowerLimit)/(1.0f - _brightnessLowerLimit)) * _brightnessPickerFrame.size.width + _brightnessPickerFrame.origin.x;
    _brightnessCursor.transform = CGAffineTransformMakeTranslation(brightnessCursorX - _brightnessPickerFrame.origin.x, 0.0f);
    
}

- (void)updateColorCursor{
    // ?????????????????????????????????????????????????????????
    
    int pixelCountX = _colorMapFrame.size.width/_tileSize;
    int pixelCountY = _colorMapFrame.size.height/_tileSize;
    CGPoint newPosition;
    newPosition.x = _currentHsvColor.h * (float)pixelCountX * _tileSize + _tileSize/2.0f;
    newPosition.y = (1.0f - _currentHsvColor.s) * (1.0f/_saturationUpperLimit) * (float)(pixelCountY - 1) * _tileSize + _tileSize/2.0f;
    _colorCursorPosition.x = (int)(newPosition.x/_tileSize) * _tileSize;
    _colorCursorPosition.y = (int)(newPosition.y/_tileSize) * _tileSize;
    
    HRRGBColor currentRgbColor = [self RGBColor];
    [_colorCursor setColorRed:currentRgbColor.r andGreen:currentRgbColor.g andBlue:currentRgbColor.b];
    
    _colorCursor.transform = CGAffineTransformMakeTranslation(_colorCursorPosition.x,_colorCursorPosition.y);
     
}

- (void)setNeedsDisplay15FPS{
    // ?????????20FPS??????????????????
    timeval now,diff;
    gettimeofday(&now, NULL);
    timersub(&now, &_lastDrawTime, &diff);
    if (timercmp(&diff, &_timeInterval15fps, >)) {
        _lastDrawTime = now;
        [self setNeedsDisplay];
        if (_delegateHasSELColorWasChanged) {
            [delegate colorWasChanged:self];
        }
    }else{
        return;
    }
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    HRRGBColor currentRgbColor = [self RGBColor];
    
    /////////////////////////////////////////////////////////////////////////////
    //
    // ??????
    //
    /////////////////////////////////////////////////////////////////////////////
    
    CGContextSaveGState(context);
    
    HRSetRoundedRectanglePath(context, _brightnessPickerFrame, 5.0f);
    CGContextClip(context);
    
    CGGradientRef gradient;
    CGColorSpaceRef colorSpace;
    size_t numLocations = 2;
    CGFloat locations[2] = { 0.0, 1.0 };
    colorSpace = CGColorSpaceCreateDeviceRGB();
    
    HRRGBColor darkColor;
    HRRGBColor lightColor;
    UIColor* darkColorFromHsv = [UIColor colorWithHue:_currentHsvColor.h saturation:_currentHsvColor.s brightness:_brightnessLowerLimit alpha:1.0f];
    UIColor* lightColorFromHsv = [UIColor colorWithHue:_currentHsvColor.h saturation:_currentHsvColor.s brightness:1.0f alpha:1.0f];
    
    RGBColorFromUIColor(darkColorFromHsv, &darkColor);
    RGBColorFromUIColor(lightColorFromHsv, &lightColor);
    
    CGFloat gradientColor[] = {
        darkColor.r,darkColor.g,darkColor.b,1.0f,
        lightColor.r,lightColor.g,lightColor.b,1.0f,
    };
    
    gradient = CGGradientCreateWithColorComponents(colorSpace, gradientColor,
                                                   locations, numLocations);
    
    CGPoint startPoint = CGPointMake(_brightnessPickerFrame.origin.x + _brightnessPickerFrame.size.width, _brightnessPickerFrame.origin.y);
    CGPoint endPoint = CGPointMake(_brightnessPickerFrame.origin.x, _brightnessPickerFrame.origin.y);
    CGContextDrawLinearGradient(context, gradient, startPoint, endPoint, 0);
    
    // Gradient???ColorSpace???????????????
    CGColorSpaceRelease(colorSpace);
    CGGradientRelease(gradient);
    
    // ????????????????????? (????????????????????????????????????????????????)
    CGContextDrawImage(context, _brightnessPickerShadowFrame, _brightnessPickerShadowImage);
    
    CGContextRestoreGState(context);
    
    
    /////////////////////////////////////////////////////////////////////////////
    //
    // ??????????????????
    //
    /////////////////////////////////////////////////////////////////////////////
    
    CGContextSaveGState(context);
    
    [[UIColor colorWithWhite:0.9f alpha:1.0f] set];
    CGContextAddRect(context, _colorMapSideFrame);
    CGContextDrawPath(context, kCGPathStroke);
    CGContextRestoreGState(context);
    
    CGContextSaveGState(context);
    float height;
    int pixelCountX = _colorMapFrame.size.width/_tileSize;
    int pixelCountY = _colorMapFrame.size.height/_tileSize;
    
    HRHSVColor pixelHsv;
    HRRGBColor pixelRgb;
    for (int j = 0; j < pixelCountY; ++j) {
        height =  _tileSize * j + _colorMapFrame.origin.y;
        float pixelY = (float)j/(pixelCountY-1); // Y(??????)???0.0f~1.0f
        for (int i = 0; i < pixelCountX; ++i) {
            float pixelX = (float)i/pixelCountX; // X(??????)???1.0f=0.0f?????????0.0f~0.95f????????????????????????
            HSVColorAt(&pixelHsv, pixelX, pixelY, _saturationUpperLimit, _currentHsvColor.v);
            RGBColorFromHSVColor(&pixelHsv, &pixelRgb);
            CGContextSetRGBFillColor(context, pixelRgb.r, pixelRgb.g, pixelRgb.b, 1.0f);
            CGContextFillRect(context, CGRectMake(_tileSize*i+_colorMapFrame.origin.x, height, _tileSize-2.0f, _tileSize-2.0f));
        }
    }
    
    CGContextRestoreGState(context);
    
    /////////////////////////////////////////////////////////////////////////////
    //
    // ????????????????????????
    //
    /////////////////////////////////////////////////////////////////////////////
    
    CGContextSaveGState(context);
    HRDrawSquareColorBatch(context, CGPointMake(CGRectGetMidX(_currentColorFrame), CGRectGetMidY(_currentColorFrame)), &currentRgbColor, _currentColorFrame.size.width/2.0f);
    CGContextRestoreGState(context);
    
    /////////////////////////////////////////////////////////////////////////////
    //
    // RGB????????????????????????
    //
    /////////////////////////////////////////////////////////////////////////////
    
    [[UIColor darkGrayColor] set];
    
    float textHeight = 20.0f;
    float textCenter = CGRectGetMidY(_currentColorFrame) - 5.0f;
    [[NSString stringWithFormat:@"R:%3d%%",(int)(currentRgbColor.r*100)] drawAtPoint:CGPointMake(_currentColorFrame.origin.x+_currentColorFrame.size.width+10.0f, textCenter - textHeight) withAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:12.0f]}];
    [[NSString stringWithFormat:@"G:%3d%%",(int)(currentRgbColor.g*100)] drawAtPoint:CGPointMake(_currentColorFrame.origin.x+_currentColorFrame.size.width+10.0f, textCenter) withAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:12.0f]}];
    [[NSString stringWithFormat:@"B:%3d%%",(int)(currentRgbColor.b*100)] drawAtPoint:CGPointMake(_currentColorFrame.origin.x+_currentColorFrame.size.width+10.0f, textCenter + textHeight) withAttributes:@{NSFontAttributeName: [UIFont boldSystemFontOfSize:12.0f]}];
}


/////////////////////////////////////////////////////////////////////////////
//
// ??????
//
/////////////////////////////////////////////////////////////////////////////

- (void)clearInput{
    _isTapStart = FALSE;
    _isTapped = FALSE;
    _isDragStart = FALSE;
	_isDragEnd = FALSE;
}

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event{
    if ([touches count] == 1) {
        UITouch* touch = [touches anyObject];
        [self setCurrentTouchPointInView:touch];
        _wasDragStart = TRUE;
        _isTapStart = TRUE;
        _touchStartPosition.x = _activeTouchPosition.x;
        _touchStartPosition.y = _activeTouchPosition.y;
        [self update];
    }
}

-(void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event{
	UITouch* touch = [touches anyObject];
    if ([touch tapCount] == 1) {
        _isDragging = TRUE;
        if (_wasDragStart) {
            _wasDragStart = FALSE;
            _isDragStart = TRUE;
        }
        [self setCurrentTouchPointInView:[touches anyObject]];
        [self update];
    }
}

-(void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event{
	UITouch* touch = [touches anyObject];
    
    if (_isDragging) {
        _isDragEnd = TRUE;
    }else{
        if ([touch tapCount] == 1) {
            _isTapped = TRUE;
        }
    }
    _isDragging = FALSE;
    [self setCurrentTouchPointInView:touch];
    [self update];
    [NSTimer scheduledTimerWithTimeInterval:1.0/20.0 target:self selector:@selector(setNeedsDisplay15FPS) userInfo:nil repeats:FALSE];
}

- (void)setCurrentTouchPointInView:(UITouch *)touch{
    CGPoint point;
	point = [touch locationInView:self];
    _activeTouchPosition.x = point.x;
    _activeTouchPosition.y = point.y;
}

- (void)setDelegate:(NSObject<HRColorPickerViewDelegate>*)picker_delegate{
    delegate = picker_delegate;
    _delegateHasSELColorWasChanged = FALSE;
    // ??????????????????????????????????????????????????????????????????????????????????????????
    if ([delegate respondsToSelector:@selector(colorWasChanged:)]) {
        _delegateHasSELColorWasChanged = TRUE;
    }
}

- (void)BeforeDealloc{
    // ????????????????????????
}


- (void)dealloc{
    CGImageRelease(_brightnessPickerShadowImage);
}

@end
