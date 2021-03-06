//
//  CJMGalleryViewController.m
//  Unroll
//
//  Created by Curt on 4/13/15.
//  Copyright (c) 2015 Bluewraith. All rights reserved.
//

#import "CJMGalleryViewController.h"
#import "CJMFIGalleryViewController.h"
#import "CJMFullImageViewController.h"
#import "CJMAListPickerViewController.h"
#import "CJMServices.h"
#import "CJMPhotoAlbum.h"
#import "CJMAlbumManager.h"
#import "CJMPhotoCell.h"
#import "CJMImage.h"
#import "CJMHudView.h"
#import "CJMFileSerializer.h"
#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>

#define CellSize [(UICollectionViewFlowLayout *)self.collectionView.collectionViewLayout itemSize]

@import Photos;

@interface CJMGalleryViewController () <CJMAListPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UICollectionViewDataSource>

@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) CJMFIGalleryViewController *fullImageVC;
@property (nonatomic) BOOL editMode;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *editButton;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *deleteButton;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *exportButton;
@property (strong, nonatomic) IBOutlet UIBarButtonItem *cameraButton;
@property (nonatomic, strong) NSArray *selectedCells;
@property (nonatomic, strong) NSMutableArray *pickerPhotos;

@property (nonatomic, strong) UIImagePickerController *imagePicker;
@property (nonatomic, strong) UIButton *flashButton;
@property (nonatomic, strong) UIButton *doneButton;

@end

@implementation CJMGalleryViewController

static NSString * const reuseIdentifier = @"GalleryCell";

#pragma mark - View prep and display

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.toolbarHidden = NO;
    self.navigationItem.title = self.album.albumTitle;
    self.navigationItem.backBarButtonItem.title = @"Albums";
}

//Make sure nav bars and associated controls are visible whenever the gallery appears.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.editMode = NO;
    [self toggleEditControls];
    self.navigationController.navigationBar.alpha = 1;
    self.navigationController.toolbar.alpha = 1;
    [self confirmEditButtonEnabled];
    [self.collectionView reloadData];
    
    if ([self.album.albumTitle isEqualToString:@"Favorites"]) {
        [self.cameraButton setEnabled:NO];
        if ([[CJMAlbumManager sharedInstance].favPhotosAlbum.albumPhotos count] < 1) {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
}

//Add photo count footer to gallery.
-(UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    UICollectionReusableView *footer = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:@"Footer" forIndexPath:indexPath];
    
    UILabel *footerLabel = (UILabel *)[footer viewWithTag:100];
    if (self.album.albumPhotos.count > 1) {
        footerLabel.text = [NSString stringWithFormat:@"%lu Photos", (unsigned long)self.album.albumPhotos.count];
    } else if (self.album.albumPhotos.count == 1) {
        footerLabel.text = @"1 Photo";
    } else {
        footerLabel.text = nil;
    }
    
    return footer;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

//If any cells are selected when exiting the gallery, set their cellSelectCover property back to hidden.
- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if (self.collectionView.indexPathsForSelectedItems.count > 0) {
        for (NSIndexPath *indexPath in self.collectionView.indexPathsForSelectedItems) {
            CJMImage *selectedItem = [self.album.albumPhotos objectAtIndex:indexPath.item];
            selectedItem.selectCoverHidden = YES;
        }
    }
}

#pragma mark - collectionView data source

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self.album.albumPhotos count];
}

//Add thumbnail to image and, if it's currently selected for editing, reveal it's cellSelectCover.
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CJMPhotoCell *cell = (CJMPhotoCell *)[collectionView dequeueReusableCellWithReuseIdentifier:reuseIdentifier forIndexPath:indexPath];
    CJMImage *imageForCell = self.album.albumPhotos[indexPath.row];
    
    [cell updateWithImage:imageForCell];
    
    if (imageForCell.thumbnailNeedsRedraw) {
        CJMFileSerializer *fileSerializer = [[CJMFileSerializer alloc] init];
        __block UIImage *tempFullImage = [[UIImage alloc] init];
        [[CJMServices sharedInstance] fetchImage:imageForCell handler:^(UIImage *fetchedImage) {
            tempFullImage = fetchedImage;
        }];
        UIImage *thumbnail = [self getCenterMaxSquareImageByCroppingImage:tempFullImage andShrinkToSize:CellSize];
        imageForCell.thumbnailNeedsRedraw = NO;
        [fileSerializer writeImage:thumbnail toRelativePath:imageForCell.thumbnailFileName];
        [cell updateWithImage:imageForCell];
//        NSLog(@"a thumbnail was redrawn");
        [[CJMAlbumManager sharedInstance] save];
    }
    
    cell.cellSelectCover.hidden = imageForCell.selectCoverHidden;
    
    return cell;
}

#pragma mark - collectionView delegate

//If in editing mode, mark cell as selected and reveal cellCover and enable delete/transfer buttons.
//Otherwise, segue to full image.
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.editMode == NO) {
        
        CJMImage *selectedImage = [self.album.albumPhotos objectAtIndex:indexPath.item];
        selectedImage.selectCoverHidden = YES;
        [self shouldPerformSegueWithIdentifier:@"ViewPhoto" sender:nil];
        
    } else if (self.editMode == YES) {
        
        [self shouldPerformSegueWithIdentifier:@"ViewPhoto" sender:nil];
        CJMPhotoCell *selectedCell =(CJMPhotoCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
        CJMImage *selectedImage = (CJMImage *)[self.album.albumPhotos objectAtIndex:indexPath.row];
        selectedImage.selectCoverHidden = NO;
        selectedCell.cellSelectCover.hidden = selectedImage.selectCoverHidden;
        self.deleteButton.enabled = YES;
        self.exportButton.enabled = [self.album.albumTitle isEqualToString:@"Favorites"] ? NO : YES;
    }
}

