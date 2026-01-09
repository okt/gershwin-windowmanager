//
//  XCBFrame.m
//  XCBKit
//
//  Created by Alessandro Sangiuliano on 05/08/19.
//  Copyright (c) 2019 alex. All rights reserved.
//

#import "XCBFrame.h"
#import "functions/Transformers.h"
#import "services/ICCCMService.h"
#import "services/TitleBarSettingsService.h"
#import "utils/CairoDrawer.h"
#import <AppKit/NSScroller.h>


@implementation XCBFrame

@synthesize minWidthHint;
@synthesize minHeightHint;
@synthesize connection;
@synthesize rightBorderClicked;
@synthesize bottomBorderClicked;
@synthesize offset;
@synthesize leftBorderClicked;
@synthesize topBorderClicked;
@synthesize titleHeight;

- (id) initWithClientWindow:(XCBWindow *)aClientWindow withConnection:(XCBConnection *)aConnection
{
    return [self initWithClientWindow:aClientWindow
                       withConnection:aConnection
                        withXcbWindow:0
                             withRect:XCBInvalidRect];
}

- (id) initWithClientWindow:(XCBWindow *)aClientWindow
             withConnection:(XCBConnection *)aConnection
              withXcbWindow:(xcb_window_t)xcbWindow
                   withRect:(XCBRect)aRect
{
    self = [super initWithXCBWindow: xcbWindow andConnection:aConnection];
    [self setWindowRect:aRect];
    [self setOriginalRect:aRect];
    /*** checks normal hints for client window **/
    [connection setIsWindowsMapUpdated:NO];
    
    ICCCMService* icccmService = [ICCCMService sharedInstanceWithConnection:connection];
    xcb_size_hints_t *sizeHints = [icccmService wmNormalHintsForWindow:aClientWindow];

    [self setMinHeightHint:sizeHints->min_height];
    [self setMinWidthHint:sizeHints->min_width];


    if (minWidthHint > [aClientWindow windowRect].size.width)
    {
        XCBRect rect = XCBMakeRect(XCBMakePoint(0,0), XCBMakeSize(minWidthHint, [aClientWindow windowRect].size.height));
        [aClientWindow setWindowRect:rect];
        [aClientWindow setOriginalRect:rect];
        rect.size.width = rect.size.width + 1;
        [self setWindowRect: rect];
        [self setOriginalRect:rect];
        uint32_t values[] = {rect.size.width};
        xcb_configure_window([aConnection connection], window, XCB_CONFIG_WINDOW_WIDTH, values);
        values[0] = minWidthHint;
        xcb_configure_window([aConnection connection], [aClientWindow window], XCB_CONFIG_WINDOW_WIDTH, values);
    }

    if (minHeightHint > [aClientWindow windowRect].size.height)
    {
        XCBRect rect = XCBMakeRect(XCBMakePoint(0,0), XCBMakeSize([aClientWindow windowRect].size.width, minHeightHint));
        [aClientWindow setWindowRect:rect];
        [aClientWindow setOriginalRect:rect];
        rect.size.height = rect.size.height + 21;
        [self setWindowRect:rect];
        [self setOriginalRect:rect];
        uint32_t values[] = {rect.size.height};
        xcb_configure_window([aConnection connection], window, XCB_CONFIG_WINDOW_HEIGHT, values);
        values[0] = minHeightHint;
        xcb_configure_window([aConnection connection], [aClientWindow window], XCB_CONFIG_WINDOW_HEIGHT, values);
    }

    connection = aConnection;
    children = [[NSMutableDictionary alloc] init];
    NSNumber *key = [NSNumber numberWithInteger:ClientWindow];
    [children setObject:aClientWindow forKey: key];
    [connection registerWindow:self];

    TitleBarSettingsService *settings = [TitleBarSettingsService sharedInstance];
    titleHeight = [settings heightDefined] ? [settings height] : [settings defaultHeight];

    [super setIsAbove:YES];
    free(sizeHints);
    icccmService = nil;
    key= nil;
    settings = nil;

    return self;
}

