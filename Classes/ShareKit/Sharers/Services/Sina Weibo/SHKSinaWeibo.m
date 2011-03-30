//  Created by «FULLUSERNAME» on «DATE».


/*

 For a step by step guide to creating your service class, start at the top and move down through the comments.
 
*/

#import "SHKSinaWeibo.h"

@implementation SHKSinaWeibo

@synthesize xAuth;

- (id)init
{
	if ((self = [super init]))
	{		
        // OAuth
		self.consumerKey = SHKSinaWeiboConsumerKey;		
		self.secretKey = SHKSinaWeiboSecretKey;
 		self.authorizeCallbackURL = [NSURL URLWithString:SHKSinaWeiboCallbackUrl];
		
        // xAuth
		self.xAuth = SHKSinaWeiboUseXAuth ? YES : NO;
		
		// -- //
		
		
		// You do not need to edit these, they are the same for everyone
        self.authorizeURL = [NSURL URLWithString:@"http://api.t.sina.com.cn/oauth/authorize"];
	    self.requestURL = [NSURL URLWithString:@"http://api.t.sina.com.cn/oauth/request_token"];
	    self.accessURL = [NSURL URLWithString:@"http://api.t.sina.com.cn/oauth/access_token"];
	}	
	return self;
}

#pragma mark -
#pragma mark Configuration : Service Defination

// Enter the name of the service
+ (NSString *)sharerTitle
{
	return @"Sina Weibo";
}

+ (BOOL)canShareImage
{
	return YES;
}

+ (BOOL)canShareText
{
	return YES;
}

#pragma mark -
#pragma mark Configuration : Dynamic Enable

- (BOOL)shouldAutoShare
{
	return NO;
}

#pragma mark -
#pragma mark Authorization

- (BOOL)isAuthorized
{		
	return [self restoreAccessToken];
}

- (void)promptAuthorization
{		
	if (xAuth)
		[super authorizationFormShow]; // xAuth process
	
	else
		[super promptAuthorization]; // OAuth process		
}

#pragma mark xAuth

+ (NSString *)authorizationFormCaption
{
	return SHKLocalizedString(@"Create a free account at %@", @"T.CN");
}

+ (NSArray *)authorizationFormFields
{
	if ([SHKTwitterUsername isEqualToString:@""])
		return [super authorizationFormFields];
	
	return [NSArray arrayWithObjects:
			[SHKFormFieldSettings label:SHKLocalizedString(@"Username") key:@"username" type:SHKFormFieldTypeText start:nil],
			[SHKFormFieldSettings label:SHKLocalizedString(@"Password") key:@"password" type:SHKFormFieldTypePassword start:nil],
			[SHKFormFieldSettings label:SHKLocalizedString(@"Follow %@", SHKSinaWeiboUsername) key:@"followMe" type:SHKFormFieldTypeSwitch start:SHKFormFieldSwitchOn],			
			nil];
}

- (void)authorizationFormValidate:(SHKFormController *)form
{
	self.pendingForm = form;
	[self tokenAccess];
}

- (void)tokenAccessModifyRequest:(OAMutableURLRequest *)oRequest
{	
	if (xAuth)
	{
		NSDictionary *formValues = [pendingForm formValues];
		
		OARequestParameter *username = [[[OARequestParameter alloc] initWithName:@"x_auth_username"
                                                                           value:[formValues objectForKey:@"username"]] autorelease];
		
		OARequestParameter *password = [[[OARequestParameter alloc] initWithName:@"x_auth_password"
                                                                           value:[formValues objectForKey:@"password"]] autorelease];
		
		OARequestParameter *mode = [[[OARequestParameter alloc] initWithName:@"x_auth_mode"
                                                                       value:@"client_auth"] autorelease];
		
		[oRequest setParameters:[NSArray arrayWithObjects:username, password, mode, nil]];
	}
}

- (void)tokenAccessTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{
	if (xAuth) 
	{
		if (ticket.didSucceed)
		{
			[item setCustomValue:[[pendingForm formValues] objectForKey:@"followMe"] forKey:@"followMe"];
			[pendingForm close];
		}
		
		else
		{
			NSString *response = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
			
			SHKLog(@"tokenAccessTicket Response Body: %@", response);
			
			[self tokenAccessTicket:ticket didFailWithError:[SHK error:response]];
			return;
		}
	}
    
	[super tokenAccessTicket:ticket didFinishWithData:data];		
}



#pragma mark -
#pragma mark UI Implementation

