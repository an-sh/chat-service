
const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const _ = require('lodash')
const { checkNameSymbols, possiblyCallback } = require('./utils')

/**
 * @mixin
 * @memberof chat-service
 */
class ServiceAPI {

  constructor (state, makeUser, clusterBus) {
    this.state = state
    this.makeUser = makeUser
    this.clusterBus = clusterBus
  }

  /**
   * Executes {@link rpc.clientRequests} handlers.
   *
   * @param {string|boolean|Object} context Is a `userName` if string,
   *   or a `bypassPermissions` if boolean, or an options hash if
   *   Object.
   * @param {string} command Command name.
   * @param {...*} args Command arguments.
   * @param {callback} [cb] Optional callback.
   *
   * @property {string} context.userName User name.
   * @property {string} context.id Socket id, it is required for
   *   `disconnect`, `roomJoin`, `roomLeave` commands.
   * @property {boolean} context.bypassHooks If `false` executes
   *   command without before and after hooks, default is `false`.
   * @property {boolean} context.bypassPermissions If `true` executes
   *   command (except `roomJoin`) bypassing any permissions checking,
   *   default is `false`.
   *
   * @return {Promise<Array>} Array of command results.
   */
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
        return this.makeUser()
      }
    }).then(user => user.exec(command, context, nargs))
      .asCallback(cb, { spread: true })
  }

  /**
   * Adds an user with a state.
   *
   * @param {string} userName User name.
   * @param {Object} state User state.
   * @param {callback} [cb] Optional callback.
   *
   * @property {Array<string>} state.whitelist User direct messages whitelist.
   * @property {Array<string>} state.blacklist User direct messages blacklist.
   * @property {boolean} state.whitelistOnly User direct messages
   *   whitelistOnly mode, default is `false`.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  addUser (userName, state, cb) {
    return checkNameSymbols(userName)
      .then(() => this.state.addUser(userName, state))
      .return()
      .asCallback(cb)
  }

  /**
   * Deletes an offline user. Will raise an error if user has online
   * sockets.
   *
   * @param {string} userName User name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  deleteUser (userName, cb) {
    return this.state.getUser(userName).then(user => {
      return user.listOwnSockets().then(sockets => {
        if (sockets && _.size(sockets) > 0) {
          return Promise.reject(new ChatServiceError('userOnline', userName))
        } else {
          return Promise.all([
            user.removeState(),
            this.state.removeUser(userName)
          ])
        }
      })
    }).return().asCallback(cb)
  }

  /**
   * Checks user existence.
   *
   * @param {string} userName User name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<boolean>} Predicate result.
   */
  hasUser (userName, cb) {
    return this.state.getUser(userName, true)
      .then(user => Boolean(user))
      .asCallback(cb)
  }

  /**
   * Checks for a name existence in an user list.
   *
   * @param {string} userName User name.
   * @param {string} listName List name.
   * @param {string} item List element.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<boolean>} Predicate result.
   */
  userHasInList (userName, listName, item, cb) {
    return this.state.getUser(userName)
      .then(user => user.directMessaging.hasInList(listName, item))
      .asCallback(cb)
  }

  /**
   * Checks for a direct messaging permission.
   *
   * @param {string} recipient Recipient name.
   * @param {string} sender Sender name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<boolean>} Predicate result.
   */
  hasDirectAccess (recipient, sender, cb) {
    return this.state.getUser(recipient)
      .then(user => user.directMessaging.checkAcess(sender))
      .return(true)
      .catchReturn(ChatServiceError, false)
      .asCallback(cb)
  }

  /**
   * Disconnects user's sockets for all service instances. Method is
   * asynchronous, returns without waiting for the completion.
   *
   * @param {string} userName User name.
   *
   * @return {undefined} Returns no data.
   */
  disconnectUserSockets (userName) {
    this.clusterBus.emit('disconnectUserSockets', userName)
  }

  /**
   * Adds a room with a state.
   *
   * @param {string} roomName Room name.
   * @param {Object} state Room state.
   * @param {callback} [cb] Optional callback.
   *
   * @property {Array<string>} state.whitelist Room whitelist.
   * @property {Array<string>} state.blacklist Room blacklist
   * @property {Array<string>} state.adminlist Room adminlist.
   * @property {boolean} state.whitelistOnly Room whitelistOnly mode,
   *   default is `false`.
   * @property {string} state.owner Room owner.
   * @property {Integer} state.historyMaxSize Room history maximum size.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  addRoom (roomName, state, cb) {
    return checkNameSymbols(roomName)
      .then(() => this.state.addRoom(roomName, state))
      .return()
      .asCallback(cb)
  }

  /**
   * Removes all room data, and removes joined user from the room.
   *
   * @param {string} roomName Room name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  deleteRoom (roomName, cb) {
    return this.execUserCommand(true, 'roomDelete', roomName)
      .return()
      .asCallback(cb)
  }

  /**
   * Checks room existence.
   *
   * @param {string} roomName Room name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<boolean>} Predicate result.
   */
  hasRoom (roomName, cb) {
    return this.state.getRoom(roomName, true)
      .then(room => Boolean(room))
      .asCallback(cb)
  }

  /**
   * Checks for a name existence in a room list.
   *
   * @param {string} roomName Room name.
   * @param {string} listName List name.
   * @param {string} item List element.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<boolean>} Predicate result.
   */
  roomHasInList (roomName, listName, item, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.hasInList(listName, item))
      .asCallback(cb)
  }

  /**
   * Checks for a room access permission.
   *
   * @param {string} roomName Room name.
   * @param {string} userName User name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<boolean>} Predicate result.
   */
  hasRoomAccess (roomName, userName, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.checkAcess(userName))
      .return(true)
      .catchReturn(ChatServiceError, false)
      .asCallback(cb)
  }

  /**
   * Changes a room owner.
   *
   * @param {string} roomName Room name.
   * @param {string} owner Owner user name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  changeRoomOwner (roomName, owner, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.ownerSet(owner))
      .return()
      .asCallback(cb)
  }

  /**
   * Changes a room history size.
   *
   * @param {string} roomName Room name.
   * @param {Integer} size Room history size.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  changeRoomHistoryMaxSize (roomName, size, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.historyMaxSizeSet(size))
      .return()
      .asCallback(cb)
  }

}

module.exports = ServiceAPI
