'use strict'

const ChatServiceError = require('./ChatServiceError')
const CommandBinder = require('./CommandBinder')
const DirectMessaging = require('./DirectMessaging')
const Promise = require('bluebird')
const UserAssociations = require('./UserAssociations')
const _ = require('lodash')
const { asyncLimit, checkNameSymbols, mixin, run } = require('./utils')

// Client commands implementation.
class User {
  constructor (server, userName) {
    this.server = server
    this.userName = userName
    this.echoChannel = `echo:${this.userName}`
    this.state = this.server.state
    this.transport = this.server.transport
    this.enableRoomsManagement = this.server.enableRoomsManagement
    this.enableDirectMessages = this.server.enableDirectMessages
    this.directMessaging = new DirectMessaging(server, userName)
    const State = this.server.state.UserState
    this.userState = new State(this.server, this.userName)
    this.commandBinder =
      new CommandBinder(this.server, this.transport, this.userName)
    const opts = {
      server,
      echoChannel: this.echoChannel,
      state: this.state,
      transport: this.transport,
      userName: this.userName,
      userState: this.userState
    }
    mixin(this, UserAssociations, opts)
  }

  // utils

  initState (state) {
    return this.directMessaging.initState(state)
  }

  removeState () {
    return this.directMessaging.removeState()
  }

  checkOnline () {
    return this.userState.getAllSockets().then(sockets => {
      if (!sockets || !sockets.length) {
        const error = new ChatServiceError('noUserOnline', this.userName)
        return Promise.reject(error)
      }
    })
  }

  processMessage (msg, setTimestamp = false) {
    delete msg.id
    delete msg.timestamp
    if (setTimestamp) {
      msg.timestamp = _.now()
    }
    msg.author = this.userName || msg.author
    return msg
  }

  exec (command, options, args) {
    const { id } = options
    const requestsNames = this.server.rpcRequestsNames
    if (!_.includes(requestsNames, command)) {
      const error = new ChatServiceError('noCommand', command)
      return Promise.reject(error)
    }
    const requiresSocket = command === 'roomJoin' || command === 'roomLeave'
    if (!id && requiresSocket) {
      const error = new ChatServiceError('noSocket', command)
      return Promise.reject(error)
    }
    const fn = this[command].bind(this)
    const cmd = this.commandBinder.makeCommand(command, fn)
    return cmd(args, options)
  }

  registerSocket (id) {
    return run(this, function * () {
      const nconnected = yield this.addUserSocket(id, this.userName)
      const commands = this.server.rpcRequestsNames
      for (const cmd of commands) {
        this.commandBinder.bindCommand(id, cmd, this[cmd].bind(this))
      }
      this.commandBinder.bindDisconnect(id, this.removeSocket.bind(this))
      yield this.transport.joinChannel(id, this.echoChannel)
      this.transport.sendToChannel(
        id, this.echoChannel, 'socketConnectEcho', id, nconnected)
    })
  }

  removeSocket (id) {
    return this.removeUserSocket(id)
  }

  // RPC handlers

  disconnectInstanceSockets () {
    return this.userState.getAllSockets().then(sockets => {
      return Promise.map(
        sockets,
        sid => this.transport.disconnectSocket(sid),
        { concurrency: asyncLimit })
    })
  }

  directAddToList (listName, values) {
    return this.directMessaging.addToList(this.userName, listName, values)
      .return()
  }

  directGetAccessList (listName) {
    return this.directMessaging.getList(this.userName, listName)
  }

  directGetWhitelistMode () {
    return this.directMessaging.getMode(this.userName)
  }

  directMessage (recipientName, msg, { id, bypassPermissions }) {
    if (!this.enableDirectMessages) {
      const error = new ChatServiceError('notAllowed')
      return Promise.reject(error)
    }
    this.processMessage(msg, true)
    return this.server.state.getUser(recipientName).then(recipient => {
      const channel = recipient.echoChannel
      return recipient.directMessaging
        .message(this.userName, msg, bypassPermissions)
        .then(() => recipient.checkOnline())
        .then(() => {
          this.transport.emitToChannel(channel, 'directMessage', msg)
          this.transport.sendToChannel(
            id, this.echoChannel, 'directMessageEcho', recipientName, msg)
          return msg
        })
    })
  }

  directRemoveFromList (listName, values) {
    return this.directMessaging.removeFromList(this.userName, listName, values)
      .return()
  }

  directSetWhitelistMode (mode) {
    return this.directMessaging.changeMode(this.userName, mode).return()
  }

