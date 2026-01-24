//
//  URSThemeIntegration.m
//  uroswm - GSTheme Window Decoration for Titlebars
//
//  Implementation of GSTheme window decoration rendering for X11 titlebars.
//

#import "URSThemeIntegration.h"
#import "URSRenderingContext.h"
#import <XCBKit/XCBConnection.h>
#import <XCBKit/XCBFrame.h>
#import <cairo/cairo.h>
#import <cairo/cairo-xcb.h>
#import <objc/runtime.h>
#import "GSThemeTitleBar.h"

// Category to expose private GSTheme methods for theme-agnostic titlebar rendering
// These methods exist in GSTheme but aren't in the public header
@interface GSTheme (URSPrivateMethods)
- (void)drawTitleBarRect:(NSRect)titleBarRect
            forStyleMask:(unsigned int)styleMask
                   state:(int)inputState
                andTitle:(NSString*)title;
@end

@implementation URSThemeIntegration

static URSThemeIntegration *sharedInstance = nil;
static NSMutableSet *fixedSizeWindows = nil;

#pragma mark - Fixed-size window tracking

+ (void)initialize {
    if (self == [URSThemeIntegration class]) {
        fixedSizeWindows = [[NSMutableSet alloc] init];
    }
}

+ (void)registerFixedSizeWindow:(xcb_window_t)windowId {
    @synchronized(fixedSizeWindows) {
        [fixedSizeWindows addObject:@(windowId)];
        NSLog(@"Registered fixed-size window %u (total: %lu)", windowId, (unsigned long)[fixedSizeWindows count]);
    }
}

+ (void)unregisterFixedSizeWindow:(xcb_window_t)windowId {
    @synchronized(fixedSizeWindows) {
        [fixedSizeWindows removeObject:@(windowId)];
        NSLog(@"Unregistered fixed-size window %u", windowId);
    }
}

+ (BOOL)isFixedSizeWindow:(xcb_window_t)windowId {
    @synchronized(fixedSizeWindows) {
        return [fixedSizeWindows containsObject:@(windowId)];
    }
}

// Edge button metrics (matching Eau theme AppearanceMetrics.h)
static const CGFloat TITLEBAR_HEIGHT = 24.0;
static const CGFloat EDGE_BUTTON_WIDTH = 28.0;
static const CGFloat RIGHT_REGION_WIDTH = 56.0;
static const CGFloat BUTTON_INNER_RADIUS = 5.0;
static const CGFloat ICON_STROKE = 1.5;
static const CGFloat ICON_INSET = 8.0;

// Button position enum (matching Eau theme EauTitleBarButtonCell.h)
typedef NS_ENUM(NSInteger, TitleBarButtonPosition) {
    TitleBarButtonPositionLeft = 0,       // Close button - left edge
    TitleBarButtonPositionRightLeft,      // Minimize - left side of right region
    TitleBarButtonPositionRightRight      // Maximize - right side of right region
};

// Draw rectangular edge button with gradient
+ (void)drawEdgeButtonInRect:(NSRect)rect
                    position:(TitleBarButtonPosition)position
                      active:(BOOL)active
                 highlighted:(BOOL)highlighted {
    // Get gradient colors
    NSColor *gradientColor1;
    NSColor *gradientColor2;

    if (active) {
        gradientColor1 = [NSColor colorWithCalibratedRed:0.833 green:0.833 blue:0.833 alpha:1];
        gradientColor2 = [NSColor colorWithCalibratedRed:0.667 green:0.667 blue:0.667 alpha:1];
    } else {
        gradientColor1 = [NSColor colorWithCalibratedRed:0.9 green:0.9 blue:0.9 alpha:1];
        gradientColor2 = [NSColor colorWithCalibratedRed:0.8 green:0.8 blue:0.8 alpha:1];
    }

    if (highlighted) {
        gradientColor1 = [gradientColor1 shadowWithLevel:0.15];
        gradientColor2 = [gradientColor2 shadowWithLevel:0.15];
    }

    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:gradientColor1
                                                         endingColor:gradientColor2];

    NSColor *borderColor = [NSColor colorWithCalibratedRed:0.4 green:0.4 blue:0.4 alpha:1.0];

    // Create path with appropriate corner rounding
    NSBezierPath *path = [self buttonPathForRect:rect position:position];

    // Fill with gradient
    [gradient drawInBezierPath:path angle:-90];

    // Stroke border
    [borderColor setStroke];
    [path setLineWidth:1.0];
    [path stroke];

    // Draw divider for minimize button
    if (position == TitleBarButtonPositionRightLeft) {
        NSBezierPath *divider = [NSBezierPath bezierPath];
        [divider moveToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect) + 4)];
        [divider lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect) - 4)];
        [borderColor setStroke];
        [divider setLineWidth:1.0];
        [divider stroke];
    }
}

