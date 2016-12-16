//
//  CJMAlbumStore.m
//  Unroll
//
//  Created by Curt on 4/12/15.
//  Copyright (c) 2015 Bluewraith. All rights reserved.
//

#import "CJMAlbumManager.h"
#import "CJMFileSerializer.h"
#import "CJMServices.h"
#import "CJMImage.h"

#define CJMAlbumFileName @"Unroll.plist"

static CJMAlbumManager *__sharedInstance;

@interface CJMAlbumManager ()

@property (nonatomic) NSMutableOrderedSet *allAlbumsEdit;
@property (nonatomic) CJMFileSerializer *fileSerializer;

@end

@implementation CJMAlbumManager

+ (instancetype)sharedInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        __sharedInstance = [CJMAlbumManager new];
    });
    return __sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.fileSerializer = [CJMFileSerializer new];
        [self registerDefaults];
        [self handleFirstTime];
    }
    return self;
}

- (void)handleFirstTime
{
    BOOL firstTime = [[NSUserDefaults standardUserDefaults] boolForKey:@"FirstTime"];
    
    if (firstTime) {
        CJMPhotoAlbum *album = [[CJMPhotoAlbum alloc] initWithName:@"My Photo Notes" andNote:@"Press Edit to customize the name and note sections."];
        
        [self.allAlbumsEdit addObject:album];
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"FirstTime"];
    }
}

- (void)registerDefaults
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"FirstTime" : @YES }];
}

#pragma mark - Content

- (NSArray *)allAlbums
{
    return [self.allAlbumsEdit array];
}


- (NSMutableOrderedSet *)allAlbumsEdit
{
    if(!self.allAlbumsEdit)
    {
        //lazy load from disk
        NSOrderedSet *set = [self.fileSerializer readObjectFromRelativePath:CJMAlbumFileName];
        self.allAlbumsEdit = [NSMutableOrderedSet new];
        
        if (set) {
            [self.allAlbumsEdit addObjectsFromArray:[set array]];
        }
    }
    return self.allAlbumsEdit;
}

#pragma mark - Content management

- (void)addAlbum:(CJMPhotoAlbum *)album
{
    [self.allAlbumsEdit addObject:album];
}

- (void)removeAlbumAtIndex:(NSUInteger)index
{
    CJMPhotoAlbum *doomedAlbum = [self.allAlbumsEdit objectAtIndex:index];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (CJMImage *cjmImage in doomedAlbum.albumPhotos) {
        [[CJMServices sharedInstance] deleteImage:cjmImage];
        }
    });
    
    [self.allAlbumsEdit removeObjectAtIndex:index];
}

- (void)replaceAlbumAtIndex:(NSInteger)toIndex withAlbumFromIndex:(NSInteger)fromIndex
{
    CJMPhotoAlbum *movingAlbum = [self.allAlbumsEdit objectAtIndex:fromIndex];
    [self.allAlbumsEdit removeObjectAtIndex:fromIndex];
    [self.allAlbumsEdit insertObject:movingAlbum atIndex:toIndex];
}

- (BOOL)containsAlbumNamed:(NSString *)name
{
    __block BOOL exists = NO;
    
    [self.allAlbumsEdit enumerateObjectsUsingBlock:^(CJMPhotoAlbum *obj, NSUInteger idx, BOOL *stop) {
        *stop = [[obj albumTitle] isEqualToString:name];
        exists = *stop;
    }];
    
    return exists;
}

- (CJMPhotoAlbum *)scanForAlbumWithName:(NSString *)name
{
    CJMPhotoAlbum *foundAlbum;
    
    for (CJMPhotoAlbum *album in self.allAlbumsEdit) {
        if ([album.albumTitle isEqualToString:name]) {
            foundAlbum = album;
            break;
        }
    }
    return foundAlbum;
}

#pragma mark - Requests to album manager

- (void)albumWithName:(NSString *)name createPreviewFromCJMImage:(CJMImage *)image
{
    CJMPhotoAlbum *album = [self scanForAlbumWithName:name];
    [image setIsAlbumPreview:YES];
    
    album.albumPreviewImage = image;
}

- (CJMImage *)albumWithName:(NSString *)name returnImageAtIndex:(NSInteger)index
{
    
    CJMPhotoAlbum *album = [self scanForAlbumWithName:name];
    
    if (album.albumPhotos.count < index + 1) {
        return nil;
    } else {
        return album.albumPhotos[index];
    }
}

- (void)albumWithName:(NSString *)albumName removeImageWithUUID:(NSString *)fileName
{
    CJMPhotoAlbum *shrinkingAlbum = [self scanForAlbumWithName:albumName];
    
    for (CJMImage *cjmImage in shrinkingAlbum.albumPhotos) {
        if ([cjmImage.fileName isEqualToString:fileName]) {
            [shrinkingAlbum removeCJMImage:cjmImage];
            break;
        }
    }
}

#pragma mark - Album saving

- (BOOL)save
{
    return [self.fileSerializer writeObject:self.allAlbumsEdit toRelativePath:CJMAlbumFileName];
}

@end
