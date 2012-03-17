//
//  SKDataDownloader.m
//  SynchroKit
//
//  Created by Kamil Burczyk on 12-02-19.
//  Copyright (c) 2012 Kamil Burczyk. All rights reserved.
//

#import "SKDataDownloader.h"

@implementation SKDataDownloader

@synthesize registeredObjects;
@synthesize objectDescriptors;
@synthesize seconds;
@synthesize updateDates;

@synthesize context;

#pragma mark constructors

- (id) initWithRegisteredObjects: (NSMutableDictionary*) _registeredObjects objectDescriptors: (NSMutableSet*) _objectDescriptors {
    self = [super init];
    if (self) {
        interrupted = FALSE;
        isDaemon = FALSE;
        
        updateDates = [[NSMutableDictionary alloc] init];
        [self setRegisteredObjects:_registeredObjects];
        [self setObjectDescriptors:_objectDescriptors];
    }
    return self;
}

- (id) initAsDaemonWithRegisteredObjects: (NSMutableDictionary*) _registeredObjects objectDescriptors: (NSMutableSet*) _objectDescriptors timeInterval: (int) _seconds {
    self = [super init];
    if (self) {
        interrupted = FALSE;
        isDaemon = TRUE;
        
        updateDates = [[NSMutableDictionary alloc] init];
        [self setRegisteredObjects:_registeredObjects];
        [self setObjectDescriptors:_objectDescriptors];
        [self setSeconds:_seconds];
        
        thread = [[NSThread alloc] initWithTarget:self selector:@selector(mainUpdateMethod) object:nil];
        [thread start];
    }
    return self;
}

#pragma mark main download loop

- (void) loadObjectsByName: (NSString*) name {
    RKObjectManager* objectManager = [RKObjectManager sharedManager];
    SKObjectConfiguration *configuration = [registeredObjects valueForKey:name];
    
    //when DataDownloader is not a daemon, download objects synchronously and return from the method
    if(isDaemon == FALSE){
        RKObjectLoader* loader = [objectManager objectLoaderWithResourcePath:[configuration downloadPath] delegate:self];
        loader.objectMapping = [objectManager.mappingProvider objectMappingForClass:[configuration objectClass]];
        [loader sendSynchronously];   
    } else { //if daemon then load asynchronously
        [objectManager loadObjectsAtResourcePath:[configuration downloadPath] delegate:self block:^(RKObjectLoader* loader) {
            loader.objectMapping = [objectManager.mappingProvider objectMappingForClass:[configuration objectClass]];
        }];        
    }
}

- (void) loadAllObjects {
    for (NSString *name in [registeredObjects allKeys]) {
        [self loadObjectsByName:name];        
    }
}

- (void) loadObjectsWhenUpdatedByName: (NSString*) name {
    RKObjectManager* objectManager = [RKObjectManager sharedManager];
    
    SKObjectConfiguration *configuration = [registeredObjects valueForKey:name];
    if (configuration.updateDatePath != Nil && [configuration.updateDatePath length] > 0) { //updateDate exists
        [objectManager loadObjectsAtResourcePath:[configuration updateDatePath] delegate:self block:^(RKObjectLoader* loader) {
            loader.objectMapping = [objectManager.mappingProvider objectMappingForClass:configuration.updateDateClass];
        }];                    
    } else {
        //no synchronization date set - force download
        [self loadObjectsByName:name];
    }
}

- (void) loadAllObjectsWhenUpdated {
    for (NSString *name in [registeredObjects allKeys]) {
        [self loadObjectsWhenUpdatedByName:name];        
    }
}

#pragma mark RKObjectLoaderDelegate methods

