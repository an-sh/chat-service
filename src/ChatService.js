'use strict'

/**
 * Node style callback. All callbacks are optional, promises may be
 * used instead. But only one API must be used per invocation.
 *
 * @callback callback
 * @param {Error} error
 * @param {...*} results
 */

/**
 * Server side related documentation.
 *
 * @example <caption>npm package usage</caption>
 *   let ChatService = require('chat-service')
 *
 * @namespace chat-service
 */

const ArgumentsValidator = require('./ArgumentsValidator')
const ChatServiceError = require('./ChatServiceError')
const MemoryState = require('./MemoryState')
const Promise = require('bluebird')
const RecoveryAPI = require('./RecoveryAPI')
const RedisState = require('./RedisState')
const Room = require('./Room')
const ServiceAPI = require('./ServiceAPI')
const SocketIOClusterBus = require('./SocketIOClusterBus')
const SocketIOTransport = require('./SocketIOTransport')
const User = require('./User')
const _ = require('lodash')
const uid = require('uid-safe')
const { EventEmitter } = require('events')
const { checkNameSymbols, convertError, execHook, logError, mixin } =
        require('./utils')

const rpcRequestsNames = [
  'directAddToList',
  'directGetAccessList',
  'directGetWhitelistMode',
  'directMessage',
  'directRemoveFromList',
  'directSetWhitelistMode',
  'listOwnSockets',
  'roomAddToList',
  'roomCreate',
  'roomDelete',
  'roomGetAccessList',
  'roomGetOwner',
  'roomGetWhitelistMode',
  'roomHistoryGet',
  'roomHistoryInfo',
  'roomJoin',
  'roomLeave',
  'roomMessage',
  'roomNotificationsInfo',
  'roomRecentHistory',
  'roomRemoveFromList',
  'roomSetWhitelistMode',
  'roomUserSeen',
  'systemMessage'
]

/**
 * Service class, is the package exported object.
 *
 * @extends EventEmitter
 *
 * @mixes chat-service.ServiceAPI
 * @mixes chat-service.RecoveryAPI
 *
 * @fires chat-service.ChatService.ready
 * @fires chat-service.ChatService.closed
 * @fires chat-service.ChatService.storeConsistencyFailure
 * @fires chat-service.ChatService.transportConsistencyFailure
 * @fires chat-service.ChatService.lockTimeExceeded
 *
 * @example <caption>starting a server</caption>
 *   let ChatService = require('chat-service')
 *   let service = new ChatService(options, hooks)
 *
 * @example <caption>server-side: adding a room</caption>
 *   let owner = 'admin'
 *   let whitelistOnly = true
 *   let whitelist = [ 'user' ]
 *   let state = { owner, whitelistOnly, whitelist }
 *   chatService.addRoom('someRoom', state).then(fn)
 *
 * @example <caption>server-side: sending a room message</caption>
 *   let room = 'someRoom'
 *   let msg = { textMessage: 'some message' }
 *   let context = {
 *     userName: 'system',
 *     bypassPermissions: true
 *   }
 *   chatService.execUserCommand(context, 'roomMessage', room, msg)
 *     .then(fn)
 *
 * @example <caption>server-side: joining an user socket to a room</caption>
 *   let room = 'someRoom'
 *   let context = {
 *     userName: 'user',
 *     id: id // socket id
 *   }
 *   chatService.execUserCommand(context, 'roomJoin', room)
 *     .then(fn) // real sockets will get a notification
 *
 * @memberof chat-service
 *
 */
class ChatService extends EventEmitter {
  /**
   * Crates an object and starts a new service instance. The {@link
   * chat-service.ChatService#close} method __MUST__ be called before
   * the node process exits.
   *
   * @param {chat-service.config.options} [options] Service
   * configuration options.
   *
   * @param {chat-service.hooks.HooksInterface} [hooks] Service
   * customisation hooks.
   */
  constructor (options = {}, hooks = {}) {
    super()
    this.options = options
    this.hooks = hooks
    this.initVariables()
    this.setOptions()
    this.setIntegraionOptions()
    this.setComponents()
    this.attachBusListeners()
    mixin(this, ServiceAPI, this.state,
      () => new User(this), this.clusterBus)
    mixin(this, RecoveryAPI, this.state, this.transport,
      this.execUserCommand.bind(this), this.instanceUID)
    this.startServer()
  }

  /**
   * ChatService errors constructor. This errors are intended to be
   * returned to clients as a part of a normal service functioning
   * (something like 403 errors). Can be also used to create custom
   * errors subclasses.
   *
   * @name ChatServiceError
   * @type Class
   * @static
   * @readonly
   *
   * @memberof chat-service.ChatService
   *
   * @see rpc.datatypes.ChatServiceError
   */

