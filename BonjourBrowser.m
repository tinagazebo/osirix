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

#include <netdb.h>

#import "BonjourBrowser.h"
#import "BrowserController.h"
#import "AppController.h"
#import "DicomFile.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

#define FILESSIZE 512*512*2

#define TIMEOUT	10
#define USEZIP NO

extern NSString			*documentsDirectory();

volatile static BOOL threadIsRunning = NO;

@implementation BonjourBrowser

+ (NSString*) bonjour2local: (NSString*) str
{
	if( str == 0L) return 0L;
	
	NSMutableString	*destPath = [NSMutableString string];
	
	[destPath appendString:documentsDirectory()];
	[destPath appendString:@"/TEMP/"];
	[destPath appendString: [str lastPathComponent]];

	return destPath;
}

- (id) initWithBrowserController: (BrowserController*) bC bonjourPublisher:(BonjourPublisher*) bPub{
	self = [super init];
	if (self != nil)
	{
		long i;
		
		browser = [[NSNetServiceBrowser alloc] init];
		services = [[NSMutableArray array] retain];
		
		[self buildFixedIPList];
		
		interfaceOsiriX = bC;
		
		strcpy( messageToRemoteService, ".....");
		
		publisher = bPub;
		
		dbFileName = 0L;
		dicomFileNames = 0L;
		paths = 0L;
		path = 0L;
		filePathToLoad = 0L;
		FileModificationDate = 0L;
		
		localVersion = 0;
		BonjourDatabaseVersion = 0;
		
		resolved = YES;
		alreadyExecuting = NO;
		
		setValueObject = 0L;
		setValueValue = 0L;
		setValueKey = 0L;
		modelVersion = 0L;
		
		serviceBeingResolvedIndex = -1;
		[browser setDelegate:self];
		
		[browser searchForServicesOfType:@"_osirix._tcp." inDomain:@""];
		
		[[NSNotificationCenter defaultCenter] addObserver: self
															  selector: @selector(updateFixedIPList:)
																  name: @"OsiriXServerArray has changed"
																object: nil];
	}
	return self;
}

- (void) dealloc
{
	[path release];
	[paths release];
	[dbFileName release];
	[dicomFileNames release];
	[modelVersion release];
	[FileModificationDate release];
	[filePathToLoad release];
	
	[super dealloc];
}

- (NSMutableArray*) services
{
	return services;
}

//- (BOOL) unzipToPath:(NSString*)_toPath
//{
//	NSFileManager              *localFm     = nil;
//	NSFileHandle               *nullHandle  = nil;
//	NSTask                     *unzipTask   = nil;
//	int                        result;
//
//	localFm     = [NSFileManager defaultManager];
//
//	nullHandle  = [NSFileHandle fileHandleForWritingAtPath:@"/dev/null"];
//	unzipTask   = [[NSTask alloc] init];
//	[unzipTask setLaunchPath:@"/usr/bin/unzip"];
//	[unzipTask setCurrentDirectoryPath: [[_toPath stringByDeletingLastPathComponent] stringByAppendingString:@"/"]];
//	[unzipTask setArguments:[NSArray arrayWithObjects: _toPath, nil]];
//	[unzipTask setStandardOutput: nullHandle];
//	[unzipTask setStandardError: nullHandle];
//	[unzipTask launch];
//	if ([unzipTask isRunning]) [unzipTask waitUntilExit];
//	result      = [unzipTask terminationStatus];
//
//	[unzipTask release];
//
//	[localFm removeFileAtPath:_toPath handler:nil];
//
//	return YES;
//}

