#include "DesktopNotification.h"
#import <UserNotifications/UserNotifications.h>

// Delegate that allows notifications to display while the app is in the foreground
@interface AuphonicNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation AuphonicNotificationDelegate

- (void) userNotificationCenter: (UNUserNotificationCenter*) center
        willPresentNotification: (UNNotification*) notification
          withCompletionHandler: (void (^)(UNNotificationPresentationOptions)) completionHandler
{
    completionHandler (UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}

@end

static AuphonicNotificationDelegate* getDelegate()
{
    static AuphonicNotificationDelegate* delegate = [[AuphonicNotificationDelegate alloc] init];
    return delegate;
}

void DesktopNotification::show (const juce::String& title, const juce::String& body)
{
    auto* center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = getDelegate();

    // Convert to NSString before the async block to avoid dangling references
    NSString* nsTitle = (NSString* _Nonnull) @(title.toRawUTF8());
    NSString* nsBody  = (NSString* _Nonnull) @(body.toRawUTF8());

    [center requestAuthorizationWithOptions: UNAuthorizationOptionAlert | UNAuthorizationOptionSound
                          completionHandler: ^(BOOL granted, NSError* error)
    {
        juce::ignoreUnused (error);
        if (! granted)
            return;

        auto* content = [[UNMutableNotificationContent alloc] init];
        content.title = nsTitle;
        content.body  = nsBody;
        content.sound = [UNNotificationSound defaultSound];

        auto* request = [UNNotificationRequest requestWithIdentifier: [[NSUUID UUID] UUIDString]
                                                             content: content
                                                             trigger: nil];

        [center addNotificationRequest: request withCompletionHandler: nil];
    }];
}
