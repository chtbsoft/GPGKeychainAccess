/*
 Copyright © Roman Zechmeister, 2016
 
 Diese Datei ist Teil von GPG Keychain.
 
 GPG Keychain ist freie Software. Sie können es unter den Bedingungen 
 der GNU General Public License, wie von der Free Software Foundation 
 veröffentlicht, weitergeben und/oder modifizieren, entweder gemäß 
 Version 3 der Lizenz oder (nach Ihrer Option) jeder späteren Version.
 
 Die Veröffentlichung von GPG Keychain erfolgt in der Hoffnung, daß es Ihnen 
 von Nutzen sein wird, aber ohne irgendeine Garantie, sogar ohne die implizite 
 Garantie der Marktreife oder der Verwendbarkeit für einen bestimmten Zweck. 
 Details finden Sie in der GNU General Public License.
 
 Sie sollten ein Exemplar der GNU General Public License zusammen mit diesem 
 Programm erhalten haben. Falls nicht, siehe <http://www.gnu.org/licenses/>.
*/

#import "KeychainController.h"
#import "ActionController.h"
#import "SheetController.h"


//KeychainController kümmert sich um das anzeigen und Filtern der Schlüssel-Liste.

@implementation KeychainController
@synthesize filterStrings, userIDsSortDescriptors, subkeysSortDescriptors, keysSortDescriptors, showSecretKeysOnly;
NSLock *updateLock;


- (void)awakeFromNib {
	[keyTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	[keyTable setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];
}



- (NSSet *)secretKeys {
	NSSet *secretKeys = [[GPGKeyManager sharedInstance].secretKeys copy];
	return secretKeys;
}

- (GPGKey *)defaultKey {
	if ([self.secretKeys count] == 0) {
		return nil;
	}
	NSString *defaultKey = [[GPGOptions sharedOptions] valueForKey:@"default-key"];
	
	if (defaultKey.length == 0) {
		return [self.secretKeys anyObject];
	}
	
	for (GPGKey *key in self.secretKeys) {
		if ([key.textForFilter rangeOfString:defaultKey].length > 0) {
			return key;
		}
	}
	return nil;
}


- (NSIndexSet *)selectionIndexes {
	return _selectionIndexes;
}
- (void)setSelectionIndexes:(NSIndexSet *)indexes {
	if (_selectionIndexes != indexes) {
		_selectionIndexes = indexes;
		[[ActionController sharedInstance] closePhotoPopover];
		
		[self fetchDetailsForSelectedKey];
	}
}



- (void)selectKeys:(NSSet *)keys {
	NSArray *list = [keysController arrangedObjects];
	NSMutableIndexSet *indexes = [NSMutableIndexSet new];
	
	[list enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		NSString *fingerprint = [obj description];
		if ([keys containsObject:fingerprint]) {
			[indexes addIndex:idx];
		}
	}];
	

	self.selectionIndexes = indexes.copy;
}

- (BOOL)fetchDetailsForSelectedKey { // Returns YES if the details will be fetched.
	if (_selectionIndexes.count == 1) {
		NSUInteger index = [_selectionIndexes firstIndex];
		if (index != NSNotFound && (NSInteger)index != -1) {
			GPGKey *key = [[keysController.arrangedObjects objectAtIndex:index] primaryKey];
			key = [self.allKeys member:key];
			if (key && !key.primaryUserID.signatures) {
				[[GPGKeyManager sharedInstance] loadSignaturesAndAttributesForKeys:[NSSet setWithObject:key] completionHandler:nil];
				return YES;
			}
		}
	}
	return NO;
}

// NSTableView delegate.
- (NSString *)tableView:(NSTableView *)tableView typeSelectStringForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	if ([tableColumn.identifier isEqualToString:@"name"]) {
		return [keysController.arrangedObjects[row] name];
	}
	return nil;
}



//Für Drag & Drop.


- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard {
	if (rowIndexes.count == 0) {
		return NO;
	}
	
	[pboard declareTypes:@[NSFilesPromisePboardType] owner:tableView];
	
	[pboard setPropertyList:@[@"asc"]
					forType:NSFilesPromisePboardType];

	return YES;
}


- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes {
	
	// Set the dragging image to the *.asc file icon.
	[session enumerateDraggingItemsWithOptions:NSDraggingItemEnumerationConcurrent
									   forView:nil
									   classes:[NSArray arrayWithObject:[NSPasteboardItem class]]
								 searchOptions:nil
									usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop) {
										NSRect frame;
										frame.size.width = 56;
										frame.size.height = 56;
										frame.origin.x = session.draggingLocation.x - 28;
										frame.origin.y = session.draggingLocation.y - 28;
										
										[draggingItem setDraggingFrame:frame contents:[NSImage imageNamed:@"asc"]];
									}];
	
}


- (NSArray *)tableView:(NSTableView *)tableView namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination forDraggedRowsWithIndexes:(NSIndexSet *)indexSet {
	NSString *fileName;
	
	NSArray *draggedKeys = [keysController.arrangedObjects objectsAtIndexes:indexSet];
	if (draggedKeys.count == 1) {
		fileName = [draggedKeys[0] shortKeyID];
	} else {
		NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
		dateFormatter.dateFormat = @"Y-MM-dd";
		NSString *date = [dateFormatter stringFromDate:[NSDate date]];
		fileName = [NSString stringWithFormat:localized(@"ExportKeysFilename"), date, draggedKeys.count];
	}
	fileName = [fileName stringByAppendingString:@".asc"];
	
	GPGController *gc = [[ActionController sharedInstance] gpgc];
	BOOL oldAsync = gc.async;
	BOOL oldArmor = gc.useArmor;
	gc.async = NO;
	gc.useArmor = YES;
	NSData *exportedData = [gc exportKeys:draggedKeys allowSecret:NO fullExport:NO];
	gc.async = oldAsync;
	gc.useArmor = oldArmor;
	
	if ([exportedData length] > 0) {
		[[NSFileManager defaultManager] createFileAtPath:[dropDestination.path stringByAppendingPathComponent:fileName] contents:exportedData attributes:@{NSFileExtensionHidden: @YES}];
		
		return @[fileName];
	} else {
		return nil;
	}
}




