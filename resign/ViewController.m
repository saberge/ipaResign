//
//  ViewController.m
//  resign
//
//  Created by 郑来贤 on 2018/6/29.
//  Copyright © 2018年 郑来贤. All rights reserved.
//

#import "ViewController.h"

static NSString *kKeyPrefsBundleIDChange            = @"keyBundleIDChange";
static NSString *kKeyBundleIDPlistApp               = @"CFBundleIdentifier";
static NSString *kKeyBundleIDPlistiTunesArtwork     = @"softwareVersionBundleId";
static NSString *kKeyInfoPlistApplicationProperties = @"ApplicationProperties";
static NSString *kKeyInfoPlistApplicationPath       = @"ApplicationPath";
static NSString *kFrameworksDirName                 = @"Frameworks";
static NSString *kPayloadDirName                    = @"Payload";
static NSString *kProductsDirName                   = @"Products";
static NSString *kInfoPlistFilename                 = @"Info.plist";
static NSString *kiTunesMetadataFileName            = @"iTunesMetadata";
static NSString *kKeyAppDisplayName                 = @"CFBundleDisplayName";


@interface ViewController (){
    NSString *entitlementsResult;
    NSString *codesigningResult;
    BOOL hasFrameworks;
    NSMutableArray *frameworks;
    NSString *appPath;
    NSTask *verifyTask;
    NSString *verificationResult;
    NSString *fileName;
    NSTask *zipTask;
    NSMutableArray *certComboBoxItems;
    NSString *getCertsResult;
    NSTask *certTask;
    NSString *entitlementPath;
}
@property (weak , nonatomic) IBOutlet NSTextField *profileTF;
@property (weak , nonatomic) IBOutlet NSComboBox *certComboBox;
@property (weak , nonatomic) IBOutlet NSTextField *bundleTF;
@property (weak , nonatomic) IBOutlet NSTextField *appNameTF;
@property (weak , nonatomic) IBOutlet NSTextField *ipaTF;
@property (strong , nonatomic) NSString *workingPath;
@property (strong , nonatomic) NSTask *unzipTask;
@property (strong , nonatomic) NSTask *provisioningTask;
@property (strong , nonatomic) NSTask *generateEntitlementsTask;
@property (strong , nonatomic) NSTask *codesignTask;
@property (weak , nonatomic) IBOutlet NSProgressIndicator *indicatorView;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    
    [self getCerts];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/zip"]) {
        [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"This app cannot run without the zip utility present at /usr/bin/zip"];
        exit(0);
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/unzip"]) {
        [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"This app cannot run without the unzip utility present at /usr/bin/unzip"];
        exit(0);
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/usr/bin/codesign"]) {
        [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"This app cannot run without the codesign utility present at /usr/bin/codesign"];
        exit(0);
    }
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


- (IBAction)onBrowseProfile:(NSButton *)sender{
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[@"mobileprovision"]];
    
    if ([openDlg runModal] == NSModalResponseOK)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [_profileTF setStringValue:fileNameOpened];
    }
}

- (IBAction)onBrowseIPA:(NSButton *)sender{
    NSOpenPanel* openDlg = [NSOpenPanel openPanel];
    
    [openDlg setCanChooseFiles:TRUE];
    [openDlg setCanChooseDirectories:FALSE];
    [openDlg setAllowsMultipleSelection:FALSE];
    [openDlg setAllowsOtherFileTypes:FALSE];
    [openDlg setAllowedFileTypes:@[@"ipa"]];
    
    if ([openDlg runModal] == NSModalResponseOK)
    {
        NSString* fileNameOpened = [[[openDlg URLs] objectAtIndex:0] path];
        [_ipaTF setStringValue:fileNameOpened];
    }
}

