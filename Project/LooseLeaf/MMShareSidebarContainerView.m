//
//  MMShareSidebarContainerView.m
//  LooseLeaf
//
//  Created by Adam Wulf on 8/8/14.
//  Copyright (c) 2014 Milestone Made, LLC. All rights reserved.
//

#import "MMShareSidebarContainerView.h"
#import "MMImageViewButton.h"
#import "MMCloudKitShareItem.h"
#import "MMEmailShareItem.h"
#import "MMTextShareItem.h"
#import "MMTwitterShareItem.h"
#import "MMFacebookShareItem.h"
#import "MMSinaWeiboShareItem.h"
#import "MMTencentWeiboShareItem.h"
#import "MMPhotoAlbumShareItem.h"
#import "MMImgurShareItem.h"
#import "MMPrintShareItem.h"
#import "MMOpenInAppShareItem.h"
#import "MMCopyShareItem.h"
#import "MMPinterestShareItem.h"
#import "NSThread+BlockAdditions.h"
#import "MMShareOptionsView.h"
#import "MMRotationManager.h"
#import "Constants.h"
#import "UIView+Debug.h"
#import "MMLargeTutorialSidebarButton.h"
#import "MMTutorialManager.h"

@interface MMShareSidebarContainerView ()

@property (nonatomic, strong) NSURL* urlToShare;

@end

@implementation MMShareSidebarContainerView{
    UIView* sharingContentView;
    UIView* buttonView;
    MMShareOptionsView* activeOptionsView;
    NSMutableArray<MMAbstractShareItem*>* shareItems;
    
    MMCloudKitShareItem* cloudKitShareItem;
    
    MMLargeTutorialSidebarButton* tutorialButton;
    UIButton* exportAsImageButton;
    UIButton* exportAsPDFButton;
}

@synthesize shareDelegate;

- (id)initWithFrame:(CGRect)frame forButton:(MMSidebarButton *)_button animateFromLeft:(BOOL)fromLeft{
    if (self = [super initWithFrame:frame forButton:_button animateFromLeft:fromLeft]) {
        // Initialization code
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(updateShareOptions)
                                                     name:UIApplicationDidBecomeActiveNotification object:nil];
        
        CGRect scrollViewBounds = self.bounds;
        scrollViewBounds.size.width = [slidingSidebarView contentBounds].origin.x + [slidingSidebarView contentBounds].size.width;
        sharingContentView = [[UIView alloc] initWithFrame:scrollViewBounds];
        
        CGRect contentBounds = [slidingSidebarView contentBounds];
        CGRect buttonBounds = scrollViewBounds;
        buttonBounds.origin.y = 0;
        buttonBounds.size.height = kHeightOfImportTypeButton + 10;
        contentBounds.origin.y = buttonBounds.origin.y + buttonBounds.size.height;
        contentBounds.size.height -= buttonBounds.size.height;
        buttonView = [[UIView alloc] initWithFrame:contentBounds];
        [sharingContentView addSubview:buttonView];
        [slidingSidebarView addSubview:sharingContentView];

        //////////////////////////////////////////
        // buttons
        
        
        exportAsImageButton = [[UIButton alloc] initWithFrame:CGRectMake(CGRectGetMinX(buttonBounds) + (CGRectGetWidth(buttonBounds) - 2 * kHeightOfImportTypeButton - 10) / 2, 10, kHeightOfImportTypeButton, kHeightOfImportTypeButton)];
        [exportAsImageButton setBackgroundImage:[UIImage imageNamed:@"exportAsImage"] forState:UIControlStateNormal];
        [exportAsImageButton setBackgroundImage:[UIImage imageNamed:@"exportAsImageHighlighted"] forState:UIControlStateSelected];
        [exportAsImageButton setAdjustsImageWhenHighlighted:NO];
        [exportAsImageButton addTarget:self action:@selector(setExportType:) forControlEvents:UIControlEventTouchUpInside];
        exportAsImageButton.selected = ![[NSUserDefaults standardUserDefaults] boolForKey:kExportAsPDFPreferenceDefault];
        [slidingSidebarView addSubview:exportAsImageButton];
        
        exportAsPDFButton = [[UIButton alloc] initWithFrame:CGRectMake(CGRectGetMinX(buttonBounds) + (CGRectGetWidth(buttonBounds) - 2 * kHeightOfImportTypeButton - 10) / 2 + 10 + kHeightOfImportTypeButton, 10, kHeightOfImportTypeButton, kHeightOfImportTypeButton)];
        [exportAsPDFButton setBackgroundImage:[UIImage imageNamed:@"exportAsPDF"] forState:UIControlStateNormal];
        [exportAsPDFButton setBackgroundImage:[UIImage imageNamed:@"exportAsPDFHighlighted"] forState:UIControlStateSelected];
        [exportAsPDFButton setAdjustsImageWhenHighlighted:NO];
        [exportAsPDFButton addTarget:self action:@selector(setExportType:) forControlEvents:UIControlEventTouchUpInside];
        exportAsPDFButton.selected = [[NSUserDefaults standardUserDefaults] boolForKey:kExportAsPDFPreferenceDefault];
        [slidingSidebarView addSubview:exportAsPDFButton];
        
        
        cloudKitShareItem = [[MMCloudKitShareItem alloc] init];
        
        shareItems = [NSMutableArray array];
        [shareItems addObject:cloudKitShareItem];
        [shareItems addObject:[[MMEmailShareItem alloc] init]];
        [shareItems addObject:[[MMTextShareItem alloc] init]];
        [shareItems addObject:[[MMPhotoAlbumShareItem alloc] init]];
        [shareItems addObject:[[MMSinaWeiboShareItem alloc] init]];
        [shareItems addObject:[[MMTencentWeiboShareItem alloc] init]];
        [shareItems addObject:[[MMTwitterShareItem alloc] init]];
        [shareItems addObject:[[MMFacebookShareItem alloc] init]];
        [shareItems addObject:[[MMPinterestShareItem alloc] init]];
        [shareItems addObject:[[MMImgurShareItem alloc] init]];
        [shareItems addObject:[[MMPrintShareItem alloc] init]];
        [shareItems addObject:[[MMCopyShareItem alloc] init]];
        [shareItems addObject:[[MMOpenInAppShareItem alloc] init]];
        
        [self updateShareOptions];
        
        
        CGRect typicalBounds = [[shareItems lastObject] button].bounds;
        tutorialButton = [[MMLargeTutorialSidebarButton alloc] initWithFrame:typicalBounds andTutorialList:^NSArray *{
            return [[MMTutorialManager sharedInstance] shareTutorialSteps];
        }];
        tutorialButton.center = CGPointMake(sharingContentView.bounds.size.width/2, sharingContentView.bounds.size.height - 100);
        [tutorialButton addTarget:self action:@selector(startWatchingExportTutorials) forControlEvents:UIControlEventTouchUpInside];
        [sharingContentView addSubview:tutorialButton];
        
    }
    return self;
}