- (void)readAllTheData:(NSNotification *)note
{
	NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];		// <- Keep this line, very important to avoid memory crash (remplissage memoire) - Antoine
	BOOL				success = YES;
	NSData				*data = [[note userInfo] objectForKey:NSFileHandleNotificationDataItem];
	
	if( data)
	{
		if( [data bytes])
		{
			if ( strcmp( messageToRemoteService, "DATAB") == 0)
			{
				// we asked for a SQL file, let's write it on disc
				[dbFileName release];
				if( serviceBeingResolvedIndex < BonjourServices) dbFileName = [[self databaseFilePathForService:[[[self services] objectAtIndex:serviceBeingResolvedIndex] name]] retain];
				else dbFileName = [[self databaseFilePathForService:[[[self services] objectAtIndex:serviceBeingResolvedIndex] valueForKey:@"Description"]] retain];
				
				[[NSFileManager defaultManager] removeFileAtPath: dbFileName handler:0L];
				
				success = [data writeToFile: dbFileName atomically:YES];
				
			//	success = [[NSFileManager defaultManager] createFileAtPath: dbFileName contents:data attributes:nil];
			}
			else if ( strcmp( messageToRemoteService, "MFILE") == 0)
			{
				[FileModificationDate release];
				FileModificationDate = [[NSString alloc] initWithData:data encoding: NSUnicodeStringEncoding];
			}
			else if ( strcmp( messageToRemoteService, "RFILE") == 0)
			{
				NSString *destPath = [BonjourBrowser bonjour2local: filePathToLoad];
				[[NSFileManager defaultManager] removeFileAtPath: destPath handler:0L];
				
				long	pos = 0, size;
				NSData	*curData = 0L;
				
				// The File
				size = NSSwapBigLongToHost( *((long*)[[data subdataWithRange: NSMakeRange(pos, 4)] bytes]));
				pos += 4;
				curData = [data subdataWithRange: NSMakeRange(pos, size)];
				pos += size;
				
				// Write the file
				success = [curData writeToFile: destPath atomically:YES];
				
				// The modification date
				size = NSSwapBigLongToHost( *((long*)[[data subdataWithRange: NSMakeRange(pos, 4)] bytes]));
				pos += 4;
				curData = [data subdataWithRange: NSMakeRange(pos, size)];
				pos += size;
				
				NSString	*str = [[NSString alloc] initWithData:curData encoding: NSUnicodeStringEncoding];
				
				// Change the modification & creation date
				NSDictionary *fattrs = [[NSFileManager defaultManager] fileAttributesAtPath:destPath traverseLink:YES];
				
				NSMutableDictionary *newfattrs = [NSMutableDictionary dictionaryWithDictionary: fattrs];
				[newfattrs setObject:[NSDate dateWithString:str] forKey:NSFileModificationDate];
				[newfattrs setObject:[NSDate dateWithString:str] forKey:NSFileCreationDate];
				[[NSFileManager defaultManager] changeFileAttributes:newfattrs atPath:destPath];
				
				[str release];
			}
			else if (strcmp( messageToRemoteService, "DICOM") == 0)
			{
				// we asked for a DICOM file(s), let's write it on disc
				
				long pos = 0, noOfFiles, size, i;
				
				noOfFiles = NSSwapBigLongToHost( *((long*)[[data subdataWithRange: NSMakeRange(pos, 4)] bytes]));
				pos += 4;
					
				for( i = 0 ; i < noOfFiles; i++)
				{
					size = NSSwapBigLongToHost( *((long*)[[data subdataWithRange: NSMakeRange(pos, 4)] bytes]));
					pos += 4;
					
					NSData	*curData = [data subdataWithRange: NSMakeRange(pos, size)];
					pos += size;
					
					size = NSSwapBigLongToHost( *((long*)[[data subdataWithRange: NSMakeRange(pos, 4)] bytes]));
					pos += 4;
					
					NSString *localPath = [NSString stringWithUTF8String: [[data subdataWithRange: NSMakeRange(pos,size)] bytes]];
					pos += size;
					
					if( [curData length])
					{
						if ([[NSFileManager defaultManager] fileExistsAtPath: localPath]) NSLog(@"strange...");
						
						[[NSFileManager defaultManager] removeFileAtPath: localPath handler:0L];
						success = [[NSFileManager defaultManager] createFileAtPath: [localPath stringByAppendingString:@"RENAME"] contents:curData attributes:nil];
						success = [[NSFileManager defaultManager] movePath:[localPath stringByAppendingString:@"RENAME"] toPath:localPath handler:0L];
						
						if( success == NO)
						{
							NSLog(@"Bonjour transfer failed");
						}
					}
				}
			}
			else if (strcmp( messageToRemoteService, "VERSI") == 0)
			{
				// we asked for the last time modification date & time of the database
				
				BonjourDatabaseVersion = NSSwapBigDoubleToHost( *((NSSwappedDouble*) [data bytes]));
			}
			else if (strcmp( messageToRemoteService, "DBVER") == 0)
			{
				// we asked for the last time modification date & time of the database
				
				[modelVersion release];
				modelVersion = [[NSString alloc] initWithData:data encoding: NSASCIIStringEncoding];
			}
			else if (strcmp( messageToRemoteService, "PASWD") == 0)
			{
				long result = NSSwapBigLongToHost( *((long*) [data bytes]));
				
				if( result) wrongPassword = NO;
				else wrongPassword = YES;
			}
			else if (strcmp( messageToRemoteService, "ISPWD") == 0)
			{
				long result = NSSwapBigLongToHost( *((long*) [data bytes]));
				
				if( result) isPasswordProtected = YES;
				else isPasswordProtected = NO;
			}
			else if (strcmp( messageToRemoteService, "SETVA") == 0)
			{
				
			}

			if( success == NO)
			{
				NSLog(@"Bonjour transfer failed");
			}
		}
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object: [note object]];
	[[note object] release];
	
	resolved = YES;
	
	[pool release];
}