- (IBAction)onResign:(NSButton *)sender{
    [self showIndicatorView];
    self.workingPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"com.sjyr.resign"];

    codesigningResult = nil;
    verificationResult = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.workingPath error:nil];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.workingPath withIntermediateDirectories:TRUE attributes:nil error:nil];
    // unzip ipa
    NSString *ipaPath = _ipaTF.stringValue;
    if ([[[ipaPath pathExtension] lowercaseString] isEqualToString:@"ipa"]) {
        if (ipaPath && [ipaPath length] > 0) {
            NSLog(@"Unzipping %@",ipaPath);
        }
        
        _unzipTask = [[NSTask alloc] init];
        [_unzipTask setLaunchPath:@"/usr/bin/unzip"];
        [_unzipTask setArguments:[NSArray arrayWithObjects:@"-q", ipaPath, @"-d", self.workingPath, nil]];
        
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkUnzip:) userInfo:nil repeats:TRUE];
        
        [_unzipTask launch];
    }
    else{
        [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"You must choose an *.ipa file"];
    }
}

- (void)checkUnzip:(NSTimer *)timer {
    if ([self.unzipTask isRunning] == 0) {
        [timer invalidate];
        self.unzipTask = nil;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self.workingPath stringByAppendingPathComponent:kPayloadDirName]]) {
            NSLog(@"Unzipping done");
            
            [self doBundleIDChange:self.bundleTF.stringValue];
            
            if (_appNameTF.stringValue.length) {
                [self doChangeAppName];
            }
            
            [self doProvisioning];
            
            
        } else {
            [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"Unzip failed"];
        }
    }
}

- (void)doChangeAppName{
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self.workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            infoPlistPath = [[[self.workingPath stringByAppendingPathComponent:kPayloadDirName]
                              stringByAppendingPathComponent:file]
                             stringByAppendingPathComponent:kInfoPlistFilename];
            break;
        }
    }
    
    NSMutableDictionary *plist = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:infoPlistPath]) {
        plist = [[NSMutableDictionary alloc] initWithContentsOfFile:infoPlistPath];
        [plist setObject:_appNameTF.stringValue forKey:kKeyAppDisplayName];
        
        NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:kCFPropertyListImmutable error:nil];
        
        [xmlData writeToFile:infoPlistPath atomically:YES];
        
    }
}

- (BOOL)doBundleIDChange:(NSString *)newBundleID {
    BOOL success = YES;
    
    success &= [self doAppBundleIDChange:newBundleID];
    success &= [self doITunesMetadataBundleIDChange:newBundleID];
    
    return success;
}

- (BOOL)doITunesMetadataBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.workingPath error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"plist"]) {
            infoPlistPath = [self.workingPath stringByAppendingPathComponent:file];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistiTunesArtwork newBundleID:newBundleID plistOutOptions:NSPropertyListXMLFormat_v1_0];
    
}

- (BOOL)doAppBundleIDChange:(NSString *)newBundleID {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self.workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    NSString *infoPlistPath = nil;
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            infoPlistPath = [[[self.workingPath stringByAppendingPathComponent:kPayloadDirName]
                              stringByAppendingPathComponent:file]
                             stringByAppendingPathComponent:kInfoPlistFilename];
            break;
        }
    }
    
    return [self changeBundleIDForFile:infoPlistPath bundleIDKey:kKeyBundleIDPlistApp newBundleID:newBundleID plistOutOptions:NSPropertyListBinaryFormat_v1_0];
}

- (BOOL)changeBundleIDForFile:(NSString *)filePath bundleIDKey:(NSString *)bundleIDKey newBundleID:(NSString *)newBundleID plistOutOptions:(NSPropertyListWriteOptions)options {
    
    NSMutableDictionary *plist = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        plist = [[NSMutableDictionary alloc] initWithContentsOfFile:filePath];
        [plist setObject:newBundleID forKey:bundleIDKey];
        
        NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:plist format:options options:kCFPropertyListImmutable error:nil];
        
        return [xmlData writeToFile:filePath atomically:YES];
        
    }
    
    return NO;
}

- (void)doProvisioning {
    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self.workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
    
    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            appPath = [[self.workingPath stringByAppendingPathComponent:kPayloadDirName] stringByAppendingPathComponent:file];
            if ([[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                NSLog(@"Found embedded.mobileprovision, deleting.");
                [[NSFileManager defaultManager] removeItemAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] error:nil];
            }
            break;
        }
    }
    
    NSString *targetPath = [appPath stringByAppendingPathComponent:@"embedded.mobileprovision"];
    
    self.provisioningTask = [[NSTask alloc] init];
    [self.provisioningTask setLaunchPath:@"/bin/cp"];
    [self.provisioningTask setArguments:[NSArray arrayWithObjects:[_profileTF stringValue], targetPath, nil]];
    
    [self.provisioningTask launch];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkProvisioning:) userInfo:nil repeats:TRUE];
}