-(void) setExportType:(id)sender{
    exportAsImageButton.selected = (exportAsImageButton == sender);
    exportAsPDFButton.selected = (exportAsPDFButton == sender);

    [[NSUserDefaults standardUserDefaults] setBool:exportAsPDFButton.selected forKey:kExportAsPDFPreferenceDefault];
    
    [self updateShareOptions];
}

-(void) startWatchingExportTutorials{
    [[MMTutorialManager sharedInstance] startWatchingTutorials:tutorialButton.tutorialList];
}

-(CGFloat) buttonWidth{
    CGFloat buttonWidth = buttonView.bounds.size.width - kWidthOfSidebarButtonBuffer; // four buffers (3 between, and 1 on the right side)
    buttonWidth /= 4; // four buttons wide
    return buttonWidth;
}

-(CGRect) buttonBounds{
    CGFloat buttonWidth = [self buttonWidth];
    CGRect buttonBounds = buttonView.bounds;
    buttonBounds.origin.y = [UIApplication sharedApplication].statusBarFrame.size.height + kWidthOfSidebarButtonBuffer;
    buttonBounds.size.height = buttonWidth + kWidthOfSidebarButtonBuffer; // includes spacing buffer
    buttonBounds.origin.x += 2*kWidthOfSidebarButtonBuffer;
    buttonBounds.size.width -= 2*kWidthOfSidebarButtonBuffer;
    return buttonBounds;
}

