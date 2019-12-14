'use strict'

const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const _ = require('lodash')
const { checkNameSymbols, possiblyCallback } = require('./utils')

/**
 * Server side operations.
 *
 * @mixin
 * @memberof chat-service
 * @see chat-service.ChatService
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
   * @param {string|boolean|Object} context Is a `userName` if
   * `string`, or a `bypassPermissions` if `boolean`, or an options
   * object if `Object`.
   * @param {string} command Command name.
   * @param {...*} args Command arguments.
   * @param {callback} [cb] Optional callback.
   *
   * @property {string} [context.userName] User name.
   * @property {string} [context.id] Socket id, it is required for
   * {@link rpc.clientRequests.roomJoin} and {@link
   * rpc.clientRequests.roomLeave} commands.
   * @property {boolean} [context.bypassHooks=false] If `false`
   * executes command without before and after hooks.
   * @property {boolean} [context.bypassPermissions=false] If `true`
   * executes command (except {@link rpc.clientRequests.roomJoin})
   * bypassing built-in permissions checking.
   *
   * @return {Promise<Array>} Array of command results.
   *
   * @see rpc.clientRequests
   */
  execUserCommand (context, command, ...args) {
    if (_.isObject(context)) {
      var { userName } = context
      context = _.clone(context)
    } else if (_.isBoolean(context)) {
      context = { bypassPermissions: context }
    } else {
      userName = context
      context = {}
    }
    context.isLocalCall = true
    const [nargs, cb] = possiblyCallback(args)
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
   * @param {Object} [state] User state.
   * @param {callback} [cb] Optional callback.
   *
   * @property {Array<string>} [state.whitelist=[]] User direct messages
   * whitelist.
   * @property {Array<string>} [state.blacklist=[]] User direct messages
   * blacklist.
   * @property {boolean} [state.whitelistOnly=false] User direct
   * messages whitelistOnly mode.
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
   * Deletes an offline user. Will raise an error if a user has online
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
   * Checks for an user existence.
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
   * Checks for a name existence in a direct messaging list.
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
   * @param {Object} [state] Room state.
   * @param {callback} [cb] Optional callback.
   *
   * @property {Array<string>} [state.whitelist=[]] Room whitelist.
   * @property {Array<string>} [state.blacklist=[]] Room blacklist
   * @property {Array<string>} [state.adminlist=[]] Room adminlist.
   * @property {boolean} [state.whitelistOnly=false] Room
   * whitelistOnly mode.
   * @property {string} [state.owner] Room owner.
   * @property {number} [state.historyMaxSize] Room history maximum
   * size. Defalut value is {@link chat-service.config.options}
   * `historyMaxSize`.
   * @property {boolean} [state.enableAccessListsUpdates] Room enable
   * access lists updates. Defalut value is {@link
   * chat-service.config.options} `enableAccessListsUpdates`.
   * @property {boolean} [state.enableUserlistUpdates] Room enable
   * userlist updates. Defalut value is {@link
   * chat-service.config.options} `enableUserlistUpdates`.
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
   * Removes all joined users from the room and removes all room data.
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
   * Checks for a room existence.
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
   * Changes the room owner.
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
   * Changes the room history size.
   *
   * @param {string} roomName Room name.
   * @param {number} size Room history size.
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

  /**
   * Enables or disables access lists updates for the room.
   *
   * @param {string} roomName Room name.
   * @param {boolean} mode Enable or disable.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @see rpc.serverNotifications.roomAccessListAdded
   * @see rpc.serverNotifications.roomAccessListRemoved
   * @see rpc.serverNotifications.roomModeChanged
   */
  changeAccessListsUpdates (roomName, mode, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.accessListsUpdatesSet(mode))
      .return()
      .asCallback(cb)
  }

  /**
   * Enables or disables user list updates for the room.
   *
   * @param {string} roomName Room name.
   * @param {boolean} mode Enable or disable.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @see rpc.serverNotifications.roomUserJoined
   * @see rpc.serverNotifications.roomUserLeft
   */
  changeUserlistUpdates (roomName, mode, cb) {
    return this.state.getRoom(roomName)
      .then(room => room.roomState.userlistUpdatesSet(mode))
      .return()
      .asCallback(cb)
  }
}

module.exports = ServiceAPI