- (void)checkProvisioning:(NSTimer *)timer {
    if ([self.provisioningTask isRunning] == 0) {
        [timer invalidate];
        self.provisioningTask = nil;
        
        NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self.workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];
        
        for (NSString *file in dirContents) {
            if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
                appPath = [[self.workingPath stringByAppendingPathComponent:kPayloadDirName] stringByAppendingPathComponent:file];
                if ([[NSFileManager defaultManager] fileExistsAtPath:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"]]) {
                    
                    BOOL identifierOK = FALSE;
                    NSString *identifierInProvisioning = @"";
                    
                    NSString *embeddedProvisioning = [NSString stringWithContentsOfFile:[appPath stringByAppendingPathComponent:@"embedded.mobileprovision"] encoding:NSASCIIStringEncoding error:nil];
                    NSArray* embeddedProvisioningLines = [embeddedProvisioning componentsSeparatedByCharactersInSet:
                                                          [NSCharacterSet newlineCharacterSet]];
                    
                    for (int i = 0; i < [embeddedProvisioningLines count]; i++) {
                        if ([[embeddedProvisioningLines objectAtIndex:i] rangeOfString:@"application-identifier"].location != NSNotFound) {
                            
                            NSInteger fromPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"<string>"].location + 8;
                            
                            NSInteger toPosition = [[embeddedProvisioningLines objectAtIndex:i+1] rangeOfString:@"</string>"].location;
                            
                            NSRange range;
                            range.location = fromPosition;
                            range.length = toPosition-fromPosition;
                            
                            NSString *fullIdentifier = [[embeddedProvisioningLines objectAtIndex:i+1] substringWithRange:range];
                            
                            NSArray *identifierComponents = [fullIdentifier componentsSeparatedByString:@"."];
                            
                            if ([[identifierComponents lastObject] isEqualTo:@"*"]) {
                                identifierOK = TRUE;
                            }
                            
                            for (int i = 1; i < [identifierComponents count]; i++) {
                                identifierInProvisioning = [identifierInProvisioning stringByAppendingString:[identifierComponents objectAtIndex:i]];
                                if (i < [identifierComponents count]-1) {
                                    identifierInProvisioning = [identifierInProvisioning stringByAppendingString:@"."];
                                }
                            }
                            break;
                        }
                    }
                    
                    NSLog(@"Mobileprovision identifier: %@",identifierInProvisioning);
                    
                    NSDictionary *infoplist = [NSDictionary dictionaryWithContentsOfFile:[appPath stringByAppendingPathComponent:@"Info.plist"]];
                    if ([identifierInProvisioning isEqualTo:[infoplist objectForKey:kKeyBundleIDPlistApp]]) {
                        NSLog(@"Identifiers match");
                        identifierOK = TRUE;
                    }
                    
                    if (identifierOK) {
                        NSLog(@"Provisioning completed.");
                        [self doEntitlementsFixing];
                    } else {
                        [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"Product identifiers don't match"];
                    }
                } else {
                    [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"Provisioning failed"];
                }
                break;
            }
        }
    }
}

- (void)doEntitlementsFixing
{
    self.generateEntitlementsTask = [[NSTask alloc] init];
    [self.generateEntitlementsTask setLaunchPath:@"/usr/bin/security"];
    [self.generateEntitlementsTask setArguments:@[@"cms", @"-D", @"-i", _profileTF.stringValue]];
    [self.generateEntitlementsTask setCurrentDirectoryPath:self.workingPath];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkEntitlementsFix:) userInfo:nil repeats:TRUE];
    
    NSPipe *pipe=[NSPipe pipe];
    [self.generateEntitlementsTask setStandardOutput:pipe];
    [self.generateEntitlementsTask setStandardError:pipe];
    NSFileHandle *handle = [pipe fileHandleForReading];
    
    [self.generateEntitlementsTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchEntitlements:)
                             toTarget:self withObject:handle];
}

