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




#import "HistogramWindow.h"
#import "HistoView.h"
#import "ROI.h"
#import "DCMPix.h"

@implementation HistoView

- (void)mouseDown:(NSEvent *)theEvent
{
	[self mouseDragged: theEvent];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
	NSRect  boundsRect = [self bounds];
	NSPoint loc = [self convertPoint:[theEvent locationInWindow] fromView:[[self window] contentView]];
	
	curMousePosition = (loc.x * dataSize) / boundsRect.size.width;
	
	curMousePosition /= bin;
	curMousePosition *= bin;
	
	if( curMousePosition < 0) curMousePosition = 0;
	if( curMousePosition >= dataSize) curMousePosition = dataSize-1;
	
	[self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)theEvent
{
	curMousePosition = -1;
	
	[self setNeedsDisplay:YES];
}

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self)
	{
		curMousePosition = -1;
    }
    return self;
}

- (void)setData:(float*)array :(long) size :(long) b
{
	dataArray=array;
	dataSize = size;
	bin = b;
	
	[self setNeedsDisplay: YES];
}

-(void)setMaxValue: (float) max :(long) p
{
	maxValue = max;
	pixels = p;
}

-(void) setCurROI: (ROI*) r
{
	curROI = r;
}

- (void)setRange:(long) mi :(long) max
{
	minV = mi;
	maxV = max;
}

- (void)drawRect:(NSRect)aRect
{
	NSRect					boundsRect=[self bounds];
	int						index, i, noAtMouse;
	float					maxX = (boundsRect.origin.x+boundsRect.size.width)/HISTOSIZE;
	NSString				*trace;
	NSMutableParagraphStyle *paragraphStyle = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
	NSDictionary			*boldFont = [NSDictionary dictionaryWithObjectsAndKeys:	[NSFont labelFontOfSize:10.0],NSFontAttributeName,
																					[NSColor blackColor],NSForegroundColorAttributeName,
																					paragraphStyle,NSParagraphStyleAttributeName,
																					nil];
	[[NSColor colorWithDeviceRed:1.0 green:1.0 blue:0.2 alpha:1.0] set];
	NSRectFill(boundsRect);

	for(index = 0 ; index < dataSize;index++)  
	{
		float value = 0;
		
		for( i = 0 ; i < bin; i++)
		{
			if( index+i < dataSize) value += dataArray[index+i];
		}
		
		float height = ((value*boundsRect.size.height)/maxValue)/bin;
		
		NSRect   histRect=NSMakeRect( index * maxX, 0, (bin * maxX)+1.0, height);
		
		long fullwl = [[curROI pix] fullwl];
		long fullww = [[curROI pix] fullww];

		long min = fullwl - fullww/2;
		long max = fullwl + fullww/2;
		
		long	wl,ww;
		
		wl = [[curROI pix] wl];
		ww = [[curROI pix] ww];
		
		float colVal = min + (index * max) / 255.;
		
		colVal -= wl - ww/2;
		colVal /= ww;
		
		if( colVal < 0) colVal = 0;
		if( colVal > 1.0) colVal = 1.0;
		
		[[NSColor colorWithDeviceRed:colVal green:colVal blue:colVal alpha:1.0] set];
		
		if( index  == curMousePosition) 
		{
			[[NSColor redColor] set];
			noAtMouse = value;
		}
		else [[NSColor blackColor] set];
		
		NSRectFill(histRect);
		
		index += bin-1;
	}
	
	if( curMousePosition != -1)
	{
		long ss, ee;
		
		ss = minV + ((curMousePosition) * (maxV-minV)) / dataSize;
		ee = minV + ((curMousePosition+bin) * (maxV-minV)) / dataSize;
		
		trace = [NSString stringWithFormat:NSLocalizedString(@"Total Pixels: %d\n\nRange:%d/%d\n\nPixels for\nthis range:%d", nil), pixels, ss, ee, noAtMouse];
	}
	else
	{
		trace = [NSString stringWithFormat:NSLocalizedString(@"Total Pixels: %d", nil), pixels];
	}
	
	NSRect dstRect = boundsRect;
	dstRect.origin.x+=4;
	[trace drawInRect: dstRect withAttributes: boldFont];
	
	[[NSColor blackColor] set];
	NSFrameRectWithWidth(boundsRect, 1.0);
}
@end