- (void) addChildWindow:(XCBWindow *)aChild withKey:(childrenMask) keyMask
{
    NSNumber* key = [NSNumber numberWithInteger:keyMask];
    [children setObject:aChild forKey: key];
    key = nil;
}

- (XCBWindow*) childWindowForKey:(childrenMask)key
{
    NSNumber* keyNumber = [NSNumber numberWithInteger:key];
    XCBWindow* child = [children objectForKey:keyNumber];
    keyNumber = nil;
    return child;
}

-(void)removeChild:(childrenMask)frameChild
{
    NSNumber* key = [NSNumber numberWithInteger:frameChild];
    [children removeObjectForKey:key];
    key = nil;
}

- (void) decorateClientWindow
{
    NSNumber* key = [NSNumber numberWithInteger:ClientWindow];
    XCBWindow *clientWindow = [children objectForKey:key];
    key = nil;

    XCBScreen *scr = [parentWindow screen];
    XCBVisual *rootVisual = [[XCBVisual alloc] initWithVisualId:[scr screen]->root_visual];
    [rootVisual setVisualTypeForScreen:scr];

    uint32_t values[2];
    uint32_t mask = XCB_CW_BACK_PIXEL | XCB_CW_EVENT_MASK;

    values[0] = [scr screen]->white_pixel;
    values[1] = TITLE_MASK_VALUES;

    TitleBarSettingsService *settings = [TitleBarSettingsService sharedInstance];

    uint16_t height = [settings heightDefined] ? [settings height] : [settings defaultHeight];

    XCBCreateWindowTypeRequest* request = [[XCBCreateWindowTypeRequest alloc] initForWindowType:XCBTitleBarRequest];
    [request setDepth:XCB_COPY_FROM_PARENT];
    [request setParentWindow:self];
    [request setXPosition:0];
    [request setYPosition:0];
    [request setWidth:[self windowRect].size.width];
    [request setHeight:height];
    [request setBorderWidth:0];
    [request setXcbClass:XCB_WINDOW_CLASS_INPUT_OUTPUT];
    [request setVisual:rootVisual];
    [request setValueMask:mask];
    [request setValueList:values];

    XCBWindowTypeResponse* response = [[super connection] createWindowForRequest:request registerWindow:YES];
    XCBTitleBar *titleBar = [response titleBar];

    [self addChildWindow:titleBar withKey:TitleBar];

    EWMHService *ewmhService = [EWMHService sharedInstanceWithConnection:connection];

    xcb_get_property_reply_t* reply = [ewmhService getProperty:[ewmhService EWMHWMName]
                              propertyType:XCB_GET_PROPERTY_TYPE_ANY
                                 forWindow:clientWindow
                                    delete:NO
                                    length:UINT32_MAX];

    NSString* windowTitle;
    if (reply)
    {
        char *value = xcb_get_property_value(reply);
        int len = xcb_get_property_value_length(reply);
        NSLog(@"Window title: %s, len: %d", value, len);
        windowTitle = [NSString stringWithCString:value length:len];
    }

    // for now if it is nil just set an empty string

    if (windowTitle == nil)
    {
        ICCCMService* icccmService = [ICCCMService sharedInstanceWithConnection:connection];

        windowTitle = [icccmService getWmNameForWindow:clientWindow];

        if (windowTitle == nil)
            windowTitle = @"";

        icccmService = nil;
    }

    [titleBar onScreen];
    [titleBar updateAttributes];
    [titleBar setIsMapped:YES];
    
    // OPTIMIZATION: Only create pixmaps - skip Cairo drawing if GSTheme will override
    // GSTheme integration in URSHybridEventHandler will render the titlebar contents
    // Creating pixmaps is still needed as GSTheme renders to them
    [titleBar createPixmap];
    
    // OPTIMIZATION: Skip button generation and Cairo drawing when GSTheme is active
    // These operations are expensive and get completely overwritten by GSTheme
    if (![titleBar isGSThemeActive]) {
        [titleBar generateButtons];
        [titleBar setButtonsAbove:YES];
        [titleBar drawTitleBarComponentsPixmaps];
        [titleBar putWindowBackgroundWithPixmap:[titleBar pixmap]];
        [titleBar putButtonsBackgroundPixmaps:YES];
        [titleBar setWindowTitle:windowTitle];
    }
    
    [titleBar setIsAbove:YES];
    [clientWindow setDecorated:YES];
    [clientWindow setWindowBorderWidth:0];
    [connection mapWindow:titleBar];
    
    // Store title for later GSTheme rendering
    [titleBar setInternalTitle:windowTitle];

    // Position client window directly below titlebar with no gap
    XCBPoint position = XCBMakePoint(0, height);
    [connection reparentWindow:clientWindow toWindow:self position:position];
    [connection mapWindow:clientWindow];
    uint32_t border[] = {0};
    // Ensure no borders on frame window
    xcb_configure_window([connection connection], window, XCB_CONFIG_WINDOW_BORDER_WIDTH, border);
    // Ensure no borders on client window
    xcb_configure_window([connection connection], [clientWindow window], XCB_CONFIG_WINDOW_BORDER_WIDTH, border);
    
    // Flush to ensure reparent and map operations complete before continuing
    [connection flush];
    
    // Create resize handle for resizable windows with decorations only
    if ([clientWindow canResize] && [clientWindow decorated]) {
        [self createResizeHandle];
    }

    titleBar = nil;
    clientWindow = nil;
    ewmhService = nil;
    windowTitle = nil;
    scr = nil;
    rootVisual = nil;
    settings = nil;

    free(reply);
}