- (void)watchEntitlements:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        entitlementsResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
    }
}

- (void)checkEntitlementsFix:(NSTimer *)timer {
    if ([self.generateEntitlementsTask isRunning] == 0) {
        [timer invalidate];
        self.generateEntitlementsTask = nil;
        NSLog(@"Entitlements fixed done");
        [self doEntitlementsEdit];
    }
}

- (void)doEntitlementsEdit
{
    NSDictionary* entitlements = entitlementsResult.propertyList;
    entitlements = entitlements[@"Entitlements"];
    NSString* filePath = [self.workingPath stringByAppendingPathComponent:@"entitlements.plist"];
    entitlementPath = filePath;
    NSData *xmlData = [NSPropertyListSerialization dataWithPropertyList:entitlements format:NSPropertyListXMLFormat_v1_0 options:kCFPropertyListImmutable error:nil];
    if(![xmlData writeToFile:filePath atomically:YES]) {
        NSLog(@"Error writing entitlements file.");
        [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Error" AndMessage:@"Failed entitlements generation"];
    }
    else {
        [self doCodeSigning];
    }
}

- (void)doCodeSigning {
    NSString *frameworksDirPath = nil;
    hasFrameworks = NO;
    NSString *appName = nil;
    frameworks = [[NSMutableArray alloc] init];

    NSArray *dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self.workingPath stringByAppendingPathComponent:kPayloadDirName] error:nil];

    for (NSString *file in dirContents) {
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"app"]) {
            appPath = [[self.workingPath stringByAppendingPathComponent:kPayloadDirName] stringByAppendingPathComponent:file];
            frameworksDirPath = [appPath stringByAppendingPathComponent:kFrameworksDirName];
            NSLog(@"Found %@",appPath);
            appName = file;
            if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksDirPath]) {
                NSLog(@"Found %@",frameworksDirPath);
                hasFrameworks = YES;
                NSArray *frameworksContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworksDirPath error:nil];
                for (NSString *frameworkFile in frameworksContents) {
                    NSString *extension = [[frameworkFile pathExtension] lowercaseString];
                    if ([extension isEqualTo:@"framework"] || [extension isEqualTo:@"dylib"]) {
                        NSString *frameworkPath = [frameworksDirPath stringByAppendingPathComponent:frameworkFile];
                        NSLog(@"Found %@",frameworkPath);
                        [frameworks addObject:frameworkPath];
                    }
                }
            }
            break;
        }
    }

    if (appPath) {
        if (hasFrameworks) {
            [self signFile:[frameworks lastObject]];
            [frameworks removeLastObject];
        } else {
            [self signFile:appPath];
        }
    }
}

- (void)signFile:(NSString*)filePath {
    NSLog(@"Codesigning %@", filePath);
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"-fs", _certComboBox.objectValue, nil];
    NSDictionary *systemVersionDictionary = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
    NSString * systemVersion = [systemVersionDictionary objectForKey:@"ProductVersion"];
    NSArray * version = [systemVersion componentsSeparatedByString:@"."];
    if ([version[0] intValue]<10 || ([version[0] intValue]==10 && ([version[1] intValue]<9 || ([version[1] intValue]==9 && [version[2] intValue]<5)))) {

        /*
         Before OSX 10.9, code signing requires a version 1 signature.
         The resource envelope is necessary.
         To ensure it is added, append the resource flag to the arguments.
         */

        NSString *resourceRulesPath = [[NSBundle mainBundle] pathForResource:@"ResourceRules" ofType:@"plist"];
        NSString *resourceRulesArgument = [NSString stringWithFormat:@"--resource-rules=%@",resourceRulesPath];
        [arguments addObject:resourceRulesArgument];
    } else {

        /*
         For OSX 10.9 and later, code signing requires a version 2 signature.
         The resource envelope is obsolete.
         To ensure it is ignored, remove the resource key from the Info.plist file.
         */

        NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", filePath];
        NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
        [infoDict removeObjectForKey:@"CFBundleResourceSpecification"];
        [infoDict writeToFile:infoPath atomically:YES];
        [arguments addObject:@"--no-strict"]; // http://stackoverflow.com/a/26204757
    }

    [arguments addObject:[NSString stringWithFormat:@"--entitlements=%@", entitlementPath]];
    [arguments addObjectsFromArray:[NSArray arrayWithObjects:filePath, nil]];
    self.codesignTask = [[NSTask alloc] init];
    [self.codesignTask setLaunchPath:@"/usr/bin/codesign"];
    [self.codesignTask setArguments:arguments];

    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCodesigning:) userInfo:nil repeats:TRUE];


    NSPipe *pipe=[NSPipe pipe];
    [self.codesignTask setStandardOutput:pipe];
    [self.codesignTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];

    [self.codesignTask launch];

    [NSThread detachNewThreadSelector:@selector(watchCodesigning:)
                             toTarget:self withObject:handle];
}