+ (NSBezierPath *)buttonPathForRect:(NSRect)frame position:(TitleBarButtonPosition)position {
    CGFloat radius = BUTTON_INNER_RADIUS;
    NSBezierPath *path = [NSBezierPath bezierPath];

    switch (position) {
        case TitleBarButtonPositionLeft:
            // Close button: rounded on right side and top-left corner
            [path moveToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame) - radius, NSMinY(frame))];
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(frame) - radius, NSMinY(frame) + radius)
                                             radius:radius
                                         startAngle:270
                                           endAngle:0];
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame) - radius)];
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(frame) - radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:0
                                           endAngle:90];
            [path lineToPoint:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame))];
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:90
                                           endAngle:180];
            [path lineToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame))];
            [path closePath];
            break;

        case TitleBarButtonPositionRightLeft:
            // Minimize button: rounded on left side only
            [path moveToPoint:NSMakePoint(NSMinX(frame) + radius, NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame))];
            [path lineToPoint:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame))];
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:90
                                           endAngle:180];
            [path lineToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame) + radius)];
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(frame) + radius, NSMinY(frame) + radius)
                                             radius:radius
                                         startAngle:180
                                           endAngle:270];
            [path closePath];
            break;

        case TitleBarButtonPositionRightRight:
            // Maximize button: top-right corner rounded
            [path moveToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame))];
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame) - radius)];
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(frame) - radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:0
                                           endAngle:90];
            [path lineToPoint:NSMakePoint(NSMinX(frame), NSMaxY(frame))];
            [path closePath];
            break;
    }

    return path;
}

// Draw close icon (X)
+ (void)drawCloseIconInRect:(NSRect)rect withColor:(NSColor *)color {
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:ICON_STROKE];
    [path setLineCapStyle:NSRoundLineCapStyle];

    [path moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    [path moveToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))];
    [path lineToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))];

    [color setStroke];
    [path stroke];
}

// Draw minimize icon (down triangle)
+ (void)drawMinimizeIconInRect:(NSRect)rect withColor:(NSColor *)color {
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:ICON_STROKE];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];

    [path moveToPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect) - 2)];
    [path lineToPoint:NSMakePoint(NSMidX(rect), NSMinY(rect) + 2)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect) - 2)];

    [color setStroke];
    [path stroke];
}

// Draw maximize icon (up triangle)
+ (void)drawMaximizeIconInRect:(NSRect)rect withColor:(NSColor *)color {
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path setLineWidth:ICON_STROKE];
    [path setLineCapStyle:NSRoundLineCapStyle];
    [path setLineJoinStyle:NSRoundLineJoinStyle];

    [path moveToPoint:NSMakePoint(NSMinX(rect), NSMinY(rect) + 2)];
    [path lineToPoint:NSMakePoint(NSMidX(rect), NSMaxY(rect) - 2)];
    [path lineToPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect) + 2)];

    [color setStroke];
    [path stroke];
}

// Get icon color based on active/highlighted state
+ (NSColor *)iconColorForActive:(BOOL)active highlighted:(BOOL)highlighted {
    NSColor *color;
    if (active) {
        color = [NSColor colorWithCalibratedRed:0.3 green:0.3 blue:0.3 alpha:1.0];
    } else {
        color = [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1.0];
    }

    if (highlighted) {
        color = [color shadowWithLevel:0.2];
    }

    return color;
}

#pragma mark - Singleton Management

+ (instancetype)sharedInstance {
    if (sharedInstance == nil) {
        sharedInstance = [[self alloc] init];
    }
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.enabled = YES;
        self.managedTitlebars = [[NSMutableArray alloc] init];
        NSLog(@"GSTheme titlebar integration initialized");
    }
    return self;
}

#pragma mark - GSTheme Management

+ (void)initializeGSTheme {
    // Load the user's current theme from system defaults
    @try {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *themeName = [defaults stringForKey:@"GSTheme"];

        NSLog(@"GSTheme user default: '%@'", themeName ?: @"(none)");

        if (themeName && [themeName length] > 0) {
            // Remove .theme extension if present
            if ([[themeName pathExtension] isEqualToString:@"theme"]) {
                themeName = [themeName stringByDeletingPathExtension];
            }

            NSLog(@"Loading user's selected theme: %@", themeName);
            GSTheme *userTheme = [GSTheme loadThemeNamed:themeName];
            if (userTheme) {
                [GSTheme setTheme:userTheme];
                NSLog(@"GSTheme loaded: %@", [userTheme name] ?: @"Unknown");
                return;
            } else {
                NSLog(@"Failed to load theme '%@', falling back to default", themeName);
            }
        } else {
            NSLog(@"No theme specified in GSTheme default, using system default");
        }

        // Fallback to whatever GSTheme gives us by default
        GSTheme *theme = [GSTheme theme];
        NSLog(@"GSTheme fallback loaded: %@", [theme name] ?: @"Default");

        // Log theme bundle info for debugging
        if (theme && [theme bundle]) {
            NSLog(@"Theme bundle path: %@", [[theme bundle] bundlePath]);
        }

    } @catch (NSException *exception) {
        NSLog(@"Failed to load GSTheme: %@", exception.reason);
    }
}

+ (GSTheme*)currentTheme {
    return [GSTheme theme];
}

+ (void)enableGSThemeTitleBars {
    NSLog(@"Enabling GSThemeTitleBar replacement for XCBTitleBar...");

    // The GSThemeTitleBar class will automatically override XCBTitleBar methods
    // when instances are created. We just need to ensure it's loaded.
    Class gsThemeClass = [GSThemeTitleBar class];
    if (gsThemeClass) {
        NSLog(@"GSThemeTitleBar class loaded successfully");
    } else {
        NSLog(@"Warning: GSThemeTitleBar class not found");
    }
}

#pragma mark - GSTheme Titlebar Rendering

