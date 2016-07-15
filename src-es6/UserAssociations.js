
const Promise = require('bluebird')
const eventToPromise = require('event-to-promise')
const { asyncLimit } = require('./utils')

// @private
// @nodoc
// @mixin
//
// Associations for User class.
let UserAssociations = {

  // @private
  userJoinRoomReport (userName, roomName) {
    return this.transport.emitToChannel(
      roomName, 'roomUserJoined', roomName, userName)
  },

  // @private
  userLeftRoomReport (userName, roomName) {
    return this.transport.emitToChannel(
      roomName, 'roomUserLeft', roomName, userName)
  },

  // @private
  userRemovedReport (userName, roomName) {
    this.transport.emitToChannel(
      this.echoChannel, 'roomAccessRemoved', roomName)
    return this.userLeftRoomReport(userName, roomName)
  },

  // @private
  socketJoinEcho (id, roomName, njoined) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'roomJoinedEcho', roomName, id, njoined)
  },

  // @private
  socketLeftEcho (id, roomName, njoined) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'roomLeftEcho', roomName, id, njoined)
  },

  // @private
  socketConnectEcho (id, nconnected) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'socketConnectEcho', id, nconnected)
  },

  // @private
  socketDisconnectEcho (id, nconnected) {
    return this.transport.sendToChannel(
      id, this.echoChannel, 'socketDisconnectEcho', id, nconnected)
  },

  // @private
  leaveChannel (id, channel) {
    return this.transport.leaveChannel(id, channel).catch(e => {
      let info = { roomName: channel, id, opType: 'transportChannel' }
      return this.consistencyFailure(e, info)
    })
  },

  // @private
  socketLeaveChannels (id, channels) {
    return Promise.map(
      channels,
      channel => this.leaveChannel(id, channel),
      { concurrency: asyncLimit })
  },

  // @private
  leaveChannelMessage (id, channel) {
    let bus = this.transport.clusterBus
    return Promise.try(() => {
      bus.emit('roomLeaveSocket', id, channel)
      return eventToPromise(bus, bus.makeSocketRoomLeftName(id, channel))
    }).timeout(this.server.busAckTimeout).catchReturn()
  },

  // @private
  channelLeaveSockets (channel, ids) {
    return Promise.map(
      ids,
      id => this.leaveChannelMessage(id, channel),
      { concurrency: asyncLimit })
  },

  // @private
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

  // @private
  leaveRoom (roomName) {
    return Promise
      .try(() => this.state.getRoom(roomName))
      .then(room => room.leave(this.userName))
      .catch(e => {
        let info = { roomName, opType: 'roomUserlist' }
        return this.consistencyFailure(e, info)
      })
  },

  // @private
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

  // @private
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

  // @private
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

  // @private
  removeSocketFromServer (id) {
    return this.removeUserSocket(id).catch(e => {
      let info = { id, opType: 'userSockets' }
      return this.consistencyFailure(e, info)
    })
  },

  // @private
  removeUserSocketsFromRoom (roomName) {
    return this.userState.removeAllSocketsFromRoom(roomName).catch(e => {
      let info = { roomName, opType: 'roomUserlist' }
      return this.consistencyFailure(e, info)
    })
  },

  // @private
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

  // @private
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
