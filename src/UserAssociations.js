
const Promise = require('bluebird')
const _ = require('lodash')
const eventToPromise = require('event-to-promise')
const { asyncLimit } = require('./utils')

const co = Promise.coroutine

// Associations for user class.
class UserAssociations {

  constructor (props) {
    _.defaults(this, props)
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
    let cn = this.echoChannel
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

  socketConnectEcho (id, nconnected) {
    this.transport.sendToChannel(
      id, this.echoChannel, 'socketConnectEcho', id, nconnected)
  }

  socketDisconnectEcho (id, nconnected) {
    this.transport.sendToChannel(
      id, this.echoChannel, 'socketDisconnectEcho', id, nconnected)
  }

  leaveChannel (id, channel) {
    return this.transport.leaveChannel(id, channel).catch(e => {
      let info = { roomName: channel, id, opType: 'transportChannel' }
      return this.consistencyFailure(e, info)
    })
  }

  socketLeaveChannels (id, channels) {
    return Promise.map(
      channels,
      channel => this.leaveChannel(id, channel),
      { concurrency: asyncLimit })
  }

  leaveChannelMessage (id, channel) {
    let bus = this.clusterBus
    return Promise.try(() => {
      bus.emit('roomLeaveSocket', id, channel)
      return eventToPromise(bus, bus.makeSocketRoomLeftName(id, channel))
    }).timeout(this.busAckTimeout).catchReturn()
  }

  channelLeaveSockets (channel, ids) {
    return Promise.map(
      ids,
      id => this.leaveChannelMessage(id, channel),
      { concurrency: asyncLimit })
  }

  rollbackRoomJoin (error, roomName, id) {
    return this.userState.removeSocketFromRoom(id, roomName).catch(e => {
      this.consistencyFailure(e, { roomName, opType: 'userRooms' })
      return [1]
    }).spread(njoined => {
      if (!njoined) {
        return this.leaveRoom(roomName)
      } else {
        return Promise.resolve()
      }
    }).thenThrow(error)
  }

  leaveRoom (roomName) {
    return Promise
      .try(() => this.state.getRoom(roomName))
      .then(room => room.leave(this.userName)
            .catch(error => this.consistencyFailure(
              error, {roomName, opType: 'roomUserlist'})))
      .catchReturn()
  }

  getNotifySettings (roomName) {
    return Promise
      .try(() => this.state.getRoom(roomName))
      .then(room => Promise.join(
        room.roomState.userlistUpdatesGet(),
        room.roomState.accessListsUpdatesGet(),
        (enableUserlistUpdates, enableAccessListsUpdates) =>
          ({ enableUserlistUpdates, enableAccessListsUpdates })))
      .catchReturn({})
  }

  joinSocketToRoom (id, roomName, isLocalCall) {
    let lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, co(function * () {
      let room = yield this.state.getRoom(roomName)
      yield room.join(this.userName)
      let enableUserlistUpdates = yield room.roomState.userlistUpdatesGet()
      return this.userState.addSocketToRoom(id, roomName).then(njoined => {
        return this.transport.joinChannel(id, roomName).then(() => {
          if (njoined === 1 && enableUserlistUpdates) {
            this.userJoinRoomReport(this.userName, roomName)
          }
          return this.socketJoinEcho(id, roomName, njoined, isLocalCall)
        }).return(njoined)
      }).catch(e => this.rollbackRoomJoin(e, roomName, id))
    }).bind(this))
  }

  leaveSocketFromRoom (id, roomName, isLocalCall) {
    let lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, co(function * () {
      let [njoined, hasChanged] =
            yield this.userState.removeSocketFromRoom(id, roomName)
      yield this.leaveChannel(id, roomName)
      if (njoined === 0) {
        yield this.leaveRoom(roomName)
      }
      if (hasChanged) {
        let { enableUserlistUpdates } = yield this.getNotifySettings(roomName)
        this.socketLeftEcho(id, roomName, njoined, isLocalCall)
        this.userLeftRoomReport(this.userName, roomName, enableUserlistUpdates)
      }
      return Promise.resolve(njoined)
    }).bind(this))
  }

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
              if (njoined) { return Promise.resolve() }
              return this.leaveRoom(roomName)
                .then(() => this.getNotifySettings(roomName))
                .then(({enableUserlistUpdates}) => this.userLeftRoomReport(
                  this.userName, roomName, enableUserlistUpdates))
            },
            { concurrency: asyncLimit })
            .then(() => this.socketDisconnectEcho(id, nconnected))
        })
      }).then(() => this.state.removeSocket(id))
  }

  removeSocketFromServer (id) {
    return this.removeUserSocket(id).catch(e => {
      let info = { id, opType: 'userSockets' }
      return this.consistencyFailure(e, info)
    })
  }

  removeUserSocketsFromRoom (roomName) {
    return this.userState.removeAllSocketsFromRoom(roomName).catch(e => {
      let info = { roomName, opType: 'roomUserlist' }
      return this.consistencyFailure(e, info)
    })
  }

  removeFromRoom (roomName) {
    let lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, co(function * () {
      let removedSockets = yield this.removeUserSocketsFromRoom(roomName)
      removedSockets = removedSockets || []
      yield this.channelLeaveSockets(roomName, removedSockets)
      if (removedSockets.length) {
        let { enableUserlistUpdates } = yield this.getNotifySettings(roomName)
        this.userRemovedReport(this.userName, roomName, enableUserlistUpdates)
      }
      return this.leaveRoom(roomName)
    }).bind(this))
  }

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
