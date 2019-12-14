'use strict'

// Notification reporting for user class.
class UserReports {
  constructor (transport, echoChannel) {
    this.transport = transport
    this.echoChannel = echoChannel
  }

  userJoinRoomReport (userName, roomName) {
    this.transport.emitToChannel(roomName, 'roomUserJoined', roomName, userName)
  }

  userLeftRoomReport (userName, roomName, enableUserlistUpdates) {
    if (enableUserlistUpdates) {
      this.transport.emitToChannel(roomName, 'roomUserLeft', roomName, userName)
    }
  }

  userRemovedReport (userName, roomName, enableUserlistUpdates) {
    const cn = this.echoChannel
    this.transport.emitToChannel(cn, 'roomAccessRemoved', roomName)
    this.userLeftRoomReport(userName, roomName, enableUserlistUpdates)
  }

  socketJoinEcho (id, roomName, njoined, isLocalCall) {
    if (isLocalCall) {
      this.transport.emitToChannel(
        this.echoChannel, 'roomJoinedEcho', roomName, id, njoined)
    } else {
      this.transport.sendToChannel(
        id, this.echoChannel, 'roomJoinedEcho', roomName, id, njoined)
    }
  }

  socketLeftEcho (id, roomName, njoined, isLocalCall) {
    if (isLocalCall) {
      this.transport.emitToChannel(
        this.echoChannel, 'roomLeftEcho', roomName, id, njoined)
    } else {
      this.transport.sendToChannel(
        id, this.echoChannel, 'roomLeftEcho', roomName, id, njoined)
    }
  }

  socketDisconnectEcho (id, nconnected) {
    this.transport.sendToChannel(
      id, this.echoChannel, 'socketDisconnectEcho', id, nconnected)
  }
}

module.exports = UserReports
