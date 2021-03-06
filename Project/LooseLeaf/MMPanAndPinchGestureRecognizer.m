//
//  MMPanAndPinchGestureRecognizer.m
//  Loose Leaf
//
//  Created by Adam Wulf on 6/8/12.
//  Copyright (c) 2012 Milestone Made, LLC. All rights reserved.
//

#import "MMPanAndPinchGestureRecognizer.h"
#import <QuartzCore/QuartzCore.h>
#import "MMBezelInGestureRecognizer.h"
#import "MMPanAndPinchScrapGestureRecognizer.h"
#import "MMTouchVelocityGestureRecognizer.h"
#import "NSMutableSet+Extras.h"
#import "NSArray+MapReduce.h"
#import "MMShadowedView.h"
#import <JotUI/JotUI.h>
#import "MMVector.h"
#import "MMPaperView.h"

#define kMinimumNumberOfTouches 2


@implementation MMPanAndPinchGestureRecognizer {
    CGPoint locationAdjustment;
    CGPoint lastLocationInView;
    UIGestureRecognizerState subState;

    // properties for pinch gesture
    CGFloat preGestureScale;
    CGPoint normalizedLocationOfScale;

    // properties for pan gesture
    CGPoint firstLocationOfPanGestureInSuperView;
    CGRect frameOfPageAtBeginningOfGesture;

    BOOL hasPannedOrScaled;
}

#pragma mark - Properties

@synthesize scrapDelegate;
@synthesize scale;
@synthesize bezelDirectionMask;
@synthesize didExitToBezel;
@synthesize scaleDirection;
@synthesize preGestureScale;
@synthesize normalizedLocationOfScale;
@synthesize firstLocationOfPanGestureInSuperView;
@synthesize frameOfPageAtBeginningOfGesture;
@synthesize hasPannedOrScaled;

- (NSArray*)validTouches {
    return [validTouches array];
}

- (NSArray*)possibleTouches {
    return [possibleTouches array];
}

- (NSArray*)ignoredTouches {
    return [ignoredTouches copy];
}

#pragma mark - Init

- (id)init {
    self = [super init];
    if (self) {
        validTouches = [[NSMutableOrderedSet alloc] init];
        possibleTouches = [[NSMutableOrderedSet alloc] init];
        ignoredTouches = [[NSMutableSet alloc] init];
        self.cancelsTouchesInView = NO;
    }
    return self;
}

- (id)initWithTarget:(id)target action:(SEL)action {
    self = [super initWithTarget:target action:action];
    if (self) {
        validTouches = [[NSMutableOrderedSet alloc] init];
        possibleTouches = [[NSMutableOrderedSet alloc] init];
        ignoredTouches = [[NSMutableSet alloc] init];
        self.cancelsTouchesInView = NO;
    }
    return self;
}

#pragma mark - SubState

//
// since Ending a gesture prevents it from re-using any
// on-screen touches to begin again, we have to begin the
// gesture immediately and then manage a substate that can
// go through the state change repeatedly.
- (UIGestureRecognizerState)subState {
    return subState;
}

- (void)setSubState:(UIGestureRecognizerState)_subState {
    subState = _subState;
    //    if(subState == UIGestureRecognizerStateBegan){
    //        DebugLog(@"%@ substate began", [self description]);
    //    }else if(subState == UIGestureRecognizerStateCancelled){
    //        DebugLog(@"%@ substate cancelled", [self description]);
    //    }else if(subState == UIGestureRecognizerStateEnded){
    //        DebugLog(@"%@ substate ended", [self description]);
    //    }else if(subState == UIGestureRecognizerStateFailed){
    //        DebugLog(@"%@ substate failed", [self description]);
    //    }
}

//
// this will make sure that the substate transitions
// into a valid state and doesn't repeat a Began/End/Cancelled/etc
- (void)processSubStateForNextIteration {
    if (subState == UIGestureRecognizerStateEnded ||
        subState == UIGestureRecognizerStateCancelled ||
        subState == UIGestureRecognizerStateFailed) {
        self.subState = UIGestureRecognizerStatePossible;
    } else if (subState == UIGestureRecognizerStateBegan) {
        self.subState = UIGestureRecognizerStateChanged;
    }
}


#pragma mark - MMTouchLifeCycleDelegate