- (void)objectLoader:(RKObjectLoader*)objectLoader didLoadObjects:(NSArray*)objects {
	[[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:@"LastUpdatedAt"];
	[[NSUserDefaults standardUserDefaults] synchronize];
	NSLog(@"Loaded objects count: %d", [objects count]);
    NSLog(@"Loaded objects: %@", objects);
    
    for (NSObject *downloadedObject in objects) { //iterate over all objects
        if ([downloadedObject conformsToProtocol:@protocol(UpdateDateProtocol)]) { //if downloaded object is an UpdateDateProtocol
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = [downloadedObject performSelector:@selector(dateFormat)];
            NSDate *objectUpdateDate = [formatter dateFromString:[downloadedObject performSelector:@selector(updateDate)]];
            NSLog(@"%@ last update date: %@", [downloadedObject performSelector:@selector(objectClassName)], [formatter stringFromDate:objectUpdateDate]);
            [updateDates setValue:objectUpdateDate forKey:[downloadedObject performSelector:@selector(objectClassName)]]; //setting update date from UpdateDateProtocol, object downloaded one line below will use it
            
            SKObjectDescriptor *objectDescriptor = [self findDescriptorByName:[downloadedObject performSelector:@selector(objectClassName)]];
            NSLog(@"object descriptor: %@", objectDescriptor);
            NSLog(@"descriptor.date: %@", objectDescriptor.lastUpdateDate);
            if (objectDescriptor == NULL || (objectDescriptor != NULL && objectDescriptor.lastUpdateDate == NULL) || (objectDescriptor != NULL && [objectDescriptor.lastUpdateDate compare: objectUpdateDate] < 0 )) { //there is no such object or object last update date is smaller than last update date on server
                NSLog(@"Changes for %@ on server. Downloading...", [downloadedObject performSelector:@selector(objectClassName)]);
                [self loadObjectsByName:[downloadedObject performSelector:@selector(objectClassName)]];
            } else {
                NSLog(@"Objects %@ synchronized for date: %@", [downloadedObject performSelector:@selector(objectClassName)], objectDescriptor.lastUpdateDate);
            }
            
            [formatter release];
        } else { //downloaded object IS NOT an UpdateDateProtocol
            NSString *name = [[downloadedObject class] description];
            NSLog(@"downloadedObject: %@", [downloadedObject class]);
            NSManagedObjectID *idf = [(NSManagedObject*) downloadedObject objectID]; //(NSManagedObjectID*) [downloadedObject performSelector:@selector(identifier)];
            NSLog(@"szukanie: %@ %@", name, idf);
            SKObjectDescriptor *objectDescriptor = [self findDescriptorByObjectID:idf];
            
            if (objectDescriptor == NULL) { //if there is no object descriptor then create one
                objectDescriptor = [[SKObjectDescriptor alloc] initWithName:name identifier:idf lastUpdateDate:[updateDates valueForKey:name]]; //it should be previously set
                [objectDescriptor setLastUsedDate:[NSDate new]];
                [objectDescriptors addObject:objectDescriptor];
                NSLog(@"Added descriptor: %@ %@ %@", name, idf, [updateDates valueForKey:name]);
                [objectDescriptor release];
            } else { //update existing object descriptor
                [objectDescriptor setLastUsedDate:[updateDates valueForKey:name]];
                NSLog(@"Updated descriptor: %@ %@ %@", name, idf, [updateDates valueForKey:name]);
            }
        }
    }
    NSLog(@"Object descriptors count: %d", [objectDescriptors count]);

}

- (void)objectLoader:(RKObjectLoader*)objectLoader didFailWithError:(NSError*)error {
	NSLog(@"Hit error: %@", error);
}

#pragma mark searcher methods

- (SKObjectDescriptor*) findDescriptorByName: (NSString*) name {
    for (SKObjectDescriptor *objectDescriptor in [self objectDescriptors]) {
        if ([objectDescriptor.name isEqualToString:name]) {
            return objectDescriptor;
        }
    }
    return NULL;    
}

- (SKObjectDescriptor*) findDescriptorByObjectID: (NSManagedObjectID*) objectID {
    for (SKObjectDescriptor *objectDescriptor in [self objectDescriptors]) {
        if ([objectDescriptor.identifier isEqual:objectID]) {
            return objectDescriptor;
        }
    }
    return NULL;
}

#pragma mark Thread methods

- (void) mainUpdateMethod {
    NSLog(@"Thread started");
    
    while (!interrupted) {
        [self loadAllObjectsWhenUpdated];
        sleep(seconds);
    }
}

- (void) interrupt {
    NSLog(@"stopping Thread");
    interrupted = TRUE;
}

@end
