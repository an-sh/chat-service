
const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const User = require('./User')
const _ = require('lodash')
const { checkNameSymbols, possiblyCallback } = require('./utils')

// @mixin
// API for server side operations.
let ServiceAPI = {

  // Executes {UserCommands}.
  //
  // @param context [String or Boolean or Object] Is a `userName` if
  //   String, or a `bypassPermissions` if Boolean, or an options hash if
  //   Object.
  // @param command [String] Command name.
  // @param args [Rest...] Command arguments with an optional callback.
  //
  // @option context [String] userName User name.
  // @option context [String] id Socket id, it is required for
  //   {UserCommands#disconnect}, {UserCommands#roomJoin},
  //   {UserCommands#roomLeave} commands.
  // @option context [Boolean] bypassHooks If `false` executes command
  //   without before and after hooks, default is `false`.
  // @option context [Boolean] bypassPermissions If `true` executes
  //   command (except {UserCommands#roomJoin}) bypassing any
  //   permissions checking, default is `false`.
  //
  // @return [Promise<Array>] Array of command results.
  execUserCommand (context, command, ...args) {
    if (_.isObject(context)) {
      var { userName } = context
    } else if (_.isBoolean(context)) {
      context = {bypassPermissions: context}
    } else {
      userName = context
      context = {}
    }
    let [nargs, cb] = possiblyCallback(args)
    return Promise.try(() => {
      if (userName) {
        return this.state.getUser(userName)
      } else {
        return new User(this)
      }
    }).then(user => user.exec(command, context, nargs))
      .asCallback(cb, { spread: true })
  },

  // Adds an user with a state.
  //
  // @param userName [String] User name.
  // @param state [Object] User state.
  // @param cb [Callback] Optional callback.
  //
  // @option state [Array<String>] whitelist User direct messages whitelist.
  // @option state [Array<String>] blacklist User direct messages blacklist.
  // @option state [Boolean] whitelistOnly User direct messages
  //   whitelistOnly mode, default is `false`.
  //
  // @return [Promise]
  addUser (userName, state, cb) {
    return checkNameSymbols(userName).then(() => {
      return this.state.addUser(userName, state)
    }).return().asCallback(cb)
  },

  // Deletes an offline user. Will raise an error if user has online
  // sockets.
  //
  // @param userName [String] User name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise]
  deleteUser (userName, cb) {
    return this.state.getUser(userName).then(user => {
      return user.listOwnSockets().then(sockets => {
        if (sockets && _.size(sockets) > 0) {
          return Promise.reject(new ChatServiceError('userOnline', userName))
        } else {
          return Promise.all([
            user.removeState(),
            this.state.removeUser(userName) // bug decaffeinate 2.16.0
          ])
        }
      })
    }).return().asCallback(cb)
  },

  // Checks user existence.
  //
  // @param userName [String] User name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise<Boolean>]
  hasUser (userName, cb) {
    return this.state.getUser(userName, true)
      .then(function (user) { if (user) { return true } else { return false } })
      .asCallback(cb)
  },

  // Checks for a name existence in an user list.
  //
  // @param userName [String] User name.
  // @param listName [String] List name.
  // @param item [String] List element.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise<Boolean>]
  userHasInList (userName, listName, item, cb) {
    return this.state.getUser(userName)
      .then(user => user.directMessagingState.hasInList(listName, item))
      .asCallback(cb)
  },

  // Checks for a direct messaging permission.
  //
  // @param recipient [String] Recipient name.
  // @param sender [String] Sender name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise<Boolean>]
  hasDirectAccess (recipient, sender, cb) {
    return this.state.getUser(recipient)
      .then(user => user.checkAcess(sender))
      .return(true)
      .catchReturn(ChatServiceError, false)
      .asCallback(cb)
  },

  // Disconnects user's sockets for all service instances. Method is
  // asynchronous, returns without waiting for the completion.
  //
  // @param userName [String] User name.
  disconnectUserSockets (userName) {
    return this.clusterBus.emit('disconnectUserSockets', userName)
  },

  // Adds a room with a state.
  //
  // @param roomName [String] Room name.
  // @param state [Object] Room state.
  // @param cb [Callback] Optional callback.
  //
  // @option state [Array<String>] whitelist Room whitelist.
  // @option state [Array<String>] blacklist Room blacklist
  // @option state [Array<String>] adminlist Room adminlist.
  // @option state [Boolean] whitelistOnly Room whitelistOnly mode,
  //   default is `false`.
  // @option state [String] owner Room owner.
  // @option state [Integer] historyMaxSize Room history maximum size.
  //
  // @return [Promise]
  addRoom (roomName, state, cb) {
    return checkNameSymbols(roomName)
      .then(() => this.state.addRoom(roomName, state))
      .return()
      .asCallback(cb)
  },

  // Removes all room data, and removes joined user from the room.
  //
  // @param roomName [String] Room name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise]
  deleteRoom (roomName, cb) {
    return this.execUserCommand(true, 'roomDelete', roomName)
      .return()
      .asCallback(cb)
  },

  // Checks room existence.
  //
  // @param roomName [String] Room name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise<Boolean>]
  hasRoom (roomName, cb) {
    return this.state.getRoom(roomName, true)
      .then(function (room) { if (room) { return true } else { return false } })
      .asCallback(cb)
  },

  // Checks for a name existence in a room list.
  //
  // @param roomName [String] Room name.
  // @param listName [String] List name.
  // @param item [String] List element.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise<Boolean>]
  roomHasInList (roomName, listName, item, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.hasInList(listName, item))
      .asCallback(cb)
  },

  // Checks for a room access permission.
  //
  // @param roomName [String] Room name.
  // @param userName [String] User name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise<Boolean>]
  hasRoomAccess (roomName, userName, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.checkAcess(userName))
      .return(true)
      .catchReturn(ChatServiceError, false)
      .asCallback(cb)
  },

  // Changes a room owner.
  //
  // @param roomName [String] Room name.
  // @param owner [String] Owner user name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise]
  changeRoomOwner (roomName, owner, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.ownerSet(owner))
      .return()
      .asCallback(cb)
  },

  // Changes a room history size.
  //
  // @param roomName [String] Room name.
  // @param size [Integer] Room history size.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise]
  changeRoomHistoryMaxSize (roomName, size, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.historyMaxSizeSet(size))
      .return()
      .asCallback(cb)
  }
}

module.exports = ServiceAPI