- (void)watchCodesigning:(NSFileHandle*)streamHandle {
    @autoreleasepool {

        codesigningResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];

    }
}

- (void)checkCodesigning:(NSTimer *)timer {
    if ([self.codesignTask isRunning] == 0) {
        [timer invalidate];
        self.codesignTask = nil;
        if (frameworks.count > 0) {
            [self signFile:[frameworks lastObject]];
            [frameworks removeLastObject];
        } else if (hasFrameworks) {
            hasFrameworks = NO;
            [self signFile:appPath];
        } else {
            NSLog(@"Codesigning done");
            [self doVerifySignature];
        }
    }
}

- (void)doVerifySignature {
    verifyTask = [[NSTask alloc] init];
    [verifyTask setLaunchPath:@"/usr/bin/codesign"];
    [verifyTask setArguments:[NSArray arrayWithObjects:@"-v", appPath, nil]];

    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkVerificationProcess:) userInfo:nil repeats:TRUE];

    NSLog(@"Verifying %@",appPath);

    NSPipe *pipe=[NSPipe pipe];
    [verifyTask setStandardOutput:pipe];
    [verifyTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];

    [verifyTask launch];

    [NSThread detachNewThreadSelector:@selector(watchVerificationProcess:)
                             toTarget:self withObject:handle];
}

- (void)watchVerificationProcess:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        verificationResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        
    }
}

- (void)checkVerificationProcess:(NSTimer *)timer {
    if ([verifyTask isRunning] == 0) {
        [timer invalidate];
        verifyTask = nil;
        if ([verificationResult length] == 0) {
            NSLog(@"Verification done");
            [self doZip];
        } else {
            NSString *error = [[codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:verificationResult];
            [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"Signing failed" AndMessage:error];
        }
    }
}

- (void)doZip {
    if (appPath) {
        NSArray *destinationPathComponents = [_ipaTF.stringValue pathComponents];
        NSString *destinationPath = @"";

        for (int i = 0; i < ([destinationPathComponents count]-1); i++) {
            destinationPath = [destinationPath stringByAppendingPathComponent:[destinationPathComponents objectAtIndex:i]];
        }

        fileName = [_ipaTF.stringValue lastPathComponent];
        fileName = [fileName substringToIndex:([fileName length] - ([[_ipaTF.stringValue pathExtension] length] + 1))];
        fileName = [fileName stringByAppendingString:@"-resigned"];
        fileName = [fileName stringByAppendingPathExtension:@"ipa"];

        destinationPath = [destinationPath stringByAppendingPathComponent:fileName];

        NSLog(@"Dest: %@",destinationPath);

        zipTask = [[NSTask alloc] init];
        [zipTask setLaunchPath:@"/usr/bin/zip"];
        [zipTask setCurrentDirectoryPath:self.workingPath];
        [zipTask setArguments:[NSArray arrayWithObjects:@"-qry", destinationPath, @".", nil]];

        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkZip:) userInfo:nil repeats:TRUE];

        NSLog(@"Zipping %@", destinationPath);

        [zipTask launch];
    }
}

