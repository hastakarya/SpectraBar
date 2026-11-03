import AppKit

struct NowPlaying {
  let isPlaying: Bool
  let title: String
  let artist: String
  let position: Double
  let duration: Double
  let artworkURL: String?

  // Every script returns "state<TAB>title<TAB>artist<TAB>position<TAB>duration<TAB>artwork URL",
  // or "" when stopped.
  init?(_ line: String) {
    let fields = line.components(separatedBy: "\t")
    guard fields.count == 6, !fields[1].isEmpty else { return nil }
    isPlaying = fields[0] == "playing"
    title = fields[1]
    artist = fields[2]
    position = Double(fields[3]) ?? 0
    duration = Double(fields[4]) ?? 0
    artworkURL = fields[5].isEmpty ? nil : fields[5]
  }
}

struct Player {
  let bundleID: String
  let nowPlaying: String
  let playPause: String
  let next: String
  let previous: String
  let seek: @Sendable (Int) -> String

  // Skips apps that are not running: a `tell` would launch them.
  func run(_ body: String) -> String? {
    guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    else { return nil }
    let source = "tell application id \"\(bundleID)\"\n\(body)\nend tell"
    return NSAppleScript(source: source)?.executeAndReturnError(nil).stringValue
  }
}

// Integers only: AppleScript writes reals with the locale's decimal separator, which may be a comma.
// shortcut: Music has no artwork URL (only raw image data), so it shows a note icon instead.
private func appPlayer(_ bundleID: String, durationDivisor: Int, artwork: String) -> Player {
  Player(
    bundleID: bundleID,
    nowPlaying: """
      if player state is stopped then return ""
      return (player state as string) & tab & (name of current track) & tab & (artist of current track) & tab & (player position as integer) & tab & ((duration of current track) div \(durationDivisor)) & tab & \(artwork)
      """,
    playPause: "playpause",
    next: "next track",
    previous: "previous track",
    seek: { "set player position to \($0)" })
}

let needsChromeJS = "needs-js"

// The JS must avoid double quotes and backslashes: it sits inside an AppleScript string.
private let youTubeMusicTrackJS = """
  (() => { const v = document.querySelector('video'); const m = navigator.mediaSession.metadata; \
  if (!v || !m || !m.title) return ''; \
  return [v.paused ? 'paused' : 'playing', m.title, m.artist, Math.floor(v.currentTime), \
  Math.floor(v.duration || 0), (m.artwork[0] || {}).src || ''].join(String.fromCharCode(9)); })()
  """

// Picks the playing YouTube Music tab, else the first one with a track, then runs `action` on it,
// so the buttons control the same tab the bar shows. Fails until Chrome's
// View > Developer > Allow JavaScript from Apple Events is on (a per-profile setting).
private func onYouTubeMusicTab(_ action: String) -> String {
  """
  set chosen to missing value
  set found to ""
  set blocked to false
  repeat with w in windows
    repeat with t in tabs of w
      if URL of t contains "music.youtube.com" then
        try
          set r to execute t javascript "\(youTubeMusicTrackJS)"
          if r starts with "playing" or (found is "" and r is not "") then
            set found to r
            set chosen to t
          end if
        on error
          set blocked to true
        end try
      end if
    end repeat
  end repeat
  if chosen is missing value then
    if blocked then return "\(needsChromeJS)"
    return ""
  end if
  \(action)
  """
}

private let youTubeMusic = Player(
  bundleID: "com.google.Chrome",
  nowPlaying: onYouTubeMusicTab("return found"),
  playPause: onYouTubeMusicTab(
    "execute chosen javascript \"document.querySelector('#play-pause-button').click()\""),
  next: onYouTubeMusicTab(
    "execute chosen javascript \"document.querySelector('.next-button').click()\""),
  previous: onYouTubeMusicTab(
    "execute chosen javascript \"document.querySelector('.previous-button').click()\""),
  seek: {
    onYouTubeMusicTab(
      "execute chosen javascript \"document.querySelector('video').currentTime = \($0)\"")
  })

// Spotify reports duration in milliseconds, Music in seconds.
let players = [
  appPlayer("com.spotify.client", durationDivisor: 1000, artwork: "(artwork url of current track)"),
  appPlayer("com.apple.Music", durationDivisor: 1, artwork: "\"\""),
  youTubeMusic,
]