  /**
   * Service instance UID.
   *
   * @name chat-service.ChatService#instanceUID
   * @type string
   * @readonly
   */

  /**
   * Cluster communication via an adapter. Emits messages to all
   * services nodes, including the sender node.
   *
   * @name chat-service.ChatService#clusterBus
   * @type EventEmitter
   * @readonly
   */

  /**
   * Transport object.
   *
   * @name chat-service.ChatService#transport
   * @type chat-service.TransportInterface
   * @readonly
   */

  /**
   * Service is ready, state and transport are up.
   * @event ready
   *
   * @memberof chat-service.ChatService
   */

  /**
   * Service is closed, state and transport are closed.
   * @event closed
   * @param {Error} [error] If was closed due to an error.
   *
   * @memberof chat-service.ChatService
   */

  /**
   * State store failed to be updated to reflect an user's connection
   * or presence state.
   *
   * @event storeConsistencyFailure
   * @param {Error} error Error.
   * @param {Object} operationInfo Operation details.
   * @property {string} operationInfo.userName User name.
   * @property {string} operationInfo.opType Operation type.
   * @property {string} [operationInfo.roomName] Room name.
   * @property {string} [operationInfo.id] Socket id.
   *
   * @see chat-service.RecoveryAPI
   *
   * @memberof chat-service.ChatService
   */

  /**
   * Failed to teardown a transport connection.
   *
   * @event transportConsistencyFailure
   *
   * @param {Error} error Error.
   * @param {Object} operationInfo Operation details.
   * @property {string} operationInfo.userName User name.
   * @property {string} operationInfo.opType Operation type.
   * @property {string} [operationInfo.roomName] Room name.
   * @property {string} [operationInfo.id] Socket id.
   *
   * @memberof chat-service.ChatService
   */

  /**
   * Lock was hold longer than a lock ttl.
   *
   * @event lockTimeExceeded
   *
   * @param {string} id Lock id.
   * @param {Object} lockInfo Lock resource details.
   * @property {string} [lockInfo.userName] User name.
   * @property {string} [lockInfo.roomName] Room name.
   *
   * @see chat-service.RecoveryAPI
   *
   * @memberof chat-service.ChatService
   */

  /**
   * Exposes an internal arguments validation method, it is run
   * automatically by all client request (command) handlers.
   *
   * @method chat-service.ChatService#checkArguments
   *
   * @param {string} name Command name.
   * @param {...*} args Command arguments.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any
   * data if validation is successful, otherwise a promise is
   * rejected.
   */

  initVariables () {
    this.instanceUID = uid.sync(18)
    this.runningCommands = 0
    this.closed = false
    // constants
    this.rpcRequestsNames = rpcRequestsNames
    this.ChatServiceError = ChatServiceError
    this.SocketIOClusterBus = SocketIOClusterBus
    this.User = User
    this.Room = Room
  }

  setOptions () {
    this.closeTimeout = this.options.closeTimeout || 15000
    this.busAckTimeout = this.options.busAckTimeout || 5000
    this.heartbeatRate = this.options.heartbeatRate || 10000
    this.heartbeatTimeout = this.options.heartbeatTimeout || 30000
    this.directListSizeLimit = this.options.directListSizeLimit || 1000
    this.roomListSizeLimit = this.options.roomListSizeLimit || 10000
    this.enableAccessListsUpdates =
      this.options.enableAccessListsUpdates || false
    this.enableDirectMessages = this.options.enableDirectMessages || false
    this.enableRoomsManagement = this.options.enableRoomsManagement || false
    this.enableUserlistUpdates = this.options.enableUserlistUpdates || false
    this.historyMaxGetMessages = this.options.historyMaxGetMessages
    if (!_.isNumber(this.historyMaxGetMessages) ||
        this.historyMaxGetMessages < 0) {
      this.historyMaxGetMessages = 100
    }
    this.historyMaxSize = this.options.historyMaxSize
    if (!_.isNumber(this.historyMaxSize) || this.historyMaxSize < 0) {
      this.historyMaxSize = 10000
    }
    this.port = this.options.port || 8000
    this.directMessagesChecker = this.hooks.directMessagesChecker
    this.roomMessagesChecker = this.hooks.roomMessagesChecker
    this.useRawErrorObjects = this.options.useRawErrorObjects || false
  }

  setIntegraionOptions () {
    this.stateConstructor = this.options.state || 'memory'
    this.stateOptions = this.options.stateOptions || {}

    this.transportConstructor = this.options.transport || 'socket.io'
    this.transportOptions = this.options.transportOptions || {}
  }