//Hide cellSelectCover and, if this was the last selected cell, disable the delete/transfer buttons.
- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    CJMPhotoCell *deselectedCell = (CJMPhotoCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
    CJMImage *deselectedImage = (CJMImage *)[self.album.albumPhotos objectAtIndex:indexPath.row];
    deselectedImage.selectCoverHidden = YES;
    deselectedCell.cellSelectCover.hidden = deselectedImage.selectCoverHidden;
    
    if ([self.collectionView indexPathsForSelectedItems].count == 0) {
        self.deleteButton.enabled = NO;
        self.exportButton.enabled = NO;
    }
}

//For all currently selected cells, switch their selected status to NO and hide cellSelectCovers.
- (void)clearCellSelections
{
    for (NSIndexPath *indexPath in [self.collectionView indexPathsForSelectedItems])
    {
        [self.collectionView deselectItemAtIndexPath:indexPath animated:YES];
        CJMPhotoCell *cell = (CJMPhotoCell *)[self.collectionView cellForItemAtIndexPath:indexPath];
        CJMImage *imageForCell = (CJMImage *)[self.album.albumPhotos objectAtIndex:indexPath.row];
        imageForCell.selectCoverHidden = YES;
        cell.cellSelectCover.hidden = imageForCell.selectCoverHidden;
    }
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"ViewPhoto"]) {
        NSIndexPath *indexPath = [self.collectionView indexPathForCell:sender];
        CJMFIGalleryViewController *vc = (CJMFIGalleryViewController *)segue.destinationViewController;
        vc.albumName = self.album.albumTitle;
        vc.albumCount = self.album.albumPhotos.count;
        vc.initialIndex = indexPath.item;
    }
}

- (void)setAlbum:(CJMPhotoAlbum *)album {
    _album = album;
    self.navigationItem.title = album.albumTitle;
}

- (BOOL)shouldPerformSegueWithIdentifier:(NSString *)identifier sender:(id)sender {
    if (self.editMode == YES) {
        return NO;
    } else {
        return YES;
    }
}

#pragma mark - NavBar items

- (IBAction)toggleEditMode:(id)sender {
    if ([self.editButton.title isEqualToString:@"Select"]) {
        [self.editButton setTitle:@"Cancel"];
        self.editMode = YES;
        [self toggleEditControls];
        self.collectionView.allowsMultipleSelection = YES;
    } else if ([self.editButton.title isEqualToString:@"Cancel"]) {
        [self.editButton setTitle:@"Select"];
        self.editMode = NO;
        [self clearCellSelections];
        [self toggleEditControls];
        self.selectedCells = nil;
        self.collectionView.allowsMultipleSelection = NO;
    }
}

//Changing navBar buttons based on current edit status.
- (void)toggleEditControls {
    if (self.editMode == YES) {
        self.cameraButton.enabled = NO;
        self.deleteButton.title = @"Delete";
        self.deleteButton.enabled = NO;
        self.exportButton.title = @"Transfer";
        self.exportButton.enabled = NO;
    } else {
        if (![self.album.albumTitle isEqualToString:@"Favorites"])
            self.cameraButton.enabled = YES;
        
        self.deleteButton.title = nil;
        self.deleteButton.enabled = NO;
        self.exportButton.title = nil;
        self.exportButton.enabled = NO;
    }
}

- (void)confirmEditButtonEnabled {
    if (self.album.albumPhotos.count == 0) {
        self.editButton.enabled = NO;
        if (![self.album.albumTitle isEqualToString:@"Favorites"]){
            UIAlertController *noPhotosAlert = [UIAlertController alertControllerWithTitle:@"No photos added yet" message:@"Tap the camera below to add photos" preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cameraAction = [UIAlertAction actionWithTitle:@"Take Picture" style:UIAlertActionStyleDefault handler:^(UIAlertAction *actionCamera) {
                [self takePhoto];
            }];
            
            UIAlertAction *fetchAction = [UIAlertAction actionWithTitle:@"Choose From Library" style:UIAlertActionStyleDefault handler:^(UIAlertAction *actionFetch) {
                [self photosFromLibrary];
            }];
            
            UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil];
            
            [noPhotosAlert addAction:cameraAction];
            [noPhotosAlert addAction:fetchAction];
            [noPhotosAlert addAction:dismissAction];
            
            [self presentViewController:noPhotosAlert animated:YES completion:nil];
        }
    } else {
        self.editButton.enabled = YES;
    }
}