- (void)checkZip:(NSTimer *)timer {
    if ([zipTask isRunning] == 0) {
        [timer invalidate];
        zipTask = nil;
        NSLog(@"Zipping done");

        [[NSFileManager defaultManager] removeItemAtPath:self.workingPath error:nil];

        NSString *result = [[codesigningResult stringByAppendingString:@"\n\n"] stringByAppendingString:verificationResult];
        NSLog(@"Codesigning result: %@",result);
        
        [self hideIndicatorView];
        [self showAlertOfKind:NSAlertStyleCritical WithTitle:@"打包成功" AndMessage:@"打包成功"];
    }
}

-(NSInteger)numberOfItemsInComboBox:(NSComboBox *)aComboBox {
    NSInteger count = 0;
    if ([aComboBox isEqual:_certComboBox]) {
        count = [certComboBoxItems count];
    }
    return count;
}

- (id)comboBox:(NSComboBox *)aComboBox objectValueForItemAtIndex:(NSInteger)index {
    id item = nil;
    if ([aComboBox isEqual:_certComboBox]) {
        item = [certComboBoxItems objectAtIndex:index];
    }
    return item;
}

- (void)getCerts {
    
    getCertsResult = nil;
    
    NSLog(@"Getting Certificate IDs");
    
    certTask = [[NSTask alloc] init];
    [certTask setLaunchPath:@"/usr/bin/security"];
    [certTask setArguments:[NSArray arrayWithObjects:@"find-identity", @"-v", @"-p", @"codesigning", nil]];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(checkCerts:) userInfo:nil repeats:TRUE];
    
    NSPipe *pipe=[NSPipe pipe];
    [certTask setStandardOutput:pipe];
    [certTask setStandardError:pipe];
    NSFileHandle *handle=[pipe fileHandleForReading];
    
    [certTask launch];
    
    [NSThread detachNewThreadSelector:@selector(watchGetCerts:) toTarget:self withObject:handle];
}

- (void)watchGetCerts:(NSFileHandle*)streamHandle {
    @autoreleasepool {
        
        NSString *securityResult = [[NSString alloc] initWithData:[streamHandle readDataToEndOfFile] encoding:NSASCIIStringEncoding];
        // Verify the security result
        if (securityResult == nil || securityResult.length < 1) {
            // Nothing in the result, return
            return;
        }
        NSArray *rawResult = [securityResult componentsSeparatedByString:@"\""];
        NSMutableArray *tempGetCertsResult = [NSMutableArray arrayWithCapacity:20];
        for (int i = 0; i <= [rawResult count] - 2; i+=2) {
            
            NSLog(@"i:%d", i+1);
            if (rawResult.count - 1 < i + 1) {
                // Invalid array, don't add an object to that position
            } else {
                // Valid object
                [tempGetCertsResult addObject:[rawResult objectAtIndex:i+1]];
            }
        }
        
        certComboBoxItems = [NSMutableArray arrayWithArray:tempGetCertsResult];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_certComboBox reloadData];
        });
    }
}

- (void)checkCerts:(NSTimer *)timer {
    if ([certTask isRunning] == 0) {
        [timer invalidate];
        certTask = nil;
        
//        if ([certComboBoxItems count] > 0) {
//            NSLog(@"Get Certs done");
//
//            if ([defaults valueForKey:@"CERT_INDEX"]) {
//
//                NSInteger selectedIndex = [[defaults valueForKey:@"CERT_INDEX"] integerValue];
//                if (selectedIndex != -1) {
//                    NSString *selectedItem = [self comboBox:certComboBox objectValueForItemAtIndex:selectedIndex];
//                    [certComboBox setObjectValue:selectedItem];
//                    [certComboBox selectItemAtIndex:selectedIndex];
//                }
//
//            }
//        } else {
//            [self showAlertOfKind:NSCriticalAlertStyle WithTitle:@"Error" AndMessage:@"Getting Certificate ID's failed"];
//        }
    }
}

// Show a critical alert
- (void)showAlertOfKind:(NSAlertStyle)style WithTitle:(NSString *)title AndMessage:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:title];
    [alert setInformativeText:message];
    [alert setAlertStyle:style];
    [alert runModal];
}

- (void)showIndicatorView{
    self.indicatorView.hidden = NO;
    [self.indicatorView startAnimation:self.indicatorView];
}

- (void)hideIndicatorView{
    self.indicatorView.hidden = YES;
}

@end
