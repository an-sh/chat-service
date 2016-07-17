
const ChatServiceError = require('./ChatServiceError')
const CommandBinder = require('./CommandBinder')
const DirectMessaging = require('./DirectMessaging')
const Promise = require('bluebird')
const UserAssociations = require('./UserAssociations')
const _ = require('lodash')
const { asyncLimit, checkNameSymbols, mix } = require('./utils')

//
// Client commands implementation.
class User extends DirectMessaging {

  constructor (server, userName) {
    super(server, userName)
    this.server = server
    this.userName = userName
    this.state = this.server.state
    this.transport = this.server.transport
    this.validator = this.server.validator
    this.hooks = this.server.hooks
    this.enableUserlistUpdates = this.server.enableUserlistUpdates
    this.enableAccessListsUpdates = this.server.enableAccessListsUpdates
    this.enableRoomsManagement = this.server.enableRoomsManagement
    this.enableDirectMessages = this.server.enableDirectMessages
    let State = this.server.state.UserState
    this.userState = new State(this.server, this.userName)
    this.lockTTL = this.state.lockTTL
    this.echoChannel = this.userState.echoChannel
  }

  initState (state) {
    return super.initState(state)
  }

  removeState () {
    return super.removeState()
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
    let { id } = options
    let requestsNames = this.server.rpcRequestsNames
    if (!_.includes(requestsNames, command)) {
      let error = new ChatServiceError('noCommand', command)
      return Promise.reject(error)
    }
    let requiresSocket = command === 'disconnect' ||
          command === 'roomJoin' || command === 'roomLeave'
    if (!id && requiresSocket) {
      let error = new ChatServiceError('noSocket', command)
      return Promise.reject(error)
    }
    let fn = this[command]
    let cmd = this.makeCommand(command, fn)
    return Promise.fromCallback(
      cb => cmd(args, options, cb),
      {multiArgs: true})
  }

  checkOnline () {
    return this.userState.getAllSockets().then(sockets => {
      if (!sockets || !sockets.length) {
        let error = new ChatServiceError('noUserOnline', this.userName)
        return Promise.reject(error)
      } else {
        return Promise.resolve()
      }
    })
  }

  consistencyFailure (error, operationInfo = {}) {
    operationInfo.userName = this.userName
    let name = operationInfo.opType === 'transportChannel'
          ? 'transportConsistencyFailure'
          : 'storeConsistencyFailure'
    this.server.emit(name, error, operationInfo)
  }

  registerSocket (id) {
    return this.state.addSocket(id, this.userName)
      .then(() => this.userState.addSocket(id, this.server.instanceUID))
      .then(nconnected => {
        if (!this.transport.getConnectionObject(id)) {
          return this.removeUserSocket(id).then(() => {
            let error = new ChatServiceError('noSocket', 'connection')
            return Promise.reject(error)
          })
        } else {
          let commands = this.server.rpcRequestsNames
          for (let idx in commands) {
            let cmd = commands[idx]
            this.bindCommand(id, cmd, this[cmd])
          }
          return [ this, nconnected ]
        }
      })
  }

  disconnectInstanceSockets () {
    return this.userState.getAllSockets().then(sockets => {
      return Promise.map(
        sockets,
        sid => this.transport.disconnectClient(sid),
        { concurrency: asyncLimit })
    })
  }

  directAddToList (listName, values) {
    return this.addToList(this.userName, listName, values).return()
  }

  directGetAccessList (listName) {
    return this.getList(this.userName, listName)
  }

  directGetWhitelistMode () {
    return this.getMode(this.userName)
  }