//socket.h
- (void) connectToService: (struct sockaddr_in*) socketAddress
{
	int socketToRemoteServer = socket(AF_INET, SOCK_STREAM, 0);
	if(socketToRemoteServer > 0)
	{
		// SEND DATA
	
		NSFileHandle * sendConnection = [[NSFileHandle alloc] initWithFileDescriptor:socketToRemoteServer closeOnDealloc:YES];
		if(sendConnection)
		{
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(readAllTheData:) name:NSFileHandleReadToEndOfFileCompletionNotification object: sendConnection];
			
			 if(connect(socketToRemoteServer, (struct sockaddr *)socketAddress, sizeof(*socketAddress)) == 0)
			 {
				// transfering the type of data we need
				NSMutableData	*toTransfer = [NSMutableData dataWithCapacity:0];
				
				[toTransfer appendBytes:messageToRemoteService length: 6];
				
				if (strcmp( messageToRemoteService, "SETVA") == 0)
				{
					const char* string;
					long stringSize;
					
					string = [setValueObject UTF8String];
					stringSize  = NSSwapHostLongToBig( strlen( string)+1);	// +1 to include the last 0 !
					
					[toTransfer appendBytes:&stringSize length: 4];
					[toTransfer appendBytes:string length: strlen( string)+1];
					
					if( setValueValue == 0L)
					{
						string = 0L;
						stringSize = 0;
					}
					else if( [setValueValue isKindOfClass:[NSNumber class]])
					{
						string = [[setValueValue stringValue] UTF8String];
						stringSize = NSSwapHostLongToBig( strlen( string)+1);	// +1 to include the last 0 !
					}
					else
					{
						string = [setValueValue UTF8String];
						stringSize = NSSwapHostLongToBig( strlen( string)+1);	// +1 to include the last 0 !
					}
					
					[toTransfer appendBytes:&stringSize length: 4];
					if( stringSize)
						[toTransfer appendBytes:string length: strlen( string)+1];
					
					string = [setValueKey UTF8String];
					stringSize = NSSwapHostLongToBig( strlen( string)+1);	// +1 to include the last 0 !
					
					[toTransfer appendBytes:&stringSize length: 4];
					[toTransfer appendBytes:string length: strlen( string)+1];
				}
				
				if (strcmp( messageToRemoteService, "RFILE") == 0)
				{
					NSData	*filenameData = [filePathToLoad dataUsingEncoding: NSUnicodeStringEncoding];
					long stringSize = NSSwapHostLongToBig( [filenameData length]);	// +1 to include the last 0 !
					
					[toTransfer appendBytes:&stringSize length: 4];
					[toTransfer appendBytes:[filenameData bytes] length: [filenameData length]];
				}
				
				if (strcmp( messageToRemoteService, "MFILE") == 0)
				{
					NSData	*filenameData = [filePathToLoad dataUsingEncoding: NSUnicodeStringEncoding];
					long stringSize = NSSwapHostLongToBig( [filenameData length]);	// +1 to include the last 0 !
					
					[toTransfer appendBytes:&stringSize length: 4];
					[toTransfer appendBytes:[filenameData bytes] length: [filenameData length]];
				}
				
				if (strcmp( messageToRemoteService, "WFILE") == 0)
				{
					NSData	*filenameData = [filePathToLoad dataUsingEncoding: NSUnicodeStringEncoding];
					long stringSize = NSSwapHostLongToBig( [filenameData length]);	// +1 to include the last 0 !
					
					[toTransfer appendBytes:&stringSize length: 4];
					[toTransfer appendBytes:[filenameData bytes] length: [filenameData length]];
					
					NSData	*fileData = [NSData dataWithContentsOfFile: filePathToLoad];
					long dataSize = NSSwapHostLongToBig( [fileData length]);
					[toTransfer appendBytes:&dataSize length: 4];
					[toTransfer appendData: fileData];
				}
				
				if (strcmp( messageToRemoteService, "DICOM") == 0)
				{
					long i, temp, noOfFiles = [paths count];
					
					temp = NSSwapHostLongToBig( noOfFiles);
					[toTransfer appendBytes:&temp length: 4];
					for( i = 0; i < noOfFiles ; i++)
					{
						const char* string = [[paths objectAtIndex: i] UTF8String];
						long stringSize = NSSwapHostLongToBig( strlen( string)+1);	// +1 to include the last 0 !
						
						[toTransfer appendBytes:&stringSize length: 4];
						[toTransfer appendBytes:string length: strlen( string)+1];
					}
					
					for( i = 0; i < noOfFiles ; i++)
					{
						const char* string = [[dicomFileNames objectAtIndex: i] UTF8String];
						long stringSize = NSSwapHostLongToBig( strlen( string)+1);	// +1 to include the last 0 !
						
						[toTransfer appendBytes:&stringSize length: 4];
						[toTransfer appendBytes:string length: strlen( string)+1];
					}
				}
				
				if ((strcmp( messageToRemoteService, "SENDD") == 0))
				{
					NSData	*file = [NSData dataWithContentsOfFile: path];
					
					long fileSize = NSSwapHostLongToBig( [file length]);
					[toTransfer appendBytes:&fileSize length: 4];
					[toTransfer appendData:file];
				}
				
				if ((strcmp( messageToRemoteService, "PASWD") == 0))
				{
					const char* passwordUTF = [password UTF8String];
					long stringSize = NSSwapHostLongToBig( strlen( passwordUTF)+1);	// +1 to include the last 0 !
					
					[toTransfer appendBytes:&stringSize length: 4];
					[toTransfer appendBytes:passwordUTF length: strlen( passwordUTF)+1];
				}
				
				[sendConnection writeData: toTransfer];
				
//					NSData				*readData;
//					NSMutableData		*data = [NSMutableData dataWithCapacity: 0];
//					while ( (readData = [sendConnection availableData]) && [readData length]) [data appendData: readData];
//					NSLog( @"Received data: %d Mb", [data length]/(1024*1024));
//					[self readAllTheData: data];
//					[sendConnection release];
				
				[sendConnection readToEndOfFileInBackgroundAndNotify];
			}
		}
		else
		{
			close(socketToRemoteServer);
		}
	}
}

