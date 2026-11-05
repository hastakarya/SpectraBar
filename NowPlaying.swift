import Foundation

struct NowPlaying {
  let isPlaying: Bool
  let title: String
  let artist: String
  let position: Double
  let duration: Double
  let artworkURL: String?

  // The helper prints "state<TAB>title<TAB>artist<TAB>position<TAB>duration<TAB>artwork URL",
  // or "none" when nothing is loaded.
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

/// Live Now Playing info from NowPlayingHelper.dylib, which must run inside Apple's perl.
@MainActor
final class NowPlayingSource {
  private(set) var latest: NowPlaying?
  private var helper: Process?
  private var commands: FileHandle?

  // MediaRemote command numbers understood by the helper.
  func togglePlayPause() { send("2") }
  func next() { send("4") }
  func previous() { send("5") }
  func seek(to seconds: Double) { send("seek \(Int(seconds))") }

  /// Starts the helper, or restarts it if it died.
  func start() {
    guard helper?.isRunning != true,
          let library = Bundle.main.path(forResource: "NowPlayingHelper", ofType: "dylib")
    else { return }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = [
      "-e",
      "use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();"
        + " my $s = DynaLoader::dl_find_symbol($l, 'spectrabar_now_playing') or die;"
        + " DynaLoader::dl_install_xsub('main::run', $s); run();",
      library,
    ]
    let output = Pipe()
    let input = Pipe()
    process.standardOutput = output
    process.standardInput = input
    guard (try? process.run()) != nil else { return }
    helper = process
    commands = input.fileHandleForWriting
    // The stream ends or fails only when the helper dies; the next refresh restarts it.
    Task {
      do {
        for try await line in output.fileHandleForReading.bytes.lines { latest = NowPlaying(line) }
      } catch {}
      latest = nil
    }
  }

  func stop() {
    helper?.terminate()
    helper = nil
  }

  private func send(_ command: String) {
    try? commands?.write(contentsOf: Data((command + "\n").utf8))
  }
}