//Acquire photo library permission and provide paths to user camera and photo library for photo import.
- (IBAction)photoGrab:(id)sender {
    //__weak CJMGalleryViewController *weakSelf = self;
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    //Access camera
    UIAlertAction *cameraAction = [UIAlertAction actionWithTitle:@"Take Photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *actionForCamera) {
        [self takePhoto];
    }];
    
    //Access photo library
    UIAlertAction *libraryAction = [UIAlertAction actionWithTitle:@"Choose From Library"       style:UIAlertActionStyleDefault handler:^(UIAlertAction *actionForLibrary) {
            [self photosFromLibrary];
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel"
                                                     style:UIAlertActionStyleCancel
                                                   handler:^(UIAlertAction *actionCancel) {}];
    
    [alertController addAction:cameraAction];
    [alertController addAction:libraryAction];
    [alertController addAction:cancel];
    
    alertController.popoverPresentationController.barButtonItem = self.cameraButton;
    [alertController.popoverPresentationController setPermittedArrowDirections:UIPopoverArrowDirectionDown];
    alertController.popoverPresentationController.sourceView = self.view;
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)photosFromLibrary {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status){
        if (status != PHAuthorizationStatusAuthorized) {
            UIAlertController *adjustPrivacyController = [UIAlertController alertControllerWithTitle:@"Denied access to Photos" message:@"You will need to give Photo Notes permission to import from your Photo Library.\n\nPlease allow Photo Notes access to your Photo Library by going to Settings>Privacy>Photos." preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *dismiss = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}];
            
            [adjustPrivacyController addAction:dismiss];
            
            [self presentViewController:adjustPrivacyController animated:YES completion:nil];
        } else {
            [self presentPhotoGrabViewController];
        }
    }];
}


//Present users photo library
- (void)presentPhotoGrabViewController { //cjm album list photo grab
    NSString * storyboardName = @"Main";
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle: nil];
    UINavigationController *navigationVC = (UINavigationController *)[storyboard instantiateViewControllerWithIdentifier:@"NavPhotoGrabViewController"];
    CJMPhotoGrabViewController *vc = (CJMPhotoGrabViewController *)[navigationVC topViewController];
    vc.delegate = self;
    vc.userColor = self.userColor;
    vc.userColorTag = self.userColorTag;
    vc.singleSelection = NO;
    [self presentViewController:navigationVC animated:YES completion:nil];
}

//Mass delete options
- (IBAction)deleteSelcted:(id)sender {
    self.selectedCells = [NSArray arrayWithArray:[self.collectionView indexPathsForSelectedItems]];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Delete photos?" message:@"You cannot recover these photos after deleting." preferredStyle:UIAlertControllerStyleActionSheet];
    
// IMPROVING AND ADDING LATER : functionality for mass export and delete on images.
//TODO: Save selected photos to Photos app and then delete
    /*
    UIAlertAction *saveThenDeleteAction = [UIAlertAction actionWithTitle:@"Save to Photos app and then delete" style:UIAlertActionStyleDefault handler:^(UIAlertAction *actionToSaveThenDelete){
        
        CJMHudView *hudView = [CJMHudView hudInView:self.navigationController.view
                                           withType:@"Pending"
                                           animated:YES];
        
        hudView.text = @"Exporting";
        
        __block UIImage *fullImage = [[UIImage alloc] init];
        
            for (NSIndexPath *itemPath in _selectedCells) {
                CJMImage *doomedImage = [_album.albumPhotos objectAtIndex:itemPath.row];
                [[CJMServices sharedInstance] fetchImage:doomedImage handler:^(UIImage *fetchedImage) {
                    fullImage = fetchedImage;
                }];
                UIImageWriteToSavedPhotosAlbum(fullImage, nil, nil, nil);
                fullImage = nil;
                
                [[CJMServices sharedInstance] deleteImage:doomedImage];
            }
            NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
            for (NSIndexPath *itemPath in _selectedCells) {
                [indexSet addIndex:itemPath.row];
            }
        [self.album removeCJMImagesAtIndexes:indexSet];
        
        [[CJMAlbumManager sharedInstance] save];
        
        [self.collectionView deleteItemsAtIndexPaths:_selectedCells];
        
        [self toggleEditMode:self];
        NSLog(@"photoAlbum count = %ld", (unsigned long)self.album.albumPhotos.count);
        
        [self confirmEditButtonEnabled];
        
        [self.collectionView performSelector:@selector(reloadData) withObject:nil afterDelay:0.4];
    }];
 */
    
    //Delete photos without saving to Photos app
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"Delete Photos Permanently" style:UIAlertActionStyleDefault handler:^(UIAlertAction *actionToDeletePermanently) {
        NSMutableArray *doomedArray = [NSMutableArray new];
        for (NSIndexPath *itemPath in self.selectedCells) {
            CJMImage *doomedImage = [self.album.albumPhotos objectAtIndex:itemPath.row];
            [doomedArray addObject:doomedImage];
        }
        [[CJMAlbumManager sharedInstance] albumWithName:self.album.albumTitle
                                               deleteImages:doomedArray];
        [[CJMAlbumManager sharedInstance] checkFavoriteCount];
        [[CJMAlbumManager sharedInstance] save];
        if (self.album.albumPhotos.count < 1) {
            [self.navigationController popViewControllerAnimated:YES];
        }
        [self.collectionView deleteItemsAtIndexPaths:self.selectedCells];
        [self toggleEditMode:self];
        [self confirmEditButtonEnabled];
        [self.collectionView performSelector:@selector(reloadData) withObject:nil afterDelay:0.4];
    }];

    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *cancelAction) {} ];

//    [alertController addAction:saveThenDeleteAction];
    [alertController addAction:deleteAction];
    [alertController addAction:cancel];
    
    alertController.popoverPresentationController.barButtonItem = self.deleteButton;
    alertController.popoverPresentationController.sourceView = self.view;
    [alertController.popoverPresentationController setPermittedArrowDirections:UIPopoverArrowDirectionDown];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

