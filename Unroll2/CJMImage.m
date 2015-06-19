//
//  CJMImage.m
//  Unroll
//
//  Created by Curt on 4/13/15.
//  Copyright (c) 2015 Bluewraith. All rights reserved.
//

#import "CJMImage.h"



@implementation CJMImage

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if(self)
    {
        _name = [aDecoder decodeObjectForKey:@"Name"];
        _local = [aDecoder decodeBoolForKey:@"Local"];
        _photoID = [aDecoder decodeObjectForKey:@"photoID"];
        _photoTitle = [aDecoder decodeObjectForKey:@"Title"];
        _photoNote = [aDecoder decodeObjectForKey:@"Note"];
        _photoCreationDate = [aDecoder decodeObjectForKey:@"CreationDate"];
        _photoLocation = [aDecoder decodeObjectForKey:@"Location"];
        
        _selected = YES;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:self.name forKey:@"Name"];
    [aCoder encodeBool:self.local forKey:@"Local"];
    [aCoder encodeObject:self.photoID forKey:@"photoID"];
    [aCoder encodeObject:self.photoTitle forKey:@"Title"];
    [aCoder encodeObject:self.photoNote forKey:@"Note"];
    [aCoder encodeObject:self.photoCreationDate forKey:@"CreationDate"];
    [aCoder encodeObject:self.photoLocation forKey:@"Location"];
    
}

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        _photoID = [NSUUID UUID];
    }
    _selected = YES;
    return self;
}

- (NSString *)fileName
{
    return [self.photoID UUIDString];
}

- (NSString *)thumbnailFileName
{
    return [[self fileName] stringByAppendingString:@"_sm"];
}

#pragma mark - Selected

- (void)toggleSelected
{
    self.selected = !self.selected;
}

@end