- (void)createResizeHandle
{
    XCBScreen *scr = [parentWindow screen];
    
    // Get scrollbar width from current theme
    CGFloat scrollerWidth = [NSScroller scrollerWidth];
    uint16_t handleSize = (uint16_t)scrollerWidth;
    
    // Create a square at bottom-right matching scrollbar width
    xcb_window_t resizeHandleWindow = xcb_generate_id([connection connection]);
    
    XCBRect frameRect = [self windowRect];
    int16_t handleX = frameRect.size.width - handleSize;
    int16_t handleY = frameRect.size.height - handleSize;
    
    uint32_t mask = XCB_CW_BACK_PIXEL | XCB_CW_EVENT_MASK | XCB_CW_CURSOR;
    uint32_t values[3];
    
    // Blue color for the handle
    xcb_alloc_color_cookie_t color_cookie = xcb_alloc_color([connection connection],
                                                             [scr screen]->default_colormap,
                                                             0, 0, 65535); // Blue: RGB(0,0,255)
    xcb_alloc_color_reply_t *color_reply = xcb_alloc_color_reply([connection connection], color_cookie, NULL);
    uint32_t blue_pixel = color_reply ? color_reply->pixel : [scr screen]->white_pixel;
    free(color_reply);
    
    // Get diagonal resize cursor (bottom-right)
    xcb_cursor_t resizeCursor = [[self cursor] selectResizeCursorForPosition:BottomRightCorner];
    
    values[0] = blue_pixel;
    values[1] = XCB_EVENT_MASK_BUTTON_PRESS | XCB_EVENT_MASK_BUTTON_RELEASE | 
                XCB_EVENT_MASK_POINTER_MOTION | XCB_EVENT_MASK_ENTER_WINDOW | XCB_EVENT_MASK_LEAVE_WINDOW;
    values[2] = resizeCursor;
    
    xcb_create_window([connection connection],
                      XCB_COPY_FROM_PARENT,
                      resizeHandleWindow,
                      window, // Parent is the frame
                      handleX, handleY,
                      handleSize, handleSize,
                      0, // no border
                      XCB_WINDOW_CLASS_INPUT_OUTPUT,
                      [scr screen]->root_visual,
                      mask,
                      values);
    
    // Create XCBWindow wrapper and register it
    XCBWindow *resizeHandle = [[XCBWindow alloc] initWithXCBWindow:resizeHandleWindow andConnection:connection];
    [resizeHandle setParentWindow:self];
    [self addChildWindow:resizeHandle withKey:ResizeHandle];
    [connection registerWindow:resizeHandle];
    
    // Map the resize handle
    xcb_map_window([connection connection], resizeHandleWindow);
    [connection flush];
    
    NSLog(@"Created resize handle for frame %u at position (%d, %d) with size %u (scrollbar width)", 
          window, handleX, handleY, handleSize);
}