+ (BOOL)renderGSThemeTitlebar:(XCBTitleBar*)titlebar
                        title:(NSString*)title
                       active:(BOOL)isActive {

    if (![[URSThemeIntegration sharedInstance] enabled] || !titlebar) {
        return NO;
    }

    GSTheme *theme = [self currentTheme];
    if (!theme) {
        NSLog(@"Warning: No GSTheme available for titlebar rendering");
        return NO;
    }

    @try {
        // Get titlebar dimensions - use parent frame width to ensure titlebar spans full window
        XCBRect xcbRect = titlebar.windowRect;
        XCBWindow *parentFrame = [titlebar parentWindow];
        uint16_t titlebarWidth = xcbRect.size.width;

        if (parentFrame) {
            XCBRect frameRect = [parentFrame windowRect];
            titlebarWidth = frameRect.size.width;

            // Resize the X11 titlebar window if it doesn't match the frame width
            if (xcbRect.size.width != frameRect.size.width) {
                NSLog(@"Resizing titlebar X11 window from %d to %d to match frame",
                      xcbRect.size.width, frameRect.size.width);

                uint32_t values[] = {frameRect.size.width};
                xcb_configure_window([[titlebar connection] connection],
                                     [titlebar window],
                                     XCB_CONFIG_WINDOW_WIDTH,
                                     values);

                // Update the titlebar's internal rect
                xcbRect.size.width = frameRect.size.width;
                [titlebar setWindowRect:xcbRect];

                // Recreate the pixmap with the new size
                [titlebar createPixmap];

                [[titlebar connection] flush];
            }
        }
        NSSize titlebarSize = NSMakeSize(titlebarWidth, xcbRect.size.height);

        // Create NSImage for GSTheme to render into
        NSImage *titlebarImage = [[NSImage alloc] initWithSize:titlebarSize];

        [titlebarImage lockFocus];

        // Clear background with titlebar background color (not transparent!)
        // Using transparent would leave garbage pixels from uninitialized pixmap
        [[NSColor lightGrayColor] set];
        NSRectFill(NSMakeRect(0, 0, titlebarSize.width, titlebarSize.height));

        // Define the titlebar rect
        NSRect titlebarRect = NSMakeRect(0, 0, titlebarSize.width, titlebarSize.height);

        // Use GSTheme to draw titlebar decoration with all button types
        NSUInteger styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
        GSThemeControlState state = isActive ? GSThemeNormalState : GSThemeSelectedState;

        NSLog(@"Drawing GSTheme titlebar with styleMask: 0x%lx, state: %d", (unsigned long)styleMask, (int)state);

        // Draw the window titlebar using GSTheme
        [theme drawWindowBorder:titlebarRect
                      withFrame:titlebarRect
                   forStyleMask:styleMask
                          state:state
                       andTitle:title ?: @""];

        // Draw rectangular edge buttons: Close on left, Minimize+Maximize on right
        NSColor *iconColor = [URSThemeIntegration iconColorForActive:isActive highlighted:NO];

        // Close button at left edge
        if (styleMask & NSClosableWindowMask) {
            NSRect closeFrame = NSMakeRect(0, 0, EDGE_BUTTON_WIDTH, TITLEBAR_HEIGHT);
            [URSThemeIntegration drawEdgeButtonInRect:closeFrame
                                             position:TitleBarButtonPositionLeft
                                               active:isActive
                                          highlighted:NO];
            NSRect iconRect = NSInsetRect(closeFrame, ICON_INSET, ICON_INSET);
            [URSThemeIntegration drawCloseIconInRect:iconRect withColor:iconColor];
            NSLog(@"Drew close button at: %@", NSStringFromRect(closeFrame));
        }

        // Minimize button at left side of right region
        if (styleMask & NSMiniaturizableWindowMask) {
            CGFloat buttonWidth = RIGHT_REGION_WIDTH / 2.0;
            NSRect miniFrame = NSMakeRect(titlebarSize.width - RIGHT_REGION_WIDTH, 0,
                                          buttonWidth, TITLEBAR_HEIGHT);
            [URSThemeIntegration drawEdgeButtonInRect:miniFrame
                                             position:TitleBarButtonPositionRightLeft
                                               active:isActive
                                          highlighted:NO];
            NSRect iconRect = NSInsetRect(miniFrame, ICON_INSET, ICON_INSET);
            [URSThemeIntegration drawMinimizeIconInRect:iconRect withColor:iconColor];
            NSLog(@"Drew miniaturize button at: %@", NSStringFromRect(miniFrame));
        }

        // Maximize button at right side of right region
        if (styleMask & NSResizableWindowMask) {
            CGFloat buttonWidth = RIGHT_REGION_WIDTH / 2.0;
            NSRect zoomFrame = NSMakeRect(titlebarSize.width - buttonWidth, 0,
                                          buttonWidth, TITLEBAR_HEIGHT);
            [URSThemeIntegration drawEdgeButtonInRect:zoomFrame
                                             position:TitleBarButtonPositionRightRight
                                               active:isActive
                                          highlighted:NO];
            NSRect iconRect = NSInsetRect(zoomFrame, ICON_INSET, ICON_INSET);
            [URSThemeIntegration drawMaximizeIconInRect:iconRect withColor:iconColor];
            NSLog(@"Drew zoom button at: %@", NSStringFromRect(zoomFrame));
        }

        [titlebarImage unlockFocus];

        // Convert NSImage to Cairo surface and apply to titlebar
        BOOL success = [self transferImage:titlebarImage toTitlebar:titlebar];

        if (success) {
            NSLog(@"GSTheme titlebar rendered successfully for: %@", title);
        } else {
            NSLog(@"Failed to transfer GSTheme titlebar for: %@", title);
        }

        return success;

    } @catch (NSException *exception) {
        NSLog(@"GSTheme titlebar rendering failed: %@", exception.reason);
        return NO;
    }
}

#pragma mark - Image Transfer

