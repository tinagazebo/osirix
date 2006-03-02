//
//  DCMPixelDataAttribute.m
//  DCMSampleApp
//
//  Created by Lance Pysher on Fri Jun 18 2004.
/*=========================================================================
  Program:   OsiriX

  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - GPL
  
  See http://homepage.mac.com/rossetantoine/osirix/copyright for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
=========================================================================*/

/***************************************** Modifications *********************************************

Version 2.3
	20050111	LP	Using vDSP to find min and max.  Will use min for rescale intercept for non CTs with signed pixel Representation
***************************************************************************************************/

#import "DCMPixelDataAttribute.h"
#import "DCM.h"
#import "jpeglib12.h"
#import <stdio.h>
#import "jpegdatasrc.h"
#import "DCMPixelDataAttributeJPEG8.h"
#import "DCMPixelDataAttributeJPEG12.h"
#import "DCMPixelDataAttributeJPEG16.h"
#import "Accelerate/Accelerate.h"
//#import "DCMPixelDataAttributeJPEG2000.h"

#import "jasper.h"

#if __ppc__

union vectorShort {
    vector short shortVec;
    short scalar[8];
};

union vectorChar {
    vector unsigned char byteVec;
    unsigned scalar[16];
};


union vectorLong {
    vector long longVec;
    short scalar[4];
};

 union  vectorFloat {
    vector float floatVec;
    float scalar[4];
};


void SwapShorts( register vector unsigned short *unaligned_input, register long size)
{
	 register long						i = size / 8;
	 register vector unsigned char		identity = vec_lvsl(0, (int*) NULL );
	 register vector unsigned char		byteSwapShorts = vec_xor( identity, vec_splat_u8(sizeof( short) - 1) );
	
	while(i-- > 0)
	{
		*unaligned_input++ = vec_perm( *unaligned_input, *unaligned_input, byteSwapShorts);
	}
}

void SwapLongs( register vector unsigned int *unaligned_input, register long size)
{
	 register long i = size / 4;
	 register vector unsigned char identity = vec_lvsl(0, (int*) NULL );
	 register vector unsigned char byteSwapLongs = vec_xor( identity, vec_splat_u8(sizeof( long )- 1 ) );
	 while(i-- > 0)
	 {
	 *unaligned_input++ = vec_perm( *unaligned_input, *unaligned_input, byteSwapLongs);
	 }
}

#endif

//altivec
#define dcmHasAltiVecMask    ( 1 << gestaltPowerPCHasVectorInstructions )  // used in  looking for a g4 

short DCMHasAltiVec()
{
	Boolean hasAltiVec = 0;
	OSErr      err;       
	long      ppcFeatures;
	
	err = Gestalt ( gestaltPowerPCProcessorFeatures, &ppcFeatures );       
	if ( err == noErr)       
	{             
		if ( ( ppcFeatures & dcmHasAltiVecMask) != 0 )
		{
			hasAltiVec = 1;
		}
	}       
	return hasAltiVec; 
}

//JPEG 2000


/******************************************************************************\
* Miscellaneous functions.
\******************************************************************************/

//static int pnm_getuint(jas_stream_t *in, int wordsize, uint_fast32_t *val);
//
//static int pnm_getsint(jas_stream_t *in, int wordsize, int_fast32_t *val)
//{
//	uint_fast32_t tmpval;
//
//	if (pnm_getuint(in, wordsize, &tmpval)) {
//		return -1;
//	}
//	if (val) {
//		assert((tmpval & (1 << (wordsize - 1))) == 0);
//		*val = tmpval;
//	}
//
//	return 0;
//}
//
//static int pnm_getuint(jas_stream_t *in, int wordsize, uint_fast32_t *val)
//{
//	uint_fast32_t tmpval;
//	int c;
//	int n;
//
//	tmpval = 0;
//	n = (wordsize + 7) / 8;
//	while (--n >= 0) {
//		if ((c = jas_stream_getc(in)) == EOF) {
//			return -1;
//		}
//		tmpval = (tmpval << 8) | c;
//	}
//	tmpval &= (((uint_fast64_t) 1) << wordsize) - 1;
//	if (val) {
//		*val = tmpval;
//	}
//
//	return 0;
//}




@implementation DCMPixelDataAttribute

- (void)dealloc {
	[transferSyntax release];
	[super dealloc];
}



- (id) initWithAttributeTag:(DCMAttributeTag *)tag 
			vr:(NSString *)vr 
			length:(long) vl 
			data:(DCMDataContainer *)dicomData 
			specificCharacterSet:(DCMCharacterSet *)specificCharacterSet
			transferSyntax:(DCMTransferSyntax *)ts
			dcmObject:(DCMObject *)dcmObject
			decodeData:(BOOL)decodeData{
	
	NSString *theVR = @"OW";
	BOOL forImplicitUseOW = NO;
	_dcmObject = dcmObject;
	_isSigned = NO;
	_framesCreated = NO;
	
	_pixelDepth = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"BitsStored"]] value] intValue];
	//NSLog(@"Init PixelDataAttr _pixelDepth %d", _pixelDepth);
	if ([ts isExplicit] && ([vr isEqualToString:@"OB"] || [vr isEqualToString:@"OW"]))
		theVR = vr;	
	else if (_pixelDepth <= 8 || [dicomData isEncapsulated]) 
		theVR = @"OB";
	else {
		forImplicitUseOW = YES;
		theVR = @"OW";
	}	
	if (DEBUG)
		NSLog(@"init Pixel Data");
	// may may an ImageIconSequence in an encapsualted file. The icon is not encapsulated so don't de-encapsulate
	
	if ([dicomData isEncapsulated] && vl == 0xffffffffl ) {
		self = [super initWithAttributeTag:tag  vr:theVR];
		[self deencapsulateData:dicomData];
		
	}
	else{
	
		self = [super init];	
		_vr = [theVR retain];
		characterSet = [specificCharacterSet retain];
		_tag = [tag retain];
		_valueLength = vl;
		_valueMultiplicity = 1;
		_values =  nil;
		if (dicomData) 
			_values = [[self valuesForVR:_vr length:_valueLength data:dicomData] retain];
		else
			_values = [[NSMutableArray array] retain];
			
		if (DEBUG) 
			NSLog([self description]);

	}

	_compression = 0;
	_numberOfFrames = 1;
	_rows = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"Rows"]] value] intValue];
	_columns = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"Columns"]] value] intValue];
	_samplesPerPixel = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"SamplesperPixel"]] value] intValue];
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"NumberofFrames"]])
		_numberOfFrames = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"NumberofFrames"]] value] intValue];
	_isSigned = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"PixelRepresentation"]] value] boolValue];

	transferSyntax = [ts retain];
	_isDecoded = NO;

	if (decodeData)
		[self decodeData];
	
	return self;
}

			

- (id)initWithAttributeTag:(DCMAttributeTag *)tag{
	return [super initWithAttributeTag:(DCMAttributeTag *)tag];
}

- (id)copyWithZone:(NSZone *)zone{
	DCMPixelDataAttribute *pixelAttr = [super copyWithZone:zone];
	return pixelAttr;
}
	

- (void)deencapsulateData:(DCMDataContainer *)dicomData{

	while ([dicomData dataRemaining]) {		
		int group = [dicomData nextUnsignedShort];
		int element = [dicomData nextUnsignedShort];
		//[dicomData nextStringWithLength:2];
		int  vl = [dicomData nextUnsignedLong];
		DCMAttributeTag *attrTag = [[[DCMAttributeTag alloc]  initWithGroup:group element:element] autorelease];
		if (DEBUG)
			NSLog(@"Attr tag: %@", [attrTag description]);
		if ([[attrTag stringValue]  isEqualToString:[(NSDictionary *)[DCMTagForNameDictionary sharedTagForNameDictionary] objectForKey:@"Item"]]) {
			[_values addObject:[dicomData nextDataWithLength:vl]];
			if (DEBUG)
				NSLog(@"add Frame %d with length: %d", [_values count],  vl);
		}
		else if ([[attrTag stringValue]  isEqualToString:[(NSDictionary *)[DCMTagForNameDictionary sharedTagForNameDictionary] objectForKey:@"SequenceDelimitationItem"]])  
				break;
		else {
			[dicomData nextDataWithLength:vl];	
		}
	}
	
}

- (void)setRows:(int)rows{
	_rows = rows;
}
- (void)setColumns:(int)columns{
	_columns = columns;
}
- (void)setNumberOfFrames:(int)frames{
	_numberOfFrames = frames;
}

- (void)setSamplesPerPixel:(int)spp{
	_samplesPerPixel = spp;
}
- (void)setBytesPerSample:(int)bps{
	_bytesPerSample = bps;
}
- (void)setPixelDepth:(int)depth{
	_pixelDepth = depth;
}
- (void)setIsShort:(BOOL)value{
	_isShort = value;
}
- (void)setCompression:(float)compression{
	_compression = compression;
}
- (void)setIsDecoded:(BOOL)value{
	_isDecoded = value;
}


- (int)rows{
	return _rows;
}
- (int)columns{
	return _columns;
}


- (DCMTransferSyntax *)transferSyntax{
	return transferSyntax;
}
- (int)samplesPerPixel{
	return _samplesPerPixel;
}
- (int)bytesPerSample{
	return _bytesPerSample;
}
- (int)pixelDepth{
	return _pixelDepth;
}
- (BOOL)isShort{
	return _isShort;
}
- (float)compression{
	return _compression;
}
- (BOOL)isDecoded{
	return _isDecoded;
}

- (int)numberOfFrames{
	return _numberOfFrames;
}

- (void)setTransferSyntax:(DCMTransferSyntax *)ts{
	[transferSyntax release];
	transferSyntax = [ts retain];
}

- (void)addFrame:(NSMutableData *)data{
	
	[_values addObject:data];
}

- (void)replaceFrameAtIndex:(int)index withFrame:(NSMutableData *)data{
	[_values replaceObjectAtIndex:index withObject:data];
}

- (void)writeBaseToData:(DCMDataContainer *)dcmData transferSyntax:(DCMTransferSyntax *)ts{
	//base class cannot convert encapsulted syntaxes yet.
	NSException *exception;
	//NS_DURING
	if (DEBUG)
		NSLog(@"Write Pixel Data %@", [transferSyntax description]);
	//if ([ts isEncapsulated] && [transferSyntax isEqualToTransferSyntax:ts] ) {
	if ([ts isEncapsulated]) {		
		[dcmData addUnsignedShort:[self group]];
		[dcmData addUnsignedShort:[self element]];
		if (DEBUG)
			NSLog(@"Write Sequence Base Length:%d", 0xffffffffl);
		if ([ts isExplicit]) {
			[dcmData addString:_vr];
			[dcmData  addUnsignedShort:0];		// reserved bytes
			[dcmData  addUnsignedLong:(0xffffffffl)];
		}
		else {			
			[dcmData  addUnsignedLong:(0xffffffffl)];
		}
	}
	//can do unencapsualated Syntaxes
	else if (![ts isEncapsulated])
		[super writeBaseToData:dcmData transferSyntax:ts];
		
	else {
		exception = [NSException exceptionWithName:@"DCMTransferSyntaxConversionError" reason:[NSString stringWithFormat:@"Cannot convert %@ to %@", [transferSyntax name], [ts name]] userInfo:nil];
		[exception raise];
	}
	/* 
	NS_HANDLER
		NSLog(@"Exception:%@	reason:%@", [exception name], [exception reason]);
		[exception raise];
	NS_ENDHANDLER
	*/	

}


- (BOOL)writeToDataContainer:(DCMDataContainer *)container withTransferSyntax:(DCMTransferSyntax *)ts{
	// valueLength should be 0xffffffff from constructor
	BOOL status = NO;
	if (DEBUG) 
		NSLog(@"Write PixelData with TS:%@  vr: %@ encapsulated: %d", [ts description], _vr, [ts isEncapsulated] );
	//NS_DURING
	if ([ts isEncapsulated] && [transferSyntax isEqualToTransferSyntax:ts]) {
		[self writeBaseToData:container transferSyntax:ts];
		NSEnumerator *enumerator = [_values objectEnumerator];
		id object;
		while (object = [enumerator nextObject]) {
			if (DEBUG)
				NSLog(@"Write Item with length:%d", [(NSData *)object length]);
			[container addUnsignedShort:(0xfffe)];		// Item
			[container addUnsignedShort:(0xe000)];
			[container addUnsignedLong:[(NSData *)object length]];		
			
			[container addData:object];
			/*
			[container addUnsignedShort:(0xfffe)];		// Item Delimiter
			[container addUnsignedShort:(0xe00d)];
			[container addUnsignedLong:(0)];
			// dummy length
			*/
			
		}
		if (DEBUG)
			NSLog(@"Write end sequence");
		[container addUnsignedShort:(0xfffe)];	// Sequence Delimiter
		[container addUnsignedShort:(0xe0dd)];
		[container addUnsignedLong:(0)];		// dummy length
	
		status = YES;
	}
	else {
		status = [super  writeToDataContainer:container withTransferSyntax:ts];
	} 
	/*
	NS_HANDLER
		status = NO;
	NS_ENDHANDLER
	*/
		return status;
}

- (NSString *)description{
	return  [NSString stringWithFormat:@"%@\t %@\t vl:%d\t vm:%d", [_tag description], _vr, [self valueLength], [self valueMultiplicity]];
}

