import AppKit

private extension NSTouchBarItem.Identifier {
  static let tray = Self("local.touchbar-display.tray")
  static let art = Self("local.touchbar-display.art")
  static let track = Self("local.touchbar-display.track")
  static let transport = Self("local.touchbar-display.transport")
}

private func symbol(_ name: String, _ description: String, size: CGFloat = 13) -> NSImage {
  NSImage(systemSymbolName: name, accessibilityDescription: description)!
    .withSymbolConfiguration(.init(pointSize: size, weight: .regular))!
}

@MainActor
final class Display: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
  private var activePlayer: Player?
  private var artURL: String?
  private let touchBar = NSTouchBar()
  private let trayButton = NSButton(title: "♪", target: nil, action: nil)
  private let art = NSImageView()
  private let track = TrackView()
  private lazy var playPauseButton = transportButton(
    symbol("play.fill", "Play or pause", size: 18), #selector(playPause))
  private lazy var spectrum = AudioSpectrum { [weak self] levels in
    DispatchQueue.main.async { MainActor.assumeIsolated { self?.track.show(levels: levels) } }
  }
  private var statusItem: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    touchBar.delegate = self
    track.onSeek = { [weak self] seconds in self?.seek(to: seconds) }

    trayButton.target = self
    trayButton.action = #selector(present)
    let trayItem = NSCustomTouchBarItem(identifier: .tray)
    trayItem.view = trayButton
    NSTouchBarItem.addSystemTrayItem(trayItem)
    DFRElementSetControlStripPresenceForIdentifier(.tray, true)
    DFRSystemModalShowsCloseBoxWhenFrontMost(true)

    setUpArt()
    setUpMenuBar()
    refresh()
    Timer.scheduledTimer(
      timeInterval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
  }

  func applicationWillTerminate(_ notification: Notification) {
    DFRElementSetControlStripPresenceForIdentifier(.tray, false)
    spectrum.stop()
  }

  func touchBar(
    _ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier
  ) -> NSTouchBarItem? {
    let item = NSCustomTouchBarItem(identifier: identifier)
    switch identifier {
    case .art: item.view = art
    case .track: item.view = track
    case .transport: item.view = makeTransport()
    default: return nil
    }
    return item
  }

  // Placement 0 keeps the system Control Strip (brightness, volume, mute) on the right.
  @objc private func present() {
    NSTouchBar.presentSystemModal(touchBar, placement: 0, trayItem: .tray)
  }

  private func minimize() {
    NSTouchBar.minimizeSystemModal(touchBar)
  }

  // A playing source wins over a paused one. The bar pops up when a track appears and steps
  // aside when none is left; while a track stays, closing it is respected until the next one.
  @objc private func refresh() {
    var chromeBlocked = false
    let found = players.compactMap { player -> (Player, NowPlaying)? in
      guard let line = player.run(player.nowPlaying) else { return nil }
      if line == needsChromeJS { chromeBlocked = true }
      return NowPlaying(line).map { (player, $0) }
    }
    let current = found.first { $0.1.isPlaying } ?? found.first
    activePlayer = current?.0
    track.track = current?.1
    track.hint = chromeBlocked ? "Chrome: allow JavaScript from Apple Events" : nil
    let isPlaying = current?.1.isPlaying == true
    playPauseButton.image = symbol(isPlaying ? "pause.fill" : "play.fill", "Play or pause", size: 18)
    showArt(current?.1.artworkURL)
    // The tap runs only while music plays, so the system recording indicator stays off otherwise.
    if isPlaying {
      spectrum.start()
    } else {
      spectrum.stop()
      track.clearLevels()
    }

    let ids: [NSTouchBarItem.Identifier] =
      current != nil ? [.art, .track, .transport] : chromeBlocked ? [.track] : []
    guard touchBar.defaultItemIdentifiers != ids else { return }
    let wasEmpty = touchBar.defaultItemIdentifiers.isEmpty
    touchBar.defaultItemIdentifiers = ids
    if ids.isEmpty { minimize() } else if wasEmpty { present() }
  }

  private func showArt(_ url: String?) {
    guard url != artURL else { return }
    artURL = url
    art.image = symbol("music.note", "Album art")
    guard let url, let link = URL(string: url) else { return }
    Task {
      guard let (data, _) = try? await URLSession.shared.data(from: link),
            url == artURL, let image = NSImage(data: data)
      else { return }
      art.image = image
    }
  }

  private func setUpArt() {
    art.imageScaling = .scaleProportionallyUpOrDown
    art.wantsLayer = true
    art.layer?.cornerRadius = 4
    art.layer?.masksToBounds = true
    art.widthAnchor.constraint(equalToConstant: 30).isActive = true
    art.heightAnchor.constraint(equalToConstant: 30).isActive = true
  }

  @objc private func playPause() {
    _ = activePlayer.flatMap { $0.run($0.playPause) }
    refresh()
  }

  @objc private func nextTrack() {
    _ = activePlayer.flatMap { $0.run($0.next) }
    refresh()
  }

  @objc private func previousTrack() {
    _ = activePlayer.flatMap { $0.run($0.previous) }
    refresh()
  }

  private func seek(to seconds: Double) {
    _ = activePlayer.flatMap { $0.run($0.seek(Int(seconds))) }
    refresh()
  }

  // Previous, play and next share one capsule.
  private func makeTransport() -> NSView {
    let stack = NSStackView(views: [
      transportButton(symbol("backward.fill", "Previous track"), #selector(previousTrack)),
      playPauseButton,
      transportButton(symbol("forward.fill", "Next track"), #selector(nextTrack)),
    ])
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
    stack.wantsLayer = true
    stack.layer?.backgroundColor = NSColor(white: 1, alpha: 0.16).cgColor
    stack.layer?.cornerRadius = 15
    stack.heightAnchor.constraint(equalToConstant: 30).isActive = true
    return stack
  }

  private func transportButton(_ image: NSImage, _ action: Selector) -> NSButton {
    let button = NSButton(image: image, target: self, action: action)
    button.isBordered = false
    button.widthAnchor.constraint(equalToConstant: 38).isActive = true
    return button
  }

  // The app has no Dock icon, so the menu bar item is the way to reopen or quit it.
  private func setUpMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.title = "♪"
    let menu = NSMenu()
    menu.addItem(withTitle: "Show on Touch Bar", action: #selector(present), keyEquivalent: "")
      .target = self
    menu.addItem(
      withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    statusItem?.menu = menu
  }
}

MainActor.assumeIsolated {
  let display = Display()
  NSApplication.shared.delegate = display
  NSApplication.shared.run()
}