// Create a dimmed/desaturated version of an image for inactive window decorations
+ (NSImage*)createDimmedImage:(NSImage*)image {
    if (!image) return nil;

    NSSize size = [image size];
    NSImage *dimmedImage = [[NSImage alloc] initWithSize:size];

    [dimmedImage lockFocus];

    // Draw the original image
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height)
             fromRect:NSZeroRect
            operation:NSCompositeSourceOver
             fraction:1.0];

    // Apply desaturation overlay using a semi-transparent gray
    // This reduces vibrancy while maintaining visibility
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.35] set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height), NSCompositeSourceAtop);

    [dimmedImage unlockFocus];

    return dimmedImage;
}

+ (BOOL)transferImage:(NSImage*)image toTitlebar:(XCBTitleBar*)titlebar {
    // Convert NSImage to bitmap representation
    NSBitmapImageRep *bitmap = nil;
    for (NSImageRep *rep in [image representations]) {
        if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            bitmap = (NSBitmapImageRep*)rep;
            break;
        }
    }

    if (!bitmap) {
        // Create bitmap from image data
        NSData *imageData = [image TIFFRepresentation];
        bitmap = [NSBitmapImageRep imageRepWithData:imageData];
    }

    if (!bitmap) {
        NSLog(@"Failed to create bitmap from NSImage for titlebar transfer");
        return NO;
    }

    NSLog(@"Creating Cairo surface for titlebar pixmap: %u, size: %dx%d",
          titlebar.pixmap, (int)image.size.width, (int)image.size.height);

    // DEBUG: Check bitmap format and sample pixel data
    NSLog(@"Bitmap format: %ldx%ld, bitsPerPixel=%ld, bytesPerRow=%ld, colorSpace=%@, format=%u",
          [bitmap pixelsWide], [bitmap pixelsHigh], [bitmap bitsPerPixel],
          [bitmap bytesPerRow], [bitmap colorSpaceName], (unsigned int)[bitmap bitmapFormat]);

    // Sample a few pixels to see actual byte values
    unsigned char *pixels = [bitmap bitmapData];
    if (pixels && [bitmap pixelsWide] >= 15 && [bitmap pixelsHigh] >= 8) {
        int closeX = 18, closeY = 12;  // Should be red button area
        int miniX = 37, miniY = 12;   // Should be yellow button area
        int zoomX = 56, zoomY = 12;   // Should be green button area

        int bytesPerPixel = [bitmap bitsPerPixel] / 8;

        // Sample close button pixel (should be red)
        int offset = (closeY * [bitmap bytesPerRow]) + (closeX * bytesPerPixel);
        if (bytesPerPixel >= 4) {
            NSLog(@"Close button pixel (%d,%d): [0]=%d [1]=%d [2]=%d [3]=%d",
                  closeX, closeY, pixels[offset], pixels[offset+1], pixels[offset+2], pixels[offset+3]);
        }

        // Sample miniaturize button pixel (should be yellow)
        offset = (miniY * [bitmap bytesPerRow]) + (miniX * bytesPerPixel);
        if (bytesPerPixel >= 4) {
            NSLog(@"Mini button pixel (%d,%d): [0]=%d [1]=%d [2]=%d [3]=%d",
                  miniX, miniY, pixels[offset], pixels[offset+1], pixels[offset+2], pixels[offset+3]);
        }

        // Sample zoom button pixel (should be green)
        offset = (zoomY * [bitmap bytesPerRow]) + (zoomX * bytesPerPixel);
        if (bytesPerPixel >= 4) {
            NSLog(@"Zoom button pixel (%d,%d): [0]=%d [1]=%d [2]=%d [3]=%d",
                  zoomX, zoomY, pixels[offset], pixels[offset+1], pixels[offset+2], pixels[offset+3]);
        }
    }

    // Create Cairo surface from XCB titlebar pixmap
    cairo_surface_t *x11Surface = cairo_xcb_surface_create(
        [titlebar.connection connection],
        titlebar.pixmap,
        titlebar.visual.visualType,
        (int)image.size.width,
        (int)image.size.height
    );

    cairo_status_t surface_status = cairo_surface_status(x11Surface);
    if (surface_status != CAIRO_STATUS_SUCCESS) {
        NSLog(@"Failed to create Cairo X11 surface for titlebar: %s", cairo_status_to_string(surface_status));
        cairo_surface_destroy(x11Surface);
        return NO;
    }

    NSLog(@"Cairo X11 surface created successfully");

    cairo_t *ctx = cairo_create(x11Surface);

    // Create Cairo image surface from bitmap data
    // NOTE: NSBitmapImageRep uses RGBA but Cairo ARGB32 expects BGRA, so we need to convert
    unsigned char *bitmapPixels = [bitmap bitmapData];
    int width = [bitmap pixelsWide];
    int height = [bitmap pixelsHigh];
    int bytesPerRow = [bitmap bytesPerRow];

    // OPTIMIZATION: Convert RGBA to BGRA using 32-bit word operations (4x faster)
    // Process entire rows at once, handling stride properly
    int rowPixels = width;
    for (int y = 0; y < height; y++) {
        uint32_t *rowPtr = (uint32_t *)(bitmapPixels + (y * bytesPerRow));
        for (int x = 0; x < rowPixels; x++) {
            uint32_t pixel = rowPtr[x];
            // RGBA (little-endian memory: A B G R) -> BGRA (little-endian: A R G B)
            // Extract channels and reassemble
            uint32_t r = (pixel >> 0) & 0xFF;
            uint32_t g = (pixel >> 8) & 0xFF;
            uint32_t b = (pixel >> 16) & 0xFF;
            uint32_t a = (pixel >> 24) & 0xFF;
            // BGRA format: B in lowest byte, then G, R, A
            rowPtr[x] = (a << 24) | (r << 16) | (g << 8) | b;
        }
    }

    cairo_surface_t *imageSurface = cairo_image_surface_create_for_data(
        bitmapPixels,
        CAIRO_FORMAT_ARGB32,
        width,
        height,
        bytesPerRow
    );

    if (cairo_surface_status(imageSurface) != CAIRO_STATUS_SUCCESS) {
        NSLog(@"Failed to create Cairo image surface for titlebar transfer");
        cairo_surface_destroy(imageSurface);
        cairo_destroy(ctx);
        cairo_surface_destroy(x11Surface);
        return NO;
    }

    NSLog(@"Painting GSTheme image to X11 surface...");

    // Paint GSTheme image to X11 surface using SOURCE operator
    // SOURCE completely replaces destination pixels (no compositing)
    // This prevents old pixmap garbage from showing through
    cairo_set_operator(ctx, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_surface(ctx, imageSurface, 0, 0);
    cairo_paint(ctx);
    cairo_surface_flush(x11Surface);

    // Force immediate X11 update to ensure GSTheme is visible
    [titlebar.connection flush];
    xcb_flush([titlebar.connection connection]);

    NSLog(@"GSTheme image painted and surface flushed");

    // Cleanup first surface
    cairo_surface_destroy(imageSurface);
    cairo_destroy(ctx);
    cairo_surface_destroy(x11Surface);

    // Paint DIMMED version to dPixmap (inactive pixmap) for unfocused windows
    // XCBWindow.drawArea uses isAbove ? pixmap : dPixmap
    xcb_pixmap_t dPixmap = [titlebar dPixmap];
    if (dPixmap != 0) {
        NSLog(@"Painting dimmed GSTheme to dPixmap (inactive pixmap): %u", dPixmap);

        // Create a dimmed version of the titlebar image for inactive state
        NSImage *dimmedImage = [self createDimmedImage:image];
        if (dimmedImage) {
            // Get bitmap from dimmed image
            NSBitmapImageRep *dimmedBitmap = nil;
            for (NSImageRep *rep in [dimmedImage representations]) {
                if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
                    dimmedBitmap = (NSBitmapImageRep*)rep;
                    break;
                }
            }
            if (!dimmedBitmap) {
                NSData *dimmedData = [dimmedImage TIFFRepresentation];
                dimmedBitmap = [NSBitmapImageRep imageRepWithData:dimmedData];
            }

            if (dimmedBitmap) {
                unsigned char *dimmedPixels = [dimmedBitmap bitmapData];
                int dimmedWidth = [dimmedBitmap pixelsWide];
                int dimmedHeight = [dimmedBitmap pixelsHigh];
                int dimmedBytesPerRow = [dimmedBitmap bytesPerRow];

                // OPTIMIZATION: Convert RGBA to BGRA using 32-bit word operations
                for (int y = 0; y < dimmedHeight; y++) {
                    uint32_t *rowPtr = (uint32_t *)(dimmedPixels + (y * dimmedBytesPerRow));
                    for (int x = 0; x < dimmedWidth; x++) {
                        uint32_t pixel = rowPtr[x];
                        uint32_t r = (pixel >> 0) & 0xFF;
                        uint32_t g = (pixel >> 8) & 0xFF;
                        uint32_t b = (pixel >> 16) & 0xFF;
                        uint32_t a = (pixel >> 24) & 0xFF;
                        rowPtr[x] = (a << 24) | (r << 16) | (g << 8) | b;
                    }
                }

                cairo_surface_t *dSurface = cairo_xcb_surface_create(
                    [titlebar.connection connection],
                    dPixmap,
                    titlebar.visual.visualType,
                    dimmedWidth,
                    dimmedHeight
                );

                if (cairo_surface_status(dSurface) == CAIRO_STATUS_SUCCESS) {
                    cairo_t *dCtx = cairo_create(dSurface);

                    cairo_surface_t *dImageSurface = cairo_image_surface_create_for_data(
                        dimmedPixels,
                        CAIRO_FORMAT_ARGB32,
                        dimmedWidth,
                        dimmedHeight,
                        dimmedBytesPerRow
                    );

                    if (cairo_surface_status(dImageSurface) == CAIRO_STATUS_SUCCESS) {
                        cairo_set_operator(dCtx, CAIRO_OPERATOR_SOURCE);
                        cairo_set_source_surface(dCtx, dImageSurface, 0, 0);
                        cairo_paint(dCtx);
                        cairo_surface_flush(dSurface);
                        NSLog(@"Dimmed GSTheme painted to dPixmap successfully");
                    }

                    cairo_surface_destroy(dImageSurface);
                    cairo_destroy(dCtx);
                }
                cairo_surface_destroy(dSurface);
            }
        }
    }

    [titlebar.connection flush];

    // Notify compositor that titlebar rendering is complete
    // Use the parent frame's window ID for compositor notification
    xcb_window_t windowId = [[titlebar parentWindow] window];
    if (windowId != 0) {
        [URSRenderingContext notifyRenderingComplete:windowId];
    }

    return YES;
}