- (void)touchesDidDie:(NSSet*)touches {
    //    DebugLog(@"%@ told that %i touches have died", self, [touches count]);
    [self touchesEnded:touches];
    if (![possibleTouches count] && ![validTouches count] && ![ignoredTouches count]) {
        // don't ask for touch info anymore.
        // i can't rely on removing myself in the reset method,
        // because i may have been told about touch ownership when this gesture isn't
        // active or even receiving touch events
        [[MMTouchVelocityGestureRecognizer sharedInstance] stopNotifyingMeWhenTouchesDie:self];
    }
}

#pragma mark - Touch Ownership


- (void)ownershipOfTouches:(NSSet*)touches isGesture:(UIGestureRecognizer*)gesture {
    if (gesture != self) {
        [[MMTouchVelocityGestureRecognizer sharedInstance] pleaseNotifyMeWhenTouchesDie:self];
        //        DebugLog(@"%@ was told that %@ owns %i touches", [self description], [gesture description], [touches count]);
        __block BOOL touchesWereStolen = NO;
        [touches enumerateObjectsUsingBlock:^(UITouch* touch, BOOL* stop) {
            if ([possibleTouches containsObject:touch] || [validTouches containsObject:touch]) {
                if ([validTouches containsObject:touch]) {
                    touchesWereStolen = YES;
                }
                [possibleTouches removeObjectsInSet:touches];
                [validTouches removeObjectsInSet:touches];
            }
            [ignoredTouches addObjectsInSet:touches];
        }];
        if ([validTouches count] < 2 && touchesWereStolen) {
            // uh oh, we have valid touches, but not enough
            if (subState != UIGestureRecognizerStatePossible) {
                self.subState = UIGestureRecognizerStateCancelled;
            }
            [possibleTouches addObjectsInOrderedSet:validTouches];
            [validTouches removeAllObjects];
        }
    }
}


#pragma mark - Touch Methods

/**
 * the first touch of a gesture.
 * this touch may interrupt an animation on this frame, so set the frame
 * to match that of the animation.
 */
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event {
    [touches enumerateObjectsUsingBlock:^(UITouch* _Nonnull obj, BOOL* _Nonnull stop) {
        if (obj.type == UITouchTypeIndirect) {
            DebugLog(@"indirect touch!");
        }
    }];
    [self processSubStateForNextIteration];

    //    DebugLog(@"%@: %i touches began", [self description], [touches count]);

    NSMutableOrderedSet* validTouchesCurrentlyBeginning = [NSMutableOrderedSet orderedSetWithSet:touches];
    [validTouchesCurrentlyBeginning removeObjectsInSet:ignoredTouches];
    //    DebugLog(@"input: %d  ignored: %d  possiblyValid: %d", [touches count], [ignoredTouches count], [validTouchesCurrentlyBeginning count]);

    [possibleTouches addObjectsFromArray:[validTouchesCurrentlyBeginning array]];
    if ([possibleTouches count] && subState == UIGestureRecognizerStatePossible) {
        //
        // next, add all new touches to the set of possible touches
        [self processPossibleTouchesFromOriginalLocationInView:CGPointZero];

        // the substate will have been updated to began if
        // 2 possible touches were moved into our validTouches
        // set.
        didExitToBezel = MMBezelDirectionNone;
        if (subState == UIGestureRecognizerStateBegan) {
            // look at the presentation of the view (as would be seen during animation)
            // (the layer will include the shadow, but our frame won't, since it's a shadow'd layer
            CGRect lFrame = [MMShadowedView contractFrame:[self.view.layer.presentationLayer frame]];
            // look at the view frame to compare
            CGRect vFrame = self.view.frame;
            if (!CGRectEqualToRect(lFrame, vFrame)) {
                // if they're not equal, then remove all animations
                // and set the frame to the presentation layer's frame
                // so that the gesture will pick up in the middle
                // of the animation instead of immediately reset to
                // its end state
                self.view.frame = lFrame;
            }
            [self.view.layer removeAllAnimations];

            // our initial distance between touches will be set when the touches move.
            // we have to wait for the movement so we can see the touches' velocity
            // to calculate if they're too close to the bezel and need adjustment
            initialDistance = 0;
            scale = 1;
        }
    }
    if (self.state == UIGestureRecognizerStatePossible) {
        // begin tracking panning, and our substate will determine when
        // we're actually moving the page
        self.state = UIGestureRecognizerStateBegan;
    }
    //    DebugLog(@"pan page valid: %d  possible: %d  ignored: %d", [validTouches count], [possibleTouches count], [ignoredTouches count]);
}

