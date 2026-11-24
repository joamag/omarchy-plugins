import QtQuick
import QtMultimedia
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The large preview's player for a video or a song: the picture (a song
// shows its cover and tags), play and pause, the time and a bar to seek
// with. It lives in its own file, loaded only when one is previewed, so the
// widget still works where Qt Multimedia is not installed.
Item {
  id: media

  property string path: ""
  property bool video: true
  // The thumbnailer's still of the video, or the song's cover.
  property string still: ""
  property string name: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
  readonly property real duration: player.duration
  readonly property bool failed: player.error !== MediaPlayer.NoError

  function toggle() {
    if (playing) player.pause()
    else player.play()
  }

  MediaPlayer {
    id: player
    source: media.path !== "" ? Model.fileUrl(media.path) : ""
    videoOutput: media.video ? videoOut : null
    audioOutput: AudioOutput {}
  }

  Item {
    id: picture
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: controls.top
    anchors.bottomMargin: Style.space(10)

    VideoOutput {
      id: videoOut
      anchors.fill: parent
      visible: media.video
      fillMode: VideoOutput.PreserveAspectFit
    }

    // The still stands in until the video first plays.
    SizedImage {
      anchors.fill: parent
      visible: media.video && media.still !== "" && player.position === 0 && !media.playing
      url: media.still !== "" ? Model.fileUrl(media.still) : ""
    }

    Row {
      visible: !media.video
      anchors.centerIn: parent
      spacing: Style.space(28)

      Item {
        id: cover
        width: Math.min(Style.space(240), picture.height)
        height: width

        SizedImage {
          anchors.fill: parent
          visible: media.still !== ""
          url: media.still !== "" ? Model.fileUrl(media.still) : ""
        }

        Text {
          anchors.centerIn: parent
          visible: media.still === ""
          textFormat: Text.PlainText
          text: Model.kindIcon("audio")
          color: media.foreground
          opacity: 0.6
          font.family: media.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(Style.space(320), picture.width - cover.width - parent.spacing)
        spacing: Style.space(6)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: player.metaData.stringValue(MediaMetaData.Title) || media.name
          color: media.foreground
          font.family: media.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WrapAnywhere
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: [player.metaData.stringValue(MediaMetaData.ContributingArtist), player.metaData.stringValue(MediaMetaData.AlbumTitle)].filter(function(s) { return s !== "" }).join(" · ")
          color: media.foreground
          opacity: 0.6
          font.family: media.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }

    // Paused, a video shows what a click does.
    Rectangle {
      visible: media.video && !media.playing && !media.failed
      anchors.centerIn: parent
      width: Style.space(64)
      height: width
      radius: width / 2
      color: Qt.rgba(0, 0, 0, 0.55)
      border.width: 1
      border.color: Color.accent

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "󰐊"
        color: media.foreground
        font.family: media.fontFamily
        font.pixelSize: Style.font.title
      }
    }

    Text {
      visible: media.failed
      anchors.centerIn: parent
      width: parent.width - Style.space(40)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: "Cannot play it: " + player.errorString
      color: media.foreground
      opacity: 0.6
      font.family: media.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }

    MouseArea {
      anchors.fill: parent
      enabled: !media.failed
      cursorShape: Qt.PointingHandCursor
      onClicked: media.toggle()
    }
  }

  // Play or pause, where it is, the bar to seek with, and how long it lasts.
  Row {
    id: controls
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Style.spacing.controlHeight
    spacing: Style.space(10)

    Button {
      width: Style.spacing.controlHeight
      height: Style.spacing.controlHeight
      iconText: media.playing ? "󰏤" : "󰐊"
      iconSize: Style.font.title
      tooltipText: media.playing ? "Pause (p)" : "Play (p)"
      foreground: media.foreground
      fontFamily: media.fontFamily
      horizontalPadding: 0
      verticalPadding: 0
      bordered: true
      enabled: !media.failed
      onClicked: media.toggle()
    }

    Text {
      id: elapsed
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Model.formatDuration(player.position)
      color: media.foreground
      font.family: media.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: controls.width - Style.spacing.controlHeight - elapsed.width - total.width - controls.spacing * 3
      height: Style.space(16)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Style.space(4)
        color: Qt.rgba(media.foreground.r, media.foreground.g, media.foreground.b, 0.18)

        Rectangle {
          height: parent.height
          width: media.duration > 0 ? parent.width * Math.min(1, player.position / media.duration) : 0
          color: Color.accent
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: media.duration > 0
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) { player.setPosition(Math.round(media.duration * Math.max(0, Math.min(1, mouse.x / width)))) }
      }
    }

    Text {
      id: total
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Model.formatDuration(media.duration)
      color: media.foreground
      opacity: 0.6
      font.family: media.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
