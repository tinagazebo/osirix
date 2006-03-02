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




#import <Cocoa/Cocoa.h>
#import "Interpolation3D.h"

#ifdef __cplusplus
#include <vtkCardinalSpline.h>
#else
typedef char* vtkCardinalSpline;
#endif

@interface Spline3D : Interpolation3D {
	vtkCardinalSpline	*xSpline, *ySpline, *zSpline;
	BOOL				computed;
}

- (id) init;
- (void) compute;

@end