-(void) updateShareOptions{
    [NSThread performBlockOnMainThread:^{
        [buttonView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        
        int buttonIndex = 0;
        CGFloat buttonWidth = [self buttonWidth];
        CGRect buttonBounds = [self buttonBounds];
        for(MMEmailShareItem* item in shareItems){
            if([item isAtAllPossibleForMimeType:[NSURL mimeForExtension:exportAsImageButton.selected ? @"png" : @"pdf"]]){
                item.delegate = self;
                
                MMSidebarButton* button = item.button;
                int column = (buttonIndex%4);
                int row = floor(buttonIndex / 4.0);
                button.frame = CGRectMake(buttonBounds.origin.x + column*(buttonWidth),
                                          buttonBounds.origin.y + row*(buttonWidth),
                                          buttonWidth, buttonWidth);
                
                [buttonView insertSubview:button atIndex:buttonIndex];
                
                buttonIndex += 1;
            }
        }
        
        UIView* lastButton = [buttonView.subviews lastObject];
        CGRect fr = buttonView.frame;
        fr.size.height = lastButton.frame.origin.y + lastButton.frame.size.height + kWidthOfSidebarButtonBuffer;
        buttonView.frame = fr;
    }];
}

#pragma mark - Sharing button tapped

-(void) show:(BOOL)animated{
    for (MMAbstractShareItem*shareItem in shareItems) {
        if([shareItem respondsToSelector:@selector(willShow)]){
            [shareItem willShow];
        }
    }
    [activeOptionsView reset];
    [activeOptionsView show];
    // hide tutorial if we have an options view visible
    tutorialButton.hidden = (BOOL)activeOptionsView;
    [super show:animated];
}

-(void) hide:(BOOL)animated onComplete:(void(^)(BOOL finished))onComplete{
    [super hide:animated onComplete:^(BOOL finished){
        [activeOptionsView hide];
        if(activeOptionsView.shouldCloseWhenSidebarHides){
            [self closeActiveSharingOptionsForButton:nil];
            while([sharingContentView.subviews count] > 1){
                // remove any options views
                [[sharingContentView.subviews objectAtIndex:1] removeFromSuperview];
            }
        }
        // notify any buttons that they're now hidden.
        for (MMAbstractShareItem*shareItem in shareItems) {
            if([shareItem respondsToSelector:@selector(didHide)]){
                [shareItem didHide];
            }
        }
        if(onComplete){
            onComplete(finished);
        }
    }];
}


-(MMAbstractShareItem*) closeActiveSharingOptionsForButton:(UIButton*)button{
    if(activeOptionsView){
        [activeOptionsView removeFromSuperview];
        [activeOptionsView reset];
        activeOptionsView = nil;
        tutorialButton.hidden = NO;
    }
    MMAbstractShareItem* shareItemForButton = nil;
    for (MMAbstractShareItem*shareItem in shareItems) {
        if(shareItem.button == button){
            shareItemForButton = shareItem;
        }
        [shareItem setShowingOptionsView:NO];
    }
    return shareItemForButton;
}

#pragma mark - Rotation

-(CGFloat) sidebarButtonRotation{
    if([MMRotationManager sharedInstance].lastBestOrientation == UIInterfaceOrientationPortrait){
        return 0;
    }else if([MMRotationManager sharedInstance].lastBestOrientation == UIInterfaceOrientationLandscapeLeft){
        return -M_PI_2;
    }else if([MMRotationManager sharedInstance].lastBestOrientation == UIInterfaceOrientationLandscapeRight){
        return M_PI_2;
    }else{
        return M_PI;
    }
}

-(void) updateInterfaceTo:(UIInterfaceOrientation)orientation{
    [activeOptionsView updateInterfaceTo:orientation];
    [UIView animateWithDuration:.3 animations:^{
        CGAffineTransform rotationTransform = CGAffineTransformMakeRotation([self sidebarButtonRotation]);
        for(MMBounceButton* button in [buttonView.subviews arrayByAddingObject:tutorialButton]){
            button.rotation = [self sidebarButtonRotation];
            button.transform = rotationTransform;
        }
    }];
}

#pragma mark - MMShareItemDelegate

-(UIImage*) imageToShare{
    return shareDelegate.imageToShare;
}

-(void) exportToPDF:(void(^)(NSURL* urlToPDF))completionBlock{
    [shareDelegate exportToPDF:completionBlock];
}

-(NSDictionary*) cloudKitSenderInfo{
    return shareDelegate.cloudKitSenderInfo;
}


-(void) mayShare:(MMAbstractShareItem *)shareItem{
    // close out all of our sharing options views,
    // if any
    [self closeActiveSharingOptionsForButton:nil];
    // now check if our new item has a sharing
    // options panel or not
    // if a popover controller is dismissed, it
    // adds the dismissal to the main queue async
    // so we need to add our next steps /after that/
    // so we need to dispatch async too
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            activeOptionsView = [shareItem optionsView];
            if(activeOptionsView){
                [activeOptionsView reset];
                CGRect frForOptions = buttonView.frame;
                frForOptions.origin.y = buttonView.bounds.size.height;
                frForOptions.size.height = sharingContentView.bounds.size.height - buttonView.frame.origin.y - buttonView.frame.size.height;
                activeOptionsView.frame = frForOptions;
                [shareItem setShowingOptionsView:YES];
                [sharingContentView addSubview:activeOptionsView];
                tutorialButton.hidden = YES;
            }else{
                tutorialButton.hidden = NO;
            }
            
            [shareDelegate mayShare:shareItem];
        }
    });
}

// called when a may share is cancelled
-(void) wontShare:(MMAbstractShareItem*)shareItem{
    // close out all of our sharing options views,
    // if any
    [self closeActiveSharingOptionsForButton:nil];
    activeOptionsView = nil;
    tutorialButton.hidden = NO;
}

-(void) didShare:(MMAbstractShareItem *)shareItem{
    [shareDelegate didShare:shareItem];
}

-(void) didShare:(MMAbstractShareItem *)shareItem toUser:(CKRecordID*)userId fromButton:(MMAvatarButton*)button{
    [shareDelegate didShare:shareItem toUser:userId fromButton:button];
}

#pragma mark - Cloud Kit State

-(void) cloudKitDidChangeState:(MMCloudKitBaseState *)currentState{
    [cloudKitShareItem cloudKitDidChangeState:currentState];
}


#pragma mark - Dealloc

-(void) dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