//Mass transfer options
- (IBAction)exportSelected:(id)sender
{
    self.selectedCells = [NSArray arrayWithArray:[self.collectionView indexPathsForSelectedItems]];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Transfer:" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
// IMPROVING AND ADDING LATER : functionality for mass copy of selected photos
//TODO: Copy selected photos to Camera Roll in the Photos app.
    /*
    UIAlertAction *photosAppExport = [UIAlertAction actionWithTitle:@"Copies of photos to Photos App" style:UIAlertActionStyleDefault handler:^(UIAlertAction *sendToPhotosApp) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            __block UIImage *fullImage = [[UIImage alloc] init];

            for (NSIndexPath *itemPath in _selectedCells) {
                CJMImage *copiedImage = [_album.albumPhotos objectAtIndex:itemPath.row];
                [[CJMServices sharedInstance] fetchImage:copiedImage handler:^(UIImage *fetchedImage) {
                    fullImage = fetchedImage;
                }];
                UIImageWriteToSavedPhotosAlbum(fullImage, nil, nil, nil);

            }
        });
        
        CJMHudView *hudView = [CJMHudView hudInView:self.navigationController.view
                                           withType:@"Success"
                                           animated:YES];
        
        hudView.text = @"Done!";
        
        [hudView performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:1.5f];
        self.navigationController.view.userInteractionEnabled = YES;
        
        [self toggleEditMode:self];
    }];
*/
    
    //Copy the selected photos to another album within Photo Notes.
    UIAlertAction *alternateAlbumExport = [UIAlertAction actionWithTitle:@"Photos And Notes To Alternate Album" style:UIAlertActionStyleDefault handler:^(UIAlertAction *sendToAlternateAlbum) {
        NSString *storyboardName = @"Main";
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:storyboardName bundle: nil];
        UINavigationController *vc = (UINavigationController *)[storyboard instantiateViewControllerWithIdentifier:@"AListPickerViewController"];
        CJMAListPickerViewController *aListPickerVC = (CJMAListPickerViewController *)[vc topViewController];
        aListPickerVC.delegate = self;
        aListPickerVC.title = @"Select Destination";
        aListPickerVC.currentAlbumName = self.album.albumTitle;
        aListPickerVC.userColor = self.userColor;
        aListPickerVC.userColorTag = self.userColorTag;
        [self presentViewController:vc animated:YES completion:nil]; //cjm 12/30
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *cancelAction) {} ];
    
//    [alertController addAction:photosAppExport];
    [alertController addAction:alternateAlbumExport];
    [alertController addAction:cancel];
    
    alertController.popoverPresentationController.barButtonItem = self.exportButton;
    [alertController.popoverPresentationController setPermittedArrowDirections:UIPopoverArrowDirectionDown];
    alertController.popoverPresentationController.sourceView = self.view;
    
    [self presentViewController:alertController animated:YES completion:nil];
    
}

#pragma mark - image picker delegate and controls

- (void)takePhoto { //cjm 01/12
    NSString *mediaType = AVMediaTypeVideo;
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:mediaType];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera] == NO) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Camera Available" message:@"There's no device camera available for Photo Notes to use." preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *actionDismiss = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:^(UIAlertAction *dismissAction) {}];
        [alert addAction:actionDismiss];
        [self presentViewController:alert animated:YES completion:nil];
    } else if (authStatus != AVAuthorizationStatusAuthorized) {
        //cjmn 05/30 TEST BELOW CODE.  Make sure this works for both iPhone and iPad, and test for issues with self in the block.
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) { //code copy/pasted from final else statement below.  Perhaps move into its own method.
                self.imagePicker = [[UIImagePickerController alloc] init];
                self.imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
                self.imagePicker.showsCameraControls = NO;
                self.imagePicker.allowsEditing = NO;
                self.imagePicker.delegate = self;
                self.imagePicker.cameraFlashMode = UIImagePickerControllerCameraFlashModeOff;
                self.imagePicker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
                
                UIView *overlay;
                if (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
                    overlay = [self customLandscapeCameraOverlay];
                } else {
                    overlay = [self customPortraitCameraOverlay];
                }
                [self.imagePicker setCameraOverlayView:overlay];
                self.imagePicker.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
                
                [self presentViewController:self.imagePicker animated:YES completion:nil];
            } else {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Camera Access Denied" message:@"Please allow Photo Notes permission to use the camera in Settings>Privacy>Camera." preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction *actionDismiss = [UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:^(UIAlertAction *dismissAction) {}];
                [alert addAction:actionDismiss];
                [self presentViewController:alert animated:YES completion:nil];
            }
        }];
    } else {
        self.imagePicker = [[UIImagePickerController alloc] init];
        self.imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
        self.imagePicker.showsCameraControls = NO;
        self.imagePicker.allowsEditing = NO;
        self.imagePicker.delegate = self;
        self.imagePicker.cameraFlashMode = UIImagePickerControllerCameraFlashModeOff;
        self.imagePicker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
        
        UIView *overlay;
        if (self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact) {
            overlay = [self customLandscapeCameraOverlay];
        } else {
            overlay = [self customPortraitCameraOverlay];
        }
        [self.imagePicker setCameraOverlayView:overlay];
        self.imagePicker.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
        
        [self presentViewController:self.imagePicker animated:YES completion:nil];
    }
}