/*** performance while resizing pixel by pixel is critical so we do everything we can to improve it also if the message signature looks bad ***/

- (void) resize:(xcb_motion_notify_event_t *)anEvent xcbConnection:(xcb_connection_t*)aXcbConnection
{

    /*** width ***/

    if (rightBorderClicked && !bottomBorderClicked && !leftBorderClicked && !topBorderClicked)
    {
        resizeFromRightForEvent(anEvent, aXcbConnection, self, minWidthHint);
        //[self configureClient];
    }

    if (leftBorderClicked && !bottomBorderClicked && !rightBorderClicked && !topBorderClicked)
    {
        resizeFromLeftForEvent(anEvent, aXcbConnection, self, minWidthHint);
        //[self configureClient];
    }


    /** height **/

    if (bottomBorderClicked && !rightBorderClicked && !leftBorderClicked)
    {
        resizeFromBottomForEvent(anEvent, aXcbConnection, self, minHeightHint, titleHeight);
        //[self configureClient];
    }


    if (topBorderClicked && !rightBorderClicked && !leftBorderClicked && !bottomBorderClicked)
    {
        resizeFromTopForEvent(anEvent, aXcbConnection, self, minHeightHint, titleHeight);
        //[self configureClient];
    }


    /** width and height **/

    if (rightBorderClicked && bottomBorderClicked && !leftBorderClicked)
    {
        resizeFromAngleForEvent(anEvent, aXcbConnection, self, minWidthHint, minHeightHint, titleHeight);
        //[self configureClient];
    }
    
    // Update resize handle position if it exists
    [self updateResizeHandlePosition];

}

- (void)updateResizeHandlePosition
{
    XCBWindow *resizeHandle = [self childWindowForKey:ResizeHandle];
    if (resizeHandle) {
        // Get current scrollbar width from theme
        CGFloat scrollerWidth = [NSScroller scrollerWidth];
        uint16_t handleSize = (uint16_t)scrollerWidth;
        
        XCBRect frameRect = [self windowRect];
        int16_t handleX = frameRect.size.width - handleSize;
        int16_t handleY = frameRect.size.height - handleSize;
        
        uint32_t values[2] = {handleX, handleY};
        xcb_configure_window([connection connection], 
                           [resizeHandle window], 
                           XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y, 
                           values);
    }
}

