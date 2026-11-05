// Reads macOS Now Playing (MediaRemote) for every player: browser tabs, installed web apps,
// Spotify, Music, Safari. Since macOS 15.4 only Apple-signed processes may read MediaRemote,
// so the app runs this library inside /usr/bin/perl, which can still load it.
//
// Every half second it prints one line to stdout:
//   state<TAB>title<TAB>artist<TAB>position<TAB>duration<TAB>artwork data URL
// or "none" when nothing is loaded. Each stdin line is a command: a MediaRemote command
// number (2 toggle play/pause, 4 next, 5 previous) or "seek <seconds>".
#import <Foundation/Foundation.h>
#include <ctype.h>
#include <dlfcn.h>

typedef void (*GetInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef Boolean (*SendCommandFunction)(int, NSDictionary *);
typedef void (*SetElapsedTimeFunction)(double);

static NSString *clean(id value) {
  NSString *text = [value description] ?: @"";
  return [[text stringByReplacingOccurrencesOfString:@"\t" withString:@" "]
      stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
}

static void printInfo(NSDictionary *info) {
  NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
  if (title.length == 0) {
    printf("none\n");
    return;
  }
  double rate = [info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] doubleValue];
  double elapsed = [info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue];
  // Elapsed time is a snapshot taken at Timestamp; playback has moved on since then.
  NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
  if (stamp && rate > 0) elapsed += -stamp.timeIntervalSinceNow * rate;
  NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
  NSString *mime = info[@"kMRMediaRemoteNowPlayingInfoArtworkMIMEType"] ?: @"image/jpeg";
  NSString *artURL = art.length
      ? [NSString stringWithFormat:@"data:%@;base64,%@", mime,
                                   [art base64EncodedStringWithOptions:0]]
      : @"";
  // Whole seconds: printf would follow perl's locale, which may use a decimal comma.
  printf("%s\t%s\t%s\t%ld\t%ld\t%s\n", rate > 0 ? "playing" : "paused", clean(title).UTF8String,
         clean(info[@"kMRMediaRemoteNowPlayingInfoArtist"]).UTF8String, (long)elapsed,
         (long)[info[@"kMRMediaRemoteNowPlayingInfoDuration"] doubleValue], artURL.UTF8String);
}

void spectrabar_now_playing(void) {
  void *mediaRemote =
      dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
  GetInfoFunction getInfo = dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingInfo");
  SendCommandFunction sendCommand = dlsym(mediaRemote, "MRMediaRemoteSendCommand");
  SetElapsedTimeFunction setElapsedTime = dlsym(mediaRemote, "MRMediaRemoteSetElapsedTime");
  if (!getInfo || !sendCommand || !setElapsedTime) exit(1);

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    char line[64];
    while (fgets(line, sizeof line, stdin)) {
      if (strncmp(line, "seek ", 5) == 0) {
        setElapsedTime(atof(line + 5));
      } else if (isdigit((unsigned char)line[0])) {
        sendCommand(atoi(line), nil);
      }
    }
    // stdin closes when the app quits; take the helper down with it.
    exit(0);
  });

  for (;;) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    getInfo(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(NSDictionary *info) {
      printInfo(info);
      fflush(stdout);
      dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    usleep(500000);
  }
}