- (void)show
{
	if (item.shareType == SHKShareTypeImage)
	{
		[item setCustomValue:item.title forKey:@"status"];
		[self showSinaWeiboForm];
	}
	
	else if (item.shareType == SHKShareTypeText)
	{
		[item setCustomValue:item.text forKey:@"status"];
		[self showSinaWeiboForm];
	}
}

- (void)showSinaWeiboForm
{
	SHKSinaWeiboForm *rootView = [[SHKSinaWeiboForm alloc] initWithNibName:nil bundle:nil];	
	rootView.delegate = self;
	
	// force view to load so we can set textView text
	[rootView view];
	
	rootView.textView.text = [item customValueForKey:@"status"];
	rootView.hasAttachment = item.image != nil;
	
	[self pushViewController:rootView animated:NO];
	
	[[SHK currentHelper] showViewController:self];	
}

- (void)sendForm:(SHKSinaWeiboForm *)form
{	
	[item setCustomValue:form.textView.text forKey:@"status"];
	[self tryToSend];
}


#pragma mark -
#pragma mark Share API Methods

- (BOOL)validate
{
	NSString *status = [item customValueForKey:@"status"];
	return status != nil && status.length > 0 && status.length <= 140;
}

- (BOOL)send
{	
	// Check if we should send follow request too
	if (xAuth && [item customBoolForSwitchKey:@"followMe"])
		[self followMe];	
	
	if (![self validate])
		[self show];
	
	else
	{	
		if (item.shareType == SHKShareTypeImage) {
			[self sendImage];
		} else {
			[self sendStatus];
		}
		
		// Notify delegate
		[self sendDidStart];	
		
		return YES;
	}
	
	return NO;
}

- (void)sendStatus
{
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://api.t.sina.com.cn/statuses/update.json"]
                                                                    consumer:consumer
                                                                       token:accessToken
                                                                       realm:nil
                                                           signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
	
	OARequestParameter *statusParam = [[OARequestParameter alloc] initWithName:@"status"
																		 value:[item customValueForKey:@"status"]];
	NSArray *params = [NSArray arrayWithObjects:statusParam, nil];
	[oRequest setParameters:params];
	[statusParam release];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:self
                                                                                 didFinishSelector:@selector(sendStatusTicket:didFinishWithData:)
                                                                                   didFailSelector:@selector(sendStatusTicket:didFailWithError:)];	
    
	[fetcher start];
	[oRequest release];
}

- (void)sendStatusTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data 
{	
	// TODO better error handling here
    
	if (ticket.didSucceed) 
		[self sendDidFinish];
	
	else
	{		
		if (SHKDebugShowLogs)
			SHKLog(@"Twitter Send Status Error: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
		
		// CREDIT: Oliver Drobnik
		
		NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];		
		
		// in case our makeshift parsing does not yield an error message
		NSString *errorMessage = @"Unknown Error";		
		
		NSScanner *scanner = [NSScanner scannerWithString:string];
		
		// skip until error message
		[scanner scanUpToString:@"\"error\":\"" intoString:nil];
		
		
		if ([scanner scanString:@"\"error\":\"" intoString:nil])
		{
			// get the message until the closing double quotes
			[scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\""] intoString:&errorMessage];
		}
		
		
		// this is the error message for revoked access
		if ([errorMessage isEqualToString:@"Invalid / used nonce"])
		{
			[self sendDidFailShouldRelogin];
		}
		else 
		{
			NSError *error = [NSError errorWithDomain:@"Twitter" code:2 userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
			[self sendDidFailWithError:error];
		}
	}
}

- (void)sendStatusTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error
{
	[self sendDidFailWithError:error];
}