- (void)addKeyUpdateCallback:(keyUpdateCallback)callback {
	if (keyUpdateCallbacks == nil) {
		keyUpdateCallbacks = [NSMutableArray array];
	}
	[keyUpdateCallbacks addObject:callback];
}

- (void)removeKeyUpdateCallback:(keyUpdateCallback)callback {
	[keyUpdateCallbacks removeObject:callback];
}



- (IBAction)updateFilteredKeyList:(id)sender {
	if ([sender isKindOfClass:[NSTextField class]]) {
		self.filterStrings = [[sender stringValue] componentsSeparatedByString:@" "];
	}
}

- (void)keysDidChange:(NSNotification *)notification {
	if (![self fetchDetailsForSelectedKey]) {
		[self willChangeValueForKey:@"allKeys"];
		[self didChangeValueForKey:@"allKeys"];
		
		NSArray *keys = notification.userInfo[@"affectedKeys"];
		NSArray *callbacksToIterate = [keyUpdateCallbacks copy];
		for (keyUpdateCallback callback in callbacksToIterate) {
			if (callback(keys)) {
				[keyUpdateCallbacks removeObject:callback];
			}
		}
	}
}

- (NSSet *)allKeys {
	NSSet *allKeys = [[GPGKeyManager sharedInstance].allKeys copy];
	return allKeys;
}

- (NSArray *)filteredKeyList {
	NSSet *filteredKeys = [self.allKeys objectsPassingTest:^BOOL(GPGKey *key, BOOL *stop) {
		if (showSecretKeysOnly && !key.secret) {
			return NO;
		}
		if (filterStrings.count > 0) {
			for (NSString *searchString in filterStrings) {
				if ([searchString length] > 0) {
					if ([[key textForFilter] rangeOfString:searchString options:NSCaseInsensitiveSearch].length == 0) {
						return NO;
					}
				}
			}
		}
		return YES;
	}];
	
	
	filteredKeyList = [filteredKeys allObjects];
	
	[numberOfKeysLabel setStringValue:[NSString stringWithFormat:localized(@"%i of %i keys listed"), filteredKeyList.count, self.allKeys.count]];
	
	return filteredKeyList;
}

+ (NSSet*)keyPathsForValuesAffectingFilteredKeyList {
	return [NSSet setWithObjects:@"allKeys", @"filterStrings", @"showSecretKeysOnly", nil];
}


// Singleton: alloc, init etc.
+ (instancetype)sharedInstance {
	static id sharedInstance = nil;
    if (!sharedInstance) {
        sharedInstance = [[super allocWithZone:nil] init];
    }
    return sharedInstance;	
}
- (id)init {
	static BOOL initialized = NO;
	if (!initialized) {
		initialized = YES;
		
		NSLog(@"GPG Keychain version: %@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]);
		
		
		// Testen ob GPG vorhanden und funktionsfähig ist.
		NSException *error = nil;
		GPGErrorCode errorCode = [GPGController testGPGError:&error];
		GPGDebugLog(@"KeychainController init testGPG: %i", errorCode);
		
		switch (errorCode) {
			case GPGErrorNotFound:
				NSRunCriticalAlertPanel(localized(@"GPG_NOT_FOUND_TITLE"), localized(@"GPG_NOT_FOUND_MESSAGE"), nil, nil, nil);
				[NSApp terminate:nil];
				break;
			case GPGErrorConfigurationError: {
				NSString *details = @"";
				if ([error isKindOfClass:[GPGException class]]) {
					details = [(GPGException *)error gpgTask].errText;
				}
				NSRunCriticalAlertPanel(localized(@"GPG_CONFIG_ERROR_TITLE"), [NSString stringWithFormat:localized(@"GPG_CONFIG_ERROR_MESSAGE"), details], nil, nil, nil);
				[NSApp terminate:nil];
				break; }
			case GPGErrorGeneralError: {
				NSString *details = @"";
				if ([error isKindOfClass:[GPGException class]]) {
					details = [(GPGException *)error gpgTask].errText;
				}
				NSRunCriticalAlertPanel(localized(@"UNKNOWN_GPG_ERROR_TITLE"), [NSString stringWithFormat:localized(@"UNKNOWN_GPG_ERROR_MESSAGE"), details], nil, nil, nil);
				[NSApp terminate:nil];
				break; }
			default:
				break;
		}

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keysDidChange:) name:GPGKeyManagerKeysDidChangeNotification object:nil];
		@try {
			GPGKeyManager *keyManager = [GPGKeyManager sharedInstance];
			if ([[GPGOptions sharedOptions] boolForKey:@"showExpertSettings"]) {
				keyManager.allowWeakDigestAlgos = YES;
			}
			[keyManager loadAllKeys];
		}
		@catch (NSException *exception) {
			NSLog(@"loadAllKeys threw exception: %@", exception);
		}
		
		
		// Sort Descriptoren anlegen.
		NSSortDescriptor *nameSort = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
		
		self.keysSortDescriptors = [NSArray arrayWithObject:nameSort];
		
		
		self = [super init];
	}
	return self;
}
+ (id)allocWithZone:(NSZone *)zone {
    return [self sharedInstance];	
}
- (id)copyWithZone:(NSZone *)zone {
    return self;
}

@end