void resizeFromRightForEvent(xcb_motion_notify_event_t *anEvent,
                             xcb_connection_t *connection,
                             XCBFrame* frame,
                             int minW)
{
    XCBWindow* clientWindow = [frame childWindowForKey:ClientWindow];
    XCBTitleBar* titleBar = (XCBTitleBar*)[frame childWindowForKey:TitleBar];
    //xcb_connection_t *connection = [[frame connection] connection];

    XCBRect frameRect = [frame windowRect];
    XCBRect titleBarRect = [titleBar windowRect];
    XCBRect clientRect = [clientWindow windowRect];

    uint32_t values[] = {anEvent->event_x};

    if (frameRect.size.width <= minW && anEvent->event_x < minW)
    {
        frameRect.size.width = minW;
        titleBarRect.size.width = minW;
        clientRect.size.width = minW;
        values[0] = minW;
        xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_WIDTH, &values);
        xcb_configure_window(connection, [titleBar window], XCB_CONFIG_WINDOW_WIDTH, &values);
        xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_WIDTH, &values);

        [frame setWindowRect:frameRect];
        [frame setOriginalRect:frameRect];

        [titleBar setWindowRect:titleBarRect];
        [titleBar setOriginalRect:titleBarRect];

        [clientWindow setWindowRect:clientRect];
        [clientWindow setOriginalRect:clientRect];
        //[titleBar drawTitleBarComponentsForColor:TitleBarUpColor];

        clientWindow = nil;
        titleBar = nil;
        connection = NULL;
        return;
    }

    xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_WIDTH, &values);
    xcb_configure_window(connection, [titleBar window], XCB_CONFIG_WINDOW_WIDTH, &values);
    xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_WIDTH, &values);
    
    // Flush to ensure smooth resizing updates
    xcb_flush(connection);
    
    frameRect.size.width = anEvent->event_x;

    [frame setWindowRect:frameRect];
    [frame setOriginalRect:frameRect];

    titleBarRect.size.width = anEvent->event_x;
    [titleBar setWindowRect:titleBarRect];
    [titleBar setOriginalRect:titleBarRect];

    clientRect.size.width = anEvent->event_x;
    [clientWindow setWindowRect:clientRect];
    [clientWindow setOriginalRect:clientRect];
    //[titleBar drawTitleBarComponentsForColor:TitleBarUpColor];

    clientWindow = nil;
    titleBar = nil;
    connection = NULL;
}

void resizeFromLeftForEvent(xcb_motion_notify_event_t *anEvent,
                            xcb_connection_t *connection,
                            XCBFrame* frame,
                            int minW)
{
    XCBWindow* clientWindow = [frame childWindowForKey:ClientWindow];
    XCBTitleBar* titleBar = (XCBTitleBar*)[frame childWindowForKey:TitleBar];
    //xcb_connection_t *connection = [[frame connection] connection];

    XCBRect rect = [frame windowRect];
    XCBRect titleBarRect = [titleBar windowRect];
    XCBRect clientRect = [clientWindow windowRect];

    int xDelta = rect.position.x - anEvent->root_x;
    uint32_t values[] = {anEvent->root_x, xDelta + rect.size.width};

    if (rect.size.width <= minW && anEvent->root_x > rect.position.x)
    {
        // When hitting minimum width, maintain the right edge position
        // Calculate the correct left position to preserve right edge
        int rightEdge = rect.position.x + rect.size.width;
        int newX = rightEdge - minW;

        rect.size.width = minW;
        rect.position.x = newX;
        titleBarRect.size.width = minW;
        titleBarRect.position.x = 0; // Relative to frame
        clientRect.size.width = minW;
        clientRect.position.x = 0; // Relative to frame

        values[0] = newX;
        values[1] = minW;
        xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_WIDTH, &values);
        values[0] = 0;
        xcb_configure_window(connection, [titleBar window], XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_WIDTH, &values);
        xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_WIDTH, &values);

        [frame setWindowRect:rect];
        [frame setOriginalRect:rect];

        titleBarRect.position.x = values[0];
        titleBarRect.size.width = values[1];
        [titleBar setWindowRect:titleBarRect];
        [titleBar setOriginalRect:titleBarRect];

        clientRect.position.x = values[0];
        clientRect.size.width = values[1];
        [clientWindow setWindowRect:clientRect];
        [clientWindow setOriginalRect:clientRect];
        //[titleBar drawTitleBarComponentsForColor:TitleBarUpColor];

        clientWindow = nil;
        titleBar = nil;
        connection = NULL;
        return;
    }


    xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_WIDTH, &values);
    rect.position.x = values[0];
    rect.size.width = values[1];
    values[0] = 0;
    xcb_configure_window(connection, [titleBar window], XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_WIDTH, &values);
    xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_WIDTH, &values);
    
    // Flush to ensure smooth resizing updates
    xcb_flush(connection);

    [frame setWindowRect:rect];
    [frame setOriginalRect:rect];

    titleBarRect.position.x = values[0];
    titleBarRect.size.width = values[1];
    [titleBar setWindowRect:titleBarRect];
    [titleBar setOriginalRect:titleBarRect];

    clientRect.position.x = values[0];
    clientRect.size.width = values[1];
    [clientWindow setWindowRect:clientRect];
    [clientWindow setOriginalRect:clientRect];
    //[titleBar drawTitleBarComponentsForColor:TitleBarUpColor];

    clientWindow = nil;
    titleBar = nil;
    connection = NULL;

}