  listOwnSockets () {
    return this.userState.getSocketsToRooms()
  }

  roomAddToList (roomName, listName, values, { bypassPermissions }) {
    return this.state.getRoom(roomName).then(room => {
      return Promise.join(
        room.addToList(this.userName, listName, values, bypassPermissions),
        room.roomState.accessListsUpdatesGet(),
        (userNames, update) => {
          if (update) {
            this.transport.emitToChannel(
              roomName, 'roomAccessListAdded', roomName, listName, values)
          }
          return this.removeRoomUsers(roomName, userNames)
        })
    }).return()
  }

  roomCreate (roomName, whitelistOnly, { bypassPermissions }) {
    if (!this.enableRoomsManagement && !bypassPermissions) {
      const error = new ChatServiceError('notAllowed')
      return Promise.reject(error)
    }
    const owner = this.userName
    return checkNameSymbols(roomName)
      .then(() => this.state.addRoom(roomName, { owner, whitelistOnly }))
      .return()
  }

  roomDelete (roomName, { bypassPermissions }) {
    if (!this.enableRoomsManagement && !bypassPermissions) {
      const error = new ChatServiceError('notAllowed')
      return Promise.reject(error)
    }
    return this.state.getRoom(roomName).then(room => {
      return room.checkIsOwner(this.userName, bypassPermissions)
        .then(() => room.startRemoving())
        .then(() => room.getUsers())
        .then(userNames => this.removeRoomUsers(roomName, userNames))
        .then(() => this.state.removeRoom(roomName))
        .then(() => room.removeState())
        .return()
    })
  }

  roomGetAccessList (roomName, listName, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.getList(this.userName, listName, bypassPermissions))
  }

  roomGetOwner (roomName, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.getOwner(this.userName, bypassPermissions))
  }

  roomGetWhitelistMode (roomName, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.getMode(this.userName, bypassPermissions))
  }

  roomRecentHistory (roomName, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.getRecentMessages(this.userName, bypassPermissions))
  }

  roomHistoryGet (roomName, msgid, limit, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.getMessages(
        this.userName, msgid, limit, bypassPermissions))
  }

  roomHistoryInfo (roomName, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.getHistoryInfo(this.userName, bypassPermissions))
  }

  roomJoin (roomName, { id, isLocalCall }) {
    return this.state.getRoom(roomName)
      .then(room => this.joinSocketToRoom(id, roomName, isLocalCall))
  }

  roomLeave (roomName, { id, isLocalCall }) {
    return this.state.getRoom(roomName)
      .then(room => this.leaveSocketFromRoom(id, room.roomName, isLocalCall))
  }

  roomMessage (roomName, msg, { bypassPermissions }) {
    return this.state.getRoom(roomName).then(room => {
      this.processMessage(msg)
      return room.message(this.userName, msg, bypassPermissions)
    }).then(pmsg => {
      this.transport.emitToChannel(roomName, 'roomMessage', roomName, pmsg)
      return pmsg.id
    })
  }

  roomNotificationsInfo (roomName, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.getNotificationsInfo(this.userName, bypassPermissions))
  }

  roomRemoveFromList (roomName, listName, values, { bypassPermissions }) {
    return this.state.getRoom(roomName).then(room => {
      return Promise.join(
        room.removeFromList(this.userName, listName, values, bypassPermissions),
        room.roomState.accessListsUpdatesGet(),
        (userNames, update) => {
          if (update) {
            this.transport.emitToChannel(
              roomName, 'roomAccessListRemoved', roomName, listName, values)
          }
          return this.removeRoomUsers(roomName, userNames)
        })
    }).return()
  }

  roomSetWhitelistMode (roomName, mode, { bypassPermissions }) {
    return this.state.getRoom(roomName).then(room => {
      return Promise.join(
        room.changeMode(this.userName, mode, bypassPermissions),
        room.roomState.accessListsUpdatesGet(),
        ([userNames, mode], update) => {
          if (update) {
            this.transport.emitToChannel(
              roomName, 'roomModeChanged', roomName, mode)
          }
          return this.removeRoomUsers(roomName, userNames)
        })
    }).return()
  }

  roomUserSeen (roomName, userName, { bypassPermissions }) {
    return this.state.getRoom(roomName)
      .then(room => room.userSeen(this.userName, userName, bypassPermissions))
  }

  systemMessage (data, { id }) {
    this.transport.sendToChannel(id, this.echoChannel, 'systemMessage', data)
    return Promise.resolve()
  }
}

module.exports = User
