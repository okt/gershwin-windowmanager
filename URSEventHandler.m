//
//  URSEventHandler.m
//  uroswm
//
//  Created by Alessandro Sangiuliano on 22/06/20.
//  Copyright (c) 2020 Alessandro Sangiuliano. All rights reserved.
//

#import "URSEventHandler.h"
#import <XCBKit/XCBScreen.h>
#import <xcb/xcb.h>
#import <XCBKit/services/EWMHService.h>

@implementation URSEventHandler

@synthesize connection;
@synthesize selectionManagerWindow;


- (id) init
{
    self  = [super init];

    if (self == nil)
    {
        NSLog(@"Unable to init...");
        return nil;
    }

    connection = [XCBConnection sharedConnectionAsWindowManager:YES];

    return self;
}

- (void) registerAsWindowManager
{
    XCBScreen *screen = [[connection screens] objectAtIndex:0];
    XCBVisual *visual = [[XCBVisual alloc] initWithVisualId:[screen screen]->root_visual];
    [visual setVisualTypeForScreen:screen];


    selectionManagerWindow = [connection createWindowWithDepth:[screen screen]->root_depth
                                                     withParentWindow:[screen rootWindow]
                                                        withXPosition:-1
                                                        withYPosition:-1
                                                            withWidth:1
                                                           withHeight:1
                                                     withBorrderWidth:0
                                                         withXCBClass:XCB_COPY_FROM_PARENT
                                                         withVisualId:visual
                                                        withValueMask:0
                                                        withValueList:NULL
                                                      registerWindow:YES];

    [connection registerAsWindowManager:YES screenId:0 selectionWindow:selectionManagerWindow];

    EWMHService *ewmhService = [EWMHService sharedInstanceWithConnection:connection];
    [ewmhService putPropertiesForRootWindow:[screen rootWindow] andWmWindow:selectionManagerWindow];
    [connection flush];

    screen = nil;
    visual = nil;
    ewmhService = nil;
}

- (void) startEventHandlerLoop
{
    xcb_generic_event_t *e;
    xcb_motion_notify_event_t *lastMotionEvent = NULL;
    BOOL needFlush = NO;

    while ((e = xcb_wait_for_event([connection connection])))
    {
        switch (e->response_type & ~0x80)
        {
            case XCB_VISIBILITY_NOTIFY:
            {
                xcb_visibility_notify_event_t *visibilityEvent = (xcb_visibility_notify_event_t *) e;
                [connection handleVisibilityEvent:visibilityEvent];
                break;
            }
            case XCB_EXPOSE:
            {
                xcb_expose_event_t *exposeEvent = (xcb_expose_event_t *) e;
                [connection handleExpose:exposeEvent];
                needFlush = YES;
                break;
            }
            case XCB_MOTION_NOTIFY:
            {
                // Motion event compression: save the latest motion event
                if (lastMotionEvent) {
                    free(lastMotionEvent);
                }
                lastMotionEvent = malloc(sizeof(xcb_motion_notify_event_t));
                memcpy(lastMotionEvent, e, sizeof(xcb_motion_notify_event_t));

                // Check if more events are queued - if so, skip processing this one
                xcb_generic_event_t *nextEvent = xcb_poll_for_event([connection connection]);
                if (nextEvent) {
                    // There's another event queued, defer motion processing
                    free(e);
                    e = nextEvent;
                    continue; // Process the next event instead
                } else {
                    // No more events, process the motion
                    [connection handleMotionNotify:lastMotionEvent];
                    needFlush = YES;
                    free(lastMotionEvent);
                    lastMotionEvent = NULL;
                }
                break;
            }
            case XCB_ENTER_NOTIFY:
            {
                xcb_enter_notify_event_t *enterEvent = (xcb_enter_notify_event_t *) e;
                [connection handleEnterNotify:enterEvent];
                break;
            }
            case XCB_LEAVE_NOTIFY:
            {
                xcb_leave_notify_event_t *leaveEvent = (xcb_leave_notify_event_t *) e;
                [connection handleLeaveNotify:leaveEvent];
                break;
            }
            case XCB_FOCUS_IN:
            {
                xcb_focus_in_event_t *focusInEvent = (xcb_focus_in_event_t *) e;
                [connection handleFocusIn:focusInEvent];
                break;
            }
            case XCB_FOCUS_OUT:
            {
                xcb_focus_out_event_t *focusOutEvent = (xcb_focus_out_event_t *) e;
                [connection handleFocusOut:focusOutEvent];
                break;
            }
            case XCB_BUTTON_PRESS:
            {
                xcb_button_press_event_t *pressEvent = (xcb_button_press_event_t *) e;
                [connection handleButtonPress:pressEvent];
                needFlush = YES;  // Button press important for responsiveness
                break;
            }
            case XCB_BUTTON_RELEASE:
            {
                xcb_button_release_event_t *releaseEvent = (xcb_button_release_event_t *) e;
                [connection handleButtonRelease:releaseEvent];
                needFlush = YES;  // Button release important for responsiveness
                break;
            }
            case XCB_MAP_NOTIFY:
            {
                //NSLog(@"");
                xcb_map_notify_event_t *notifyEvent = (xcb_map_notify_event_t *) e;
                //NSLog(@"MAP NOTIFY for window %u", notifyEvent->window);
                [connection handleMapNotify:notifyEvent];
                break;
            }
            case XCB_MAP_REQUEST:
            {
                xcb_map_request_event_t *mapRequestEvent = (xcb_map_request_event_t *) e;
                [connection handleMapRequest:mapRequestEvent];
                needFlush = YES;
                break;
            }
            case XCB_UNMAP_NOTIFY:
            {
                xcb_unmap_notify_event_t *unmapNotifyEvent = (xcb_unmap_notify_event_t *) e;
                [connection handleUnMapNotify:unmapNotifyEvent];
                break;
            }
            case XCB_DESTROY_NOTIFY:
            {
                xcb_destroy_notify_event_t *destroyNotify = (xcb_destroy_notify_event_t *) e;
                [connection handleDestroyNotify:destroyNotify];
                needFlush = YES;
                break;
            }
            case XCB_CLIENT_MESSAGE:
            {
                xcb_client_message_event_t *clientMessageEvent = (xcb_client_message_event_t *)e;
                [connection handleClientMessage:clientMessageEvent];
                needFlush = YES;
                break;
            }
            case XCB_CONFIGURE_REQUEST:
            {
                xcb_configure_request_event_t *configRequest = (xcb_configure_request_event_t *) e;
                [connection handleConfigureWindowRequest:configRequest];
                needFlush = YES;
                break;
            }
            case XCB_CONFIGURE_NOTIFY:
            {
                xcb_configure_notify_event_t *configureNotify = (xcb_configure_notify_event_t *) e;
                [connection handleConfigureNotify:configureNotify];
                break;
            }
            case XCB_PROPERTY_NOTIFY:
            {
                xcb_property_notify_event_t *propEvent = (xcb_property_notify_event_t *) e;
                [connection handlePropertyNotify:propEvent];
                break;
            }
            default:
                break;
        }

        // Batched flush: only flush when needed and at end of event processing
        if (needFlush) {
            [connection flush];
            [connection setNeedFlush:NO];
            needFlush = NO;
        }

        free(e);
    }

}

- (void) dealloc
{
    connection = nil;
    selectionManagerWindow = nil;
}
@end
