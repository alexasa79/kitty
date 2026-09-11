// License: GPLv3
// Exercise the built Cocoa view in-process, without inspecting other apps or
// requiring Accessibility permissions. Only the terminal selection is mocked.
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *selection = nil;
static NSMutableArray<NSString *> *notifications;
static NSString *reader_cached_text;

static void record_notification(id self, SEL cmd, NSString *notification) {
    (void)cmd;
    [notifications addObject:notification];
    reader_cached_text = [self accessibilityValue];
}

static NSString *selected_text(id self, SEL cmd) {
    (void)self; (void)cmd;
    return selection;
}

static void require_true(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void check_selection(id view, NSString *text, NSUInteger expected_length) {
    selection = text;
    NSString *expected = text ? text : @"";
    NSRange range = [view accessibilitySelectedTextRange];
    require_true(NSEqualRanges(range, NSMakeRange(0, expected_length)), "selection range must use UTF-16 offsets");
    require_true([[view accessibilityValue] isEqual:expected], "AXValue must expose the selected text");
    require_true([view accessibilityNumberOfCharacters] == (NSInteger)expected_length, "character count must match the selection");
    require_true(NSEqualRanges([view accessibilityVisibleCharacterRange], range), "visible range must match the exposed buffer");
    NSArray<NSValue *> *ranges = [view accessibilitySelectedTextRanges];
    require_true(ranges.count == 1 && NSEqualRanges(ranges[0].rangeValue, range), "plural selection ranges must agree");
    require_true([[view accessibilityStringForRange:range] isEqual:expected], "range-based extraction must return selected text");
    require_true([[[view accessibilityAttributedStringForRange:range] string] isEqual:expected], "attributed extraction must return selected text");
    require_true([[view accessibilityStringForRange:NSMakeRange(expected_length, 0)] isEqual:@""], "empty range at end is valid");
    require_true([view accessibilityStringForRange:NSMakeRange(NSNotFound, 1)] == nil, "NSNotFound must be rejected");
    require_true([view accessibilityStringForRange:NSMakeRange(1, NSUIntegerMax)] == nil, "overflowing range must be rejected");
    require_true([view accessibilityAttributedStringForRange:NSMakeRange(expected_length + 1, 0)] == nil, "out of bounds attributed range must be rejected");
    require_true(NSEqualRanges([view selectedRange], NSMakeRange(0, 0)), "dictation insertion position must remain unchanged");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        require_true(argc == 2, "expected Cocoa module path");
        void *handle = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
        require_true(handle != NULL, dlerror());
        Class base = NSClassFromString(@"GLFWContentView");
        require_true(base != Nil, "Cocoa view must be loaded");
        Class test_class = objc_allocateClassPair(base, "SelectionTestView", 0);
        Method getter = class_getInstanceMethod(base, @selector(accessibilitySelectedText));
        require_true(class_addMethod(test_class, @selector(accessibilitySelectedText), (IMP)selected_text, method_getTypeEncoding(getter)), "install selection fixture");
        SEL post = NSSelectorFromString(@"postAccessibilitySelectionNotification:");
        Method post_method = class_getInstanceMethod(base, post);
        require_true(post_method != NULL, "selection change notification support must exist");
        require_true(class_addMethod(test_class, post, (IMP)record_notification, method_getTypeEncoding(post_method)), "install notification observer");
        objc_registerClassPair(test_class);
        id view = ((id (*)(id, SEL, void *))objc_msgSend)([test_class alloc], NSSelectorFromString(@"initWithGlfwWindow:"), NULL);
        require_true(view != nil, "create view");
        check_selection(view, @"hello", 5);
        for (NSString *name in @[@"accessibilitySelectedText", @"accessibilitySelectedTextRange", @"accessibilitySelectedTextRanges",
                @"accessibilityValue", @"accessibilityNumberOfCharacters", @"accessibilityVisibleCharacterRange",
                @"accessibilityStringForRange:", @"accessibilityAttributedStringForRange:", @"isAccessibilityFocused"]) {
            require_true([view isAccessibilitySelectorAllowed:NSSelectorFromString(name)], name.UTF8String);
        }
        require_true(![view isAccessibilityFocused], "detached view must not claim focus");
        check_selection(view, nil, 0);
        check_selection(view, @"", 0);
        check_selection(view, @"A\U0001F600e\u0301\n\u4E2D", 7);
        require_true([[view accessibilityStringForRange:NSMakeRange(1, 2)] isEqual:@"\U0001F600"], "surrogate pair extraction");
        require_true([[view accessibilityStringForRange:NSMakeRange(3, 2)] isEqual:@"e\u0301"], "combining mark extraction");
        NSRange old_range = [view accessibilitySelectedTextRange];
        selection = @"x";
        require_true([view accessibilityStringForRange:old_range] == nil, "stale range after selection shrinks must be rejected");
        check_selection(view, nil, 0);
        // Readers cache the native view, which is shared by all Kitty tabs.
        // Both notifications must let a reader refresh its value on each switch.
        notifications = [NSMutableArray array];
        SEL changed = NSSelectorFromString(@"notifyAccessibilitySelectionChanged");
        require_true([view respondsToSelector:changed], "selection change entry point must exist");
        for (NSString *tab_text in @[@"first tab", @"second tab", @"first tab", @"", @"new selection"]) {
            selection = tab_text;
            [notifications removeAllObjects];
            ((void (*)(id, SEL))objc_msgSend)(view, changed);
            require_true([notifications isEqual:@[NSAccessibilityValueChangedNotification, NSAccessibilitySelectedTextChangedNotification]], "notify both value and selection changes");
            require_true([reader_cached_text isEqual:tab_text], "reader must refresh cached text after tab/selection changes");
        }
        printf("accessibility selection probe passed\n");
    }
    return 0;
}
