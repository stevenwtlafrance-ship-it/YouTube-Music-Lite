import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "yt-music"
  ipcTarget: "yt-music"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var musicStatus: hostWidget ? hostWidget.musicStatus : null

  property bool openedFromHotkey: false
  property bool busy: false
  property bool refreshing: false
  property string statusText: ""

  readonly property string ctlPath: Quickshell.env("HOME") + "/.local/bin/yt-music-ctl"
  readonly property color fg: root.barForeground
  readonly property string fam: root.bar ? root.bar.fontFamily : Style.font.family

  property bool loggedIn: false
  property var playlists: []
  readonly property var playlistOptions: root.playlists.map(function(playlist) {
    return { value: playlist.id, label: playlist.title }
  })
  property var playlistTracks: []
  property string activePlaylistTitle: ""
  property string activePlaylistId: ""
  property var searchResults: []
  property string searchQuery: ""
  property bool searching: false
  property var likedVideoIds: ({})

  function open() {
    statusText = ""
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    root.openedFromHotkey = true
    root.open()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    root.opened ? root.close() : root.openFromHotkey()
  }

  function refresh() {
    if (root.refreshing) return
    root.refreshing = true
    statusProc.running = true
  }

  function parseProcessJson(raw) {
    try {
      return JSON.parse(String(raw || "{}"))
    } catch (e) {
      root.statusText = "Invalid backend response"
      return null
    }
  }

  function loadPlaylists() {
    playlistsProc.running = true
  }

  function openPlaylist(id, title) {
    root.activePlaylistId = id
    root.activePlaylistTitle = title
    root.playlistTracks = []
    root.statusText = ""
    tracksProc.command = [root.ctlPath, "playlist", id]
    tracksProc.running = true
  }

  function playSelectedPlaylist() {
    if (!root.activePlaylistId || root.busy) return
    root.busy = true
    queueProc.command = [root.ctlPath, "queue", root.activePlaylistId]
    queueProc.running = true
  }

  function selectPlaylist(id) {
    for (var i = 0; i < root.playlists.length; i++) {
      if (root.playlists[i].id === id) {
        root.openPlaylist(id, root.playlists[i].title)
        return
      }
    }
  }

  function closePlaylist() {
    root.activePlaylistId = ""
    root.activePlaylistTitle = ""
    root.playlistTracks = []
  }

  function logout() {
    if (root.busy) return
    root.busy = true
    logoutProc.running = true
  }

  function search(query) {
    if (query === undefined || query.trim() === "") return
    root.searchQuery = query.trim()
    root.searchResults = []
    root.searching = true
    searchProc.command = [root.ctlPath, "search", root.searchQuery]
    searchProc.running = true
  }

  function playNow(videoId) {
    if (root.busy) return
    root.busy = true
    playNowProc.command = [root.ctlPath, "play", videoId]
    playNowProc.running = true
  }

  function playMix(videoId) {
    if (root.busy) return
    root.busy = true
    mixProc.command = [root.ctlPath, "mix", videoId]
    mixProc.running = true
  }

  function sendCmd(command, args) {
    if (root.busy) return
    root.busy = true
    statusText = "Sending " + command + "…"
    cmdProc.command = [root.ctlPath, command].concat((args || []).map(String))
    cmdProc.running = true
  }

  function likeCurrent() {
    if (!root.musicStatus || !root.musicStatus.videoId) return
    sendCmd("like", [root.musicStatus.videoId])
  }

  function dislikeCurrent() {
    if (!root.musicStatus || !root.musicStatus.videoId) return
    sendCmd("dislike", [root.musicStatus.videoId])
  }

  // -------------------------------------------------------------- status refresh

  Process {
    id: statusProc
    command: [root.ctlPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (hostWidget && hostWidget.reloadState) hostWidget.reloadState()
      }
    }
    stderr: StdioCollector {
      id: statusErr
      waitForEnd: true
      onStreamFinished: {
        var msg = String(statusErr.text || "").trim()
        if (msg !== "") root.statusText = msg.split("\n")[0]
      }
    }
    onExited: function(exitCode) {
      root.refreshing = false
      if (!root.loggedIn && playlistsProc.state !== Process.Running)
        root.loadPlaylists()
    }
  }

  Process {
    id: playlistsProc
    command: [root.ctlPath, "playlists"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = root.parseProcessJson(text)
        if (data && data.ok) {
          root.loggedIn = true
          root.playlists = data.playlists || []
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg.indexOf("Not logged in") !== -1) {
          root.loggedIn = false
          root.playlists = []
        }
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      root.refreshing = false
    }
  }

  Process {
    id: tracksProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = root.parseProcessJson(text)
        if (data && data.ok) {
          root.playlistTracks = data.tracks || []
          root.activePlaylistTitle = data.title || root.activePlaylistTitle
        }
      }
    }
    onExited: function(exitCode) {
      root.busy = false
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = root.parseProcessJson(text)
        if (data && data.ok && data.query === root.searchQuery) {
          root.searchResults = data.songs || []
          root.searching = false
        }
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.searching = false
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      root.searching = false
    }
  }

  Process {
    id: playNowProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        statusText = "Playing ✓"
        afterCommand.restart()
      } else {
        statusText = "Play failed"
      }
    }
  }

  Process {
    id: mixProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) statusText = "Mix started ✓"
      else statusText = "Mix failed"
    }
  }

  Process {
    id: queueProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data = root.parseProcessJson(text)
        if (data && data.ok)
          root.statusText = "Playing " + (data.title || root.activePlaylistTitle) + " ✓"
        else if (data && data.error)
          root.statusText = data.error
      }
    }
    stderr: StdioCollector {
      id: queueErr
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "") root.statusText = msg.split("\n")[0]
      }
    }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) root.statusText = "Could not play playlist"
      if (exitCode === 0) afterCommand.restart()
    }
  }

  Process {
    id: logoutProc
    command: [root.ctlPath, "logout"]
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        root.loggedIn = false
        root.playlists = []
        root.activePlaylistId = ""
        root.activePlaylistTitle = ""
        root.playlistTracks = []
        root.close()
      }
    }
  }

  Process {
    id: cmdProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      id: cmdErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        statusText = "Command failed"
        return
      }
      var action = String(cmdProc.command[1] || "Command")
      action = action.charAt(0).toUpperCase() + action.slice(1).replace(/-/g, " ")
      statusText = action + " ✓"
      if (action === "Remove" && root.activePlaylistId) {
        tracksProc.command = [root.ctlPath, "playlist", root.activePlaylistId]
        tracksProc.running = true
      }
      afterCommand.restart()
    }
  }

  Timer {
    id: afterCommand
    interval: 1600
    onTriggered: root.refresh()
  }

  Timer {
    id: autoRefresh
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: searchDebounce
    interval: 450
    repeat: false
    onTriggered: root.search(searchField.text)
  }

  Menu {
    id: trackMenu
    property string videoId: ""

    MenuItem {
      text: "Remove from playlist"
      onTriggered: root.sendCmd("remove", [root.activePlaylistId, trackMenu.videoId])
    }
  }

  Component.onCompleted: root.loadPlaylists()

  // ---------------------------------------------------------------- surface

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
     contentWidth: 540
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "c") root.close()
        else if (t === "l") root.loadPlaylists()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: Math.min(panelFlick.width - Style.space(40), Style.space(540))
          x: Math.max(0, (panelFlick.width - width) / 2)
          spacing: Style.spacing.panelGap

          // ---- not logged in
          Rectangle {
            visible: !root.loggedIn
            width: parent.width
            height: Style.space(120)
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.fg, Color.accent)

            Column {
              anchors.centerIn: parent
              width: parent.width - Style.space(64)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: Model.ICON.music
                color: root.fg
                font.family: root.fam
                font.pixelSize: Style.font.displayLarge
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.loggedIn ? "" : "Not logged in"
                color: root.fg
                font.family: root.fam
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Click below to open browser and log into YouTube Music.\nRun  yt-music-ctl login  in a terminal afterwards if needed."
                color: Qt.darker(root.fg, 1.4)
                font.family: root.fam
                font.pixelSize: Style.font.bodySmall
              }
              Button {
                anchors.horizontalCenter: parent.horizontalCenter
                height: Style.spacing.controlHeight
                iconText: Model.ICON.login
                text: "Login to YouTube Music"
                fontFamily: root.fam
                fontSize: Style.font.bodySmall
                foreground: root.fg
                onClicked: {
                  root.close()
                  if (root.bar) root.bar.run("omarchy-launch-terminal yt-music-ctl login")
                }
              }
            }
          }

          // ---- now playing hero
            Rectangle {
              id: nowPlayingCard
              visible: Model.isActive(root.musicStatus)
              width: parent.width
              height: Style.space(136)
              radius: Style.cornerRadius
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)

              Item {
              id: heroRow
              anchors.fill: parent

              Rectangle {
                id: albumArt
                width: Style.space(96)
                height: Style.space(96)
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.cornerRadius
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
                clip: true

                Image {
                  id: albumImage
                  anchors.fill: parent
                  source: root.musicStatus && root.musicStatus.videoId
                    ? "https://i.ytimg.com/vi/" + root.musicStatus.videoId + "/hqdefault.jpg"
                    : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                }

                Text {
                  anchors.centerIn: parent
                  visible: albumImage.status !== Image.Ready
                  text: Model.ICON.note
                  color: Color.accent
                  font.family: root.fam
                  font.pixelSize: Style.font.displayLarge
                }
              }

              Row {
                id: heroActions
                anchors.right: parent.right
                anchors.rightMargin: Style.space(14)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(20)
                spacing: Style.space(6)

                Item {
                  width: Style.space(28)
                  height: Style.space(32)
                  Text {
                    anchors.centerIn: parent
                    text: Model.ICON.prev
                    color: root.fg
                    font.family: root.fam
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sendCmd("prev", [])
                  }
                }

                Item {
                  width: Style.space(28)
                  height: Style.space(32)
                  Text {
                    anchors.centerIn: parent
                    text: root.musicStatus && root.musicStatus.paused ? Model.ICON.play : Model.ICON.pause
                    color: root.fg
                    font.family: root.fam
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sendCmd("toggle", [])
                  }
                }

                Item {
                  width: Style.space(28)
                  height: Style.space(32)
                  Text {
                    anchors.centerIn: parent
                    text: Model.ICON.next
                    color: root.fg
                    font.family: root.fam
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sendCmd("next", [])
                  }
                }

                Item {
                  width: Style.space(28)
                  height: Style.space(32)
                  Text {
                    anchors.centerIn: parent
                    text: Model.ICON.like
                    color: Color.accent
                    font.family: root.fam
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.likeCurrent()
                  }
                }

                Item {
                  width: Style.space(28)
                  height: Style.space(32)
                  Text {
                    anchors.centerIn: parent
                    text: Model.ICON.dislike
                    color: root.fg
                    font.family: root.fam
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dislikeCurrent()
                  }
                }

                Item {
                  width: Style.space(28)
                  height: Style.space(32)
                  Text {
                    anchors.centerIn: parent
                    text: Model.ICON.shuffle
                    color: root.fg
                    font.family: root.fam
                    font.pixelSize: Style.font.body
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sendCmd("shuffle", [])
                  }
                }
              }

              Text {
                anchors.left: albumArt.right
                anchors.leftMargin: Style.space(18)
                anchors.right: heroActions.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: heroActions.verticalCenter
                textFormat: Text.PlainText
                text: root.musicStatus
                  ? Model.fmtPosition(root.musicStatus.position || 0, root.musicStatus.duration || 0)
                  : ""
                color: Qt.darker(root.fg, 1.4)
                font.family: root.fam
                font.pixelSize: Style.font.caption
              }

              Column {
                anchors.left: albumArt.right
                anchors.leftMargin: Style.space(18)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(18)
                anchors.top: parent.top
                anchors.topMargin: Style.space(18)
                anchors.bottom: heroActions.top
                anchors.bottomMargin: Style.space(4)
                spacing: Style.space(3)

                Text {
                  textFormat: Text.PlainText
                  text: "NOW PLAYING"
                  color: Color.accent
                  font.family: root.fam
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: root.musicStatus ? (root.musicStatus.title || "") : ""
                  color: root.fg
                  font.family: root.fam
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: root.musicStatus ? (root.musicStatus.artist || "") : ""
                  color: Qt.darker(root.fg, 1.4)
                  font.family: root.fam
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Rectangle {
                anchors.left: albumArt.right
                anchors.leftMargin: Style.space(18)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(18)
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(10)
                height: Style.space(3)
                radius: height / 2
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

                Rectangle {
                  width: parent.width * (root.musicStatus && root.musicStatus.duration > 0
                    ? Math.min(1, Math.max(0, root.musicStatus.position / root.musicStatus.duration))
                    : 0)
                  height: parent.height
                  radius: height / 2
                  color: Color.accent
                }
              }
            }
          }

            // ---- search
            Item {
              width: parent.width
              height: Style.spacing.controlHeight

              Row {
                width: parent.width - Style.space(40)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.spacing.sm

                TextField {
                  id: searchField
                  width: parent.width - Style.space(132) - Style.spacing.sm * 3
                  height: Style.spacing.controlHeight
                  placeholderText: "Lookup tunes..."
                  horizontalAlignment: Text.AlignHCenter
                  foreground: root.fg
                  hasCursor: false
                  onTextChanged: {
                    var query = text.trim()
                    root.searchQuery = query
                    root.searchResults = []
                    root.searching = query !== ""
                    if (query === "") {
                      searchDebounce.stop()
                    } else {
                      searchDebounce.restart()
                    }
                  }
                  onAccepted: root.search(text)
                }
                Button {
                  width: Style.space(44)
                  height: Style.spacing.controlHeight
                  iconText: Model.ICON.search
                  tooltipText: "Search"
                  fontFamily: root.fam
                  foreground: root.fg
                  enabled: !root.busy
                  onClicked: root.search(searchField.text)
                }
                Button {
                  width: Style.space(44)
                  height: Style.spacing.controlHeight
                  iconText: Model.ICON.close
                  tooltipText: "Clear lookup"
                  fontFamily: root.fam
                  foreground: root.fg
                  visible: searchField.text !== "" || root.searchQuery !== "" || root.searching || root.searchResults.length > 0
                  onClicked: {
                    searchField.text = ""
                    root.searchQuery = ""
                    root.searchResults = []
                    root.searching = false
                  }
                }
                Button {
                  width: Style.space(44)
                  height: Style.spacing.controlHeight
                  iconText: Model.ICON.logout
                  tooltipText: "Log out"
                  fontFamily: root.fam
                  foreground: root.fg
                  visible: root.loggedIn
                  enabled: !root.busy
                  onClicked: root.logout()
                }
              }
            }

          // ---- search results
          Column {
            visible: root.searchResults.length > 0 || root.searching
            width: parent.width
            spacing: Style.spacing.panelGap

            PanelSectionHeader {
              text: "SEARCH RESULTS — " + root.searchQuery.toUpperCase()
              foreground: root.fg
              fontFamily: root.fam
            }

            Text {
              visible: root.searching
              textFormat: Text.PlainText
              text: "Searching…"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fam
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.searchResults
              delegate: Item {
                width: contentColumn.width
                height: Style.space(40)

                Row {
                  anchors.fill: parent
                  spacing: Style.spacing.sm

                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(24)
                    text: Model.ICON.note
                    color: Color.accent
                    font.family: root.fam
                    font.pixelSize: Style.font.bodySmall
                    verticalAlignment: Text.AlignVCenter
                  }

                  Column {
                    width: parent.width - Style.space(24) - Style.space(180)
                    spacing: 0

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: modelData.title
                      color: root.fg
                      font.family: root.fam
                      font.pixelSize: Style.font.bodySmall
                    }
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: modelData.artist
                      color: Qt.darker(root.fg, 1.4)
                      font.family: root.fam
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(80)
                    text: Model.fmtDuration(modelData.duration)
                    horizontalAlignment: Text.AlignRight
                    color: Qt.darker(root.fg, 1.4)
                    font.family: root.fam
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                  }

                  Button {
                    width: Style.space(52)
                    height: Style.space(28)
                    iconText: Model.ICON.play
                    tooltipText: "Play"
                    fontFamily: root.fam
                    foreground: root.fg
                    enabled: !root.busy
                    onClicked: root.playNow(modelData.videoId)
                  }

                  Button {
                    width: Style.space(44)
                    height: Style.space(28)
                    iconText: Model.ICON.shuffle
                    tooltipText: "Start mix"
                    fontFamily: root.fam
                    foreground: root.fg
                    enabled: !root.busy
                    onClicked: root.playMix(modelData.videoId)
                  }
                }
              }
            }
          }

          // ---- playlists
          Column {
            visible: root.loggedIn
            width: parent.width
            spacing: Style.spacing.panelGap

            Item {
              width: parent.width
              height: Style.space(24)

              PanelSectionHeader {
                anchors.centerIn: parent
                text: "PLAYLISTS"
                foreground: root.fg
                fontFamily: root.fam
              }
            }

            Item {
              width: parent.width
              height: Style.spacing.controlHeight

              Dropdown {
                width: parent.width - Style.space(40)
                anchors.horizontalCenter: parent.horizontalCenter
                label: ""
                showLabel: false
                options: root.playlistOptions
                value: root.activePlaylistId
                foreground: root.fg
                fontFamily: root.fam
                onChanged: function(selectedValue) { root.selectPlaylist(selectedValue) }
              }
            }
           }

            // ---- playlist tracks view
          Column {
            visible: root.playlistTracks.length > 0
            width: parent.width
            spacing: Style.spacing.panelGap

            Item {
              width: parent.width
              height: Style.space(24)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.activePlaylistTitle.toUpperCase() + " (" + root.playlistTracks.length + ")"
                color: root.fg
                font.family: root.fam
                font.pixelSize: Style.font.caption
                font.bold: true
                verticalAlignment: Text.AlignVCenter
              }

              Button {
                id: playPlaylistButton
                anchors.right: closePlaylistButton.left
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(32)
                height: Style.space(24)
                iconText: Model.ICON.play
                tooltipText: "Play playlist"
                fontFamily: root.fam
                foreground: Color.accent
                onClicked: root.playSelectedPlaylist()
              }

              Button {
                id: closePlaylistButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(32)
                height: Style.space(24)
                iconText: Model.ICON.close
                tooltipText: "Close playlist"
                fontFamily: root.fam
                foreground: root.fg
                onClicked: root.closePlaylist()
              }
            }

            Repeater {
              model: root.playlistTracks
              delegate: Item {
                id: trackRow
                width: contentColumn.width
                height: Style.space(36)

                Row {
                  anchors.fill: parent
                  spacing: Style.spacing.sm

                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(20)
                    text: index + 1
                    color: Qt.darker(root.fg, 1.4)
                    font.family: root.fam
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                  }

                  Column {
                    width: parent.width - Style.space(20) - Style.space(200)
                    spacing: 0

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: modelData.title
                      color: root.fg
                      font.family: root.fam
                      font.pixelSize: Style.font.bodySmall
                    }
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      elide: Text.ElideRight
                      text: modelData.artist
                      color: Qt.darker(root.fg, 1.4)
                      font.family: root.fam
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(64)
                    text: Model.fmtDuration(modelData.duration)
                    horizontalAlignment: Text.AlignRight
                    color: Qt.darker(root.fg, 1.4)
                    font.family: root.fam
                    font.pixelSize: Style.font.caption
                    verticalAlignment: Text.AlignVCenter
                  }

                  Button {
                    width: Style.space(52)
                    height: Style.space(28)
                    iconText: Model.ICON.play
                    tooltipText: "Play"
                    fontFamily: root.fam
                    foreground: root.fg
                    enabled: !root.busy
                    onClicked: root.playNow(modelData.videoId)
                  }

                  Button {
                    width: Style.space(44)
                    height: Style.space(28)
                    iconText: Model.ICON.shuffle
                    tooltipText: "Start mix"
                    fontFamily: root.fam
                    foreground: root.fg
                    enabled: !root.busy
                    onClicked: root.playMix(modelData.videoId)
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.RightButton
                  onClicked: function(mouse) {
                    trackMenu.videoId = modelData.videoId
                    var point = trackRow.mapToItem(panelFlick, mouse.x, mouse.y)
                    trackMenu.popup(panelFlick, point.x, point.y)
                    mouse.accepted = true
                  }
                }
              }
            }
          }

        }
      }
    }
  }
}