- (BOOL)convertToTransferSyntax:(DCMTransferSyntax *)ts quality:(int)quality{
	BOOL status = NO;
	NS_DURING
	if (DEBUG)
		NSLog(@"Convert Syntax %@ to %@", [transferSyntax description], [ts description]);
		//already there do nothing
	if ([transferSyntax isEqualToTransferSyntax:ts])  {
		status = YES;
		goto finishedConversion;
		//return YES;
	}

		
		//syntax is unencapsulated little Endian Explicit or Implicit for both. do nothing
	if ([[DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax] isEqualToTransferSyntax:ts] && [[DCMTransferSyntax ImplicitVRLittleEndianTransferSyntax] isEqualToTransferSyntax:transferSyntax]) {
		status =  YES;
		goto finishedConversion;
	}
	if ([[DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax] isEqualToTransferSyntax:transferSyntax] && [[DCMTransferSyntax ImplicitVRLittleEndianTransferSyntax] isEqualToTransferSyntax:ts]) {
		status = YES;
		goto finishedConversion;
		//return YES;
	}

		
		
		
		// we need to decode pixel data
	if (![[DCMTransferSyntax OsiriXTransferSyntax] isEqualToTransferSyntax:transferSyntax]) {
		[self decodeData];
	}
	
	// may need to change PixelRepresentation to 1 if it was compressed and has a intercept
	if ([[_dcmObject attributeValueWithName:@"RescaleIntercept" ] intValue] < 0) {
		//NSLog(@"Set Pixel Representation to 1");
		[_dcmObject setAttributeValues:[NSMutableArray arrayWithObject:[NSNumber numberWithBool:YES]] forName:@"PixelRepresentation"];
	}
		
		
	//unencapsulated syntaxes
	if ([[DCMTransferSyntax ExplicitVRBigEndianTransferSyntax] isEqualToTransferSyntax:ts]) {
		//[_dcmObject removePlanarAndRescaleAttributes];
	
		[self setTransferSyntax:ts];
		status = YES;
		goto finishedConversion;
		//return YES;
	}
	if ([[DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax] isEqualToTransferSyntax:ts]) {
		if (_pixelDepth > 8)
			[self convertHostToLittleEndian];
		//[_dcmObject removePlanarAndRescaleAttributes];
		[self setTransferSyntax:ts];
		status = YES;
		goto finishedConversion;
		//return YES;
	}
	if ([[DCMTransferSyntax ImplicitVRLittleEndianTransferSyntax] isEqualToTransferSyntax:ts]) {
		if (_pixelDepth > 8)
			[self convertHostToLittleEndian];
		//[_dcmObject removePlanarAndRescaleAttributes];
		[self setTransferSyntax:ts];
		status = YES;
		goto finishedConversion;
		//return YES;
	}
	
	//jpeg2000
	if ([[DCMTransferSyntax JPEG2000LosslessTransferSyntax] isEqualToTransferSyntax:ts] || [[DCMTransferSyntax JPEG2000LossyTransferSyntax] isEqualToTransferSyntax:ts] ) {
		
		int i =0;
		NSEnumerator *enumerator = [_values objectEnumerator];
		NSMutableData *data;
		NSMutableArray *array = [NSMutableArray array];
		while (data = [enumerator nextObject]) {
			NSMutableData *newData = [self encodeJPEG2000:data quality:quality];
			[array addObject:newData];
		}
		for (i = 0; i< [array count]; i++) {
			[_values replaceObjectAtIndex:i withObject:[array objectAtIndex:i]];
		}
		
		if 	( [[DCMTransferSyntax JPEG2000LossyTransferSyntax] isEqualToTransferSyntax:ts] )
			[self setLossyImageCompressionRatio:[_values objectAtIndex:0]];
			
		//[_dcmObject removePlanarAndRescaleAttributes];
		[self createOffsetTable];
		[self setTransferSyntax:ts];
		if (DEBUG)
			NSLog(@"Converted to Syntax %@", [transferSyntax description]);
		status = YES;
		goto finishedConversion;
		//return YES;
	}
	
		//jpeg
	if ([[DCMTransferSyntax JPEGBaselineTransferSyntax] isEqualToTransferSyntax:ts] || [[DCMTransferSyntax JPEGExtendedTransferSyntax] isEqualToTransferSyntax:ts] || [[DCMTransferSyntax JPEGLosslessTransferSyntax] isEqualToTransferSyntax:ts] ) {
		
		//int i =0;
		NSMutableArray *values = [NSMutableArray arrayWithArray:_values];
		[_values removeAllObjects];
		NSEnumerator *enumerator = [values objectEnumerator];
		NSMutableData *data;
		//NSMutableArray *array = [NSMutableArray array];
		//[_dcmObject removePlanarAndRescaleAttributes];
		float q = 1.0;
		
		if (quality == DCMLosslessQuality)
			q = 100;
		else if (quality == DCMHighQuality)
			q = 90;
		else if (quality == DCMMediumQuality)
			q = 80;
		else if (quality == DCMLowQuality)
			q = 70;
		
		
		_min = 0;
		_max = 0;
		while (data = [enumerator nextObject]) {
			NSMutableData *newData;
			if (_pixelDepth <= 8) 
				newData = [self compressJPEG8:data  compressionSyntax:ts   quality:q];
			//else if (_pixelDepth <= 12) 
			else if (_pixelDepth <= 16) 				
				newData = [self compressJPEG12:data  compressionSyntax:ts   quality:q];
			else	{	
				newData = [self compressJPEG12:data  compressionSyntax:ts   quality:q];

			}
			[self addFrame:newData];

			
		}
		/*
		for (i = 0; i< [array count]; i++) {
			[_values replaceObjectAtIndex:i withObject:[array objectAtIndex:i]];
		}
		*/	
		if 	( [[DCMTransferSyntax JPEGBaselineTransferSyntax] isEqualToTransferSyntax:ts] || [[DCMTransferSyntax JPEGExtendedTransferSyntax] isEqualToTransferSyntax:ts])
			[self setLossyImageCompressionRatio:[_values objectAtIndex:0]];
		[self createOffsetTable];
		[self setTransferSyntax:ts];

		status = YES;
		//goto finishedConversion;
		//return YES;
	}
	finishedConversion:
	
	NS_HANDLER
		status = NO;
	NS_ENDHANDLER
	if (DEBUG)
		NSLog(@"Converted to Syntax %@ status:%d", [transferSyntax description], status);
	return status;
}

//Pixel Decoding
- (NSMutableData *)convertDataFromLittleEndianToHost:(NSMutableData *)data{

	void *ptr = malloc([data length]);	// Much faster than using the mutableBytes function
	if( ptr)
	{
		BlockMoveData( [data bytes], ptr, [data length]);
		
		if (NSHostByteOrder() == NS_BigEndian){
			if (_pixelDepth <= 16 && _pixelDepth > 8) {		
				//NSLog(@"Swap shorts");
				
				#if __ppc__
				if ( DCMHasAltiVec()) { 
					 SwapShorts(ptr, [data length]/2); 
				}
				else
				#endif
				{	
					
					int i = 0;
					unsigned short *shortsToSwap = ptr;
					//signed short *signedShort = ptr;
					int length = [data length]/2;
					for (i = 0; i < length; i++) {
						shortsToSwap[i] = NSSwapShort(shortsToSwap[i]);
					}
				}
			}
			else if (_pixelDepth > 16) {
				
				#if __ppc__
				if ( DCMHasAltiVec()) { 
					 SwapLongs(ptr, [data length]/4);			 
				}
				else
				#endif
				{		
					int i = 0;
					unsigned long *longsToSwap = ptr;
					//signed short *signedShort = ptr;
					int length = [data length]/4;
					for (i = 0; i < length; i++) {
						longsToSwap[i] = NSSwapLong(longsToSwap[i]);
					}
				}
			}
		}
		
		[data replaceBytesInRange:NSMakeRange(0, [data length]) withBytes: ptr];
		
		free( ptr);
	}
	return data;
}
//  Big Endian to host will need Intel Vectorizing rather than Altivec
- (NSMutableData *)convertDataFromBigEndianToHost:(NSMutableData *)data{
	if (NSHostByteOrder() == NS_LittleEndian){
		if (_pixelDepth <= 16 && _pixelDepth > 8) {		
			int i = 0;
			unsigned short *shortsToSwap = [data mutableBytes];
			//signed short *signedShort = [data mutableBytes];
			int length = [data length]/2;
			for (i = 0; i < length; i++) {
				shortsToSwap[i] = NSSwapShort(shortsToSwap[i]);
			}
		}
		else if (_pixelDepth > 16) {
			int i = 0;
			unsigned long *longsToSwap = [data mutableBytes];
			//signed short *signedShort = [data mutableBytes];
			int length = [data length]/4;
			for (i = 0; i < length; i++) {
				longsToSwap[i] = NSSwapLong(longsToSwap[i]);
			}
		}
	}
	return data;

}
- (void)convertBigEndianToHost{
}
- (void)convertHostToBigEndian{
	if (NSHostByteOrder() == NS_LittleEndian){
		NSEnumerator *enumerator = [_values objectEnumerator];
		NSMutableData *data;
		while (data = [enumerator nextObject]) {
			if (_pixelDepth <= 16) {	
				int i = 0;
				unsigned short *shortsToSwap = [data mutableBytes];
				//signed short *signedShort = [data mutableBytes];
				int length = [data length]/2;
				for (i = 0; i < length; i++) {
					shortsToSwap[i] = NSSwapShort(shortsToSwap[i]);
				}
			}
			else {	
				int i = 0;
				unsigned long *longsToSwap = [data mutableBytes];
				//signed short *signedShort = [data mutableBytes];
				int length = [data length]/4;
				for (i = 0; i < length; i++) {
					longsToSwap[i] = NSSwapLong(longsToSwap[i]);
				}
			}
		}
	}
	[self setTransferSyntax:[DCMTransferSyntax ExplicitVRBigEndianTransferSyntax]];
}

- (void)convertLittleEndianToHost{
	if (NSHostByteOrder() == NS_BigEndian){
		NSEnumerator *enumerator = [_values objectEnumerator];
		NSMutableData *data;
		while (data = [enumerator nextObject]) {
			if (_pixelDepth <= 16) {
				#if __ppc__
				if ( DCMHasAltiVec()) { 
					 SwapShorts([data mutableBytes], [data length]/2);			 
				}
				else
				#endif
				{		
					int i = 0;
					unsigned short *shortsToSwap = [data mutableBytes];
					//signed short *signedShort = [data mutableBytes];
					int length = [data length]/2;
					for (i = 0; i < length; i++) {
						shortsToSwap[i] = NSSwapShort(shortsToSwap[i]);
					}
				}
			}
			else {
				#if __ppc__
				if ( DCMHasAltiVec()) { 
					 SwapLongs([data mutableBytes], [data length]/4);			 
				}
				else
				#endif
				{		
					int i = 0;
					unsigned long *longsToSwap = [data mutableBytes];
					//signed short *signedShort = [data mutableBytes];
					int length = [data length]/4;
					for (i = 0; i < length; i++) {
						longsToSwap[i] = NSSwapLong(longsToSwap[i]);
					}
				}
			}
		}
		[self setTransferSyntax:[DCMTransferSyntax ExplicitVRBigEndianTransferSyntax]];
	}
	
	else
		[self setTransferSyntax:[DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax]];
}

- (void)convertHostToLittleEndian{
	if (NSHostByteOrder() == NS_BigEndian){
		NSEnumerator *enumerator = [_values objectEnumerator];
		NSMutableData *data;
		while (data = [enumerator nextObject]) {
			if (_pixelDepth <= 16) {
				#if __ppc__
				if ( DCMHasAltiVec()) 
					 SwapShorts([data mutableBytes], [data length]/2);
				else
				#endif
				{
					unsigned short *shortsToSwap = [data mutableBytes];
					int length = [data length]/2;
					while (length--) {
						*shortsToSwap = NSSwapShort(*shortsToSwap);
						shortsToSwap++;
					}
				}
			}
			else {
				#if __ppc__
				if ( DCMHasAltiVec()) { 
					 SwapLongs([data mutableBytes], [data length]/4);			 
				}
				else
				#endif
				{		
					int i = 0;
					unsigned long *longsToSwap = [data mutableBytes];
					//signed short *signedShort = [data mutableBytes];
					int length = [data length]/4;
					for (i = 0; i < length; i++) {
						longsToSwap[i] = NSSwapLong(longsToSwap[i]);
					}
				}
			}
		}
	}
	[self setTransferSyntax:[DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax]];
}

- (NSMutableData *)convertJPEG8ToHost:(NSData *)jpegData{ 
	/*
	NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithData:jpegData];
	if ([imageRep isPlanar])
		NSLog(@"isPlanar: %d", [imageRep numberOfPlanes]);
	else
		NSLog(@"meshed");
	int length = [imageRep pixelsHigh] * [imageRep pixelsWide] * [imageRep samplesPerPixel];
	return [NSMutableData dataWithBytes:[imageRep bitmapData] length:length];
	*/
	return [self convertJPEG8LosslessToHost:jpegData];
}