void resizeFromBottomForEvent(xcb_motion_notify_event_t *anEvent,
                              xcb_connection_t *connection,
                              XCBFrame* frame,
                              int minH,
                              uint16_t titleBarHeight)
{
    XCBWindow* clientWindow = [frame childWindowForKey:ClientWindow];
    //xcb_connection_t *connection = [[frame connection] connection];

    XCBRect rect = [frame windowRect];
    XCBRect clientRect = [clientWindow windowRect];

    uint32_t values[] = {anEvent->event_y};

    if (rect.size.height <= minH + titleBarHeight && anEvent->event_y < minH)
    {
        rect.size.height = minH + titleBarHeight;
        clientRect.size.height = minH;
        values[0] = clientRect.size.height;
        xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_HEIGHT, &values);
        values[0] = rect.size.height;
        xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_HEIGHT, &values);

        [frame setWindowRect:rect];
        [frame setOriginalRect:rect];

        [clientWindow setWindowRect:clientRect];
        [clientWindow setOriginalRect:clientRect];

        clientWindow = nil;
        connection = NULL;
        return;
    }

    values[0] = anEvent->event_y - titleBarHeight;
    xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_HEIGHT, &values);
    clientRect.size.height = values[0];
    values[0] = anEvent->event_y;
    xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_HEIGHT, &values);
    
    // Flush to ensure smooth resizing updates
    xcb_flush(connection);
    
    [clientWindow setWindowRect:clientRect];
    [clientWindow setOriginalRect:clientRect];


    rect.size.height = values[0];
    [frame setWindowRect:rect];
    [frame setOriginalRect:rect];

    clientWindow = nil;
    connection = NULL;
}

void resizeFromTopForEvent(xcb_motion_notify_event_t *anEvent,
                           xcb_connection_t *connection,
                           XCBFrame* frame,
                           int minH,
                           uint16_t titleBarHeight)
{
    XCBWindow* clientWindow = [frame childWindowForKey:ClientWindow];
    XCBTitleBar* titleBar = (XCBTitleBar*)[frame childWindowForKey:TitleBar];
    //xcb_connection_t *connection = [[frame connection] connection];

    XCBRect rect = [frame windowRect];
    XCBRect titleBarRect = [titleBar windowRect];
    XCBRect clientRect = [clientWindow windowRect];

    int yDelta = rect.position.y - anEvent->root_y;

    uint32_t values[] = {anEvent->root_y, yDelta + rect.size.height};

    if (rect.size.height <= minH + titleBarHeight && anEvent->root_y > rect.position.y)
    {
        // When hitting minimum height, maintain the bottom edge position
        // Calculate the correct top position to preserve bottom edge
        int bottomEdge = rect.position.y + rect.size.height;
        int newY = bottomEdge - (minH + titleBarHeight + 2);  // +2 for top and bottom borders

        rect.size.height = minH + titleBarHeight + 2;  // +2 for borders
        rect.position.y = newY;
        clientRect.size.height = minH;
        clientRect.position.y = 1 + titleBarHeight;  // Inside top border + titlebar

        values[0] = clientRect.position.y;
        values[1] = clientRect.size.height;
        xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_Y | XCB_CONFIG_WINDOW_HEIGHT, &values);

        values[0] = newY;
        values[1] = rect.size.height;
        xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_Y | XCB_CONFIG_WINDOW_HEIGHT, &values);


        [frame setWindowRect:rect];
        [frame setOriginalRect:rect];

        [clientWindow setWindowRect:clientRect];
        [clientWindow setOriginalRect:clientRect];

        titleBar = nil;
        clientWindow = nil;
        connection = NULL;

        return;
    }

    xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_Y | XCB_CONFIG_WINDOW_HEIGHT, &values);

    rect.position.y = values[0];
    rect.size.height = values[1];
    values[0] = 1;  // Inside top border

    xcb_configure_window(connection, [titleBar window], XCB_CONFIG_WINDOW_Y, &values);

    titleBarRect.position.y = values[0];

    values[0] = 1 + titleBarHeight;  // Inside top border + titlebar height
    values[1] = rect.size.height - titleBarHeight;  // Subtract titlebar height only

    xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_Y | XCB_CONFIG_WINDOW_HEIGHT, &values);
    clientRect.size.height = values[1];
    
    // Flush to ensure smooth resizing updates
    xcb_flush(connection);

    [frame setWindowRect:rect];
    [frame setOriginalRect:rect];

    [titleBar setWindowRect:titleBarRect];
    [titleBar setOriginalRect:titleBarRect];


    [clientWindow setWindowRect:clientRect];
    [clientWindow setOriginalRect:clientRect];

    clientWindow = nil;
    titleBar = nil;
    connection = NULL;
}

