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



#import <Foundation/Foundation.h>


@interface DicomDirParser : NSObject
{
	NSString				*data, *dirpath;
}

- (id) init:(NSString*) file;
- (NSMutableArray*) parseArray:(NSMutableArray*) files;

@end