- (NSMutableData *)convertJPEG2000ToHost:(NSData *)jpegData{
	//unsigned short		theGroup, theElement;
	int					 fmtid;
	//unsigned char		theTmpBuf [256];
	//unsigned char		*theTmpBufP;
	//unsigned char		*tmpBufPtr2;
	unsigned long		i,  theLength,  x, y, decompressedLength;
	//short				theErr;
	//unsigned short		*theImage16P, theUShort1;
	unsigned char		*theCompressedP;
	//unsigned char		theHigh, theLow;
	//long				ok = FALSE;
	NSMutableData				*pixelData;
		
		
	jas_image_t *jasImage;
	jas_matrix_t *pixels[4];
	char *fmtname;
	
	theCompressedP = (unsigned char*)[jpegData bytes];
	theLength = [jpegData length];
	jas_init();
	jas_stream_t *jasStream = jas_stream_memopen((char *)theCompressedP, theLength);
		
	if ((fmtid = jas_image_getfmt(jasStream)) < 0)
	{
		//RETURN( -32);
		NSLog(@"JPEG2000 stream failure");
		return nil;
	}
		// Decode the image. 
	if (!(jasImage = jas_image_decode(jasStream, fmtid, 0)))
	{
		//RETURN( -35);
		NSLog(@"JPEG2000 decode failed");
		return nil;
	}
	
	
		// Close the image file. 
		jas_stream_close(jasStream);
		int numcmpts = jas_image_numcmpts(jasImage);
		int width = jas_image_cmptwidth(jasImage, 0);
		int height = jas_image_cmptheight(jasImage, 0);
		int depth = jas_image_cmptprec(jasImage, 0);
		//int j;
		//int k = 0;
		fmtname = jas_image_fmttostr(fmtid);
		
		int bitDepth = 0;
		if (depth == 8)
			bitDepth = 1;
		else if (depth <= 16)
			bitDepth = 2;
		else if (depth > 16)
			bitDepth = 4;
		decompressedLength =  width * height * bitDepth * numcmpts;
		unsigned char *newPixelData = malloc(decompressedLength);
		
		for (i=0; i < numcmpts; i++)
		{
			pixels[ i] = jas_matrix_create(1, (unsigned int) width);
		}
		
		if( numcmpts == 1)
		{
			if (depth > 8)
			{
				for (y=0; y < (long) height; y++)
				{
					jas_image_readcmpt(jasImage, 0, 0, y, width, 1, pixels[0]);
					
					unsigned short *px = newPixelData + y * width*2;
					
					int_fast32_t	*ptr = &(pixels[0])->rows_[0][0];
					x = width;
					while( x-- > 0) *px++ = *ptr++;			//jas_matrix_getv(pixels[0],x);
				}
			}
			else
			{
				for (y=0; y < (long) height; y++)
				{
					jas_image_readcmpt(jasImage, 0, 0, y, width, 1, pixels[0]);
					
					char *px = newPixelData + y * width;
					
					//ICI char * aulieu de 32
					int_fast32_t	*ptr = &(pixels[0])->rows_[0][0];
					x = width;
					while( x-- > 0) *px++ =	*ptr++;		//jas_matrix_getv(pixels[0],x);
				}
			}
		}
		else
		{
			for (y=0; y < (long) height; y++)
			{
				for( i = 0 ; i < numcmpts; i++)
					jas_image_readcmpt(jasImage, i, 0, y, width, 1, pixels[ i]);
				
				char *px = newPixelData + y * width * 3;
				
				int_fast32_t	*ptr1 = &(pixels[0])->rows_[0][0];
				int_fast32_t	*ptr2 = &(pixels[1])->rows_[0][0];
				int_fast32_t	*ptr3 = &(pixels[2])->rows_[0][0];
				
				x = width;
				while( x-- > 0)
				{
					*px++ =	*ptr1++;
					*px++ =	*ptr2++;
					*px++ =	*ptr3++;		//jas_matrix_getv(pixels[0],x);
				}
			}
		}
		
		jas_image_destroy(jasImage);
		jas_image_clearfmts();
		pixelData = [NSMutableData dataWithBytes:newPixelData length:decompressedLength ];
		free(newPixelData);

  return pixelData;
}

- (NSMutableData *)convertRLEToHost:(NSData *)rleData{
	/*
		RLE header is 64 bytes long as a sequence of 16  unsigned longs.
		First elements is number of segments.  The next are length of the segments.
	*/
	NSLog(@"convertRLEToHost");
	unsigned long offsetTable[16];
	[rleData getBytes:offsetTable  range:NSMakeRange(0, 64)];
	int i;
	for (i = 0; i < 16; i++)
		offsetTable[i] = NSSwapLittleLongToHost(offsetTable[i]);
	int segmentCount = offsetTable[0];
	i = 0;
	/*
		if n >= 0  and < 127
			output next n+1 bytes literally
		if n < 0 and > -128
			output next byte 1-n times
		if n = -128 do nothing
	*/
	NSMutableData *decompressedData = [NSMutableData data];
	
	NS_DURING	
	int j,k, position;
	int decompressedLength = _rows * _columns;
	if (_pixelDepth > 8)
		decompressedLength *= 2;
	signed char *buffer = (signed char *)[rleData bytes];
	//buffer += 16;
	NSMutableData *data;
	//NSLog(@"segment count: %d", segmentCount);
	switch (segmentCount){
		case 1:
			j = 0;
			data = [NSMutableData dataWithLength:decompressedLength];
			unsigned char *newData = [data mutableBytes];
			position = offsetTable[1];
			NSLog(@"position: %d", position);
			while ( j < decompressedLength) {
				if ((buffer[position] >= 0)) {
					int runLength = buffer[position] + 1;
					position++;
					for (k = 0; k < runLength; k++) 
						newData[j++] = buffer[position++];
				}
				else if ((buffer[position] < 0) && (buffer[position] > -128)) {
					int runLength = 1 - buffer[position];
					position++;
					for ( k = 0; k < runLength; k++)
						newData[j++] = buffer[position];
					position++;
				}
				else if (buffer[position] == -128)
					position++;
			}
			[decompressedData appendData:data];
			break;
		case 2:
			data = [NSMutableData dataWithLength:decompressedLength * 2];
			for (i = 0; i< segmentCount; i++) {
				j = i;			
				unsigned char *newData = [data mutableBytes];
				position = offsetTable[i+1];
				while ( j < decompressedLength) {
					if ((buffer[position] >= 0)) {
						int runLength = buffer[position] + 1;
						position++;
						for (k = 0; k < runLength; k++) 
							newData[j+=2] = buffer[position++];
					}
					else if ((buffer[position] < 0) && (buffer[position] > -128)) {
						int runLength = 1 - buffer[position];
						position++;
						for ( k = 0; k < runLength; k++)
							newData[j+=2] = buffer[position];
						position++;
					}
					else if (buffer[position] == -128)
						position++;
				}
			}
			[decompressedData appendData:data];
			break;
		case 3:
			for (i = 0; i< segmentCount; i++) {
				j = 0;
				data = [NSMutableData dataWithLength:decompressedLength];
				unsigned char *newData = [data mutableBytes];
				position = offsetTable[i+1];
				while ( j < decompressedLength) {
					if ((buffer[position] >= 0)) {
						int runLength = buffer[position] + 1;
						position++;
						for (k = 0; k < runLength; k++) 
							newData[j++] = buffer[position++];
					}
					else if ((buffer[position] < 0) && (buffer[position] > -128)) {
						int runLength = 1 - buffer[position];
						position++;
						for ( k = 0; k < runLength; k++)
							newData[j++] = buffer[position];
						position++;
					}
					else if (buffer[position] == -128)
						position++;
				}
				[decompressedData appendData:data];
			}
		break;
		
	}
	//NSLog(@"Decompressed RLE data");
	NS_HANDLER
		NSLog(@"Error deompressing RLE");
		decompressedData = nil;
	NS_ENDHANDLER
	return decompressedData;
}

- (NSMutableData *)encodeJPEG2000:(NSMutableData *)data quality:(int)quality{
	NSMutableData *jpeg2000Data;

	jas_image_t *image;
	jas_image_cmptparm_t cmptparms[3];
	jas_image_cmptparm_t *cmptparm;
	int i;
	int width = _columns;
	int height = _rows;
	int spp = _samplesPerPixel;
	int prec = _pixelDepth;
	DCMAttributeTag *signedTag = [DCMAttributeTag tagWithName:@"PixelRepresentation"];
	DCMAttribute *signedAttr = [[_dcmObject attributes] objectForKey:[signedTag stringValue]];
	BOOL sgnd = [[signedAttr value] boolValue];
		if (_isSigned)
			sgnd = _isSigned;
	
	

	//init jasper
	jas_init();
	// set up stream

	
	//set up component parameters
	for (i = 0, cmptparm = cmptparms; i < spp; ++i, ++cmptparm) {
		cmptparm->tlx = 0;
		cmptparm->tly = 0;
		cmptparm->hstep = 1;
		cmptparm->vstep = 1;
		cmptparm->width = width;
		cmptparm->height = height;
		cmptparm->prec = prec;
		cmptparm->sgnd = sgnd;
	}
	//create jasper image
	if (!(image = jas_image_create(spp, cmptparms, JAS_CLRSPC_UNKNOWN))) {
		return nil;
	}
	//set colorspace
	DCMAttributeTag *tag = [DCMAttributeTag tagWithName:@"PhotometricInterpretation"];
	DCMAttribute *attr = [[_dcmObject attributes] objectForKey:[tag stringValue]];
	NSString *photometricInterpretation = [attr value];
	//int jasColorSpace = JAS_CLRSPC_UNKNOWN;
	if ([photometricInterpretation isEqualToString:@"MONOCHROME1"] || [photometricInterpretation isEqualToString:@"MONOCHROME1"]) {
		jas_image_setclrspc(image, JAS_CLRSPC_SGRAY);
		jas_image_setcmpttype(image, 0,
		  JAS_IMAGE_CT_COLOR(JAS_CLRSPC_CHANIND_GRAY_Y));
	}
	else if ([photometricInterpretation isEqualToString:@"RGB"] || [photometricInterpretation isEqualToString:@"ARGB"]) {
		jas_image_setclrspc(image, JAS_CLRSPC_SRGB);
		jas_image_setcmpttype(image, 0,
		  JAS_IMAGE_CT_COLOR(JAS_CLRSPC_CHANIND_RGB_R));
		jas_image_setcmpttype(image, 1,
		  JAS_IMAGE_CT_COLOR(JAS_CLRSPC_CHANIND_RGB_G));
		jas_image_setcmpttype(image, 2,
		  JAS_IMAGE_CT_COLOR(JAS_CLRSPC_CHANIND_RGB_B));
	}
	else if ([photometricInterpretation isEqualToString:@"YBR_FULL_422"] || [photometricInterpretation isEqualToString:@"YBR_PARTIAL_422"] || [photometricInterpretation isEqualToString:@"YBR_FULL"]) {
		jas_image_setclrspc(image, JAS_CLRSPC_FAM_YCBCR);
		jas_image_setcmpttype(image, 0,
		  JAS_IMAGE_CT_COLOR(JAS_CLRSPC_CHANIND_YCBCR_Y));
		jas_image_setcmpttype(image, 1,
		  JAS_IMAGE_CT_COLOR(JAS_CLRSPC_CHANIND_YCBCR_CB));
		jas_image_setcmpttype(image, 2,
		  JAS_IMAGE_CT_COLOR(JAS_CLRSPC_CHANIND_YCBCR_CR));
		
	}
		/*
	if ([photometricInterpretation isEqualToString:@"CMYK"])
		jasColorSpace = JCS_CMYK;
		*/
		
	//component data
	int cmptno;	
	int x,y;
	jas_matrix_t *jasData[3];
	//int_fast64_t v;
	long long v;
	jasData[0] = 0;
	jasData[1] = 0;
	jasData[2] = 0;	
	for (cmptno = 0; cmptno < spp; ++cmptno) {

		if (!(jasData[cmptno] = jas_matrix_create(1, width))) {
			return nil;
		}
	}

	int pos = 0;
	for (y = 0; y < height; ++y) {
		for (x = 0; x < width; ++x) {			
			for (cmptno = 0; cmptno < spp; ++cmptno) {								
				if (_pixelDepth <= 8) {
					unsigned char s;
					[data getBytes:&s  range:NSMakeRange(pos,1)];
					pos++;
					v =(long long) s;
				}
				else if (sgnd) {
					signed short s;
					[data getBytes:&s  range:NSMakeRange(pos,2)];
					pos+=2;
					v = (long long)s;

				}
				else {
					unsigned short s;
					[data getBytes:&s  range:NSMakeRange(pos,2)];
					pos+=2;
					v = (long long)s;
				}
				jas_matrix_setv(jasData[cmptno], x, v);

			} //cmpt
		}	// x
		for (cmptno = 0; cmptno < spp; ++cmptno) {
			if (jas_image_writecmpt(image, cmptno, 0, y, width, 1, jasData[cmptno])) {
			
				//goto done;
			}
		} // for
	}  // y
	//done  reading data
	for (cmptno = 0; cmptno < spp; ++cmptno) {
		if (jasData[cmptno]) {
			jas_matrix_destroy(jasData[cmptno]);
		}
	}
	

	char *optstr = "rate=0.05";
	if (quality == DCMLosslessQuality)
		optstr = nil;
	else if (quality == DCMHighQuality)
		optstr = "rate=0.1";
	else if (quality ==  DCMLowQuality)
		optstr = "rate=0.03";

	NSString *tmpFile = @"/tmp/dcm.jpc";
	jas_stream_t  *out = jas_stream_fopen("/tmp/dcm.jpc", "w+b");
	jpc_encode(image, out, optstr);

	long compressedLength = jas_stream_length(out);

	jpeg2000Data = [NSMutableData dataWithContentsOfFile:tmpFile];
	//int n = jas_stream_write(out, [jpeg2000Data mutableBytes], compressedLength);

	for (i =0; i < compressedLength/4; i+=2500) {
			int s;
			[jpeg2000Data getBytes:&s  range:NSMakeRange(i,4)];
	}
	//}
	(void) jas_stream_close(out);
	jas_image_destroy(image);
	jas_image_clearfmts();
	[[NSFileManager defaultManager] removeFileAtPath: tmpFile handler:nil];
	char zero = 0;
	if ([jpeg2000Data length] % 2) 
		[jpeg2000Data appendBytes:&zero length:1];
	return jpeg2000Data;
}

- (void)decodeData{
	//NSLog(@"decode data");
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	if (!_framesCreated)
		[self createFrames];
	int i;
	if (!_isDecoded){
		for (i = 0; i < [_values count] ;i++){
			[self replaceFrameAtIndex:i withFrame:[self decodeFrameAtIndex:i]];
		}
	}
	[self setTransferSyntax:[DCMTransferSyntax OsiriXTransferSyntax]];
	_isDecoded = YES;
	NSString *colorspace = [_dcmObject attributeValueWithName:@"PhotometricInterpretation"];
	if ([colorspace hasPrefix:@"YBR"] || [colorspace hasPrefix:@"PALETTE"]){
		//remove Palette stuff
		NSMutableDictionary *attributes = [_dcmObject attributes];
		NSEnumerator *enumerator = [attributes keyEnumerator];
		NSString *key;
		NSMutableArray *keysToRemove = [NSMutableArray array];
		while (key = [enumerator nextObject]) {
			DCMAttribute *attr = [attributes objectForKey:key];
			if ([(DCMAttributeTag *)[attr attrTag] group] == 0x0028 && ([(DCMAttributeTag *)[attr attrTag] element] > 0x1100 && [(DCMAttributeTag *)[attr attrTag] element] <= 0x1223))
				[keysToRemove addObject:key];
			}
		[attributes removeObjectsForKeys:keysToRemove];
		[_dcmObject setAttributeValues:[NSMutableArray arrayWithObject:@"RGB"] forName:@"PhotometricInterpretation"];
	}
	[pool release];
}