#pragma mark - GSTheme Method Swizzling Implementations

// These methods replace XCBTitleBar's drawing methods
- (void)gstheme_drawTitleBarComponentsPixmaps {
    // Replace XCBTitleBar's Cairo drawing with GSTheme
    NSLog(@"GSTheme: Replacing drawTitleBarComponentsPixmaps with GSTheme rendering");

    XCBTitleBar *titlebar = (XCBTitleBar*)self;
    [URSThemeIntegration renderGSThemeTitlebar:titlebar
                                         title:titlebar.windowTitle
                                        active:YES];
}

- (void)gstheme_drawTitleBarComponents {
    // Replace XCBTitleBar's Cairo drawing with GSTheme
    NSLog(@"GSTheme: Replacing drawTitleBarComponents with GSTheme rendering");

    XCBTitleBar *titlebar = (XCBTitleBar*)self;
    [URSThemeIntegration renderGSThemeTitlebar:titlebar
                                         title:titlebar.windowTitle
                                        active:YES];
}

- (void)gstheme_drawTitleBarForColor:(TitleBarColor)aColor {
    // Replace XCBTitleBar's Cairo drawing with GSTheme
    NSLog(@"GSTheme: Replacing drawTitleBarForColor: with GSTheme rendering");

    XCBTitleBar *titlebar = (XCBTitleBar*)self;
    BOOL isActive = (aColor == TitleBarUpColor);
    [URSThemeIntegration renderGSThemeTitlebar:titlebar
                                         title:titlebar.windowTitle
                                        active:isActive];
}

