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

@protocol Schedulable;

@interface Scheduler : NSObject {
    @private
    id _delegate;                               // Delegate
    id <Schedulable> _schedulableObject;        // Object which has work units to be scheduled
    NSMutableSet *_workUnitsRemaining;          // Work units not yet performed in schedule
    NSLock *_remainingUnitsLock;                // Lock to keep the remaining work units set consistent
    BOOL _scheduleWasCancelled;                 // Flag set when schedule is cancelled
    unsigned _numberOfThreads;                  // Number of simultaneous threads used to perform work
    unsigned _numberOfDetachedThreads;          // The current number of worker threads detached.
}

-(id)initForSchedulableObject:(id <Schedulable>)schedObj andNumberOfThreads:(unsigned)numThreads;
-(id)initForSchedulableObject:(id <Schedulable>)schedObj;
-(void)dealloc;

-(void)performScheduleForWorkUnits:(NSSet *)workUnits;
-(void)cancelSchedule;

// Template method. Overload in subclasses
-(NSSet *)_workUnitsToExecuteForRemainingUnits:(NSSet *)remainingUnits;

// Accessors
-(unsigned)numberOfThreads;
-(unsigned) numberOfDetachedThreads;

-(id)delegate;
-(void)setDelegate:(id)delegate;

-(id <Schedulable>)schedulableObject;

-(NSMutableSet *)_workUnitsRemaining;

@end

@interface Scheduler (SchedulerDelegateMethods)

// Sent in the main thread
-(void)schedulerWillBeginSchedule:(Scheduler *)sender;

// The following are sent in the worker thread
-(BOOL)scheduler:(Scheduler *)scheduler shouldBeginUnits:(NSSet *)units;
-(void)scheduler:(Scheduler *)scheduler didCompleteUnits:(NSSet *)units;

// Sent in the main thread
-(void)schedulerDidCancelSchedule:(Scheduler *)scheduler;
-(void)schedulerDidFinishSchedule:(Scheduler *)scheduler;

@end