- (void)decodeRescale{
/*
	NSEnumerator *enumerator = [_values objectEnumerator];
	NSMutableData *data;
	while (data = [enumerator nextObject]) {
		[self decodeRescaleScalar:data];
	}	
*/
}

- (void)encodeRescale:(NSMutableData *)data WithRescaleIntercept:(int)offset{
	int length = [data length];
	int halfLength = length/2;
	[_dcmObject  setAttributeValues:[NSMutableArray arrayWithObject:[NSNumber numberWithFloat:1.0]] forName:@"RescaleSlope"];
	[_dcmObject  setAttributeValues:[NSMutableArray arrayWithObject:[NSNumber numberWithFloat:offset]] forName:@"RescaleIntercept"];
	int i;
	signed short *pixelData = (signed short *)[data bytes]; 
	for (i= 0; i<halfLength; i++) {
		pixelData[i] =  (pixelData[i]  - offset); 
		
		if (DEBUG && !( i % 2500))
			NSLog(@"rescaled %d", pixelData[i]);
		
	}
}

- (void)encodeRescale:(NSMutableData *)data WithPixelDepth:(int)pixelDepth{

	[self encodeRescaleScalar:data withPixelDepth:pixelDepth];

}

#if __ppc__
- (void)decodeRescaleAltivec:(NSMutableData *)data{
	union vectorShort rescaleInterceptV ;
    union  vectorFloat rescaleSlopeV;
   // NSMutableData *tempData;
    short rescaleIntercept;
    float rescaleSlope;
    vector unsigned short eight = (vector unsigned short)(8);
    vector short *vPointer = (vector short *)[data mutableBytes];
	signed short *pointer =  (signed short *)[data mutableBytes]; 
    int length = [data length];
    int i = 0;
    int j = 0;
	
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] != nil)
            rescaleIntercept = ([[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] value] intValue]);
	else 
            rescaleIntercept = 0.0;
            
    //rescale Slope
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] != nil) 
            rescaleSlope = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] value] floatValue];
        
	else 
            rescaleSlope = 1.0;
		
	if ((rescaleIntercept != 0) || (rescaleSlope != 1)) {		
	   
		//Swap non G4 acceptable values. Then do rest with Altivec
	   int halfLength = length/2;
	   int vectorLength = length/16;
	   int nonVectorLength = (int)fmod(length,8);
		*pointer =+ (length - nonVectorLength);
		
		//align
		for (i= 0;  i < vectorLength; i++)            
			*vPointer++ = vec_rl(*vPointer, eight);
			//vPointer[i] = vec_rl(vPointer[i], eight);
		
		for (j = 0; j < 8; j++)
			rescaleInterceptV.scalar[j] = rescaleIntercept;                       
		
		for (j = 0; j < 4; j++)
			 rescaleSlopeV.scalar[j] = rescaleSlope;
			 
			 
		//slope is one can vecadd
		if ((rescaleIntercept != 0) && (rescaleSlope == 1)) {
			
			short *pixelData = (short *)[data mutableBytes];
			vPointer = (vector short *)[data mutableBytes];
			
			for (i = length - nonVectorLength ; i< length; i++)
				pixelData[i] =  pixelData[i] + rescaleIntercept; 
					
			for (i= 0; i<vectorLength; i++)   
				*vPointer++ = vec_add(*vPointer, rescaleInterceptV.shortVec);
		}  
		//can't vec multiple and add      
		else if ((rescaleIntercept != 0) && (rescaleSlope != 1)) {
			short *pixelData = (short *)[data bytes]; 
			//no vector for shorts and floats
			for (i= 0; i<halfLength; i++) 
				*pixelData++ =  *pixelData * rescaleSlope + rescaleIntercept;  
		}    
	}
}
- (void)encodeRescaleAltivec:(NSMutableData *)data withPixelDepth:(int)pixelDepth;{
	short rescaleIntercept = 0;
    float rescaleSlope = 1.0;
	int length = [data length];
	int halfLength = length/2;
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] != nil)
		rescaleIntercept = ([[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] value] intValue]);
	else {
		switch (_pixelDepth) {
			case 8:
				rescaleIntercept = -127;
				break;
			case 9:
				rescaleIntercept = -255;
				break;
			case 10:
				rescaleIntercept = -511;
				break;
			case 11:
				rescaleIntercept = -1023;
				break;
			case 12:
				rescaleIntercept = -2047;
				break;
			case 13:
				rescaleIntercept = -4095;
				break;
			case 14:
				rescaleIntercept = -8191;
				break;
			case 15:
				rescaleIntercept = -16383;
				break;
			case 16:
				rescaleIntercept = -32767;
				break;
		}	
		DCMAttributeTag *tag = [DCMAttributeTag tagWithName:@"RescaleIntercept" ];
		DCMAttribute *attr = [DCMAttribute attributeWithAttributeTag:tag  vr:[tag vr]  values:[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%f", rescaleIntercept]]];
		[_dcmObject setAttribute:attr];
	}
            
    //rescale Slope
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] != nil) 
		rescaleSlope = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] value] floatValue];
        
	else  {
		rescaleSlope = 1.0;
		DCMAttributeTag *tag = [DCMAttributeTag tagWithName:@"RescaleSlope" ];
		DCMAttribute *attr = [DCMAttribute attributeWithAttributeTag:tag  vr:[tag vr]  values:[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%f", rescaleSlope]]];
		[_dcmObject setAttribute:attr];
	}
	
	union vectorShort rescaleInterceptV ;
    union  vectorFloat rescaleSlopeV;
   // NSMutableData *tempData;

    vector unsigned short eight = (vector unsigned short)(8);
    vector short *vPointer = (vector short *)[data mutableBytes];
	signed short *pointer =  (signed short *)[data mutableBytes]; 

    int i = 0;
    int j = 0;

	  //rescale Intercept
       
            //Swap non G4 acceptable values. Then do rest with Altivec


       int vectorLength = length/16;
       int nonVectorLength = (int)fmod(length,8);

        *pointer =+ (length - nonVectorLength);
        
        for (i= nonVectorLength;  i < vectorLength; i++)            
            *vPointer++ = vec_rl(*vPointer, eight);
        
        for (j = 0; j < 8; j++)
			rescaleInterceptV.scalar[j] = -rescaleIntercept;                       
		
		for (j = 0; j < 4; j++)
			 rescaleSlopeV.scalar[j] = rescaleSlope;

        if ((rescaleIntercept != 0) && (rescaleSlope == 1)) {
            
            short *pixelData = (short *)[data mutableBytes];
            vPointer = (vector short *)[data mutableBytes];
            for (i = 0; i< nonVectorLength; i++)
				*pixelData++ =  *pixelData - rescaleIntercept; 
                    
            for (i= nonVectorLength; i<vectorLength; i++)   
                *vPointer++ = vec_add(*vPointer, rescaleInterceptV.shortVec);
        }        
        else if ((rescaleIntercept != 0) && (rescaleSlope != 1)) {
            short *pixelData = (short *)[data bytes]; 
			//n0 vector for shorts and floats
            for (i= 0; i<halfLength; i++) 
                *pixelData++ =  *pixelData / rescaleSlope - rescaleIntercept;  
        }

    
}

#endif

- (void)decodeRescaleScalar:(NSMutableData *)data{
    short rescaleIntercept;
    float rescaleSlope;
	int length = [data length];
	 int halfLength = length/2;
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] != nil)
            rescaleIntercept = ([[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] value] intValue]);
	else 
            rescaleIntercept = 0.0;
            
    //rescale Slope
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] != nil) 
            rescaleSlope = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] value] floatValue];
        
	else 
            rescaleSlope = 1.0;
			
	if ((rescaleIntercept != 0) || (rescaleSlope != 1)) {
		
		int i;
		short *pixelData = (short *)[data bytes]; 
		short value;
		for (i= 0; i<halfLength; i++) {
			value = *pixelData * rescaleSlope + rescaleIntercept;
			if (value < 0)
				_isSigned = YES;
			*pixelData++ =  value; 
		}
	}
}