- (long) BonjourServices
{
	return BonjourServices;
}

- (void) buildFixedIPList
{
	long			i;
	NSArray			*osirixServersArray		= [[NSUserDefaults standardUserDefaults] arrayForKey: @"OSIRIXSERVERS"];
	
	
	
	for( i = 0; i < [osirixServersArray count]; i++)
	{
		[services addObject: [osirixServersArray objectAtIndex: i]];
	}
}


//———————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————

- (void) updateFixedIPList: (NSNotification*) note
{
	[services removeObjectsInRange: NSMakeRange( BonjourServices, [services count] - BonjourServices)];
	[self buildFixedIPList];
	[interfaceOsiriX displayBonjourServices];
}


//———————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————


- (void) fixedIP: (int) index
{
	struct sockaddr_in service;
	const char	*host_name = [[[services objectAtIndex: index] valueForKey:@"Address"] UTF8String];
	
	bzero((char *) &service, sizeof(service));
	service.sin_family = AF_INET;
	
	if (isalpha(host_name[0]))
	{
		struct hostent *hp;
		
		hp = gethostbyname( host_name);
		if( hp) bcopy(hp->h_addr, (char *) &service.sin_addr, hp->h_length);
		else service.sin_addr.s_addr = inet_addr( host_name);
	}
	else service.sin_addr.s_addr = inet_addr( host_name);
	
	service.sin_port = htons(8780);
	
	[self connectToService: &service];
}

- (void) netServiceDidResolveAddress:(NSNetService *)sender
{
   if ([[sender addresses] count] > 0)
   {
        NSData * address;
        struct sockaddr * socketAddress;
        NSString * ipAddressString = nil;
        NSString * portString = nil;
        char buffer[256];
        int index;

        // Iterate through addresses until we find an IPv4 address
        for (index = 0; index < [[sender addresses] count]; index++) {
            address = [[sender addresses] objectAtIndex:index];
            socketAddress = (struct sockaddr *)[address bytes];

            if (socketAddress->sa_family == AF_INET) break;
        }

        // Be sure to include <netinet/in.h> and <arpa/inet.h> or else you'll get compile errors.

        if (socketAddress) {
            switch(socketAddress->sa_family) {
                case AF_INET:
                    if (inet_ntop(AF_INET, &((struct sockaddr_in *)socketAddress)->sin_addr, buffer, sizeof(buffer))) {
                        ipAddressString = [NSString stringWithCString:buffer];
                        portString = [NSString stringWithFormat:@"%d", ntohs(((struct sockaddr_in *)socketAddress)->sin_port)];
                    }
                    
                    // Cancel the resolve now that we have an IPv4 address.
                    [sender stop];
                    [sender release];
                    serviceBeingResolved = nil;

                    break;
                case AF_INET6:
                    // OsiriX server doesn't support IPv6
                    return;
            }
        }
		
		[self connectToService: (struct sockaddr_in *) socketAddress];
	}
}

