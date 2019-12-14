'use strict'

const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const UserReports = require('./UserReports')
const _ = require('lodash')
const eventToPromise = require('event-to-promise')
const { asyncLimit, execHook, mixin, run } = require('./utils')

const co = Promise.coroutine

// Associations for user class.
class UserAssociations {
  constructor (props) {
    _.defaults(this, props)
    this.busAckTimeout = this.server.busAckTimeout
    this.clusterBus = this.server.clusterBus
    this.onJoin = this.server.hooks.onJoin
    this.onLeave = this.server.hooks.onLeave
    this.lockTTL = this.state.lockTTL
    mixin(this, UserReports, this.transport, this.echoChannel)
  }

  consistencyFailure (error, operationInfo) {
    operationInfo.userName = this.userName
    const name = operationInfo.opType === 'transportChannel'
      ? 'transportConsistencyFailure'
      : 'storeConsistencyFailure'
    this.server.emit(name, error, operationInfo)
  }

  leaveChannel (id, channel) {
    return this.transport.leaveChannel(id, channel).catch(e => {
      const info = { roomName: channel, id, opType: 'transportChannel' }
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
    const bus = this.clusterBus
    return Promise.try(() => {
      bus.emit('roomLeaveSocket', id, channel)
      const ackEventName = `socketRoomLeft:${id}:${channel}`
      return eventToPromise(bus, ackEventName)
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
      }
    }).thenThrow(error)
  }

  leaveRoom (roomName) {
    return Promise
      .try(() => this.state.getRoom(roomName))
      .then(room => room.leave(this.userName).catch(error => {
        this.consistencyFailure(error, { roomName, opType: 'roomUserlist' })
      }))
      .catchReturn()
  }

  getNotifySettings (roomName) {
    return Promise
      .try(() => this.state.getRoom(roomName))
      .then(room => room.getNotificationsInfo(null, true))
      .catchReturn({})
  }

  joinSocketToRoom (id, roomName, isLocalCall) {
    const lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, co(function * () {
      const room = yield this.state.getRoom(roomName)
      yield room.join(this.userName)
      try {
        const [enableUserlistUpdates, [njoined, hasChanged]] = yield Promise.all([
          room.roomState.userlistUpdatesGet(),
          this.userState.addSocketToRoom(id, roomName),
          this.transport.joinChannel(id, roomName)])
        if (hasChanged) {
          if (this.onJoin) {
            yield execHook(this.onJoin, this.server, { id, roomName, njoined })
          }
          if (njoined === 1 && enableUserlistUpdates) {
            this.userJoinRoomReport(this.userName, roomName)
          }
          this.socketJoinEcho(id, roomName, njoined, isLocalCall)
        }
        return njoined
      } catch (e) {
        yield this.rollbackRoomJoin(e, roomName, id)
      }
    }).bind(this))
  }

  leaveSocketFromRoom (id, roomName, isLocalCall) {
    const lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, co(function * () {
      const [{ enableUserlistUpdates }, [njoined, hasChanged]] = yield Promise.all([
        this.getNotifySettings(roomName),
        this.userState.removeSocketFromRoom(id, roomName),
        this.leaveChannel(id, roomName)])
      if (njoined === 0) {
        yield this.leaveRoom(roomName)
      }
      if (hasChanged) {
        this.socketLeftEcho(id, roomName, njoined, isLocalCall)
        this.userLeftRoomReport(this.userName, roomName, enableUserlistUpdates)
        if (this.onLeave) {
          yield execHook(this.onLeave, this.server, { id, roomName, njoined })
            .catchReturn(Promise.resolve())
        }
      }
      return njoined
    }).bind(this))
  }

  addUserSocket (id) {
    return this.state.addSocket(id, this.userName)
      .then(() => this.userState.addSocket(id, this.server.instanceUID))
      .then(nconnected => {
        if (!this.transport.getSocket(id)) {
          return this.removeUserSocket(id).then(() => {
            const error = new ChatServiceError('noSocket', 'connection')
            return Promise.reject(error)
          })
        } else {
          return nconnected
        }
      })
  }

  removeUserSocket (id) {
    return run(this, function * () {
      let [roomsRemoved, joinedSockets, nconnected] =
            yield this.userState.removeSocket(id)
      roomsRemoved = roomsRemoved || []
      joinedSockets = joinedSockets || []
      nconnected = nconnected || 0
      yield this.socketLeaveChannels(id, roomsRemoved)
      yield Promise.map(roomsRemoved, co(function * (roomName, idx) {
        const njoined = joinedSockets[idx]
        if (this.onLeave) {
          yield execHook(this.onLeave, this.server, { id, roomName, njoined })
            .catchReturn(Promise.resolve())
        }
        this.socketLeftEcho(id, roomName, njoined)
        if (njoined) { return }
        yield this.leaveRoom(roomName)
        const { enableUserlistUpdates } = yield this.getNotifySettings(roomName)
        this.userLeftRoomReport(this.userName, roomName, enableUserlistUpdates)
      }).bind(this), { concurrency: asyncLimit })
      this.socketDisconnectEcho(id, nconnected)
      yield this.state.removeSocket(id)
      return { roomsRemoved, joinedSockets, nconnected }
    }).catch(e => {
      const info = { id, opType: 'userSockets' }
      return this.consistencyFailure(e, info)
    })
  }

  removeUserSocketsFromRoom (roomName) {
    return this.userState.removeAllSocketsFromRoom(roomName).catch(e => {
      const info = { roomName, opType: 'roomUserlist' }
      return this.consistencyFailure(e, info)
    })
  }

  removeFromRoom (roomName) {
    const lock = this.userState.lockToRoom(roomName, this.lockTTL)
    return Promise.using(lock, co(function * () {
      let removedSockets = yield this.removeUserSocketsFromRoom(roomName)
      removedSockets = removedSockets || []
      yield this.channelLeaveSockets(roomName, removedSockets)
      if (removedSockets.length) {
        if (this.onLeave) {
          yield Promise.map(removedSockets, (id) => {
            return execHook(this.onLeave, this.server, { id, roomName, njoined: 0 })
              .catchReturn(Promise.resolve())
          }, { concurrency: asyncLimit })
        }
        const { enableUserlistUpdates } = yield this.getNotifySettings(roomName)
        this.userRemovedReport(this.userName, roomName, enableUserlistUpdates)
      }
      return this.leaveRoom(roomName)
    }).bind(this))
  }

  removeRoomUsers (roomName, userNames) {
    userNames = userNames || []
    return Promise.map(userNames, userName => {
      return this.state.getUser(userName)
        .then(user => user.removeFromRoom(roomName))
        .catchReturn()
    }, { concurrency: asyncLimit })
  }
}

module.exports = UserAssociations
