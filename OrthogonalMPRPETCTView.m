/*=========================================================================
  Program:   OsiriX

  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - GPL
  
  See http://homepage.mac.com/rossetantoine/osirix/copyright.html for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
=========================================================================*/

#import "OrthogonalMPRPETCTView.h"


@implementation OrthogonalMPRPETCTView

- (id)initWithFrame:(NSRect)frameRect
{
	[super initWithFrame:frameRect];
	blendingFactor = 0.5f;
	curCLUTMenu = NSLocalizedString(@"No CLUT", nil);
	return self;
}

- (void) setCrossPosition: (long) x: (long) y
{
	crossPositionX = x;
	crossPositionY = y;
	[controller setCrossPosition: x: y: self];
}

-(void) setBlendingFactor:(float) f
{
	[controller setBlendingFactor:f];
}

-(void) superSetBlendingFactor:(float) f
{
	[super setBlendingFactor:f];
}

- (void) flipVertical:(id) sender
{
	[controller flipVertical: sender : self];
}

- (void) superFlipVertical:(id) sender
{
	[super flipVertical: sender];
}

- (void) flipHorizontal:(id) sender
{
	[controller flipHorizontal: sender : self];
}

- (void) superFlipHorizontal:(id) sender
{
	[super flipHorizontal: sender];
}

- (NSString*) curCLUTMenu
{
	return curCLUTMenu;
}

- (void) setCurCLUTMenu: (NSString*) clut
{
	curCLUTMenu = clut;
}

- (BOOL) becomeFirstResponder
{
	[super becomeFirstResponder];
	[[NSNotificationCenter defaultCenter] postNotificationName: @"UpdateCLUTMenu" object: curCLUTMenu userInfo: 0L];
	[[NSNotificationCenter defaultCenter] postNotificationName: @"UpdateWLWWMenu" object: curWLWWMenu userInfo: 0L];
}

@end