// This object is the delegate of its NSNetServiceBrowser object.
- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    // add every service found on the network

	// remove my own sharing service
	if( aNetService == [publisher netService] || [[aNetService name] isEqualToString: [publisher serviceName]] == YES)
	{
		
	}
	else
	{
		[services insertObject:aNetService atIndex:BonjourServices];
		BonjourServices ++;
	}
	// update interface
    if(!moreComing) [interfaceOsiriX displayBonjourServices];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
    // This case is slightly more complicated. We need to find the object in the list and remove it.
    NSEnumerator * enumerator = [services objectEnumerator];
    NSNetService * currentNetService;

    while(currentNetService = [enumerator nextObject]) {
        if ([currentNetService isEqual:aNetService])
		{
			// deleting the associate SQL temporary file
			if ([[NSFileManager defaultManager] fileExistsAtPath: [self databaseFilePathForService:[aNetService name]] ])
			{
				[[NSFileManager defaultManager] removeFileAtPath: [self databaseFilePathForService:[currentNetService name]] handler:self];
			}
									
			if( [interfaceOsiriX currentBonjourService] == [services indexOfObject: aNetService])
			{
				[interfaceOsiriX resetToLocalDatabase];
			}

			// deleting service from list
            [services removeObject:currentNetService];

			BonjourServices --;
            break;
        }
    }

    if (serviceBeingResolved && [serviceBeingResolved isEqual:aNetService]) {
        [serviceBeingResolved stop];
        [serviceBeingResolved release];
        serviceBeingResolved = nil;
    }

    if(!moreComing)
	{
		[interfaceOsiriX displayBonjourServices];
	}
}
//
//- (void) stopService
//{
//	return;
//	
//	if (serviceBeingResolved)
//	{
//        [serviceBeingResolved stop];
//        [serviceBeingResolved release];
//        serviceBeingResolved = nil;
//    }
//}

- (void) resolveServiceWithIndex:(int)index msg: (void*) msg
{
	serviceBeingResolvedIndex = index;
	strcpy( messageToRemoteService, msg);
	resolved = YES;
	
    //  Make sure to cancel any previous resolves.
    if (serviceBeingResolved) {
        [serviceBeingResolved stop];
        [serviceBeingResolved release];
        serviceBeingResolved = nil;
    }

	
    if(-1 == index)
	{
    }
	else if( index >= BonjourServices)
	{
		resolved = NO;
		[self fixedIP: index];
	}
	else
	{        
        serviceBeingResolved = [services objectAtIndex:index];
        [serviceBeingResolved retain];
        [serviceBeingResolved setDelegate:self];
		
		[serviceBeingResolved scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:	NSDefaultRunLoopMode];
		
		resolved = NO;
		[serviceBeingResolved resolveWithTimeout:5];
    }
}

- (BOOL) isBonjourDatabaseUpToDate: (int) index
{
	BOOL result;
	
	if( alreadyExecuting == YES) return YES;
	
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	alreadyExecuting = YES;
	[interfaceOsiriX setBonjourDownloading: YES];
	
	[self resolveServiceWithIndex: index msg:"VERSI"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	
	if( localVersion == BonjourDatabaseVersion) result = YES;
	else result = NO;
	
	[interfaceOsiriX setBonjourDownloading: NO];
	alreadyExecuting = NO;
	return result;
}

- (void) setBonjourDatabaseValueThread:(NSNumber*) object
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self resolveServiceWithIndex: [object intValue] msg:"SETVA"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
		
	[self resolveServiceWithIndex: [object intValue] msg:"VERSI"];
	timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	localVersion = BonjourDatabaseVersion;
	
	threadIsRunning = NO;
	
	[pool release];
}