- (void)encodeRescaleScalar:(NSMutableData *)data withPixelDepth:(int)pixelDepth;{

	short rescaleIntercept = 0;
    float rescaleSlope = 1.0;
	int length = [data length];
	int halfLength = length/2;
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] != nil &&
			[[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] value] intValue] < 0)
		rescaleIntercept = ([[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleIntercept" ]] value] intValue]);
	else {
		switch (_pixelDepth) {
			case 8:
				rescaleIntercept = -127;
				break;
			case 9:
				rescaleIntercept = -255;
				break;
			case 10:
				rescaleIntercept = -511;
				break;
			case 11:
				rescaleIntercept = -1023;
				break;
			case 12:
				rescaleIntercept = -2047;
				break;
			case 13:
				//rescaleIntercept = 4095;
				//break;
			case 14:
				//rescaleIntercept = 8191;
				//break;
			case 15:
				//rescaleIntercept = 16383;
				//break;
			case 16:
				//rescaleIntercept = 32767;
				[self findMinAndMax:data];
				if (_min < 0)
					rescaleIntercept = _min;
				break;
			default: rescaleIntercept = -2047;
		}	

	[_dcmObject  setAttributeValues:[NSMutableArray arrayWithObject:[NSNumber numberWithInt:rescaleIntercept]] forName:@"RescaleIntercept"];
	}
            
    //rescale Slope
	if ([_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] != nil) 
		rescaleSlope = [[[_dcmObject attributeForTag:[DCMAttributeTag tagWithName:@"RescaleSlope" ]] value] floatValue];
        
	else  {
	
		if (rescaleIntercept > -2048)
			rescaleSlope = 1.0;
		else if (_max - _min > pow(2, pixelDepth))
			rescaleSlope = (_max - _min) / pow(2, pixelDepth);
				
		rescaleSlope = 1.0;	
		[_dcmObject  setAttributeValues:[NSMutableArray arrayWithObject:[NSNumber numberWithFloat:rescaleSlope]] forName:@"RescaleSlope"];
	}
		
	if (DEBUG) {
		NSLog(@"rescales Intercept: %d slope: %f", rescaleIntercept, rescaleSlope);
		NSLog(@"max: %d min %d", _max, _min);
	}
	if ((rescaleIntercept != 0) || (rescaleSlope != 1)) {
		int i;
		signed short *pixelData = (signed short *)[data bytes]; 
		for (i= 0; i<halfLength; i++) {
			pixelData[i] =  (pixelData[i]  - rescaleIntercept) / rescaleSlope; 
			
			if (DEBUG && !( i % 2500))
				NSLog(@"rescaled %d", pixelData[i]);
			
		}
	}
}


-(void)createOffsetTable{
	/*
		offset should be item tag 4 bytes length 4 bytes last item length
	*/
	if (DEBUG)
		NSLog(@"create Offset table");
	NSMutableData *offsetTable = [NSMutableData data];
	unsigned long offset = 0;
	[offsetTable appendBytes:&offset length:4];
	int i;
	int count = [_values count];
	for (i = 1; i < count; i++) {
		offset += NSSwapHostLongToLittle([(NSData *)[_values objectAtIndex:i -1] length] + 8);
		[offsetTable appendBytes:&offset length:4];
	}
	[_values insertObject:offsetTable atIndex:0];
}

- (NSMutableData *)interleavePlanesInData:(NSMutableData *)planarData{
	DCMAttributeTag *tag = [DCMAttributeTag tagWithName:@"PlanarConfiguration"];
	DCMAttribute *attr = [_dcmObject attributeForTag:(DCMAttributeTag *)tag];
	int numberofPlanes = [[attr value] intValue];
	int i,j, k;
	int bytes = 1;
	if (_pixelDepth <= 8)
		bytes = 1;
	else if (_pixelDepth <= 16)
		bytes = 2;
	else
		bytes = 4;
	int planeLength = _rows * _columns;
	NSMutableData *interleavedData = nil;
	if (numberofPlanes > 0 && numberofPlanes <= 4) {
		interleavedData = [NSMutableData dataWithLength:[planarData length]];
		if (bytes == 1) {

			unsigned char *planarBuffer = (unsigned char *)[planarData  bytes];
			unsigned char *bitmapData = (unsigned char *)[interleavedData  mutableBytes];
			for(i=0; i< _rows; i++){

				for(j=0; j< _columns; j++){
					for (k = 0; k < _samplesPerPixel; k++)
						*bitmapData++ = planarBuffer[planeLength*k + i*_columns + j ];

				}
			}
		}
		else if (bytes == 2) {
			unsigned short *planarBuffer = (unsigned short *)[planarData  mutableBytes];
			unsigned short *bitmapData = (unsigned short *)[interleavedData  mutableBytes];
			for(i=0; i< _rows; i++){
				for(j=0; j< _columns; j++){
					for (k = 0; k < _samplesPerPixel; k++)
						*bitmapData++ = planarBuffer[planeLength*k + i*_columns + j ];

				}
			}
		}
		else {
			unsigned long *planarBuffer = (unsigned long *)[planarData  mutableBytes];
			unsigned long *bitmapData = (unsigned long *)[interleavedData  mutableBytes];
			for(i=0; i< _rows; i++){
				for(j=0; j< _columns; j++){
					for (k = 0; k < _samplesPerPixel; k++)
						*bitmapData++ = planarBuffer[planeLength*k + i*_columns + j ];

				}
			}
		}
	}
	//already interleaved
	else
		interleavedData = planarData;
	return interleavedData;
}

- (void)interleavePlanes{
	DCMAttributeTag *tag = [DCMAttributeTag tagWithName:@"PlanarConfiguration"];
	DCMAttribute *attr = [_dcmObject attributeForTag:(DCMAttributeTag *)tag];
	int numberofPlanes = [[attr value] intValue];
	NSMutableArray *dataArray = [NSMutableArray array];
	int i,j, k;
	int bytes = 1;
	if (_pixelDepth <= 8)
		bytes = 1;
	else if (_pixelDepth <= 16)
		bytes = 2;
	else
		bytes = 4;
	int planeLength = _rows * _columns;
	if (numberofPlanes > 0 && numberofPlanes <= 4) {
		NSEnumerator *enumerator = [_values objectEnumerator];
		NSMutableData *planarData;

		while (planarData = [enumerator nextObject]) {
			NSMutableData *interleavedData = [NSMutableData dataWithLength:[planarData length]];
			if (bytes == 1) {

				unsigned char *planarBuffer = (unsigned char *)[planarData  bytes];
				unsigned char *bitmapData = (unsigned char *)[interleavedData  mutableBytes];
				for(i=0; i< _rows; i++){

					for(j=0; j< _columns; j++){
						for (k = 0; k < _samplesPerPixel; k++)
							*bitmapData++ = planarBuffer[planeLength*k + i*_columns + j ];

					}
				}
			}
			else if (bytes == 2) {
				unsigned short *planarBuffer = (unsigned short *)[planarData  mutableBytes];
				unsigned short *bitmapData = (unsigned short *)[interleavedData  mutableBytes];
				for(i=0; i< _rows; i++){
					for(j=0; j< _columns; j++){
						for (k = 0; k < _samplesPerPixel; k++)
							*bitmapData++ = planarBuffer[planeLength*k + i*_columns + j ];

					}
				}
			}
			else {
				unsigned long *planarBuffer = (unsigned long *)[planarData  mutableBytes];
				unsigned long *bitmapData = (unsigned long *)[interleavedData  mutableBytes];
				for(i=0; i< _rows; i++){
					for(j=0; j< _columns; j++){
						for (k = 0; k < _samplesPerPixel; k++)
							*bitmapData++ = planarBuffer[planeLength*k + i*_columns + j ];

					}
				}
			}
			[dataArray addObject:interleavedData];
		}
		for (i = 0; i< [dataArray count]; i++)
			[_values replaceObjectAtIndex:i withObject:[dataArray objectAtIndex:i]];
	}
}

- (void)setLossyImageCompressionRatio:(NSMutableData *)data{
	int numBytes = 1;
	if (_pixelDepth > 8)
		numBytes = 2;
	float uncompressedSize = _rows * _columns * _samplesPerPixel * numBytes;
	float compression = uncompressedSize/(float)[data length];

	NSString *ratio = [NSString stringWithFormat:@"%f", compression];
	DCMAttributeTag *ratioTag = [DCMAttributeTag tagWithName:@"LossyImageCompressionRatio"];
	DCMAttribute *ratioAttr = [DCMAttribute attributeWithAttributeTag:ratioTag vr:[ratioTag vr] values:[NSMutableArray arrayWithObject:ratio]];
	
	DCMAttributeTag *compressionTag = [DCMAttributeTag tagWithName:@"LossyImageCompression"];
	DCMAttribute *compressionAttr = [DCMAttribute attributeWithAttributeTag:compressionTag vr:[compressionTag vr] values:[NSMutableArray arrayWithObject:@"01"]];
	
	[[_dcmObject attributes] setObject:ratioAttr  forKey:[ratioTag stringValue]];
	[[_dcmObject attributes] setObject:compressionAttr  forKey:[compressionTag stringValue]];
	//LossyImageCompression
}

- (void)findMinAndMax:(NSMutableData *)data{
	int i = 0;
	int length;
	DCMAttributeTag *signedTag = [DCMAttributeTag tagWithName:@"PixelRepresentation"];
	DCMAttribute *signedAttr = [[_dcmObject attributes] objectForKey:[signedTag stringValue]];
	BOOL isSigned = [[signedAttr value] boolValue];
	float max,  min;
	
	if (_pixelDepth <= 8) 
		length = [data length];
	else if (_pixelDepth <= 16)
		length = [data length]/2;
	else
		length = [data length] / 4;
		
	float *fBuffer = malloc(length * 4);
	if (_pixelDepth <= 8) {
		unsigned char *buffer = (unsigned char *)[data bytes];
		while (i < length) {
			fBuffer[i] = (float)buffer[i];
			i++;
		}
	}
	else if (_pixelDepth <= 16 && (isSigned || _isSigned)) {
		signed short  *buffer = (signed short *)[data bytes];
		while (i < length) {
			fBuffer[i] = (float)buffer[i];
			i++;
		}
	}
	else if (_pixelDepth <= 16) {
		unsigned short  *buffer = (unsigned short  *)[data bytes];
		while (i < length){
			fBuffer[i] = (float)buffer[i];
			i++;
		}
	}
//	else
//		int *buffer = (int *) [data bytes];
		
	vDSP_minv (fBuffer, 1, &min, length);
	vDSP_maxv (fBuffer, 1, &max, length);
	NSLog(@"vmax: %f vmin: %f", max, min);
	
	free(fBuffer);

	/*
	if (_pixelDepth <= 8) {
		_max = 255;
		_min = 0;
	}
	else  {
	
		if ((_min == 0) && (_max == 0)) {
			if (isSigned || _isSigned) {				
				signed short *buffer = (signed short *)[data bytes];
				signed short value;
				length = [data length]/ 2;
				_min = 32768;
				_max = -32767;
				for (i= 0; i < length; i++) {
					value = buffer[i];
					if (value < _min) {
						//NSLog(@"New min: %d old min: %d i: %d x: %d  y: %d", value, _min, i, i/256, i%256);
						_min = value;
					}
					if (value > _max)
						_max = value;
					
				}
			}
			else {
				_max = 0;
				_min = 65535;
				unsigned short *buffer = (unsigned short *)[data bytes];
				unsigned short value;
				length = [data length]/ 2;
				for (i = 0; i < length; i++) {
					value = buffer[i];
					if (value < _min)
						_min = value;
					if (value > _max)
						_max = value;
					
				}
			}
		}
	}
	*/
	if (DEBUG)
		NSLog(@"min %d max %d", _min, _max);
}

- (NSMutableData *)convertPaletteToRGB:(NSMutableData *)data{
	
	//NSLog(@"convertPaletteToRGB");
	BOOL			fSetClut = NO, fSetClut16 = NO;
	unsigned char   *clutRed = 0L, *clutGreen = 0L, *clutBlue = 0L;
	int		clutEntryR = 0, clutEntryG = 0, clutEntryB = 0;
	unsigned short		clutDepthR, clutDepthG, clutDepthB;
	unsigned short	*shortRed = 0L, *shortGreen = 0L, *shortBlue = 0L;
	long height = _rows;
	long width = _columns;
	long realwidth = width;
	long depth = _pixelDepth;
	int j;
	NSMutableData *rgbData = nil;
	NS_DURING
	//PhotoInterpret
	if ([[_dcmObject attributeValueWithName:@"PhotometricInterpretation"] rangeOfString:@"PALETTE"].location != NSNotFound) {
		BOOL found = NO, found16 = NO;
		NSLog(@"PALETTE COLOR");
		clutRed = malloc( 65536);
		clutGreen = malloc( 65536);
		clutBlue = malloc( 65536);
		
		// initialisation
		clutEntryR = clutEntryG = clutEntryB = 0;
		clutDepthR = clutDepthG = clutDepthB = 0;
		
		for (j = 0; j < 65536; j++){
			clutRed[ j] = 0;
			clutGreen[ j] = 0;
			clutBlue[ j] = 0;
		}
		
	
		
		NSArray *redLUTDescriptor = [_dcmObject attributeArrayWithName:@"RedPaletteColorLookupTableDescriptor"];
		clutEntryR = (unsigned short)[[redLUTDescriptor objectAtIndex:0] intValue];
		clutDepthR = (unsigned short)[[redLUTDescriptor objectAtIndex:2] intValue];
		NSArray *greenLUTDescriptor = [_dcmObject attributeArrayWithName:@"GreenPaletteColorLookupTableDescriptor"];
		clutEntryG = (unsigned short)[[greenLUTDescriptor objectAtIndex:0] intValue];
		clutDepthG = (unsigned short)[[greenLUTDescriptor objectAtIndex:2] intValue];
		NSArray *blueLUTDescriptor = [_dcmObject attributeArrayWithName:@"BluePaletteColorLookupTableDescriptor"];
		clutEntryB = (unsigned short)[[blueLUTDescriptor objectAtIndex:0] intValue];
		clutDepthB = (unsigned short)[[blueLUTDescriptor objectAtIndex:2] intValue];
		
		if( clutEntryR > 256) NSLog(@"R-Palette > 256");
		if( clutEntryG > 256) NSLog(@"G-Palette > 256");
		if( clutEntryB > 256) NSLog(@"B-Palette > 256");
		
		//NSLog(@"%d red entries with depth: %d", clutEntryR , clutDepthR);
		//NSLog(@"%d green entries with depth: %d", clutEntryG , clutDepthG);
		//NSLog(@"%d blue entries with depth: %d", clutEntryB , clutDepthB);
		unsigned long nbVal;
		unsigned short *val;
		
		NSMutableData *segmentedRedData = [_dcmObject attributeValueWithName:@"SegmentedRedPaletteColorLookupTableData"];		
		if (segmentedRedData)	// SEGMENTED PALETTE - 16 BIT !
		{
			NSLog(@"Segmented LUT");
			if (clutDepthR == 16  && clutDepthG == 16  && clutDepthB == 16)
			{
				long			length, xx, xxindex, jj;
				
				shortRed = malloc( 65535L * sizeof( unsigned short));
				shortGreen = malloc( 65535L * sizeof( unsigned short));
				shortBlue = malloc( 65535L * sizeof( unsigned short));
				
				// extract the RED palette clut data
				val = (unsigned short *)[segmentedRedData bytes];
				if (val != NULL)
				{
					unsigned short  *ptrs =  (unsigned short*) val;
					nbVal = [segmentedRedData length] / 2;
					
					NSLog(@"red");
					
					xxindex = 0;
					for( jj = 0; jj < nbVal;jj++)
					{
						int type = NSSwapShort(ptrs[jj]);
						//NSLog(@"Type: %d", type);
						switch(type)
						{
							case 0:	// Discrete
								jj++;
								length = NSSwapShort(ptrs[jj]);
								jj++;
								for( xx = xxindex; xxindex < xx + length; xxindex++)
								{
									unsigned short pixel = NSSwapShort(ptrs[ jj++]);
									shortRed[ xxindex] = pixel;
									//if( xxindex < 256) NSLog(@"Type: %d  pixel:%d, swapped: %d", shortRed[ xxindex], NSSwapShort(shortRed[ xxindex]));
								}
								jj--;
							break;
							
							case 1:	// Linear
								jj++;
								length = NSSwapShort(ptrs[jj]);
								for( xx = xxindex; xxindex < xx + length; xxindex++)
								{
									unsigned short pixel = NSSwapShort(ptrs[ jj + 1]);
									shortRed[ xxindex] = shortRed[ xx-1] + ((pixel - shortRed[ xx-1]) * (1+xxindex - xx)) / (length);
									//if( xxindex < 256) NSLog(@"%d", shortRed[ xxindex]);
								}
								jj ++;
							break;
							
							case 2: // Indirect
								NSLog(@"indirect not supported");
								jj++;
								length = NSSwapShort(ptrs[jj]);

								jj += 2;
							break;
							
							default:
								NSLog(@"Error, Error, OsiriX will soon crash...");
							break;
						}
					}
					found16 = YES; 	// this is used to let us know we have to look for the other element */
					NSLog(@"%d", xxindex);
				}//endif
				
											// extract the GREEN palette clut data
				NSMutableData *segmentedGreenData = [_dcmObject attributeValueWithName:@"SegmentedGreenPaletteColorLookupTableData"];
				val = (unsigned short *)[segmentedGreenData bytes];
				if (val != NULL)
				{
					unsigned short  *ptrs =  (unsigned short*) val;
					nbVal = [segmentedGreenData length] / 2;
					
					NSLog(@"green");
					
					xxindex = 0;
					for( jj = 0; jj < nbVal; jj++)
					{
						int type = NSSwapShort(ptrs[jj]);
						//NSLog(@"Green Type: %d", type);
						switch(type)
						{
							case 0:	// Discrete
								jj++;
								length = NSSwapShort(ptrs[jj]);
								jj++;
								for( xx = xxindex; xxindex < xx + length; xxindex++)
								{
									unsigned short pixel = NSSwapShort(ptrs[ jj++]);
									shortGreen[ xxindex] = pixel;
									//if( xxindex < 256) NSLog(@"%d", shortGreen[ xxindex]);
								}
								jj--;
							break;
							
							case 1:	// Linear
								jj++;
								length = NSSwapShort(ptrs[jj]);
								for( xx = xxindex; xxindex < xx + length; xxindex++)
								{
									unsigned short pixel = NSSwapShort(ptrs[ jj + 1]);
									shortGreen[ xxindex] = shortGreen[ xx-1] + ((pixel - shortGreen[ xx-1]) * (1+xxindex - xx)) / (length);
								//	if( xxindex < 256) NSLog(@"%d", shortGreen[ xxindex]);
								}
								jj ++;
							break;
							
							case 2: // Indirect
								NSLog(@"indirect not supported");
								jj++;
								length = NSSwapShort(ptrs[jj]);

								jj += 2;
							break;
							
							default:
								NSLog(@"Error, Error, OsiriX will soon crash...");
							break;
						}
					}
					found16 = YES; 	// this is used to let us know we have to look for the other element 
					NSLog(@"%d", xxindex);
				}//endif
				
											// extract the BLUE palette clut data
				NSMutableData *segmentedBlueData = [_dcmObject attributeValueWithName:@"SegmentedBluePaletteColorLookupTableData"];
				val = (unsigned short *)[segmentedBlueData  bytes];
				if (val != NULL)
				{
					unsigned short  *ptrs =  (unsigned short*) val;
					nbVal = [segmentedBlueData length] / 2;
					
					NSLog(@"blue");
					
					xxindex = 0;
					for( jj = 0; jj < nbVal; jj++)
					{
						int type = NSSwapShort(ptrs[jj]);
						//NSLog(@"Blue Type: %d", type);
						switch(type)
						{
							case 0:	// Discrete
								jj++;
								length = NSSwapShort(ptrs[jj]);
								jj++;
								for( xx = xxindex; xxindex < xx + length; xxindex++)
								{
									unsigned short pixel = NSSwapShort(ptrs[ jj++]);
									shortBlue[ xxindex] = pixel;
						//			if( xxindex < 256) NSLog(@"%d", shortBlue[ xxindex]);
								}
								jj--;
							break;
							
							case 1:	// Linear
								jj++;
								length = NSSwapShort(ptrs[jj]);
								for( xx = xxindex; xxindex < xx + length; xxindex++)
								{
									unsigned short pixel = NSSwapShort(ptrs[ jj + 1]);
									shortBlue[ xxindex] = shortBlue[ xx-1] + ((pixel - shortBlue[ xx-1]) * (xxindex - xx + 1)) / (length);
									//if( xxindex < 256) NSLog(@"%d", shortBlue[ xxindex]);
								}
								jj ++;
							break;
							
							case 2: // Indirect
								NSLog(@"indirect not supported");
								jj++;
								length = NSSwapShort(ptrs[jj]);

								jj += 2;
							break;
							
							default:
								NSLog(@"Error, Error, OsiriX will soon crash...");
							break;
						}
					}
					found16 = YES; 	// this is used to let us know we have to look for the other element 
					NSLog(@"%d", xxindex);
				}//endif
				/*
				for( jj = 0; jj < 65535; jj++)
				{
					shortRed[jj] =shortRed[jj]>>8;
					shortGreen[jj] =shortGreen[jj]>>8;
					shortBlue[jj] =shortBlue[jj]>>8;
				}
				*/
			}  //end 16 bit
			else if (clutDepthR == 8  && clutDepthG == 8  && clutDepthB == 8)
			{
				NSLog(@"Segmented palettes for 8 bits ??");
			}
			else
			{
				NSLog(@"Dont know this kind of DICOM CLUT...");
			}
		} //end segmented
		// EXTRACT THE PALETTE data only if there is 256 entries and depth is 16 bits
		else if (clutDepthR == 16  && clutDepthG == 16  && clutDepthB == 16) {
			
			NSData *redCLUT = [_dcmObject attributeValueWithName:@"RedPaletteColorLookupTableData"];
			if (redCLUT) {
				if (clutEntryR == 0) 
					clutEntryR = [redCLUT length] / 2;
				
				//NSLog(@"Red CLUT length: %d %d ", clutEntryR, lutLength);
				unsigned short  *ptrs =  (unsigned short*) [redCLUT bytes];				
				for (j = 0; j < clutEntryR; j++, ptrs++) {
					clutRed [j] = (int) (NSSwapLittleShortToHost(*ptrs)/256);
				}
				found = YES; 	// this is used to let us know we have to look for the other element 
			}//endif red
			
					// extract the GREEN palette clut data
			NSData *greenCLUT = [_dcmObject attributeValueWithName:@"GreenPaletteColorLookupTableData"];
			if (greenCLUT) {
				if (clutEntryG == 0)
					clutEntryG = [greenCLUT length] / 2;
				unsigned short  *ptrs =  (unsigned short*) [greenCLUT bytes];
				for (j = 0; j < clutEntryG; j++, ptrs++) clutGreen [j] = (int) (NSSwapLittleShortToHost(*ptrs)/256);
			}//endif green
			
			// extract the BLUE palette clut data
			NSData *blueCLUT = [_dcmObject attributeValueWithName:@"BluePaletteColorLookupTableData"];
			if (blueCLUT) {
				if (clutEntryB == 0)
					clutEntryB = [blueCLUT length] / 2;
				unsigned short  *ptrs =  (unsigned short*) [blueCLUT bytes];
				for (j = 0; j < clutEntryB; j++, ptrs++) clutBlue [j] = (int) (NSSwapLittleShortToHost(*ptrs)/256);
			} //endif blue
			
		}  //end 16 bit
		
		// if ...the palette has 256 entries and thus we extract the clut datas
	
		else if (clutDepthR == 8  && clutDepthG == 8  && clutDepthB == 8) {
			NSLog(@"Converting 8 bit LUT. Red LUT: %@", [[_dcmObject attributeWithName:@"RedPaletteColorLookupTableData"] description]);
			DCMAttribute *redCLUT = [_dcmObject attributeWithName:@"RedPaletteColorLookupTableData"];
			//NSData *redCLUT = [_dcmObject attributeValueWithName:@"RedPaletteColorLookupTableData"];
			if (redCLUT) {
				// in case we have an array rather than NSData
				if ([redCLUT valueMultiplicity] > 1) {
					NSArray *lut = [redCLUT values];
					for (j = 0; j < clutEntryR; j++) clutRed [j] = (int) [[lut objectAtIndex:j] intValue];
					found = YES;
				}
				else{
					unsigned char  *ptrs =  (unsigned char*) [[redCLUT value] bytes];
					for (j = 0; j < clutEntryR; j++, ptrs++) clutRed [j] = (int) (*ptrs);
						found = YES; 	// this is used to let us know we have to look for the other element 
				}
			}
			
			// extract the GREEN palette clut data
			DCMAttribute *greenCLUT = [_dcmObject attributeWithName:@"GreenPaletteColorLookupTableData"];
			//NSData *greenCLUT = [_dcmObject attributeValueWithName:@"GreenPaletteColorLookupTableData"];
			if (greenCLUT) {
				// in case we have an array rather than NSData
				if ([greenCLUT valueMultiplicity] > 1) {
					NSArray *lut = [greenCLUT values];
					for (j = 0; j < clutEntryG; j++) clutGreen [j] = (int) [[lut objectAtIndex:j] intValue];
					found = YES;
				}
				else{
					unsigned char  *ptrs =  (unsigned char*) [[greenCLUT value] bytes];
					for (j = 0; j < clutEntryG; j++, ptrs++) clutGreen [j] = (int) (*ptrs);
						found = YES; 	// this is used to let us know we have to look for the other element 
				}
			}
			
			// extract the BLUE palette clut data
			DCMAttribute *blueCLUT = [_dcmObject attributeWithName:@"BluePaletteColorLookupTableData"];
			//NSData *blueCLUT = [_dcmObject attributeValueWithName:@"BluePaletteColorLookupTableData"];
			if (blueCLUT) {
				// in case we have an array rather than NSData
				if ([blueCLUT valueMultiplicity] > 1) {
					NSArray *lut = [blueCLUT values];
					for (j = 0; j < clutEntryB; j++) clutBlue [j] = (int) [[lut objectAtIndex:j] intValue];
					found = YES;
				}
				else{
					unsigned char  *ptrs =  (unsigned char*) [[greenCLUT value] bytes];
					for (j = 0; j < clutEntryB; j++, ptrs++) clutBlue [j] = (int) (*ptrs);
						found = YES; 	// this is used to let us know we have to look for the other element 
				}

			}
			// let the rest of the routine know that it should set the clut
		}
		if (found) fSetClut = YES;
		if (found16) fSetClut16 = YES;
	
	} // endif ...extraction of the color palette
	
// This image has a palette -> Convert it to a RGB image !
	if( fSetClut)
	{
		
		if( clutRed != 0L && clutGreen != 0L && clutBlue != 0L)
		{
			unsigned char   *bufPtr = (unsigned char*) [data bytes];
			unsigned short	*bufPtr16 = (unsigned short*) [data bytes];
			unsigned char   *tmpImage;
			long			totSize, pixelR, pixelG, pixelB, x, y;
			int i= 0;
			totSize = (long) ((long) height * (long) realwidth * 3L);
			//tmpImage = malloc( totSize);
			rgbData = [NSMutableData dataWithLength:totSize];
			tmpImage = [rgbData mutableBytes];
			
			//if( _pixelDepth != 8) NSLog(@"Palette with a non-8 bit image??? : %d ", _pixelDepth);
			//NSLog(@"height; %d  width %d totSize: %d, length: %d", height, realwidth, totSize, [data length]);
			switch(_pixelDepth)
			{
				case 8:
					
					for( y = 0; y < height; y++)
					{
						for( x = 0; x < width; x++)
						{
							pixelR = pixelG = pixelB = bufPtr[y*width + x];
							
							if( pixelR > clutEntryR) {	pixelR = clutEntryR-1;}
							if( pixelG > clutEntryG) {	pixelG = clutEntryG-1;}
							if( pixelB > clutEntryB) {	pixelB = clutEntryB-1;}

							tmpImage[y*width*3 + x*3 + 0] = clutRed[ pixelR];
							tmpImage[y*width*3 + x*3 + 1] = clutGreen[ pixelG];
							tmpImage[y*width*3 + x*3 + 2] = clutBlue[ pixelB];
						}
					}
				
				break;
			
				case 16:
					i = 0;
					for( y = 0; y < height; y++)
					{
						for( x = 0; x < width; x++)
						{
							pixelR = pixelG = pixelB = bufPtr16[i];
							tmpImage[i*3 + 0] = clutRed[ pixelR];
							tmpImage[i*3 + 1] = clutGreen[ pixelG];
							tmpImage[i*3 + 2] = clutBlue[ pixelB];
							i++;
							
						}
					}
				break;
			}
			
		}
	}
	
	if( fSetClut16){
		unsigned short	*bufPtr = (unsigned short*) [data bytes];
		unsigned short   *tmpImage;
		long			totSize, x, y, ii;

		unsigned short pixel;
		
		totSize = (long) ((long) _rows * (long) _columns * 3L * 2);
		rgbData = [NSMutableData dataWithLength:totSize];
		tmpImage = (unsigned short *)[rgbData mutableBytes];
		
		if( depth != 16) NSLog(@"Segmented Palette with a non-16 bit image???");
		
		ii = height * realwidth;
				
		for( y = 0; y < height; y++)
		{
			for( x = 0; x < width; x++)
			{
				//pixel = NSSwapShort(bufPtr[y*width + x]);
				pixel = (bufPtr[y*width + x]);
				tmpImage[y*width*3 + x*3 + 0] = shortRed[pixel];
				tmpImage[y*width*3 + x*3 + 1] = shortGreen[ pixel];
				tmpImage[y*width*3 + x*3 + 2] = shortBlue[ pixel];
				//if ((y*width + x) % 5000 == 0)
				//	NSLog(@"y: %d x: %d red: %d  green: %d  blue: %d", y , x, shortRed[pixel], shortGreen[ pixel],shortBlue[ pixel]);
			}
		}
		

	} //done converting Palette
NS_HANDLER
	rgbData = nil;
	NSLog(@"Exception converting Palette to RGB: %@", [localException name]);
NS_ENDHANDLER
	if( clutRed != 0L)
		free(clutRed);
	if ( clutGreen != 0L)
		free(clutGreen);
	if (clutBlue != 0L)
		free(clutBlue);
		
	if (shortRed != 0L)
		free(shortRed);
	if (shortGreen != 0L)	
		free(shortGreen);
	if (shortBlue != 0L)
		free(shortBlue);
	//NSLog(@"end palette conversion end length: %d", [rgbData length]);
	_pixelDepth = 8;	
	return rgbData;

}

- (NSMutableData *) convertYBrToRGB:(NSData *)ybrData kind:(NSString *)theKind isPlanar:(BOOL)isPlanar
{
  long			loop, size;
  unsigned char		*pYBR, *pRGB;
  unsigned char		*theRGB;
  int			y, y1, b, r;
  NSMutableData *rgbData;
  
  NSLog(@"convertYBrToRGB:%@ isPlanar:%d", theKind, isPlanar);
  // the planar configuration should be set to 0 whenever
  // YBR_FULL_422 or YBR_PARTIAL_422 is used
  if (![theKind isEqualToString:@"YBR_FULL"] && isPlanar == 1)
    return nil;
  
  // allocate room for the RGB image
  int length = ( _rows *  _columns * 3);
  rgbData = [NSMutableData dataWithLength:length];
  theRGB = [rgbData mutableBytes];
  if (theRGB == nil) return nil;
  pRGB = theRGB;
  size = (long) _rows * (long) _columns;
 // int kind = 0;
 
  
  switch (isPlanar)
  {
    case 0 : // all pixels stored one after the other
      if ([theKind isEqualToString:@"YBR_FULL"])
      {
          // loop on the pixels of the image
          for (loop = 0L, pYBR = (unsigned char *)[ybrData bytes]; loop < size; loop++, pYBR += 3)
          {
            // get the Y, B and R channels from the original image
            y = (int) pYBR [0];
            b = (int) pYBR [1];
            r = (int) pYBR [2];
            
            // red
            *pRGB = (unsigned char) (y + (1.402 *  r));
            pRGB++;	// move the ptr to the Green
            
            // green
            *pRGB = (unsigned char) (y - (0.344 * b) - (0.714 * r));
            pRGB++;	// move the ptr to the Blue
            
            // blue
            *pRGB = (unsigned char) (y + (1.772 * b));
            pRGB++;	// move the ptr to the next Red
            
			} // for ...loop on the elements of the image to convert
		}
          
        else if ([theKind isEqualToString:@"YBR_FULL_422"] || [theKind isEqualToString:@"YBR_PARTIAL_422"])
        {
          // loop on the pixels of the image
          for (loop = 0L, pYBR = (unsigned char *)[ybrData bytes]; loop < (size / 2); loop++)
          {
            // get the Y, B and R channels from the original image
            y  = (int) pYBR [0];
            y1 = (int) pYBR [1];
            // the Cb and Cr values are sampled horizontally at half the Y rate
            b = (int) pYBR [2];
            r = (int) pYBR [3];
            
            // ***** first pixel *****
            // red 1
            *pRGB = (unsigned char) ((1.1685 * y) + (0.0389 * b) + (1.596 * r));
            pRGB++;	// move the ptr to the Green
            
            // green 1
            *pRGB = (unsigned char) ((1.1685 * y) - (0.401 * b) - (0.813 * r));
            pRGB++;	// move the ptr to the Blue
            
            // blue 1
            *pRGB = (unsigned char) ((1.1685 * y) + (2.024 * b));
            pRGB++;	// move the ptr to the next Red
            
            
            // ***** second pixel *****
            // red 2
            *pRGB = (unsigned char) ((1.1685 * y1) + (0.0389 * b) + (1.596 * r));
            pRGB++;	// move the ptr to the Green
            
            // green 2
            *pRGB = (unsigned char) ((1.1685 * y1) - (0.401 * b) - (0.813 * r));
            pRGB++;	// move the ptr to the Blue
            
            // blue 2
            *pRGB = (unsigned char) ((1.1685 * y1) + (2.024 * b));
            pRGB++;	// move the ptr to the next Red

            // the Cb and Cr values are sampled horizontally at half the Y rate
            pYBR += 4;
            
          } // for ...loop on the elements of the image to convert                
		}  //YBR 422
    //  } // switch ...kind of YBR
	break;
    case 1 : // each plane is stored separately (only allowed for YBR_FULL)
    {
      unsigned char *pY, *pB, *pR;	// ptr to Y, Cb and Cr channels of the original image
      NSLog(@"YBR FULL and planar");  
      // points to the begining of each channel in memory
      pY = (unsigned char *)[ybrData bytes];
      pB = (unsigned char *) (pY + size);
      pR = (unsigned char *) (pB + size);
        
      // loop on the pixels of the image
      for (loop = 0L; loop < size; loop++, pY++, pB++, pR++)
      {
        // red
        *pRGB = (unsigned char) ((int) *pY + (1.402 *  (int) *pR) - 179.448);
        pRGB++;	// move the ptr to the Green
            
        // green
        *pRGB = (unsigned char) ((int) *pY - (0.344 * (int) *pB) - (0.714 * (int) *pR) + 135.45);
        pRGB++;	// move the ptr to the Blue
            
        // blue
        *pRGB = (unsigned char) ((int) *pY + (1.772 * (int) *pB) - 226.8);
        pRGB++;	// move the ptr to the next Red
            
      } // for ...loop on the elements of the image to convert
    } // case 1
	break;
  
  } // switch
    
  return rgbData;
  
}

- (NSMutableData *)convertToFloat:(NSMutableData *)data{
	NSMutableData *floatData = nil;
	float rescaleIntercept = 0.0;
	float rescaleSlope = 1.0;
	vImage_Buffer src16, dstf, src8;
	dstf.height = src16.height = src8.height = _rows;
	dstf.width = src16.width = src8.width = _columns;
	dstf.rowBytes = _columns * sizeof(float);
	
	if ([_dcmObject attributeValueWithName:@"RescaleIntercept" ]  != nil)
            rescaleIntercept = (float)([[_dcmObject attributeValueWithName:@"RescaleIntercept" ] floatValue]);            
	if ([_dcmObject attributeValueWithName:@"RescaleSlope" ] != nil) 
            rescaleSlope = [[_dcmObject attributeValueWithName:@"RescaleSlope" ] floatValue];        		
	// 8 bit grayscale		
	if (_samplesPerPixel == 1 && _pixelDepth <= 8){
		src8.rowBytes = _columns * sizeof(char);
		src8.data = (unsigned char *)[data bytes];
		floatData = [NSMutableData dataWithLength:[data length] * sizeof(float)/sizeof(char)];
		dstf.data = (float *)[floatData mutableBytes];
		vImageConvert_Planar8toPlanarF (&src8, &dstf, 0, 256,0);		
	}
	// 16 bit signed
	else if (_samplesPerPixel == 1 && _pixelDepth <= 16 && _isSigned){
		src16.rowBytes = _columns * sizeof(short);
		src16.data = (short *)[data bytes];
		floatData = [NSMutableData dataWithLength:[data length]  * sizeof(float)/sizeof(short)];
		dstf.data = (float *)[floatData mutableBytes];
		vImageConvert_16SToF ( &src16, &dstf, rescaleIntercept, rescaleSlope, 0); 		
	}
	//16 bit unsigned
	else if (_samplesPerPixel == 1 && _pixelDepth <= 16 && !(_isSigned)){
		src16.rowBytes = _columns * sizeof(short);
		src16.data = (unsigned short *)[data bytes];
		floatData = [NSMutableData dataWithLength:[data length] * sizeof(float)/sizeof(unsigned short)];
		dstf.data = (float *)[floatData mutableBytes];
		vImageConvert_16UToF ( &src16, &dstf, rescaleIntercept, rescaleSlope, 0); 		
	}
	//rgb 8 bit interleaved
	else if (_samplesPerPixel > 1 && _pixelDepth <= 8){
		//convert to ARGB first
		src8.rowBytes = _columns * sizeof(char) * 3;
		src8.data = (unsigned char *)[data bytes];
		vImage_Buffer argb;
		argb.height = _rows;
		argb.width = _columns;
		argb.rowBytes = _columns * sizeof(char) * 4;
		NSMutableData *argbData = [NSMutableData dataWithLength:_rows * _columns * 4];
		argb.data = (unsigned char *)[argbData mutableBytes];
		vImageConvert_RGB888toARGB8888 (&src8,  //src
										NULL,	//alpha src
										0,	//alpha
										&argb,	//dst
										0, 0);		//flags need a extra arg for some reason
										

		floatData = [NSMutableData dataWithLength:[argbData length]  * sizeof(float)/sizeof(char)];
		dstf.data = (float *)[floatData mutableBytes];
		vImageConvert_Planar8toPlanarF (&argb, &dstf, 0, 256, 0);	
	}
	else if( _pixelDepth == 32)
	{
		unsigned long	*uslong = (unsigned long*) [data bytes];
		long			*slong = (long*) [data bytes];
		floatData = [NSMutableData dataWithLength:[data length]];
		float			*tDestF = (float *)[floatData mutableBytes];
	
		
		if(_isSigned)
		{
			long x = _rows * _columns;
			while( x-->0)
			{
				*tDestF++ = ((float) (*slong++)) * rescaleSlope + rescaleIntercept;
			}
		}
		else
		{
			long x = _rows * _columns;
			while( x-->0)
			{
				*tDestF++ = ((float) (*uslong++)) * rescaleSlope + rescaleIntercept;
			}
		}

	}


	
	return floatData;	
}
- (NSMutableData *)convertDataToRGBColorSpace:(NSMutableData *)data{
	//NSLog(@"convert data to  RGB colorspace");
	NSMutableData *rgbData = nil;
	NSString *colorspace = [_dcmObject attributeValueWithName:@"PhotometricInterpretation"];
	BOOL isPlanar = [[_dcmObject attributeValueWithName:@"PlanarConfiguration"] intValue];
	if ([colorspace hasPrefix:@"YBR"])
		rgbData = [self convertYBrToRGB:data kind:colorspace isPlanar:isPlanar];
	else if ([colorspace hasPrefix:@"PALETTE"])
		rgbData = [self  convertPaletteToRGB:data];
	else
		rgbData = data;
	
	return rgbData;
}

- (void)convertToRGBColorspace{
	//NSLog(@"convert tp RGB colorspace");
	NSString *colorspace = [_dcmObject attributeValueWithName:@"PhotometricInterpretation"];
	BOOL isPlanar = [[_dcmObject attributeValueWithName:@"PlanarConfiguration"] intValue];
	NSEnumerator *enumerator = [_values objectEnumerator];
	NSMutableData *data;
	NSMutableArray *newValues = [NSMutableArray array];
	if ([colorspace hasPrefix:@"YBR"]){
		while (data = [enumerator nextObject]){
			[newValues addObject:[self convertYBrToRGB:data kind:colorspace isPlanar:isPlanar]];
		}
		[_values release];
		_values = [newValues retain];
		[_dcmObject setAttributeValues:[NSMutableArray arrayWithObject:@"RGB"] forName:@"PhotometricInterpretation"];
	}
	else if ([colorspace hasPrefix:@"PALETTE"]){
	
		while (data = [enumerator nextObject]){
			[newValues addObject:[self convertPaletteToRGB:data]];
		}
		[_values release];
		_values = [newValues retain];
		//remove PAlette stuff
		NSMutableDictionary *attributes = [_dcmObject attributes];
		NSEnumerator *enumerator = [attributes keyEnumerator];
		NSString *key;
		NSMutableArray *keysToRemove = [NSMutableArray array];
		while (key = [enumerator nextObject]) {
			DCMAttribute *attr = [attributes objectForKey:key];
			if ([(DCMAttributeTag *)[attr attrTag] group] == 0x0028 && ([(DCMAttributeTag *)[attr attrTag] element] > 0x1100 && [(DCMAttributeTag *)[attr attrTag] element] <= 0x1223))
				[keysToRemove addObject:key];
			}
		[attributes removeObjectsForKeys:keysToRemove];
		[_dcmObject setAttributeValues:[NSMutableArray arrayWithObject:@"RGB"] forName:@"PhotometricInterpretation"];
		[_dcmObject setAttributeValues:[NSMutableArray arrayWithObject:[NSNumber numberWithInt:8]] forName:@"BitsStored"];
		_pixelDepth = 8;
	}
	
}

- (NSMutableData *)createFrameAtIndex:(int)index{
	//NSLog(@"Create frame at Index %d", index);
	//NSDate *timestamp = [NSDate date];
	NSMutableData *subData = nil;
	if (!_framesCreated){	
		//NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		if ([transferSyntax isEncapsulated])	{
			NSLog(@"encapsulated");
			NSMutableArray *offsetTable = [NSMutableArray array];
			/*offset table will be first fragment
				if single image value = 0;
				each offset is an unsigned long to the first byte of the Item tag. We have already removed the tags.
				The 0 frame starts on 0
				the 1 frame starts of offset - 8  ( Two Item tag and lengths)
				The 2 frame starts at offset - 16   ( three Item tag and lengths)
				So will use 0 for first frame, and then  subtract (n-1) * 8
			*/
			int startMerge = 0;
			unsigned  long offset;
			if ([_values count] > 1  && [(NSData *)[_values objectAtIndex:0] length] > 0) {
				startMerge = 1;
				int i;
				NSData *offsetData = [_values objectAtIndex:0];
				unsigned long *offsets = (unsigned long *)[offsetData bytes];
				int numberOfOffsets = [offsetData length]/4;
				for ( i = 0; i < numberOfOffsets; i++) {
					if ([transferSyntax isLittleEndian]) 
						offset = NSSwapLittleLongToHost(offsets[i]);
					else
						offset = offsets[i];
					[offsetTable addObject:[NSNumber numberWithLong:offset]];
				}
			}
			else 
				[offsetTable addObject:[NSNumber numberWithLong:0]];

			
			//most likely way to have data with one frame per data object.
			NSMutableArray *values = [NSMutableArray arrayWithArray:_values];
			//remove offset table
			[values removeObjectAtIndex:0];				
			if ([values count] == _numberOfFrames) {
				subData = [values objectAtIndex:index];
			//need to figure out where the data starts and ends
			}
			else{
			
				int currentOffset = [[offsetTable objectAtIndex:index] longValue];
				int currentLength = 0;
				if (index < _numberOfFrames - 1)
					currentLength =  [[offsetTable objectAtIndex:index + 1] longValue] - currentOffset;
				else{
					//last offset - currentLength =  total length of items 
					int itemsLength = 0;
					NSEnumerator *enumerator = [values objectEnumerator];
					NSData *aData;
					while (aData = [enumerator nextObject])
						itemsLength += [aData length];
					currentLength = itemsLength - currentOffset;
				}
				/*now we need to find the item that == the start of the offset
					find which items contain the data.
					need to add for item tag and length 8 bytes * (n - 1) items
				*/
				int combinedLength = 0;
				int startingItem = 0;
				int dataLength = 0;
				int endItem = 0;
				while (combinedLength < currentOffset && startingItem < [values count]) {
					combinedLength += ([(NSData *)[values objectAtIndex:startingItem] length] + 8);
					startingItem++;
				}
				endItem = startingItem;
				dataLength = ([(NSData *)[values objectAtIndex:endItem] length] + 8);
				while ((dataLength < currentLength) && (endItem < [values count])) {
					endItem++;
					dataLength += ([(NSData *)[values objectAtIndex:endItem] length] + 8);
				}
				int j;
				subData = [NSMutableData data];
				for (j = startingItem; j <= endItem ; j++) 
					[subData appendData:[values objectAtIndex:j]];	
			} //appending fragments

		} //end encapsulated
		//multiple frames
		else if (_numberOfFrames > 0) {
		//	NSLog(@"multiframe");
			
			int depth = 1;
			if (_pixelDepth <= 8) 
				depth = 1;
			else if (_pixelDepth  <= 16)
				depth = 2;
			else
				depth = 4;
			int frameLength = _rows * _columns * _samplesPerPixel * depth;
			NSRange range = NSMakeRange(index * frameLength, frameLength);
			NSData *subdata = [[_values objectAtIndex:0]  subdataWithRange:range];
			subData = [[subdata mutableCopy] autorelease];
			//subData = subdata;
			
		}
		//only one fame
		else 
			subData =[_values objectAtIndex:0];
		//NSLog(@"interval: %f", -[timestamp timeIntervalSinceNow]);
	}		
	return subData;
}

- (void)createFrames{
	//NSLog(@"createFrames");
	if (!_framesCreated){
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		if (DEBUG)
			NSLog(@"Decode Data");
		// if encapsulated we need to use offset table to create frames
		if ([transferSyntax isEncapsulated]) {
			if (DEBUG)
				NSLog(@"Data is encapsulated");
			NSMutableArray *offsetTable = [NSMutableArray array];
			/*offset table will be first fragment
				if single image value = 0;
				each offset is an unsigned long to the first byte of the Item tag. We have already removed the tags.
				The 0 frame starts on 0
				the 1 frame starts of offset - 8  ( Two Item tag and lengths)
				The 2 frame starts at offset - 16   ( three Item tag and lengths)
				So will use 0 for first frame, and then  subtract (n-1) * 8
			*/
			unsigned  long offset;
				
			
			int startMerge = 0;

			if ([_values count] > 1  && [(NSData *)[_values objectAtIndex:0] length] > 0) {
				startMerge = 1;
				int i;
				NSData *offsetData = [_values objectAtIndex:0];
				unsigned long *offsets = (unsigned long *)[offsetData bytes];
				int numberOfOffsets = [offsetData length]/4;
				for ( i = 0; i < numberOfOffsets; i++) {
					if ([transferSyntax isLittleEndian]) 
						offset = NSSwapLittleLongToHost(offsets[i]);
					else
						offset = offsets[i];
					[offsetTable addObject:[NSNumber numberWithLong:offset]];
				}
			}
			else 
				[offsetTable addObject:[NSNumber numberWithLong:0]];

		
			
			//most likely way to have data with one frame per data object.
			NSMutableArray *values = [NSMutableArray arrayWithArray:_values];
			//remove offset table
			[values removeObjectAtIndex:0];
			
			[_values removeAllObjects];
			int i;
			NSMutableData *subData;
			if (DEBUG)
				NSLog(@"number of Frames: %d", _numberOfFrames);
			for (i = 0; i < _numberOfFrames; i++) {	
				if (DEBUG)
					NSLog(@"Frame %d", i);
				//one to one match between frames and items
				
				if ([values count] == _numberOfFrames) {
					subData = [values objectAtIndex:i];
				}
				
				//need to figure out where the data starts and ends
				else{
				
					int currentOffset = [[offsetTable objectAtIndex:i] longValue];
					int currentLength = 0;
					if (i < _numberOfFrames - 1)
						currentLength =  [[offsetTable objectAtIndex:i + 1] longValue] - currentOffset;
					else{
						//last offset - currentLength =  total length of items 
						int itemsLength = 0;
						NSEnumerator *enumerator = [values objectEnumerator];
						NSData *aData;
						while (aData = [enumerator nextObject])
							itemsLength += [aData length];
						currentLength = itemsLength - currentOffset;
					}
					/*now we need to find the item that == the start of the offset
						find which items contain the data.
						need to add for item tag and length 8 bytes * (n - 1) items
					*/
					int combinedLength = 0;
					int startingItem = 0;
					int dataLength = 0;
					int endItem = 0;
					while (combinedLength < currentOffset && startingItem < [values count]) {
						combinedLength += ([(NSData *)[values objectAtIndex:startingItem] length] + 8);
						startingItem++;
					}
					endItem = startingItem;
					dataLength = ([(NSData *)[values objectAtIndex:endItem] length] + 8);
					while ((dataLength < currentLength) && (endItem < [values count])) {
						endItem++;
						dataLength += ([(NSData *)[values objectAtIndex:endItem] length] + 8);
					}
					int j;
					subData = [NSMutableData data];
					for (j = startingItem; j <= endItem ; j++) 
						[subData appendData:[values objectAtIndex:j]];	
				}
				//subdata is new frame;
				[self addFrame:subData];
			}
		}
		else{
		if (_numberOfFrames > 0) {
				//need to parse data into separate frame NSData objects:
				//NSDate *timeStamp = [NSDate date];
				//NSLog(@"Start create Frames: %f", -[timeStamp timeIntervalSinceNow]);
				int i = 0;
				int depth = 1;
				if (_pixelDepth <= 8) 
					depth = 1;
				else if (_pixelDepth  <= 16)
					depth = 2;
				else
					depth = 4;
				int frameLength = _rows * _columns * _samplesPerPixel * depth;
				NSMutableData *rawData = [[[_values objectAtIndex:0] retain] autorelease];
				[_values removeAllObjects];
				for (i = 0; i < _numberOfFrames; i++) {
					NSAutoreleasePool *subPool = [[NSAutoreleasePool alloc] init];
					//NSLog(@"create Frame %d: %f", i , -[timeStamp timeIntervalSinceNow]);
					NSRange range = NSMakeRange(i * frameLength, frameLength);
					NSMutableData *data = [NSMutableData dataWithData:[rawData subdataWithRange:range]];
					[self addFrame:data];
					[subPool release];
				}
				//NSLog(@"end create Frames: %f", -[timestamp timeIntervalSinceNow]);
				//[rawData release];
				//NSLog(@"release rawData Frames: %f", -[timeStamp timeIntervalSinceNow]);

			}
		}
			
		_framesCreated = YES;
		[pool release];
	}
}

- (NSMutableData *)decodeFrameAtIndex:(int)index{
	//NSDate *timeStamp = [NSDate date];
	//NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL colorspaceIsConverted = NO;
	NSMutableData *subData = nil;
	if (_framesCreated) {
		//NSLog(@"frames created");
		subData = [_values objectAtIndex:index];
	}
	else
		subData = [self createFrameAtIndex:index];
		
	if ([_values count] > 0 && index < _numberOfFrames){
		//NSLog(@"decodeFrameAtIndex: %d syntax %@", index, [transferSyntax description]);
			
		if (DEBUG)
				NSLog(@"to decoders:%@", [transferSyntax description]);
			// data to decoders
		NSMutableData *data = nil;
		if (!_isDecoded){
			if ([transferSyntax isEncapsulated]){
				//NSLog(@"Encapsulated: %@", [DCMTransferSyntax description]);
				if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGBaselineTransferSyntax]]) {
					data = [[[self convertJPEG8ToHost:subData] mutableCopy] autorelease];
					colorspaceIsConverted = YES;

				}
				// 8 bit jpegs
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGExtendedTransferSyntax]] && _pixelDepth <= 8) {
					colorspaceIsConverted = YES;
					data = [[[self convertJPEG8ToHost:subData] mutableCopy] autorelease];

				}
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGLosslessTransferSyntax]] && _pixelDepth <= 8) {
					data = [[[self convertJPEG8LosslessToHost:subData] mutableCopy] autorelease];

				}
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGLossless14TransferSyntax]] && _pixelDepth <= 8) { 
					data = [[[self convertJPEG8LosslessToHost:subData] mutableCopy] autorelease];

				}

					
				//12 bit jpegs
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGExtendedTransferSyntax]] && _pixelDepth <= 12) {
					
					data = [[[self convertJPEG12ToHost:subData] mutableCopy] autorelease];

				}
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGLosslessTransferSyntax]] && _pixelDepth <= 12) {
					data = [[[self convertJPEG12ToHost:subData] mutableCopy] autorelease];

				}
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGLossless14TransferSyntax]] && _pixelDepth <= 12) {
					data = [[[self convertJPEG12ToHost:subData] mutableCopy] autorelease];

				}

				//jpeg 16s
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGExtendedTransferSyntax]] && _pixelDepth <= 16) {
					data = [[[self convertJPEG16ToHost:subData] mutableCopy] autorelease];		
				}
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGLosslessTransferSyntax]] && _pixelDepth <= 16) {
					
					data = [[[self convertJPEG16ToHost:subData] mutableCopy] autorelease];
					
				}
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEGLossless14TransferSyntax]] && _pixelDepth <= 16) {
					data = [[[self convertJPEG16ToHost:subData] mutableCopy] autorelease];		
				}
				
				//JPEG 2000
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEG2000LosslessTransferSyntax]] || [transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax JPEG2000LossyTransferSyntax]] ) {
					data = [[[self convertJPEG2000ToHost:subData] mutableCopy] autorelease];

				}
				else if ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax RLETransferSyntax]]){
					data = [[[self convertRLEToHost:subData] mutableCopy] autorelease];

				}
				else {
					NSLog(@"Unknown compressed transfer syntax: %@", [transferSyntax  description]);

				}
			}
			//non encapsulated
			else if (_pixelDepth > 8) {
				//Little Endian Data and BigEndian Host
				if ((NSHostByteOrder() == NS_BigEndian) &&
				 ([transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax ImplicitVRLittleEndianTransferSyntax]] || 
				 [transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax]])) {
					data = [self convertDataFromLittleEndianToHost:subData];
				}
				//Big Endian Data and little Endian host
				else  if ((NSHostByteOrder() == NS_LittleEndian) &&
				 [transferSyntax isEqualToTransferSyntax:[DCMTransferSyntax ExplicitVRBigEndianTransferSyntax]])
					data = [self convertDataFromBigEndianToHost:subData];
				//no swap needed
				else
					data = subData;
			
			}
			//everything else
			else data = subData;
		} //end if decoded
		else
			data = subData;
		
		NSString *colorspace = [_dcmObject attributeValueWithName:@"PhotometricInterpretation"];
		if (([colorspace hasPrefix:@"YBR"] || [colorspace hasPrefix:@"PALETTE"]) && !colorspaceIsConverted){
			data = [self convertDataToRGBColorSpace:data];	
		}
		else{
		int numberofPlanes = [[_dcmObject attributeValueWithName:@"PlanarConfiguration"] intValue];			
		if (numberofPlanes > 0 && numberofPlanes <= 4)
			data = [self interleavePlanesInData:data];
		}
		

		//NSLog(@"End decode frames: %f", -[timeStamp timeIntervalSinceNow]);	
		return data;
	}
	else{
		NSLog(@"No frame %d to decode", index);
		return nil;
	}
	return nil;

}