void resizeFromAngleForEvent(xcb_motion_notify_event_t *anEvent,
                             xcb_connection_t *connection,
                             XCBFrame *frame,
                             int minW,
                             int minH,
                             uint16_t titleBarHeight)
{
    XCBWindow* clientWindow = [frame childWindowForKey:ClientWindow];
    XCBTitleBar* titleBar = (XCBTitleBar*)[frame childWindowForKey:TitleBar];
    //xcb_connection_t *connection = [[frame connection] connection];

    XCBRect rect = [frame windowRect];
    XCBRect titleBarRect = [titleBar windowRect];
    XCBRect clientRect = [clientWindow windowRect];

    uint32_t values[] = {anEvent->event_x, anEvent->event_y};

    if (rect.size.width <= minW && anEvent->event_x < minW &&
        rect.size.height <= minH + titleBarHeight && anEvent->event_y < minH)
    {
        rect.size.width = minW;
        titleBarRect.size.width = minW;
        clientRect.size.width = minW;

        rect.size.height = minH + titleBarHeight;
        clientRect.size.height = minH;

        values[0] = rect.size.width;
        values[1] = rect.size.height;

        xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, &values);
        values[0] = titleBarRect.size.width;
        xcb_configure_window(connection, [titleBar window], XCB_CONFIG_WINDOW_WIDTH, &values);
        values[0] = clientRect.size.width;
        values[1] = clientRect.size.height;
        xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, &values);

        [frame setWindowRect:rect];
        [frame setOriginalRect:rect];

        [titleBar setWindowRect:titleBarRect];
        [titleBar setOriginalRect:titleBarRect];

        [clientWindow setWindowRect:clientRect];
        [clientWindow setOriginalRect:clientRect];
        //[titleBar drawTitleBarComponentsForColor:TitleBarUpColor];

        titleBar = nil;
        clientWindow = nil;
        connection = NULL;

        return;
    }

    xcb_configure_window(connection, [frame window], XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, &values);
    xcb_configure_window(connection, [titleBar window], XCB_CONFIG_WINDOW_WIDTH, &values);
    values[1] = values[1] - titleBarHeight;
    xcb_configure_window(connection, [clientWindow window], XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, &values);
    
    // Flush to ensure smooth resizing updates
    xcb_flush(connection);

    rect.size.width = anEvent->event_x;
    rect.size.height = anEvent->event_y;
    [frame setWindowRect:rect];
    [frame setOriginalRect:rect];


    titleBarRect.size.width = anEvent->event_x;
    [titleBar setWindowRect:titleBarRect];
    [titleBar setOriginalRect:titleBarRect];

    clientRect.size.width = anEvent->event_x;
    clientRect.size.height = values[1];
    [clientWindow setWindowRect:clientRect];
    [clientWindow setOriginalRect:clientRect];
    //[titleBar drawTitleBarComponentsForColor:TitleBarUpColor];

    titleBar = nil;
    clientWindow = nil;
    connection = NULL;
}