- (void) setBonjourDatabaseValue:(int) index item:(NSManagedObject*) obj value:(id) value forKey:(NSString*) key
{
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	alreadyExecuting = YES;
	[interfaceOsiriX setBonjourDownloading: YES];
	
	[setValueObject release];
	[setValueValue release];
	[setValueKey release];
	
	setValueObject = [[[[obj objectID] URIRepresentation] absoluteString] retain];
	setValueValue = [value retain];
	setValueKey = [key retain];
	
	threadIsRunning = YES;
	[NSThread detachNewThreadSelector:@selector(setBonjourDatabaseValueThread:) toTarget:self withObject:[NSNumber numberWithInt: index]];
	while( threadIsRunning == YES) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	
	[interfaceOsiriX setBonjourDownloading: NO];
	alreadyExecuting = NO;
}

- (void) getFileModificationThread : (NSNumber*) object
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self resolveServiceWithIndex: [object intValue]  msg:"MFILE"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];};
	
	threadIsRunning = NO;
	
	[pool release];
}

- (NSDate*) getFileModification:(NSString*) pathFile index:(int) index 
{
	NSMutableString	*returnedFile = 0L;
	NSDate			*modificationDate = 0L;
	
	if( [[NSFileManager defaultManager] fileExistsAtPath: [BonjourBrowser bonjour2local: pathFile]])
	{
		NSDictionary *fattrs = [[NSFileManager defaultManager] fileAttributesAtPath:[BonjourBrowser bonjour2local: pathFile] traverseLink:YES];
		return [fattrs objectForKey:NSFileModificationDate];
	}
	
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];};
	alreadyExecuting = YES;
	[interfaceOsiriX setBonjourDownloading: YES];
	
	[filePathToLoad release];
	
	filePathToLoad = [pathFile retain];
	
	threadIsRunning = YES;
	[NSThread detachNewThreadSelector:@selector(getFileModificationThread:) toTarget:self withObject:[NSNumber numberWithInt: index]];
	while( threadIsRunning == YES) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	
	if( resolved == YES)
	{
		modificationDate = [NSDate dateWithString: FileModificationDate];
	}

	[interfaceOsiriX setBonjourDownloading: NO];
	alreadyExecuting = NO;
	
	return modificationDate;
}

- (void) getFileThread:(NSNumber*) object
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	[self resolveServiceWithIndex: [object intValue] msg:"RFILE"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	
	threadIsRunning = NO;
	
	[pool release];
}

- (NSString*) getFile:(NSString*) pathFile index:(int) index 
{
	NSString	*returnedFile = 0L;
	
	// Does the file already exist?
	
	returnedFile = [BonjourBrowser bonjour2local: pathFile];
	
	if( [[NSFileManager defaultManager] fileExistsAtPath:returnedFile]) return returnedFile;
	else returnedFile = 0L;
	
	//
	
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	alreadyExecuting = YES;
	[interfaceOsiriX setBonjourDownloading: YES];
	
	[filePathToLoad release];
	filePathToLoad = [pathFile retain];
	
	threadIsRunning = YES;
	[NSThread detachNewThreadSelector:@selector(getFileThread:) toTarget:self withObject:[NSNumber numberWithInt: index]];
	while( threadIsRunning == YES) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	
	if( resolved == YES)
	{
		returnedFile = [BonjourBrowser bonjour2local: filePathToLoad];
	}
	
	[interfaceOsiriX setBonjourDownloading: NO];
	alreadyExecuting = NO;
	
	return returnedFile;
}

- (void) sendFileThread:(NSNumber*) object
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self resolveServiceWithIndex: [object intValue] msg:"WFILE"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	
	threadIsRunning = NO;
	
	[pool release];
}

- (BOOL) sendFile:(NSString*) pathFile index:(int) index 
{
	BOOL succeed = NO;
	
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	alreadyExecuting = YES;
	[interfaceOsiriX setBonjourDownloading: YES];
	
	[filePathToLoad release];
	
	filePathToLoad = [pathFile retain];
	
	threadIsRunning = YES;
	[NSThread detachNewThreadSelector:@selector(sendFileThread:) toTarget:self withObject:[NSNumber numberWithInt: index]];
	while( threadIsRunning == YES) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	
	if( resolved == YES)
	{
		succeed = YES;
	}
	
	[interfaceOsiriX setBonjourDownloading: NO];
	alreadyExecuting = NO;
	
	return succeed;
}