- (void)sendImage {
	
	NSURL *serviceURL = nil;
	if([item customValueForKey:@"profile_update"]){
		serviceURL = [NSURL URLWithString:@"http://api.twitter.com/1/account/update_profile_image.json"];
	} else {
		serviceURL = [NSURL URLWithString:@"https://api.twitter.com/1/account/verify_credentials.json"];
	}
	
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:serviceURL
																	consumer:consumer
																	   token:accessToken
																	   realm:@"http://api.twitter.com/"
														   signatureProvider:signatureProvider];
	[oRequest setHTTPMethod:@"GET"];
	
	if([item customValueForKey:@"profile_update"]){
		[oRequest prepare];
	} else {
		[oRequest prepare];
        
		NSDictionary * headerDict = [oRequest allHTTPHeaderFields];
		NSString * oauthHeader = [NSString stringWithString:[headerDict valueForKey:@"Authorization"]];
		
		[oRequest release];
		oRequest = nil;
		
		serviceURL = [NSURL URLWithString:@"http://img.ly/api/2/upload.xml"];
		oRequest = [[OAMutableURLRequest alloc] initWithURL:serviceURL
												   consumer:consumer
													  token:accessToken
													  realm:@"http://api.twitter.com/"
										  signatureProvider:signatureProvider];
		[oRequest setHTTPMethod:@"POST"];
		[oRequest setValue:@"https://api.twitter.com/1/account/verify_credentials.json" forHTTPHeaderField:@"X-Auth-Service-Provider"];
		[oRequest setValue:oauthHeader forHTTPHeaderField:@"X-Verify-Credentials-Authorization"];
	}
    
	CGFloat compression = 0.9f;
	NSData *imageData = UIImageJPEGRepresentation([item image], compression);
	
	// TODO
	// Note from Nate to creator of sendImage method - This seems like it could be a source of sluggishness.
	// For example, if the image is large (say 3000px x 3000px for example), it would be better to resize the image
	// to an appropriate size (max of img.ly) and then start trying to compress.
	
	while ([imageData length] > 700000 && compression > 0.1) {
		// NSLog(@"Image size too big, compression more: current data size: %d bytes",[imageData length]);
		compression -= 0.1;
		imageData = UIImageJPEGRepresentation([item image], compression);
		
	}
	
	NSString *boundary = @"0xKhTmLbOuNdArY";
	NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary];
	[oRequest setValue:contentType forHTTPHeaderField:@"Content-Type"];
	
	NSMutableData *body = [NSMutableData data];
	NSString *dispKey = @"";
	if([item customValueForKey:@"profile_update"]){
		dispKey = @"Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n";
	} else {
		dispKey = @"Content-Disposition: form-data; name=\"media\"; filename=\"upload.jpg\"\r\n";
	}
    
	
	[body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[dispKey dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:[@"Content-Type: image/jpg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[body appendData:imageData];
	[body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
	
	if([item customValueForKey:@"profile_update"]){
		// no ops
	} else {
		[body appendData:[[NSString stringWithFormat:@"--%@\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[NSString stringWithString:@"Content-Disposition: form-data; name=\"message\"\r\n\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[[item customValueForKey:@"status"] dataUsingEncoding:NSUTF8StringEncoding]];
		[body appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];	
	}
	
	[body appendData:[[NSString stringWithFormat:@"--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
	
	// setting the body of the post to the reqeust
	[oRequest setHTTPBody:body];
    
	// Notify delegate
	[self sendDidStart];
    
	// Start the request
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
																						  delegate:self
																				 didFinishSelector:@selector(sendImageTicket:didFinishWithData:)
																				   didFailSelector:@selector(sendImageTicket:didFailWithError:)];	
	
	[fetcher start];
	
	
	[oRequest release];
}

- (void)sendImageTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data {
	// TODO better error handling here
	// NSLog([[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
	
	if (ticket.didSucceed) {
		[self sendDidFinish];
		// Finished uploading Image, now need to posh the message and url in twitter
		NSString *dataString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
		NSRange startingRange = [dataString rangeOfString:@"<url>" options:NSCaseInsensitiveSearch];
		//NSLog(@"found start string at %d, len %d",startingRange.location,startingRange.length);
		NSRange endingRange = [dataString rangeOfString:@"</url>" options:NSCaseInsensitiveSearch];
		//NSLog(@"found end string at %d, len %d",endingRange.location,endingRange.length);
		
		if (startingRange.location != NSNotFound && endingRange.location != NSNotFound) {
			NSString *urlString = [dataString substringWithRange:NSMakeRange(startingRange.location + startingRange.length, endingRange.location - (startingRange.location + startingRange.length))];
			//NSLog(@"extracted string: %@",urlString);
			[item setCustomValue:[NSString stringWithFormat:@"%@ %@",[item customValueForKey:@"status"],urlString] forKey:@"status"];
			[self sendStatus];
		}
		
		
	} else {
		[self sendDidFailWithError:nil];
	}
}

- (void)sendImageTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error {
	[self sendDidFailWithError:error];
}


- (void)followMe
{
	// remove it so in case of other failures this doesn't get hit again
	[item setCustomValue:nil forKey:@"followMe"];
	
	OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://api.t.sina.com.cn/friendships/create/%@.json", SHKTwitterUsername]]
																	consumer:consumer
																	   token:accessToken
																	   realm:nil
														   signatureProvider:nil];
	
	[oRequest setHTTPMethod:@"POST"];
	
	OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:nil // Currently not doing any error handling here.  If it fails, it's probably best not to bug the user to follow you again.
                                                                                 didFinishSelector:nil
                                                                                   didFailSelector:nil];	
	
	[fetcher start];
	[oRequest release];
}

@end