- (UIView *)customLandscapeCameraOverlay {
    CGRect frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width);
    
    UIView *mainOverlay = [[UIView alloc] initWithFrame:frame];
    [mainOverlay setBackgroundColor:[UIColor clearColor]];
    
    UIView *buttonBar = [[UIView alloc] init];
    [buttonBar setBackgroundColor:[UIColor clearColor]];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [mainOverlay addSubview:buttonBar];
    NSLayoutConstraint *horizontalConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:mainOverlay attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0.0];
    NSLayoutConstraint *bottomConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:mainOverlay attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0];
    NSLayoutConstraint *widthConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:mainOverlay attribute:NSLayoutAttributeWidth multiplier:1.0 constant:-16.0];
    NSLayoutConstraint *heightConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1.0 constant:(frame.size.height / 4.0)];
    [mainOverlay addConstraints:@[horizontalConst, bottomConst, widthConst, heightConst]];
    
    UIButton *cameraButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [cameraButton setImage:[UIImage imageNamed:@"CameraShutter"] forState:UIControlStateNormal];
    //    [cameraButton setImage:[UIImage imageNamed:@"PressedCameraShutter"] forState:UIControlStateHighlighted]; not selecting new image
    [cameraButton setTintColor:[UIColor whiteColor]];
    [cameraButton addTarget:self action:@selector(shutterPressed) forControlEvents:UIControlEventTouchUpInside];
    cameraButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:cameraButton];
    NSLayoutConstraint *buttonHorizon = [NSLayoutConstraint constraintWithItem:cameraButton attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0.0];
    NSLayoutConstraint *buttonVert = [NSLayoutConstraint constraintWithItem:cameraButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0.0];
    [buttonBar addConstraints:@[buttonHorizon, buttonVert]];
    
    UIImage *currentFlash;
    if (self.imagePicker.cameraFlashMode == UIImagePickerControllerCameraFlashModeOn) {
        currentFlash = [UIImage imageNamed:@"FlashOn"];
    } else {
        currentFlash = [UIImage imageNamed:@"FlashOff"];
    }
    self.flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.flashButton addTarget:self action:@selector(updateFlashMode) forControlEvents:UIControlEventTouchUpInside];
    [self.flashButton setImage:currentFlash forState:UIControlStateNormal];
    [self.flashButton setTintColor:[UIColor whiteColor]];
    self.flashButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:self.flashButton];
    NSLayoutConstraint *flashTop = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeTop multiplier:1.0 constant:16.0];
    NSLayoutConstraint *flashLead = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeLeading multiplier:1.0 constant:8.0];
    NSLayoutConstraint *flashHeight = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1.0 constant:44.0];
    NSLayoutConstraint *flashWidth = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeWidth multiplier:1.0 constant:44.0];
    [buttonBar addConstraints:@[flashTop, flashLead, flashHeight, flashWidth]];
    
    UIButton *camFlipButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [camFlipButton setImage:[UIImage imageNamed:@"CamFlip"] forState:UIControlStateNormal];
    [camFlipButton addTarget:self action:@selector(reverseCamera) forControlEvents:UIControlEventTouchUpInside];
    [camFlipButton setTintColor:[UIColor whiteColor]];
    camFlipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:camFlipButton];
    NSLayoutConstraint *flipTop = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.flashButton attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0.0];
    NSLayoutConstraint *flipTrail = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:-8.0];
    NSLayoutConstraint *flipWidth = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeWidth multiplier:1.0 constant:44.0];
    NSLayoutConstraint *flipHeight = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1.0 constant:44.0];
    [buttonBar addConstraints:@[flipTop, flipTrail, flipWidth, flipHeight]];
    
    self.doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.doneButton setTitle:@"Done" forState:UIControlStateNormal];
    [self.doneButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    [self.doneButton addTarget:self action:@selector(photoCaptureFinished) forControlEvents:UIControlEventTouchUpInside];
    self.doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:self.doneButton];
    [self.doneButton setEnabled:NO];
    NSLayoutConstraint *doneBottom = [NSLayoutConstraint constraintWithItem:self.doneButton attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-8.0];
    NSLayoutConstraint *doneTrail = [NSLayoutConstraint constraintWithItem:self.doneButton attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:-8.0];
    [buttonBar addConstraints:@[doneBottom, doneTrail]];
    
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self action:@selector(cancelCamera) forControlEvents:UIControlEventTouchUpInside];
    [buttonBar addSubview:cancelButton];
    NSLayoutConstraint *cancelBottom = [NSLayoutConstraint constraintWithItem:cancelButton attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-8.0];
    NSLayoutConstraint *cancelLead = [NSLayoutConstraint constraintWithItem:cancelButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeLeading multiplier:1.0 constant:8.0];
    [buttonBar addConstraints:@[cancelBottom, cancelLead]];
    
    return mainOverlay;
}

