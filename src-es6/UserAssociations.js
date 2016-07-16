
const Promise = require('bluebird')
const eventToPromise = require('event-to-promise')
const { asyncLimit } = require('./utils')

// @mixin
//
// Associations for User class.
let UserAssociations = {

  userJoinRoomReport (userName, roomName) {
    return this.transport.emitToChannel(
      roomName, 'roomUserJoined', roomName, userName)
  },

  userLeftRoomReport (userName, roomName) {
    return this.transport.emitToChannel(
      roomName, 'roomUserLeft', roomName, userName)
  },

  userRemovedReport (userName, roomName) {
    this.transport.emitToChannel(
      this.echoChannel, 'roomAccessRemoved', roomName)
    return this.userLeftRoomReport(userName, roomName)
  },

  socketJoinEcho (id, roomName, njoined) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'roomJoinedEcho', roomName, id, njoined)
  },

  socketLeftEcho (id, roomName, njoined) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'roomLeftEcho', roomName, id, njoined)
  },

  socketConnectEcho (id, nconnected) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'socketConnectEcho', id, nconnected)
  },

  socketDisconnectEcho (id, nconnected) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'socketDisconnectEcho', id, nconnected)
  },

  leaveChannel (id, channel) {
    return this.transport.leaveChannel(id, channel).catch(e => {
      let info = { roomName: channel, id, opType: 'transportChannel' }
      return this.consistencyFailure(e, info)
    })
  },

  socketLeaveChannels (id, channels) {
    return Promise.map(
      channels,
      channel => this.leaveChannel(id, channel),
      { concurrency: asyncLimit })
  },

  leaveChannelMessage (id, channel) {
    let bus = this.transport.clusterBus
    return Promise.try(() => {
      bus.emit('roomLeaveSocket', id, channel)
      return eventToPromise(bus, bus.makeSocketRoomLeftName(id, channel))
    }).timeout(this.server.busAckTimeout).catchReturn()
  },

  channelLeaveSockets (channel, ids) {
    return Promise.map(
      ids,
      id => this.leaveChannelMessage(id, channel),
      { concurrency: asyncLimit })
  },

  rollbackRoomJoin (error, roomName, id) {
    return this.userState.removeSocketFromRoom(id, roomName).catch(e => {
      this.consistencyFailure(e, { roomName, opType: 'userRooms' })
      return 1
    }).then(njoined => {
      if (!njoined) {
        return this.leaveRoom(roomName)
      } else {
        return Promise.resolve()
      }
    }).thenThrow(error)
  },

  leaveRoom (roomName) {
    return Promise
      .try(() => this.state.getRoom(roomName))
      .then(room => room.leave(this.userName))
      .catch(e => {
        let info = { roomName, opType: 'roomUserlist' }
        return this.consistencyFailure(e, info)
      })
  },

  joinSocketToRoom (id, roomName) {
    let lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, () => {
      return this.state.getRoom(roomName).then(room => {
        return room.join(this.userName).then(() => {
          return this.userState.addSocketToRoom(id, roomName).then(njoined => {
            return this.transport.joinChannel(id, roomName).then(() => {
              if (njoined === 1) {
                this.userJoinRoomReport(this.userName, roomName)
              }
              return this.socketJoinEcho(id, roomName, njoined)
            }).return(njoined)
          }).catch(e => this.rollbackRoomJoin(e, roomName, id))
        })
      })
    })
  },

  leaveSocketFromRoom (id, roomName) {
    let lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, () => {
      return this.userState.removeSocketFromRoom(id, roomName).then(njoined => {
        return this.leaveChannel(id, roomName).then(() => {
          this.socketLeftEcho(id, roomName, njoined)
          if (!njoined) {
            return this.leaveRoom(roomName)
              .then(() => this.userLeftRoomReport(this.userName, roomName))
          } else {
            return Promise.resolve()
          }
        }).return(njoined)
      })
    })
  },

  removeUserSocket (id) {
    return this.userState.removeSocket(id)
      .spread((roomsRemoved, joinedSockets, nconnected) => {
        roomsRemoved = roomsRemoved || []
        joinedSockets = joinedSockets || []
        nconnected = nconnected || 0
        return this.socketLeaveChannels(id, roomsRemoved).then(() => {
          return Promise.map(
            roomsRemoved,
            (roomName, idx) => {
              let njoined = joinedSockets[idx]
              this.socketLeftEcho(id, roomName, njoined)
              if (!njoined) {
                return this.leaveRoom(roomName)
                  .then(() => this.userLeftRoomReport(this.userName, roomName))
              } else {
                return Promise.resolve()
              }
            },
            { concurrency: asyncLimit })
            .then(() => this.socketDisconnectEcho(id, nconnected))
        })
      }).then(() => this.state.removeSocket(id))
  },

  removeSocketFromServer (id) {
    return this.removeUserSocket(id).catch(e => {
      let info = { id, opType: 'userSockets' }
      return this.consistencyFailure(e, info)
    })
  },

  removeUserSocketsFromRoom (roomName) {
    return this.userState.removeAllSocketsFromRoom(roomName).catch(e => {
      let info = { roomName, opType: 'roomUserlist' }
      return this.consistencyFailure(e, info)
    })
  },

  removeFromRoom (roomName) {
    let lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, () => {
      return this.removeUserSocketsFromRoom(roomName).then((removedSockets) => {
        removedSockets = removedSockets || []
        return this.channelLeaveSockets(roomName, removedSockets).then(() => {
          if (removedSockets.length) {
            this.userRemovedReport(this.userName, roomName)
          }
          return this.leaveRoom(roomName)
        })
      })
    })
  },

  removeRoomUsers (roomName, userNames) {
    userNames = userNames || []
    return Promise.map(
      userNames,
      userName => {
        return this.state.getUser(userName)
          .then(user => user.removeFromRoom(roomName))
          .catchReturn()
      },
      { concurrency: asyncLimit })
  }

}

module.exports = UserAssociations
