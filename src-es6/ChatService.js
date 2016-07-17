
const ArgumentsValidator = require('./ArgumentsValidator')
const ChatServiceError = require('./ChatServiceError')
const ChatServiceEvents = require('./ChatServiceEvents')
const MemoryState = require('./MemoryState')
const Promise = require('bluebird')
const RecoveryAPI = require('./RecoveryAPI')
const RedisState = require('./RedisState')
const ServiceAPI = require('./ServiceAPI')
const SocketIOTransport = require('./SocketIOTransport')
const _ = require('lodash')
const uid = require('uid-safe')
const { execHook, mix } = require('./utils')

const rpcRequestsNames = [
  'directAddToList',
  'directGetAccessList',
  'directGetWhitelistMode',
  'directMessage',
  'directRemoveFromList',
  'directSetWhitelistMode',
  'disconnect',
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
  'roomRecentHistory',
  'roomRemoveFromList',
  'roomSetWhitelistMode',
  'roomUserSeen',
  'systemMessage'
]

/**
 * Service class, is the package exported object.
 * @mixes ServiceAPI
 * @mixes RecoveryAPI
 */
class ChatService extends ChatServiceEvents {

  /**
   * Crates an object and starts a new service instance.
   *
   * @param {Options} options Service configuration options.
   *
   * @param {Array<Plugin>} hooks Service customisation hooks.
   */
  constructor (options = {}, hooks = {}) {
    super()
    this.options = options
    this.hooks = hooks
    this.setOptions()
    this.setComponents()
    this.startServer()
  }

  /**
   * @name ChatService#instanceUID
   * @type string
   * @readonly
   */

  /**
   * @name ChatServiceError
   * @type Class
   * @memberof ChatService
   * @static
   * @readonly
   */

  setOptions () {
    this.instanceUID = uid.sync(18)
    this.runningCommands = 0
    this.rpcRequestsNames = rpcRequestsNames
    this.closed = false

    this.closeTimeout = this.options.closeTimeout || 15000
    this.busAckTimeout = this.options.busAckTimeout || 5000
    this.heartbeatRate = this.options.heartbeatRate || 10000
    this.heartbeatTimeout = this.options.heartbeatTimeout || 30000
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
    this.defaultHistoryLimit = this.options.defaultHistoryLimit
    if (!_.isNumber(this.defaultHistoryLimit) ||
        this.defaultHistoryLimit < 0) {
      this.defaultHistoryLimit = 10000
    }

    this.port = this.options.port || 8000
    this.useRawErrorObjects = this.options.useRawErrorObjects || false

    this.adapterConstructor = this.options.adapter || 'memory'
    this.adapterOptions = _.castArray(this.options.adapterOptions)
    this.stateConstructor = this.options.state || 'memory'
    this.stateOptions = this.options.stateOptions || {}
    this.transportConstructor = this.options.transport || 'socket.io'
    this.transportOptions = this.options.transportOptions || {}

    this.directMessagesChecker = this.hooks.directMessagesChecker
    this.roomMessagesChecker = this.hooks.roomMessagesChecker
  }

  setComponents () {
    let State = (() => {
      switch (true) {
        case this.stateConstructor === 'memory':
          return MemoryState
        case this.stateConstructor === 'redis':
          return RedisState
        case _.isFunction(this.stateConstructor):
          return this.stateConstructor
        default:
          throw new Error(`Invalid state: ${this.stateConstructor}`)
      }
    })()
    let Transport = (() => {
      switch (true) {
        case this.transportConstructor === 'socket.io':
          return SocketIOTransport
        case _.isFunction(this.transportConstructor):
          return this.transportConstructor
        default:
          throw new Error(`Invalid transport: ${this.transportConstructor}`)
      }
    })()
    this.validator = new ArgumentsValidator(this)
    this.state = new State(this, this.stateOptions)
    this.transport = new Transport(
      this, this.transportOptions,
      this.adapterConstructor, this.adapterOptions)
  }

  startServer () {
    return Promise.try(() => {
      if (this.hooks.onStart) {
        return this.clusterBus.listen()
          .then(() => execHook(this.hooks.onStart, this))
          .then(() => this.transport.setEvents())
      } else {
        // tests spec compatibility
        return this.transport.setEvents().then(() => this.clusterBus.listen())
      }
    }).then(() => {
      this.state.updateHeartbeat()
      let hbupdater = this.state.updateHeartbeat.bind(this.state)
      this.hbtimer = setInterval(hbupdater, this.heartbeatRate)
      return this.emit('ready')
    }).catch(error => {
      this.closed = true
      return this.transport.close()
        .then(() => this.state.close())
        .finally(() => this.emit('closed', error))
    })
  }

  /**
   * Closes server.
   * @note __MUST__ be called before node process shutdown to correctly
   *   update the state.
   * @param {Callback} [cb] Optional callback.
   * @return {Promise<void>}
   */
  close (cb) {
    if (this.closed) { return Promise.resolve() }
    this.closed = true
    clearInterval(this.hbtimer)
    let closeError = null
    return this.transport.close().then(
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

mix(ChatService, ServiceAPI, RecoveryAPI)
ChatService.ChatServiceError = ChatServiceError

module.exports = ChatService