  setAdapterOptions () {
    // adapter options compatibility
    this.adapterConstructor = this.transportOptions.adapter ||
      this.options.adapter || 'memory'
    this.adapterOptions = _.castArray(
      this.transportOptions.adapterOptions || this.options.adapterOptions)
    const opts = {
      adapterConstructor: this.adapterConstructor,
      adapterOptions: this.adapterOptions
    }
    this.transportOptions = _.assign(opts, this.transportOptions)
  }

  setComponents () {
    let State, Transport
    if (this.stateConstructor === 'memory') {
      State = MemoryState
    } else if (this.stateConstructor === 'redis') {
      State = RedisState
    } else if (_.isFunction(this.stateConstructor)) {
      State = this.stateConstructor
    } else {
      throw new Error(`Invalid state: ${this.stateConstructor}`)
    }
    if (this.transportConstructor === 'socket.io') {
      Transport = SocketIOTransport
    } else if (_.isFunction(this.transportConstructor)) {
      Transport = this.transportConstructor
    } else {
      throw new Error(`Invalid transport: ${this.transportConstructor}`)
    }
    this.setAdapterOptions()
    this.validator = new ArgumentsValidator(this)
    this.checkArguments = this.validator.checkArguments.bind(this.validator)
    this.state = new State(this, this.stateOptions)
    this.transport = new Transport(this, this.transportOptions)
    this.clusterBus = this.transport.clusterBus
  }

  attachBusListeners () {
    this.clusterBus.on('roomLeaveSocket', (id, roomName) => {
      this.transport.leaveChannel(id, roomName)
        .then(() => this.clusterBus.emit('socketRoomLeft', id, roomName))
        .catchReturn()
    })
    this.clusterBus.on('disconnectUserSockets', userName => {
      this.state.getUser(userName)
        .then(user => user.disconnectInstanceSockets())
        .catchReturn()
    })
    this.clusterBus.on('socketRoomLeft', (id, roomName) => {
      const emit = EventEmitter.prototype.emit
      emit.call(this.clusterBus, `socketRoomLeft:${id}:${roomName}`)
    })
  }

  // for transport plugins integration
  convertError (error) {
    return convertError(error, this.useRawErrorObjects)
  }

  // for transport plugins integration
  onConnect (id) {
    if (this.hooks.onConnect) {
      return Promise.try(() => execHook(this.hooks.onConnect, this, id))
        .then(loginData => _.castArray(loginData))
        .catch(logError)
    } else {
      return Promise.resolve([])
    }
  }

  // for transport plugins integration
  registerClient (userName, id) {
    return checkNameSymbols(userName)
      .then(() => this.state.getOrAddUser(userName))
      .then(user => user.registerSocket(id))
      .catch(logError)
  }

  waitCommands () {
    if (this.runningCommands > 0) {
      return Promise.fromCallback(cb => {
        this.once('commandsFinished', cb)
      })
    } else {
      return Promise.resolve()
    }
  }

  closeTransport () {
    return this.transport.close()
      .then(() => this.waitCommands())
      .timeout(this.closeTimeout)
  }

  startServer () {
    return Promise.try(() => {
      if (this.hooks.onStart) {
        return this.clusterBus.listen()
          .then(() => execHook(this.hooks.onStart, this))
          .then(() => this.transport.setEvents())
      } else {
        // tests spec compatibility
        this.transport.setEvents()
        return this.clusterBus.listen()
      }
    }).then(() => {
      this.state.updateHeartbeat()
      const hbupdater = this.state.updateHeartbeat.bind(this.state)
      this.hbtimer = setInterval(hbupdater, this.heartbeatRate)
      return this.emit('ready')
    }).catch(error => {
      this.closed = true
      return this.closeTransport()
        .then(() => this.state.close())
        .finally(() => this.emit('closed', error))
    })
  }

  /**
   * Closes server.
   * @note __MUST__ be called before node process shutdown to correctly
   *   update the state.
   * @param {callback} [cb] Optional callback.
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  close (cb) {
    if (this.closed) { return Promise.resolve() }
    this.closed = true
    clearInterval(this.hbtimer)
    let closeError = null
    return this.closeTransport().then(
      () => execHook(this.hooks.onClose, this, null),
      error => {
        if (this.hooks.onClose) {
          return execHook(this.hooks.onClose, this, error)
        } else {
          return Promise.reject(error)
        }
      }).catch(error => {
      closeError = error
      return Promise.reject(error)
    }).finally(() => {
      return this.state.close()
        .finally(() => this.emit('closed', closeError))
    }).asCallback(cb)
  }
}

// for custom errors
ChatService.ChatServiceError = ChatServiceError

// for transport plugin implementations
ChatService.SocketIOClusterBus = SocketIOClusterBus

// for store plugin implementations
ChatService.User = User
ChatService.Room = Room

module.exports = ChatService