- (void)touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event {
    [self processSubStateForNextIteration];

    if (subState == UIGestureRecognizerStatePossible) {
        initialDistance = 0;
        if (scale < 1) {
            scaleDirection = MMScaleDirectionLarger;
        } else if (scale > 1) {
            scaleDirection = MMScaleDirectionSmaller;
        }
        scale = 1;
    } else {
        NSMutableOrderedSet* validTouchesCurrentlyMoving = [NSMutableOrderedSet orderedSetWithOrderedSet:validTouches];
        [validTouchesCurrentlyMoving intersectSet:touches];
        if ([validTouchesCurrentlyMoving count]) {
            // we're moving some of our valid touches.
            // check if we need to adjust our initial distance of the gesture
            // because they started very close to the bezel
            BOOL adjustInitialDistance = NO;
            if (subState == UIGestureRecognizerStateChanged && !initialDistance) {
                initialDistance = [self distanceBetweenTouches:validTouches];
                // if we've just adjusted our initial distance, then
                // we need to flag it in case we also have a finger
                // near the bezel, which would reduce our accuracy
                // of the gesture's initial scale
                adjustInitialDistance = YES;
            }
            if (subState == UIGestureRecognizerStateChanged) {
                BOOL isTooCloseToTheBezel = NO;
                CGFloat pxVelocity = [self pxVelocity];
                for (UITouch* touch in validTouches) {
                    CGPoint point = [touch locationInView:self.view.superview];
                    if (point.x < kBezelInGestureWidth + pxVelocity ||
                        point.y < kBezelInGestureWidth ||
                        point.x > self.view.superview.frame.size.width - kBezelInGestureWidth - pxVelocity ||
                        point.y > self.view.superview.frame.size.height - kBezelInGestureWidth) {
                        // at least one of the touches is very close
                        // to the bezel, which will reduce our accuracy.
                        // so flag that here
                        isTooCloseToTheBezel = YES;
                    }
                }
                if (!isTooCloseToTheBezel) {
                    // only allow scale change if the touches are
                    // not on the edge of the screen. This is because
                    // the location of the touch on the edge isn't very accurate
                    // which messes up our scale accuracy
                    CGFloat newScale = [self distanceBetweenTouches:validTouches] / initialDistance;
                    if (initialDistance < 130) {
                        // don't alow scaling if the original pinch was very close together
                        newScale = 1.0;
                    }
                    if (newScale > scale) {
                        scaleDirection = MMScaleDirectionLarger;
                    } else if (newScale < scale) {
                        scaleDirection = MMScaleDirectionSmaller;
                    }
                    scale = newScale;
                } else {
                    // the finger is too close to the edge,
                    // which changes the accuracy of the touch location
                    if (adjustInitialDistance) {
                        // if we're beginning the gesture by pulling
                        // a finger in from the bezel, then the
                        // initial distance is artificially too small
                        // because the lack of accuracy in the touch
                        // location. so adjust by the bezel width to
                        // get closer to truth
                        initialDistance += kBezelInGestureWidth;
                    }
                }
            }
        }
    }
    self.state = UIGestureRecognizerStateChanged;
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
    // forward to our own method and ignore the event
    [self touchesEnded:touches];
}