- (UIView *)customPortraitCameraOverlay { //cjm 01/12
    UIView *mainOverlay = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    
    UIView *buttonBar = [[UIView alloc] init];
    [buttonBar setBackgroundColor:[UIColor clearColor]];
    buttonBar.translatesAutoresizingMaskIntoConstraints = NO;
    [mainOverlay addSubview:buttonBar];
    NSLayoutConstraint *horizontalConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:mainOverlay attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0.0];
    NSLayoutConstraint *bottomConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:mainOverlay attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0];
    NSLayoutConstraint *widthConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:mainOverlay attribute:NSLayoutAttributeWidth multiplier:1.0 constant:-16.0];
    NSLayoutConstraint *heightConst = [NSLayoutConstraint constraintWithItem:buttonBar attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1.0 constant:([UIScreen mainScreen].bounds.size.height / 4.0)];
    [mainOverlay addConstraints:@[horizontalConst, bottomConst, widthConst, heightConst]];
    
    UIButton *cameraButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [cameraButton setImage:[UIImage imageNamed:@"CameraShutter"] forState:UIControlStateNormal];
    //    [cameraButton setImage:[UIImage imageNamed:@"PressedCameraShutter"] forState:UIControlStateHighlighted]; not selecting new image
    [cameraButton setTintColor:[UIColor whiteColor]];
    [cameraButton addTarget:self action:@selector(shutterPressed) forControlEvents:UIControlEventTouchUpInside];
    cameraButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:cameraButton];
    NSLayoutConstraint *buttonHorizon = [NSLayoutConstraint constraintWithItem:cameraButton attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeCenterX multiplier:1.0 constant:0.0];
    NSLayoutConstraint *buttonVert = [NSLayoutConstraint constraintWithItem:cameraButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0.0];
    [buttonBar addConstraints:@[buttonHorizon, buttonVert]];
    
    UIImage *currentFlash;
    if (self.imagePicker.cameraFlashMode == UIImagePickerControllerCameraFlashModeOn) {
        currentFlash = [UIImage imageNamed:@"FlashOn"];
    } else {
        currentFlash = [UIImage imageNamed:@"FlashOff"];
    }
    self.flashButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.flashButton addTarget:self action:@selector(updateFlashMode) forControlEvents:UIControlEventTouchUpInside];
    [self.flashButton setImage:currentFlash forState:UIControlStateNormal];
    [self.flashButton setTintColor:[UIColor whiteColor]];
    self.flashButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:self.flashButton];
    NSLayoutConstraint *flashTop = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeTop multiplier:1.0 constant:16.0];
    NSLayoutConstraint *flashLead = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeLeading multiplier:1.0 constant:8.0];
    NSLayoutConstraint *flashHeight = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1.0 constant:44.0];
    NSLayoutConstraint *flashWidth = [NSLayoutConstraint constraintWithItem:self.flashButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeWidth multiplier:1.0 constant:44.0];
    [buttonBar addConstraints:@[flashTop, flashLead, flashHeight, flashWidth]];
    
    UIButton *camFlipButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [camFlipButton setImage:[UIImage imageNamed:@"CamFlip"] forState:UIControlStateNormal];
    [camFlipButton addTarget:self action:@selector(reverseCamera) forControlEvents:UIControlEventTouchUpInside];
    [camFlipButton setTintColor:[UIColor whiteColor]];
    camFlipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:camFlipButton];
    NSLayoutConstraint *flipTop = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.flashButton attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0.0];
    NSLayoutConstraint *flipTrail = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:-8.0];
    NSLayoutConstraint *flipWidth = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeWidth multiplier:1.0 constant:44.0];
    NSLayoutConstraint *flipHeight = [NSLayoutConstraint constraintWithItem:camFlipButton attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeHeight multiplier:1.0 constant:44.0];
    [buttonBar addConstraints:@[flipTop, flipTrail, flipWidth, flipHeight]];
    
    self.doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.doneButton setTitle:@"Done" forState:UIControlStateNormal];
    [self.doneButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
    [self.doneButton addTarget:self action:@selector(photoCaptureFinished) forControlEvents:UIControlEventTouchUpInside];
    self.doneButton.translatesAutoresizingMaskIntoConstraints = NO;
    [buttonBar addSubview:self.doneButton];
    [self.doneButton setEnabled:NO];
    NSLayoutConstraint *doneBottom = [NSLayoutConstraint constraintWithItem:self.doneButton attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-8.0];
    NSLayoutConstraint *doneTrail = [NSLayoutConstraint constraintWithItem:self.doneButton attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:-8.0];
    [buttonBar addConstraints:@[doneBottom, doneTrail]];
    
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self action:@selector(cancelCamera) forControlEvents:UIControlEventTouchUpInside];
    [buttonBar addSubview:cancelButton];
    NSLayoutConstraint *cancelBottom = [NSLayoutConstraint constraintWithItem:cancelButton attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeBottom multiplier:1.0 constant:-8.0];
    NSLayoutConstraint *cancelLead = [NSLayoutConstraint constraintWithItem:cancelButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:buttonBar attribute:NSLayoutAttributeLeading multiplier:1.0 constant:8.0];
    [buttonBar addConstraints:@[cancelBottom, cancelLead]];
    
    return mainOverlay;
}

