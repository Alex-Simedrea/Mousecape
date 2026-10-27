//
//  backup.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "backup.h"
#import "apply.h"

NSString *backupStringForIdentifier(NSString *identifier) {
    return [NSString stringWithFormat:@"com.alexzielenski.mousecape.%@", identifier];
}

void backupCursorForIdentifier(NSString *ident) {
    bool registered = false;
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)ident.UTF8String, &registered);
    
//     dont try to backup a nonexistant cursor
    if (!registered)
        return;
    
    NSString *backupIdent = backupStringForIdentifier(ident);
    MCIsCursorRegistered(CGSMainConnectionID(), (char *)backupIdent.UTF8String, &registered);
    
//     don't re-back it up
    if (registered)
        return;
    
    NSDictionary *cape = capeWithIdentifier(ident);
    (void)applyCapeForIdentifier(cape, backupIdent, YES);
    
}

void backupAllCursors() {
    // Check each name separately so newly supported aliases also get backed up
    // when a previous Mousecape build already backed up the legacy arrow.
    // Backup main cursors first
    NSUInteger i = 0;
    NSString *key = nil;
    while ((key = defaultCursors[i]) != nil) {
        backupCursorForIdentifier(key);
        i++;
    }
    // no need to backup core cursors
    
}