+ (BOOL)renderGSThemeToWindow:(XCBWindow*)window
                        frame:(XCBFrame*)frame
                        title:(NSString*)title
                       active:(BOOL)isActive {

    if (![[URSThemeIntegration sharedInstance] enabled] || !window || !frame) {
        return NO;
    }

    GSTheme *theme = [self currentTheme];
    if (!theme) {
        NSLog(@"Warning: No GSTheme available for standalone titlebar rendering");
        return NO;
    }

    @try {
        // Get the frame's titlebar area
        XCBWindow *titlebarWindow = [frame childWindowForKey:TitleBar];
        if (!titlebarWindow || ![titlebarWindow isKindOfClass:[XCBTitleBar class]]) {
            NSLog(@"Warning: No titlebar found in frame for GSTheme rendering");
            return NO;
        }
        XCBTitleBar *titlebar = (XCBTitleBar*)titlebarWindow;

        // Get titlebar dimensions - use frame width to ensure titlebar spans full window
        XCBRect titlebarRect = [titlebar windowRect];
        XCBRect frameRect = [frame windowRect];

        // DEBUG: Add 2 pixels to width and shift 1 pixel left to cover both edges
        uint16_t targetWidth = frameRect.size.width + 2;
        int16_t targetX = -1;  // Shift titlebar 1 pixel left
        NSDebugLog(@"DEBUG: Resizing titlebar X11 window to %d at x=%d (frame=%d, current titlebar=%d)",
              targetWidth, targetX, frameRect.size.width, titlebarRect.size.width);

        uint32_t values[2] = {(uint32_t)targetX, targetWidth};
        xcb_configure_window([[frame connection] connection],
                             [titlebar window],
                             XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_WIDTH,
                             values);

        // Update the titlebar's internal rect
        titlebarRect.size.width = targetWidth;
        [titlebar setWindowRect:titlebarRect];

        // Recreate the pixmap with the new size
        [titlebar createPixmap];

        [[frame connection] flush];

        // Use frame width to ensure titlebar matches window width exactly
        // DEBUG: Add 2 pixels (1 on each side) to cover both edges
        NSSize titlebarSize = NSMakeSize(frameRect.size.width + 2, titlebarRect.size.height);
        NSDebugLog(@"DEBUG: Using titlebarSize.width = %d (frame was %d)", (int)titlebarSize.width, (int)frameRect.size.width);

        // DEBUG: Also get client window dimensions for comparison
        XCBWindow *clientWin = [frame childWindowForKey:ClientWindow];
        XCBRect clientRect = clientWin ? [clientWin windowRect] : XCBMakeRect(XCBMakePoint(0,0), XCBMakeSize(0,0));
        NSLog(@"DEBUG DIMENSIONS: frame=%dx%d, titlebar=%dx%d, client=%dx%d",
              (int)frameRect.size.width, (int)frameRect.size.height,
              (int)titlebarRect.size.width, (int)titlebarRect.size.height,
              (int)clientRect.size.width, (int)clientRect.size.height);

        NSLog(@"Rendering standalone GSTheme titlebar: %dx%d (frame: %dx%d) for window %u",
              (int)titlebarSize.width, (int)titlebarSize.height,
              (int)frameRect.size.width, (int)frameRect.size.height, [window window]);

        // Create NSImage for GSTheme to render into
        NSImage *titlebarImage = [[NSImage alloc] initWithSize:titlebarSize];

        [titlebarImage lockFocus];
        
        // Set up the graphics state for theme drawing
        NSGraphicsContext *gctx = [NSGraphicsContext currentContext];
        [gctx saveGraphicsState];

        // Use GSTheme to draw titlebar decoration
        NSRect drawRect = NSMakeRect(0, 0, titlebarSize.width, titlebarSize.height);

        // Check if this is a fixed-size window (only show close button)
        XCBWindow *clientWindow = [frame childWindowForKey:ClientWindow];
        xcb_window_t clientWindowId = clientWindow ? [clientWindow window] : 0;
        BOOL isFixedSize = clientWindowId && [URSThemeIntegration isFixedSizeWindow:clientWindowId];

        NSUInteger styleMask;
        if (isFixedSize) {
            // Fixed-size windows only get close button
            styleMask = NSTitledWindowMask | NSClosableWindowMask;
            NSLog(@"Using fixed-size styleMask (close button only) for window %u", clientWindowId);
        } else {
            // Normal windows get all buttons
            styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
        }
        GSThemeControlState state = isActive ? GSThemeNormalState : GSThemeSelectedState;

        NSLog(@"Drawing standalone GSTheme titlebar with styleMask: 0x%lx, state: %d", (unsigned long)styleMask, (int)state);

        // Log GSTheme padding and size values to verify Eau theme values
        if ([theme respondsToSelector:@selector(titlebarPaddingLeft)]) {
            NSLog(@"GSTheme titlebarPaddingLeft: %.1f", [theme titlebarPaddingLeft]);
        }
        if ([theme respondsToSelector:@selector(titlebarPaddingRight)]) {
            NSLog(@"GSTheme titlebarPaddingRight: %.1f", [theme titlebarPaddingRight]);
        }
        if ([theme respondsToSelector:@selector(titlebarPaddingTop)]) {
            NSLog(@"GSTheme titlebarPaddingTop: %.1f", [theme titlebarPaddingTop]);
        }
        if ([theme respondsToSelector:@selector(titlebarButtonSize)]) {
            NSLog(@"GSTheme titlebarButtonSize: %.1f", [theme titlebarButtonSize]);
        }
        NSLog(@"Expected Eau values: paddingLeft=2, paddingRight=2, paddingTop=6, buttonSize=13");

        // Get theme font settings for titlebar text
        NSString *themeFontName = @"LuxiSans"; // Default from Eau theme
        float themeFontSize = 13.0;            // Default from Eau theme

        // Try to get font settings from theme bundle
        NSBundle *themeBundle = [theme bundle];
        if (themeBundle) {
            NSDictionary *themeInfo = [themeBundle infoDictionary];
            if (themeInfo) {
                NSString *fontName = [themeInfo objectForKey:@"NSFont"];
                NSString *fontSize = [themeInfo objectForKey:@"NSFontSize"];

                if (fontName) {
                    themeFontName = fontName;
                    NSLog(@"Theme font name: %@", themeFontName);
                }
                if (fontSize) {
                    themeFontSize = [fontSize floatValue];
                    NSLog(@"Theme font size: %.1f", themeFontSize);
                }
            }
        }

        // Set the font for titlebar text rendering
        NSFont *titlebarFont = [NSFont fontWithName:themeFontName size:themeFontSize];
        if (!titlebarFont) {
            // Fallback if LuxiSans is not available
            titlebarFont = [NSFont systemFontOfSize:themeFontSize];
            NSLog(@"Using system font fallback at size %.1f (LuxiSans not available)", themeFontSize);
        } else {
            NSLog(@"Using theme font: %@ %.1f", themeFontName, themeFontSize);
        }

        // *** THEME-AGNOSTIC APPROACH ***
        // Call the theme's titlebar drawing method. Different themes may use
        // different method names:
        //   - Base GSTheme: drawTitleBarRect (uppercase T)
        //   - Eau theme: drawtitleRect (lowercase t)
        // We check for theme-specific methods first, then fall back to base.
        
        NSRect titleBarRect = NSMakeRect(0, 0, titlebarSize.width, titlebarSize.height);
        
        // Pre-fill the entire rect with the theme's border/control stroke color
        // This ensures no black pixels remain at edges where the theme may not draw
        // (e.g., Eau's drawTitleBarBackground insets by 1 pixel)
        NSColor *prefillColor = [NSColor colorWithCalibratedWhite:0.4 alpha:1.0]; // Grey40 #666666 - matches Eau border
        [prefillColor set];
        NSRectFill(titleBarRect);
        
        NSDebugLog(@"DEBUG: Calling theme titlebar drawing with rect=%@", NSStringFromRect(titleBarRect));
        
        // Check for Eau-style drawtitleRect (lowercase 't')
        SEL eauSelector = @selector(drawtitleRect:forStyleMask:state:andTitle:);
        // Check for base drawTitleBarRect (uppercase 'T')
        SEL baseSelector = @selector(drawTitleBarRect:forStyleMask:state:andTitle:);
        
        @try {
            if ([theme respondsToSelector:eauSelector]) {
                // Eau theme (and similar) - call drawtitleRect directly
                NSDebugLog(@"DEBUG: Theme responds to drawtitleRect (Eau-style)");
                
                NSMethodSignature *sig = [theme methodSignatureForSelector:eauSelector];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:eauSelector];
                [inv setTarget:theme];
                [inv setArgument:&titleBarRect atIndex:2];
                [inv setArgument:&styleMask atIndex:3];
                [inv setArgument:&state atIndex:4];
                NSString *titleStr = title ?: @"";
                [inv setArgument:&titleStr atIndex:5];
                [inv invoke];
                
                NSDebugLog(@"DEBUG: Successfully called theme's drawtitleRect");
            } else if ([theme respondsToSelector:baseSelector]) {
                // Base GSTheme - call drawTitleBarRect
                NSDebugLog(@"DEBUG: Theme responds to drawTitleBarRect (base-style)");
                [theme drawTitleBarRect:titleBarRect
                           forStyleMask:styleMask
                                  state:state
                               andTitle:title ?: @""];
                NSDebugLog(@"DEBUG: Successfully called theme's drawTitleBarRect");
            } else {
                // Fallback: simple gray background
                NSDebugLog(@"DEBUG: Theme doesn't respond to any titlebar drawing method, using fallback");
                [[NSColor lightGrayColor] set];
                NSRectFill(titleBarRect);
            }
        } @catch (NSException *e) {
            NSDebugLog(@"DEBUG: Titlebar drawing threw exception: %@, using fallback", e.reason);
            [[NSColor lightGrayColor] set];
            NSRectFill(titleBarRect);
        }
        
        // Restore graphics state
        [gctx restoreGraphicsState];

        // *** BUTTON DRAWING ***
        // Draw rectangular edge buttons: Close on left, Minimize+Maximize on right

        NSLog(@"Drawing edge buttons for theme: %@", [theme name]);

        CGFloat titlebarWidth = titlebarSize.width;
        NSColor *iconColor = [self iconColorForActive:isActive highlighted:NO];

        // Close button at left edge
        if (styleMask & NSClosableWindowMask) {
            NSRect closeFrame = NSMakeRect(0, 0, EDGE_BUTTON_WIDTH, TITLEBAR_HEIGHT);

            // Draw button background
            [self drawEdgeButtonInRect:closeFrame
                              position:TitleBarButtonPositionLeft
                                active:isActive
                           highlighted:NO];

            // Draw X icon
            NSRect iconRect = NSInsetRect(closeFrame, ICON_INSET, ICON_INSET);
            [self drawCloseIconInRect:iconRect withColor:iconColor];

            NSLog(@"Drew close button at: %@", NSStringFromRect(closeFrame));
        }

        // Minimize button at left side of right region
        if (styleMask & NSMiniaturizableWindowMask) {
            CGFloat buttonWidth = RIGHT_REGION_WIDTH / 2.0;
            NSRect miniFrame = NSMakeRect(titlebarWidth - RIGHT_REGION_WIDTH, 0,
                                          buttonWidth, TITLEBAR_HEIGHT);

            // Draw button background
            [self drawEdgeButtonInRect:miniFrame
                              position:TitleBarButtonPositionRightLeft
                                active:isActive
                           highlighted:NO];

            // Draw down-triangle icon
            NSRect iconRect = NSInsetRect(miniFrame, ICON_INSET, ICON_INSET);
            [self drawMinimizeIconInRect:iconRect withColor:iconColor];

            NSLog(@"Drew miniaturize button at: %@", NSStringFromRect(miniFrame));
        }

        // Maximize button at right side of right region
        if (styleMask & NSResizableWindowMask) {
            CGFloat buttonWidth = RIGHT_REGION_WIDTH / 2.0;
            NSRect zoomFrame = NSMakeRect(titlebarWidth - buttonWidth, 0,
                                          buttonWidth, TITLEBAR_HEIGHT);

            // Draw button background
            [self drawEdgeButtonInRect:zoomFrame
                              position:TitleBarButtonPositionRightRight
                                active:isActive
                           highlighted:NO];

            // Draw up-triangle icon
            NSRect iconRect = NSInsetRect(zoomFrame, ICON_INSET, ICON_INSET);
            [self drawMaximizeIconInRect:iconRect withColor:iconColor];

            NSLog(@"Drew zoom button at: %@", NSStringFromRect(zoomFrame));
        }

        [titlebarImage unlockFocus];

        // Transfer the image to the titlebar
        BOOL success = [self transferImage:titlebarImage toTitlebar:titlebar];

        if (success) {
            NSLog(@"Standalone GSTheme titlebar rendered successfully for: %@", title);
        } else {
            NSLog(@"Failed to transfer standalone GSTheme titlebar for: %@", title);
        }

        return success;

    } @catch (NSException *exception) {
        NSLog(@"Standalone GSTheme titlebar rendering failed: %@", exception.reason);
        return NO;
    }
}