//Converting photo captured by in-app camera to CJMImage.
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info //cjm 01/12
{
    [self.doneButton setEnabled:YES];
    [self.doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    UIImage *newPhoto = [info objectForKey:UIImagePickerControllerOriginalImage];
    NSData *newPhotoData = UIImageJPEGRepresentation(newPhoto, 1.0);
//    CJMImage *newImage = [[CJMImage alloc] init];
    UIImage *thumbnail = [self getCenterMaxSquareImageByCroppingImage:newPhoto andShrinkToSize:CellSize];
    
    NSDictionary *dic = [NSDictionary dictionaryWithObjects:@[newPhotoData, thumbnail] forKeys:@[@"newImage", @"newThumbnail"]];
    
    if (!self.pickerPhotos) {
        self.pickerPhotos = [[NSMutableArray alloc] init];
    }
    [self.pickerPhotos addObject:dic];
}

- (void)photoCaptureFinished { //cjm 01/12
    CJMFileSerializer *fileSerializer = [[CJMFileSerializer alloc] init];
    
    for (NSDictionary *dic in self.pickerPhotos) {
        NSData *newPhotoData = [dic valueForKey:@"newImage"];
        UIImage *thumbnail = [dic valueForKey:@"newThumbnail"];
        CJMImage *newImage = [[CJMImage alloc] init];
        
        [fileSerializer writeObject:newPhotoData toRelativePath:newImage.fileName];
        [fileSerializer writeImage:thumbnail toRelativePath:newImage.thumbnailFileName];
        
        
        [newImage setInitialValuesForCJMImage:newImage inAlbum:self.album.albumTitle];
        newImage.photoCreationDate = [NSDate date];
        newImage.thumbnailNeedsRedraw = NO;
        [self.album addCJMImage:newImage];
    }
    self.flashButton = nil;
    self.doneButton = nil;
    self.imagePicker = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
    
    [[CJMAlbumManager sharedInstance] save];
}

- (void)shutterPressed { //cjm 01/12
    NSLog(@"TAKE THE PICTURE");
    [self.imagePicker takePicture];
}

- (void)updateFlashMode {
    if (self.imagePicker.cameraFlashMode == UIImagePickerControllerCameraFlashModeOff) {
        [self.imagePicker setCameraFlashMode:UIImagePickerControllerCameraFlashModeOn];
        [self.flashButton setImage:[UIImage imageNamed:@"FlashOn"] forState:UIControlStateNormal];
    } else {
        [self.imagePicker setCameraFlashMode:UIImagePickerControllerCameraFlashModeOff];
        [self.flashButton setImage:[UIImage imageNamed:@"FlashOff"] forState:UIControlStateNormal];
    }
}

- (void)reverseCamera {
    if (self.imagePicker.cameraDevice == UIImagePickerControllerCameraDeviceRear) {
        self.imagePicker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
    } else {
        self.imagePicker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
    }
}

- (void)cancelCamera { //cjm 01/12
    self.pickerPhotos = nil;
    self.imagePicker = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - CJMImage prep code

//Holy Grail of of thumbnail creation.  Well... Holy Dixie Cup may be more appropriate.
//Takes full UIImage and compresses to thumbnail with size ~100KB.
- (UIImage *)getCenterMaxSquareImageByCroppingImage:(UIImage *)image andShrinkToSize:(CGSize)newSize
{
    //Get crop bounds
    CGSize centerSquareSize;
    double originalImageWidth = CGImageGetWidth(image.CGImage);
    double originalImageHeight = CGImageGetHeight(image.CGImage);
    if (originalImageHeight <= originalImageWidth) {
        centerSquareSize.width = originalImageHeight;
        centerSquareSize.height = originalImageHeight;
    } else {
        centerSquareSize.width = originalImageWidth;
        centerSquareSize.height = originalImageWidth;
    }
    //Determine crop origin
    double x = (originalImageWidth - centerSquareSize.width) / 2.0;
    double y = (originalImageHeight - centerSquareSize.height) / 2.0;
    
    //Crop and create CGImageRef.  This is where an improvement likely lies.
    CGRect cropRect = CGRectMake(x, y, centerSquareSize.height, centerSquareSize.width);
    CGImageRef imageRef = CGImageCreateWithImageInRect([image CGImage], cropRect);
    UIImage *cropped = [UIImage imageWithCGImage:imageRef scale:0.0 orientation:image.imageOrientation];
    
    //Scale the image down to the smaller file size and return
    UIGraphicsBeginImageContextWithOptions(newSize, NO, 0.0);
    [cropped drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGImageRelease(imageRef);
    return newImage;
}

#pragma mark - CJMPhotoGrabber Delegate

- (void)photoGrabViewControllerDidCancel:(CJMPhotoGrabViewController *)controller
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

//iterate through array of selected photos, convert them to CJMImages, and add to the current album.
- (void)photoGrabViewController:(CJMPhotoGrabViewController *)controller didFinishSelectingPhotos:(NSArray *)photos {
    NSMutableArray *newImages = [[NSMutableArray alloc] init];
    //Pull the images, image creation dates, and image locations from each PHAsset in the received array.
    CJMFileSerializer *fileSerializer = [[CJMFileSerializer alloc] init];
    
    if (!self.imageManager) {
        self.imageManager = [[PHCachingImageManager alloc] init];
    }
    
    __block NSInteger counter = [photos count];
//    __weak CJMGalleryViewController *weakSelf = self;
    
    dispatch_group_t imageLoadGroup = dispatch_group_create();
    for (int i = 0; i < photos.count; i++)
    {
        __block CJMImage *assetImage = [[CJMImage alloc] init];
        PHAsset *asset = (PHAsset *)photos[i];
        
        PHImageRequestOptions *options = [PHImageRequestOptions new];
        options.networkAccessAllowed = YES;
        options.version = PHImageRequestOptionsVersionCurrent;
        
        dispatch_group_enter(imageLoadGroup);
        @autoreleasepool {
            [self.imageManager requestImageDataForAsset:asset
                                                options:options
                                          resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {
                                              
                                              counter--;
                                              if(![info[PHImageResultIsDegradedKey] boolValue])
                                              {
                                                  [fileSerializer writeObject:imageData toRelativePath:assetImage.fileName];
                                                  dispatch_group_leave(imageLoadGroup);
                                              }
                                              
                                          }];
        }
        
        dispatch_group_enter(imageLoadGroup);
        @autoreleasepool {
            [self.imageManager requestImageForAsset:asset
                                         targetSize:CellSize
                                        contentMode:PHImageContentModeAspectFill
                                            options:options
                                      resultHandler:^(UIImage *result, NSDictionary *info) {
                                              if(![info[PHImageResultIsDegradedKey] boolValue])
                                              {
                                                  [fileSerializer writeImage:result toRelativePath:assetImage.thumbnailFileName];
                                                  assetImage.thumbnailNeedsRedraw = NO;
                                                  
                                                  dispatch_group_leave(imageLoadGroup);
                                              }
                                                                                              }];
        }
        
        [assetImage setInitialValuesForCJMImage:assetImage inAlbum:self.album.albumTitle];
//        assetImage.photoLocation = [asset location];
        assetImage.photoCreationDate = [asset creationDate];
        
        [newImages addObject:assetImage];
    }

    [self.album addMultipleCJMImages:newImages];

    dispatch_group_notify(imageLoadGroup, dispatch_get_main_queue(), ^{
        self.navigationController.view.userInteractionEnabled = YES;
        [self.collectionView reloadData];
        [self dismissViewControllerAnimated:YES completion:nil];
        [[CJMAlbumManager sharedInstance] save];
        self.navigationController.view.userInteractionEnabled = YES;
        
//        NSLog(@"••••• FIN");
    });
}



#pragma mark - CJMAListPicker Delegate

//Dismiss list of albums to transfer photos to and deselect previously selected photos.
- (void)aListPickerViewControllerDidCancel:(CJMAListPickerViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
    [self toggleEditMode:self];
}

//take CJMImages in selected cells in current album and transfer them to the picked album.
- (void)aListPickerViewController:(CJMAListPickerViewController *)controller didFinishPickingAlbum:(CJMPhotoAlbum *)album {
    NSMutableArray *transferringImages = [NSMutableArray new];
    
    for (NSIndexPath *itemPath in self.selectedCells) {
        CJMImage *imageToTransfer = [self.album.albumPhotos objectAtIndex:itemPath.row];
        imageToTransfer.selectCoverHidden = YES;
        if (imageToTransfer.isAlbumPreview == YES) {
            [imageToTransfer setIsAlbumPreview:NO];
            self.album.albumPreviewImage = nil;
        }
        [transferringImages addObject:imageToTransfer];
    }
    
    [album addMultipleCJMImages:transferringImages];
    
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (NSIndexPath *itemPath in self.selectedCells) {
        [indexSet addIndex:itemPath.row];
    }
    [self.album removeCJMImagesAtIndexes:indexSet];
    
    if (self.album.albumPreviewImage == nil && self.album.albumPhotos.count > 0) {
        [[CJMAlbumManager sharedInstance] albumWithName:self.album.albumTitle
                              createPreviewFromCJMImage:(CJMImage *)[self.album.albumPhotos objectAtIndex:0]];
    }
    
    [[CJMAlbumManager sharedInstance] save];
    if (self.album.albumPhotos.count < 1) {
        [self.navigationController popViewControllerAnimated:YES];
    }
    [self.collectionView deleteItemsAtIndexPaths:self.selectedCells];
    [self toggleEditMode:self];
    [self.collectionView reloadData];
    [self dismissViewControllerAnimated:YES completion:nil];
    [self confirmEditButtonEnabled];
    
    //Presents and dismisses HUD confirming action complete.
    CJMHudView *hudView = [CJMHudView hudInView:self.navigationController.view
                                       withType:@"Success"
                                       animated:YES];
    hudView.text = @"Done!";
    [hudView performSelector:@selector(removeFromSuperview) withObject:nil afterDelay:1.5f];
    [self.collectionView performSelector:@selector(reloadData) withObject:nil afterDelay:0.2];
    self.navigationController.view.userInteractionEnabled = YES;
}

#pragma mark - collectionViewFlowLayout Delegate

//Establishes cell size based on device screen size.  4 cells across in portrait, 5 cells across in landscape.
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (UIInterfaceOrientationIsLandscape([[UIApplication sharedApplication] statusBarOrientation])) {
        CGFloat viewWidth = lroundf(collectionView.frame.size.width);
        int cellWidth = (viewWidth/5) - 2;
        return CGSizeMake(cellWidth, cellWidth);
    } else {
        CGFloat viewWidth = lroundf(collectionView.frame.size.width);
        int cellWidth = (viewWidth/4) - 2;
        return CGSizeMake(cellWidth, cellWidth);
    }
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout insetForSectionAtIndex:(NSInteger)section
{
    return UIEdgeInsetsMake(1, 1, 1, 1);
}

//resizes collectionView cells per sizeForItemAtIndexPath when user rotates device.
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self.collectionView.collectionViewLayout invalidateLayout];
}

@end