- (void) moveTo:(XCBPoint)coordinates
{
    // Minimal implementation for maximum performance
    XCBPoint pos = XCBMakePoint(coordinates.x - offset.x, coordinates.y - offset.y);

    uint32_t values[] = {(uint32_t)pos.x, (uint32_t)pos.y};
    xcb_configure_window([connection connection], window, XCB_CONFIG_WINDOW_X | XCB_CONFIG_WINDOW_Y, values);
    // PERFORMANCE FIX: Don't flush on every motion event - let the event loop batch flushes
    // xcb_flush([connection connection]);

    // Update internal state only - skip expensive rect operations during drag
    XCBRect rect = [super windowRect];
    rect.position = pos;
    [super setWindowRect:rect];
}

- (void) configureClient
{
    xcb_configure_notify_event_t event;
    XCBWindow *clientWindow = [self childWindowForKey:ClientWindow];
    XCBRect rect = [[self geometries] rect];
    XCBRect clientRect = [clientWindow rectFromGeometries];
    TitleBarSettingsService *settings = [TitleBarSettingsService sharedInstance];
    uint16_t height = [settings heightDefined] ? [settings height] : [settings defaultHeight];

    /*** synthetic event: coordinates must be in root space. ***/

    event.event = [clientWindow window];
    event.window = [clientWindow window];
    event.x = rect.position.x;
    event.y = rect.position.y + height;
    event.border_width = 0;
    event.width = clientRect.size.width;
    event.height = clientRect.size.height;
    event.override_redirect = 0;
    event.above_sibling = XCB_NONE;
    event.response_type = XCB_CONFIGURE_NOTIFY;
    event.sequence = 0;

    [connection sendEvent:(const char*) &event toClient:clientWindow propagate:NO];

    [clientWindow setWindowRect:clientRect];

    clientWindow = nil;
    settings = nil;
}

- (MousePosition) mouseIsOnWindowBorderForEvent:(xcb_motion_notify_event_t *)anEvent
{
    int rightBorder = [super windowRect].size.width;
    int bottomBorder = [super windowRect].size.height;
    int leftBorder = [super windowRect].position.x;
    int topBorder = [super windowRect].position.y;
    MousePosition position = None;

    if (rightBorder == anEvent->event_x || (rightBorder - 3) < anEvent->event_x)
    {
        position = RightBorder;
    }


    if (bottomBorder == anEvent->event_y || (bottomBorder - 3) < anEvent->event_y)
    {
        position = BottomBorder;
    }

    if ((bottomBorder == anEvent->event_y || (bottomBorder - 3) < anEvent->event_y) &&
        (rightBorder == anEvent->event_x || (rightBorder - 3) < anEvent->event_x))
    {
        position = BottomRightCorner;
    }

    if (leftBorder == anEvent->root_x || (leftBorder + 3) > anEvent->root_x)
    {
        position = LeftBorder;
    }

    if (topBorder == anEvent->root_y || (topBorder + 3) > anEvent->root_y)
    {
        position = TopBorder;
    }

    return position;

}

- (void) restoreDimensionAndPosition
{
    XCBWindow *clientWindow = [self childWindowForKey:ClientWindow];
    XCBTitleBar *titleBar = (XCBTitleBar*)[self childWindowForKey:TitleBar];

    [super restoreDimensionAndPosition];
    [clientWindow restoreDimensionAndPosition];
    [titleBar restoreDimensionAndPosition];
    [titleBar drawTitleBarComponents];

    clientWindow = nil;
    titleBar = nil;
}


/********************************
 *                               *
 *            ACCESSORS          *
 *                               *
 ********************************/

- (void)setChildren:(NSMutableDictionary *)aChildrenSet
{
    children = aChildrenSet;
}

-(NSMutableDictionary*) getChildren
{
    return children;
}

- (void) dealloc
{
    [children removeAllObjects]; //not needed probably
    children = nil;
}


@end
