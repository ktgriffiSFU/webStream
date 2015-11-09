//
//  SirenViewController.m
//  webStream
//
//  Created by Kyle Griffith on 2015-10-27.
//  Copyright (c) 2015 Kyle Griffith. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SirenViewController.h"
@interface SirenViewController()

@end

@implementation SirenViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIAlertView *myAlert = [[UIAlertView alloc] initWithTitle:@"Alert" message:@"Message" delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil, nil];
    [myAlert show];
   
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
@end