- (void)touchesEnded:(NSSet*)touches {
    [self processSubStateForNextIteration];

    //    DebugLog(@"%@: %i touches ended", [self description], [touches count]);

    // pan and pinch and bezel
    BOOL cancelledFromBezel = NO;
    NSMutableOrderedSet* validTouchesCurrentlyEnding = [NSMutableOrderedSet orderedSetWithOrderedSet:validTouches];
    [validTouchesCurrentlyEnding intersectSet:touches];


    CGPoint originalLocationInView = [self locationInView:self.view];
    if (self.subState == UIGestureRecognizerStateChanged && [validTouchesCurrentlyEnding count]) {
        //
        // make sure we've actually seen two fingers on the page
        // before we change state or worry about bezeling

        // looking at the velocity and then adding a fraction
        // of a second to the bezel width will help determine if
        // we're bezelling the gesture or not
        CGFloat pxVelocity = [self pxVelocity];
        for (UITouch* touch in validTouchesCurrentlyEnding) {
            CGPoint point = [touch locationInView:self.view.superview];
            BOOL bezelDirHasLeft = ((self.bezelDirectionMask & MMBezelDirectionLeft) == MMBezelDirectionLeft);
            BOOL bezelDirHasRight = ((self.bezelDirectionMask & MMBezelDirectionRight) == MMBezelDirectionRight);
            BOOL bezelDirHasUp = ((self.bezelDirectionMask & MMBezelDirectionUp) == MMBezelDirectionUp);
            BOOL bezelDirHasDown = ((self.bezelDirectionMask & MMBezelDirectionDown) == MMBezelDirectionDown);
            if (point.x < kBezelInGestureWidth + ABS(pxVelocity) && bezelDirHasLeft) {
                didExitToBezel = didExitToBezel | MMBezelDirectionLeft;
                cancelledFromBezel = YES;
            } else if (point.y < kBezelInGestureWidth && bezelDirHasUp) {
                didExitToBezel = didExitToBezel | MMBezelDirectionUp;
                cancelledFromBezel = YES;
            } else if (point.x > self.view.superview.frame.size.width - kBezelInGestureWidth - ABS(pxVelocity) && bezelDirHasRight) {
                didExitToBezel = didExitToBezel | MMBezelDirectionRight;
                cancelledFromBezel = YES;
            } else if (point.y > self.view.superview.frame.size.height - kBezelInGestureWidth && bezelDirHasDown) {
                didExitToBezel = didExitToBezel | MMBezelDirectionDown;
                cancelledFromBezel = YES;
            }
        }

        [validTouches minusOrderedSet:validTouchesCurrentlyEnding];
        [possibleTouches removeObjectsInSet:touches];
        [ignoredTouches removeObjectsInSet:touches];
        if ([validTouches count] == 1) {
            [possibleTouches addObjectsInSet:[validTouches set]];
            [validTouches removeAllObjects];
        }

        if (![validTouches count] && ([possibleTouches count] || [ignoredTouches count])) {
            // we can't pan the page anymore, but we still have touches
            // active, so put us back into possible state and we may
            // pick the page back up again later
            if (cancelledFromBezel) {
                self.subState = UIGestureRecognizerStateEnded;
            } else {
                self.subState = UIGestureRecognizerStatePossible;
            }
        }

        if ([validTouches count] == 0 && [possibleTouches count] == 0 && [ignoredTouches count] == 0 &&
            subState == UIGestureRecognizerStateChanged) {
            self.subState = UIGestureRecognizerStateEnded;
            self.state = UIGestureRecognizerStateEnded;
        }
    } else {
        //
        // only 1 finger during this gesture, and it's exited
        // so it doesn't count for bezeling or pan/pinch
        [validTouches minusOrderedSet:validTouchesCurrentlyEnding];
        [possibleTouches removeObjectsInSet:touches];
        [ignoredTouches removeObjectsInSet:touches];
        if (![validTouches count] && ![possibleTouches count] && ![ignoredTouches count]) {
            self.state = UIGestureRecognizerStateFailed;
        }
    }
    [self processPossibleTouchesFromOriginalLocationInView:originalLocationInView];
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event {
    return [self touchesEnded:touches withEvent:event];
}

- (void)ignoreTouch:(UITouch*)touch forEvent:(UIEvent*)event {
    //    DebugLog(@"%@: 1 touches ignored", [self description]);

    [ignoredTouches addObject:touch];
    [possibleTouches removeObject:touch];
    [validTouches removeObject:touch];

    if ([validTouches count] < kMinimumNumberOfTouches) {
        if (subState == UIGestureRecognizerStateChanged ||
            subState == UIGestureRecognizerStateBegan) {
            self.subState = UIGestureRecognizerStateFailed;
        }
    }
    if (![validTouches count] && ![possibleTouches count] && ![ignoredTouches count]) {
        self.state = UIGestureRecognizerStateEnded;
    }
    //
    // sometimes iOS will tell us about touches that we should ignore.
    // this will make sure that we forget about these touches if iOS
    // stops notifying us after telling us to ignore
    [[MMTouchVelocityGestureRecognizer sharedInstance] pleaseNotifyMeWhenTouchesDie:self];
}


#pragma mark - Helper Methods

/**
 * calculates the pixel velocity
 * per fraction of a second (1/20)
 * to helper determine how wide to make
 * the bezel
 */
- (CGFloat)pxVelocity {
    // calculate the average X direction velocity
    // so we can determine how wide to make the bezel
    // exit of the gesture. this helps us work with
    // really fast bezelling without accidentally zooming
    // into list view or missing the bezel altogether
    int count = 0;
    CGPoint averageVelocity = CGPointZero;
    for (UITouch* touch in validTouches) {
        struct DurationCacheObject cache = [[MMTouchVelocityGestureRecognizer sharedInstance] velocityInformationForTouch:touch withIndex:nil];
        averageVelocity.x = averageVelocity.x * count + cache.directionOfTouch.x;
        count += 1;
        averageVelocity.x /= count;
    }
    // calculate the pixels moved per 20th of a second
    // and add that to the bezel that we'll allow
    CGFloat pxVelocity = averageVelocity.x * [MMTouchVelocityGestureRecognizer maxVelocity] * 0.05; // velocity per fraction of a second
    return pxVelocity;
}

- (CGFloat)distanceBetweenTouches:(NSOrderedSet*)touches {
    if ([touches count] >= 2) {
        UITouch* touch1 = [touches objectAtIndex:0];
        UITouch* touch2 = [touches objectAtIndex:1];
        CGPoint initialPoint1 = [touch1 locationInView:self.view.superview];
        CGPoint initialPoint2 = [touch2 locationInView:self.view.superview];
        return DistanceBetweenTwoPoints(initialPoint1, initialPoint2);
    }
    return 0;
}


// this will look at our possible touches, and move them
// into valid touches if necessary
- (void)processPossibleTouchesFromOriginalLocationInView:(CGPoint)originalLocationInView {
    if (![scrapDelegate isAllowedToPan]) {
        // we're not allowed to pan, so ignore all touches
        if ([possibleTouches count]) {
            //            DebugLog(@"%@ might begin, but isn't allowed", [self description]);
        }
        [ignoredTouches addObjectsInSet:[possibleTouches set]];
        [possibleTouches removeAllObjects];
    }
    if ([possibleTouches count] && subState == UIGestureRecognizerStatePossible) {
        NSMutableSet* allPossibleTouches = [NSMutableSet setWithSet:[possibleTouches set]];
        for (MMScrapView* _scrap in [scrapDelegate.scrapsToPan reverseObjectEnumerator]) {
            NSSet* touchesInScrap = [_scrap matchingPairTouchesFrom:allPossibleTouches];
            if ([touchesInScrap count]) {
                // two+ possible touches match this scrap
                [ignoredTouches addObjectsInSet:touchesInScrap];
                [possibleTouches removeObjectsInSet:touchesInScrap];
            } else {
                // remove all touches from allPossibleTouches that match this scrap
                // since grabbing a scrap requires that it hit the visible portion of the scrap,
                // this will remove any touches that don't grab a scrap but do land in a scrap
                [allPossibleTouches removeObjectsInSet:[_scrap allMatchingTouchesFrom:allPossibleTouches]];
            }
        }

        if ([possibleTouches count] >= kMinimumNumberOfTouches) {
            NSArray* firstTwoPossibleTouches = [[possibleTouches array] subarrayWithRange:NSMakeRange(0, 2)];
            NSSet* claimedTouches = [NSSet setWithArray:firstTwoPossibleTouches];
            //            DebugLog(@"pan page claiming %d touches", [claimedTouches count]);
            [scrapDelegate ownershipOfTouches:claimedTouches isGesture:self];
            [validTouches addObjectsInSet:claimedTouches];
            [possibleTouches removeObjectsInSet:claimedTouches];

            // need to reset to initial state
            // soft reset. keep the touches that we know
            // about, but reset everything else
            initialDistance = 0;
            scale = 1;
            didExitToBezel = MMBezelDirectionNone;
            scaleDirection = MMScaleDirectionNone;
            locationAdjustment = CGPointZero;
            lastLocationInView = CGPointZero;

            self.subState = UIGestureRecognizerStateBegan;
            hasPannedOrScaled = YES;

            // reset the location and the initial distance of the gesture
            // so that the new first two touches position won't immediatley
            // change where the page is or what its scale is
            CGPoint newLocationInView = [self locationInView:self.view];
            if (CGPointEqualToPoint(originalLocationInView, CGPointZero)) {
                locationAdjustment = CGPointZero;
            } else {
                locationAdjustment = CGPointMake(locationAdjustment.x + (newLocationInView.x - originalLocationInView.x),
                                                 locationAdjustment.y + (newLocationInView.y - originalLocationInView.y));
            }
            initialDistance = [self distanceBetweenTouches:validTouches] / scale;

            // Reset Panning
            // ====================================================================================
            // we know a valid gesture has 2 touches down
            // find the location of the first touch in relation to the superview.
            // since the superview doesn't move, this'll give us a static coordinate system to
            // measure panning distance from
            firstLocationOfPanGestureInSuperView = [self locationInView:self.view.superview];
            // note the origin of the frame before the gesture begins.
            // all adjustments of panning/zooming will be offset from this origin.
            frameOfPageAtBeginningOfGesture = self.view.frame;

            // Reset Scaling
            // ====================================================================================
            // remember the scale of the view before the gesture begins. we'll normalize the gesture's
            // scale value to the superview location by multiplying it to the page's current scale
            preGestureScale = [(MMPaperView*)self.view scale];
            // the normalized location of the gesture is (0 < x < 1, 0 < y < 1).
            // this lets us locate where the gesture should be in the view from any width or height
            CGPoint beginningLocationInView = [self locationInView:self.view];
            normalizedLocationOfScale = CGPointMake(beginningLocationInView.x / self.view.frame.size.width,
                                                    beginningLocationInView.y / self.view.frame.size.height);
        }
    }
}

- (BOOL)containsTouch:(UITouch*)touch {
    return [validTouches containsObject:touch];
}

- (CGPoint)locationInView:(UIView*)view {
    if ([validTouches count] >= kMinimumNumberOfTouches) {
        CGPoint loc1 = [[validTouches firstObject] locationInView:self.view];
        CGPoint loc2 = [[validTouches objectAtIndex:1] locationInView:self.view];
        lastLocationInView = CGPointMake((loc1.x + loc2.x) / 2 - locationAdjustment.x, (loc1.y + loc2.y) / 2 - locationAdjustment.y);
    }
    return [self.view convertPoint:lastLocationInView toView:view];
}


#pragma mark - UIGestureRecognizerSubclass

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer*)preventedGestureRecognizer {
    return NO;
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer*)preventingGestureRecognizer {
    return NO;
}