- (NSImage *)imageAtIndex:(int)index ww:(float)ww  wl:(float)wl{
	float min;
	float max;
	//NSLog(@"pre ww: %f wl:%f", ww, wl);
	//get min and max
	if (ww == 0.0 && wl == 0.0) {
		ww = [[_dcmObject attributeValueWithName:@"WindowWidth"] floatValue]; 
		wl = [[_dcmObject attributeValueWithName:@"WindowCenter"] floatValue]; 
			//NSLog(@"ww: %f  wl: %f", ww, wl);
	}
	min = wl - ww/2;
	max = wl + ww/2;
	
	NSData *data = [self decodeFrameAtIndex:(int)index];
	NSImage *image = [[[NSImage alloc] init] autorelease];
	float rescaleIntercept, rescaleSlope;
	int spp;
	unsigned char *bmd;
	NSString *colorSpaceName;
	
	if ([_dcmObject attributeValueWithName:@"RescaleIntercept"] != nil)
            rescaleIntercept = ([[_dcmObject attributeValueWithName:@"RescaleIntercept"] floatValue]);
	else 
            rescaleIntercept = 0.0;
            
    //rescale Slope
	if ([_dcmObject attributeValueWithName:@"RescaleSlope" ] != nil) 
		rescaleSlope = [[_dcmObject attributeValueWithName:@"RescaleSlope" ] floatValue];
        
	else 
		rescaleSlope = 1.0;
		// color 
	NSString *pi = [_dcmObject attributeValueWithName:@"PhotometricInterpretation"]; 
	if ([pi isEqualToString:@"RGB"] || ([pi hasPrefix:@"YBR"] || [pi isEqualToString:@"PALETTE"] ) ) {
		bmd = (unsigned char *)[data bytes];
		spp = 3;
		colorSpaceName = NSCalibratedRGBColorSpace;
	
	}
	// 8 bit gray
	else if (_pixelDepth <= 8) {
		bmd = (unsigned char *)[data bytes];
		spp = 1;
		colorSpaceName = NSCalibratedBlackColorSpace;
	}
	//16 bit gray
	else {
	//convert to Float
		NSMutableData *data8 = [NSMutableData dataWithLength:_rows*_columns];
		vImage_Buffer src16, dstf, dst8;
		dstf.height = src16.height = dst8.height=  _rows;
		dstf.width = src16.width = dst8.width =  _columns;
		src16.rowBytes = _columns*2;
		dstf.rowBytes = _columns*sizeof(float);
		dst8.rowBytes = _columns;
		
		src16.data = (unsigned short *)[data bytes];
		dstf.data = malloc(_rows*_columns * sizeof(float) + 100);
		dst8.data = (unsigned char *)[data8 mutableBytes];
		if (_isSigned)
			vImageConvert_16SToF( &src16, &dstf, rescaleIntercept, rescaleSlope, 0);
		else
			vImageConvert_16UToF( &src16, &dstf, rescaleIntercept, rescaleSlope, 0);
			
		
		vImageConvert_PlanarFtoPlanar8 (
				 &dstf, 
				 &dst8, 
				max, 
				min, 
				nil		
		);
		//NSLog(@"max %f min: %f intercept: %f, slope: %f", max, min, rescaleIntercept, rescaleSlope);
		free(dstf.data);	
		bmd = dst8.data;
		spp =1;
		colorSpaceName = NSCalibratedWhiteColorSpace;
		
	}
	NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:&bmd
	pixelsWide:_columns 
	pixelsHigh:_rows 
	bitsPerSample:8 
	samplesPerPixel:spp 
	hasAlpha:NO 
	isPlanar:NO 
	colorSpaceName:colorSpaceName 		
	bytesPerRow:0
	bitsPerPixel:0];
				
	[image addRepresentation:rep];
	return image;
}

/*
- (NSXMLNode *)xmlNode{
	NSXMLNode *myNode;
	NSXMLNode *groupAttr = [NSXMLNode attributeWithName:@"group" stringValue:[NSString stringWithFormat:@"%d",[[self tag] group]]];
	NSXMLNode *elementAttr = [NSXMLNode attributeWithName:@"element" stringValue:[NSString stringWithFormat:@"%d",[[self tag] element]]];
	NSXMLNode *vrAttr = [NSXMLNode attributeWithName:@"vr" stringValue:[[self tag] vr]];
	NSArray *attrs = [NSArray arrayWithObjects:groupAttr,elementAttr, vrAttr, nil];
	NSEnumerator *enumerator = [[self values] objectEnumerator];
	id value;
	//NSMutableArray *elements = [NSMutableArray array];

	
	myNode = [NSXMLNode elementWithName:@"element" children:nil attributes:attrs];
	return myNode;
}
*/







@end