- (NSString*) getDatabaseFile:(int) index
{
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	alreadyExecuting = YES;
	[interfaceOsiriX setBonjourDownloading: YES];
	
	[dbFileName release];
	dbFileName = 0L;
	
	isPasswordProtected = NO;
	
	[self resolveServiceWithIndex: index msg:"DBVER"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	
	if( resolved == YES)
	{
		if( [modelVersion isEqualToString:[[NSUserDefaults standardUserDefaults] stringForKey: @"DATABASEVERSION"]] == NO)
		{
			NSRunAlertPanel( NSLocalizedString( @"Bonjour Database", 0L), NSLocalizedString( @"Database structure is not identical. Use the SAME version of OsiriX on clients and servers to correct the problem.", 0L), nil, nil, nil);
			[interfaceOsiriX setBonjourDownloading: NO];
			alreadyExecuting = NO;
			return 0L;
		}
		
		if( serviceBeingResolvedIndex != index)
		{
			[self resolveServiceWithIndex: index msg:"ISPWD"];
			NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
			while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
		}
		else
		{
			resolved = YES;
		}
		
		if( resolved == YES)
		{
			if( isPasswordProtected)
			{
				[password release];
				password = 0L;
				
				password = [[interfaceOsiriX askPassword] retain];
				
				wrongPassword = YES;
				[self resolveServiceWithIndex: index msg:"PASWD"];
				NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
				while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
				
				if( resolved == NO || wrongPassword == YES)
				{
					NSRunAlertPanel( NSLocalizedString( @"Bonjour Database", 0L), NSLocalizedString( @"Wrong password.", 0L), nil, nil, nil);
					
					[interfaceOsiriX setBonjourDownloading: NO];
					alreadyExecuting = NO;
					return 0L;
				}
			}
			
			[self resolveServiceWithIndex: index msg:"DATAB"];
			NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
			while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
			
			if( resolved == YES)
			{
				[self resolveServiceWithIndex: index msg:"VERSI"];
				NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
				while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
				
				localVersion = BonjourDatabaseVersion;
			}
		}
	}
	
	[interfaceOsiriX setBonjourDownloading: NO];
	alreadyExecuting = NO;
	return dbFileName;
}

- (void) sendDICOMFileThread : (NSNumber*) object
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self resolveServiceWithIndex: [object intValue] msg:"SENDD"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	
	threadIsRunning = NO;
	
	[pool release];
}

- (BOOL) sendDICOMFile:(int) index path:(NSString*) ip
{
	if( [[NSFileManager defaultManager] fileExistsAtPath: ip] == NO) return NO;
	
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};
	alreadyExecuting = YES;	
	[interfaceOsiriX setBonjourDownloading: YES];
	
	[path release];
	path = [ip retain];
	
	threadIsRunning = YES;
	[NSThread detachNewThreadSelector:@selector(sendDICOMFileThread:) toTarget:self withObject:[NSNumber numberWithInt: index]];
	while( threadIsRunning == YES) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	
	[interfaceOsiriX setBonjourDownloading: NO];
	alreadyExecuting = NO;
	return YES;
}

- (void) getDICOMFileThread : (NSNumber*) object
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self resolveServiceWithIndex: [object intValue] msg:"DICOM"];
	NSDate	*timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
	while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	if( resolved == NO)
	{
		// Try again
		NSLog(@"failed, but try again");
		
		[self resolveServiceWithIndex: [object intValue] msg:"DICOM"];
		timeout = [NSDate dateWithTimeIntervalSinceNow: TIMEOUT];
		while( resolved == NO && [timeout timeIntervalSinceNow] >= 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
		if( resolved == NO) NSLog(@"failed...");
	}
	
	threadIsRunning = NO;
	
	[pool release];
}

