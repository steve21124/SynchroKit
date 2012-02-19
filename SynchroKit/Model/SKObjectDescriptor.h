//
//  SKObjectDescriptor.h
//  SynchroKit
//
//  Created by Kamil Burczyk on 12-02-19.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SKObjectDescriptor : NSObject{
    NSString *name;
    int identifier;
    NSDate *lastUsedDate;
    int usedCount;
}

@property(nonatomic, retain) NSString* name;
@property(nonatomic, assign) int identifier;
@property(nonatomic, retain) NSDate* lastUsedDate;
@property(nonatomic, assign) int usedCount;

@end