- (void)reset {
    [super reset];
    self.subState = UIGestureRecognizerStatePossible;
    initialDistance = 0;
    scale = 1;
    [validTouches removeAllObjects];
    [possibleTouches removeAllObjects];
    [ignoredTouches removeAllObjects];
    didExitToBezel = MMBezelDirectionNone;
    scaleDirection = MMScaleDirectionNone;
    locationAdjustment = CGPointZero;
    lastLocationInView = CGPointZero;
    hasPannedOrScaled = NO;
    // don't ask for touch info anymore
    [[MMTouchVelocityGestureRecognizer sharedInstance] stopNotifyingMeWhenTouchesDie:self];
}

- (void)setEnabled:(BOOL)enabled {
    if (enabled != self.enabled) {
        [super setEnabled:enabled];
        if (!enabled) {
            self.subState = UIGestureRecognizerStatePossible;
            initialDistance = 0;
            scale = 1;
            [validTouches removeAllObjects];
            [possibleTouches removeAllObjects];
            [ignoredTouches removeAllObjects];
            didExitToBezel = MMBezelDirectionNone;
            scaleDirection = MMScaleDirectionNone;
            locationAdjustment = CGPointZero;
            lastLocationInView = CGPointZero;
            hasPannedOrScaled = NO;
        }
    }
}


#pragma mark - Description

- (NSString*)uuid {
    if ([self.view respondsToSelector:@selector(uuid)]) {
        return [self.view performSelector:@selector(uuid)];
    }
    return nil;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"[%@ %@ %p]", NSStringFromClass([self class]), [self uuid], self];
}

@end