- (NSString*) getDICOMFile:(int) index forObject:(NSManagedObject*) image noOfImages: (long) noOfImages
{
	while( alreadyExecuting == YES) {[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];};		// [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];	//
	alreadyExecuting = YES;
//	NSLog(@"IN");
//	[interfaceOsiriX setBonjourDownloading: YES];

	// Does this file already exist?
	NSString	*uniqueFileName = [NSString stringWithFormat:@"%@-%@-%@-%d.%@", [image valueForKeyPath:@"series.study.patientUID"], [image valueForKey:@"sopInstanceUID"], [[image valueForKey:@"path"] lastPathComponent], [[image valueForKey:@"instanceNumber"] intValue], [image valueForKey:@"extension"]];
	NSString	*dicomFileName = [[documentsDirectory() stringByAppendingPathComponent:@"/TEMP/"] stringByAppendingPathComponent: [DicomFile NSreplaceBadCharacter:uniqueFileName]];
	if( [[NSFileManager defaultManager] fileExistsAtPath: dicomFileName])
	{
		//NSLog(@"OUT");
		alreadyExecuting = NO;
		return dicomFileName;
	}

	[dicomFileNames release];
	dicomFileNames = [[NSMutableArray alloc] initWithCapacity: 0];
	
	[paths release];
	paths = [[NSMutableArray alloc] initWithCapacity: 0];
	
	// TRY TO LOAD MULTIPLE DICOM FILES AT SAME TIME -> better network performances
	
	NSSortDescriptor	*sort = [[[NSSortDescriptor alloc] initWithKey:@"instanceNumber" ascending:YES] autorelease];
	NSArray				*images = [[[[image valueForKey: @"series"] valueForKey:@"images"] allObjects] sortedArrayUsingDescriptors: [NSArray arrayWithObject: sort]];
	long				size = 0, i = [images indexOfObject: image];
	
	do
	{
		NSManagedObject	*curImage = [images objectAtIndex: i];
		
		NSString	*uniqueFileName = [NSString stringWithFormat:@"%@-%@-%@-%d.%@", [curImage valueForKeyPath:@"series.study.patientUID"], [curImage valueForKey:@"sopInstanceUID"], [[curImage valueForKey:@"path"] lastPathComponent], [[curImage valueForKey:@"instanceNumber"] intValue], [image valueForKey:@"extension"]];
		
		dicomFileName = [[documentsDirectory() stringByAppendingPathComponent:@"/TEMP/"] stringByAppendingPathComponent: [DicomFile NSreplaceBadCharacter:uniqueFileName]];
		
		if( [[NSFileManager defaultManager] fileExistsAtPath: dicomFileName] == NO)
		{
		//	NSLog( [curImage valueForKey:@"path"]);
			[paths addObject: [curImage valueForKey:@"path"]];
			[dicomFileNames addObject: dicomFileName];
			
			size += [[curImage valueForKeyPath:@"width"] intValue] * [[curImage valueForKeyPath:@"height"] intValue] * 2 * [[curImage valueForKeyPath:@"numberOfFrames"] intValue];
			
			if([[[curImage valueForKey:@"path"] pathExtension] isEqualToString:@"zip"])
			{
				// it is a ZIP
				NSLog(@"BONJOUR ZIP");
				NSString *xmlPath = [[[curImage valueForKey:@"path"] stringByDeletingPathExtension] stringByAppendingPathExtension:@"xml"];
				if(![[NSFileManager defaultManager] fileExistsAtPath:xmlPath])
				{
					// it has an XML descriptor with it
					NSLog(@"BONJOUR XML");
					[paths addObject:xmlPath];
					[dicomFileNames addObject: [[dicomFileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"xml"]];
				}
			}
		}
		i++;
		
	}while( size < FILESSIZE*noOfImages && i < [images count]);
	
	threadIsRunning = YES;
	[NSThread detachNewThreadSelector:@selector(getDICOMFileThread:) toTarget:self withObject:[NSNumber numberWithInt: index]];
	while( threadIsRunning == YES) [NSThread sleepUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
	
	alreadyExecuting = NO;
	
	if( [dicomFileNames count] == 0) return 0L;
	
	if( [[NSFileManager defaultManager] fileExistsAtPath: [dicomFileNames objectAtIndex: 0]] == NO) return 0L;
	
	return [dicomFileNames objectAtIndex: 0];
}

- (NSString *) databaseFilePathForService:(NSString*) name
{
	NSMutableString *filePath = [NSMutableString stringWithCapacity:0];
	[filePath appendString:documentsDirectory()];
	[filePath appendString:@"/TEMP/"];
	[filePath appendString:[name stringByAppendingString:@".sql"]];
	return filePath;
}

// delegate of a NSFileManager

-(BOOL)fileManager:(NSFileManager *)manager shouldProceedAfterError:(NSDictionary *)errorDict
{
    int result;
    result = NSRunAlertPanel(NSLocalizedString(@"OsiriX", nil), NSLocalizedString(@"File operation error:	%@ with file: %@", nil), NSLocalizedString(@"Proceed", nil), NSLocalizedString(@"Stop", nil), NULL, [errorDict objectForKey:@"Error"], [errorDict objectForKey:@"path"]);
        
    if (result == NSAlertDefaultReturn)
        return YES;
    else
        return NO;
}

- (void)fileManager:(NSFileManager *)manager willProcessPath:(NSString *)path
{
}

@end