#pragma mark - Titlebar Management

+ (void)refreshAllTitlebars {
    URSThemeIntegration *integration = [URSThemeIntegration sharedInstance];

    if (!integration.enabled) {
        return;
    }

    for (XCBTitleBar *titlebar in integration.managedTitlebars) {
        // Determine if window is active (simplified for now)
        BOOL isActive = YES; // TODO: Implement proper active window detection

        [self renderGSThemeTitlebar:titlebar
                              title:titlebar.windowTitle
                             active:isActive];
    }

    NSLog(@"Refreshed %lu titlebars with GSTheme decorations", (unsigned long)[integration.managedTitlebars count]);
}

#pragma mark - Event Handlers

- (void)handleWindowCreated:(XCBTitleBar*)titlebar {
    if (!self.enabled || !titlebar) {
        return;
    }

    // Add to managed windows list
    if (![self.managedTitlebars containsObject:titlebar]) {
        [self.managedTitlebars addObject:titlebar];
        NSLog(@"Added titlebar to GSTheme management: %@", titlebar.windowTitle);
    }

    // Render GSTheme decoration
    [URSThemeIntegration renderGSThemeTitlebar:titlebar
                                         title:titlebar.windowTitle
                                        active:YES];
}

- (void)handleWindowFocusChanged:(XCBTitleBar*)titlebar isActive:(BOOL)active {
    if (!self.enabled || !titlebar) {
        return;
    }

    // Re-render with updated active state
    [URSThemeIntegration renderGSThemeTitlebar:titlebar
                                         title:titlebar.windowTitle
                                        active:active];
}


#pragma mark - Configuration

- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) {
        return; // Prevent recursion
    }

    _enabled = enabled;

    // Set user default to inform XCBKit about GSTheme status
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:@"UROSWMGSThemeEnabled"];
    [defaults synchronize];

    if (enabled) {
        NSLog(@"GSTheme integration enabled - XCBKit will skip Cairo button drawing");
        // Don't call refreshAllTitlebars here - let the periodic timer handle it
    } else {
        NSLog(@"GSTheme integration disabled - falling back to Cairo rendering");
    }
}

#pragma mark - Cleanup

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (void)disableXCBTitleBarDrawing:(XCBTitleBar*)titlebar {
    // This method was declared but not used in our independent implementation
    NSLog(@"URSThemeIntegration: disableXCBTitleBarDrawing called (not needed for independent system)");
}

@end