  directMessage (recipientName, msg, {id, bypassPermissions}) {
    if (!this.enableDirectMessages) {
      let error = new ChatServiceError('notAllowed')
      return Promise.reject(error)
    }
    this.processMessage(msg, true)
    return this.server.state.getUser(recipientName).then(recipient => {
      let channel = recipient.echoChannel
      return recipient.message(this.userName, msg, bypassPermissions)
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
    return this.removeFromList(this.userName, listName, values).return()
  }

  directSetWhitelistMode (mode) {
    return this.changeMode(this.userName, mode).return()
  }

  disconnect (reason, {id}) {
    return this.removeSocketFromServer(id)
  }

  listOwnSockets () {
    return this.userState.getSocketsToRooms()
  }

  roomAddToList (roomName, listName, values, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.addToList(this.userName, listName, values, bypassPermissions)
    }).then(userNames => {
      if (this.enableAccessListsUpdates) {
        this.transport.emitToChannel(
          roomName, 'roomAccessListAdded', roomName, listName, values)
      }
      return this.removeRoomUsers(roomName, userNames).return()
    })
  }

  roomCreate (roomName, whitelistOnly, {bypassPermissions}) {
    if (!this.enableRoomsManagement && !bypassPermissions) {
      let error = new ChatServiceError('notAllowed')
      return Promise.reject(error)
    }
    return checkNameSymbols(roomName).then(() => { // TODO rewrite
      return this.state.addRoom(
        roomName, {owner: this.userName, whitelistOnly})
    }).return()
  }

  roomDelete (roomName, {bypassPermissions}) {
    if (!this.enableRoomsManagement && !bypassPermissions) {
      let error = new ChatServiceError('notAllowed')
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

  roomGetAccessList (roomName, listName, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.getList(this.userName, listName, bypassPermissions)
    })
  }

  roomGetOwner (roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.getOwner(this.userName, bypassPermissions)
    })
  }

  roomGetWhitelistMode (roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.getMode(this.userName, bypassPermissions)
    })
  }

  roomRecentHistory (roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.getRecentMessages(this.userName, bypassPermissions)
    })
  }

  roomHistoryGet (roomName, msgid, limit, {bypassPermissions}) {
    return this.state.getRoom(roomName)
      .then(room => { // TODO rewrite
        return room.getMessages(this.userName, msgid, limit, bypassPermissions)
      }
    )
  }

  roomHistoryInfo (roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.getHistoryInfo(this.userName, bypassPermissions)
    })
  }

  roomJoin (roomName, {id}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return this.joinSocketToRoom(id, roomName)
    })
  }

  roomLeave (roomName, {id}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return this.leaveSocketFromRoom(id, room.roomName)
    })
  }

  roomMessage (roomName, msg, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => {
      this.processMessage(msg)
      return room.message(this.userName, msg, bypassPermissions)
    }).then(pmsg => {
      this.transport.emitToChannel(roomName, 'roomMessage', roomName, pmsg)
      return pmsg.id
    })
  }

  roomRemoveFromList (roomName, listName, values, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.removeFromList(this.userName, listName, values, bypassPermissions)
    }).then(userNames => {
      if (this.enableAccessListsUpdates) {
        this.transport.emitToChannel(roomName, 'roomAccessListRemoved',
                                     roomName, listName, values)
      }
      return this.removeRoomUsers(roomName, userNames)
    }).return()
  }

  roomSetWhitelistMode (roomName, mode, {bypassPermissions}) {
    return this.state.getRoom(roomName).then(room => { // TODO rewrite
      return room.changeMode(this.userName, mode, bypassPermissions)
    }).spread((userNames, mode) => {
      if (this.enableAccessListsUpdates) {
        this.transport.emitToChannel(roomName, 'roomModeChanged', roomName, mode)
      }
      return this.removeRoomUsers(roomName, userNames)
    })
  }

  roomUserSeen (roomName, userName, {bypassPermissions}) { // TODO rewrite
    return this.state.getRoom(roomName).then(room => {
      return room.userSeen(this.userName, userName, bypassPermissions)
    })
  }

  systemMessage (data, {id}) {
    this.transport.sendToChannel(id, this.echoChannel, 'systemMessage', data)
    return Promise.resolve()
  }

}

mix(User, CommandBinder, UserAssociations)

module.exports = User
