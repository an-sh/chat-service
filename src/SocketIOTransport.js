
const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const RedisAdapter = require('socket.io-redis')
const SocketIOClusterBus = require('./SocketIOClusterBus')
const SocketServer = require('socket.io')
const _ = require('lodash')
const { convertError, run } = require('./utils')

// Socket.io transport.
class SocketIOTransport {

  constructor (server, options, adapterConstructor, adapterOptions) {
    this.server = server
    this.options = options
    this.adapterConstructor = adapterConstructor
    this.adapterOptions = adapterOptions
    this.io = this.options.io
    this.middleware = options.middleware
    this.namespace = this.options.namespace || '/chat-service'
    let Adapter = (() => {
      switch (true) {
        case this.adapterConstructor === 'memory':
          return null
        case this.adapterConstructor === 'redis':
          return RedisAdapter
        case _.isFunction(this.adapterConstructor):
          return this.adapterConstructor
        default:
          let c = this.adapterConstructor
          throw new Error(`Invalid transport adapter: ${c}`)
      }
    })()
    if (!this.io) {
      this.ioOptions = this.options.ioOptions
      this.http = this.options.http
      if (this.http) {
        this.dontCloseIO = true
        this.io = new SocketServer(this.options.http, this.ioOptions)
      } else {
        this.io = new SocketServer(this.server.port, this.ioOptions)
      }
      if (Adapter) {
        this.adapter = new Adapter(...this.adapterOptions)
        this.io.adapter(this.adapter)
      }
    } else {
      this.dontCloseIO = true
    }
    this.nsp = this.io.of(this.namespace)
    this.server.io = this.io
    this.server.nsp = this.nsp
    this.clusterBus = new SocketIOClusterBus(this.server, this.nsp.adapter)
    this.closed = false
  }

  rejectLogin (socket, error) {
    error = convertError(error, this.server.useRawErrorObjects)
    socket.emit('loginRejected', error)
    socket.disconnect()
    return Promise.resolve()
  }

  confirmLogin (socket, userName, authData) {
    authData.id = socket.id
    socket.emit('loginConfirmed', userName, authData)
    return Promise.resolve()
  }

  ensureUserName (socket, userName) {
    return Promise.try(() => {
      if (!userName) {
        let { query } = socket.handshake
        userName = query && query.user
        if (!userName) {
          return Promise.reject(new ChatServiceError('noLogin'))
        }
      }
      return Promise.resolve(userName)
    })
  }

  setEvents () {
    if (this.middleware) {
      let middleware = _.castArray(this.middleware)
      for (let fn of middleware) {
        this.nsp.use(fn)
      }
    }
    this.nsp.on('connection', socket => {
      return run(this, function * () {
        let id = socket.id
        let [userName, authData = {}] = yield this.server.onConnect(id)
        userName = yield this.ensureUserName(socket, userName)
        yield this.server.registerClient(userName, id)
        yield this.confirmLogin(socket, userName, authData)
      }).catch(error => this.rejectLogin(socket, error))
    })
    return Promise.resolve()
  }

  close () {
    this.closed = true
    this.nsp.removeAllListeners('connection')
    this.clusterBus.removeAllListeners()
    return Promise.try(() => {
      if (!this.dontCloseIO) {
        this.io.close()
      } else if (this.http) {
        this.io.engine.close()
      } else {
        for (let [, socket] of _.toPairs(this.nsp.connected)) {
          socket.disconnect()
        }
      }
      return Promise.resolve()
    })
  }

  bindHandler (id, name, fn) {
    let socket = this.getSocket(id)
    if (socket) {
      socket.on(name, fn)
    }
  }

  getSocket (id) {
    return this.nsp.connected[id]
  }

  emitToChannel (channel, eventName, ...eventData) {
    this.nsp.to(channel).emit(eventName, ...eventData)
  }

  sendToChannel (id, channel, eventName, ...eventData) {
    let socket = this.getSocket(id)
    if (!socket) {
      this.emitToChannel(channel, eventName, ...eventData)
    } else {
      socket.to(channel).emit(eventName, ...eventData)
    }
  }

  joinChannel (id, channel) {
    let socket = this.getSocket(id)
    if (!socket) {
      return Promise.reject(new ChatServiceError('invalidSocket', id))
    } else {
      return Promise.fromCallback(fn => socket.join(channel, fn))
    }
  }

  leaveChannel (id, channel) {
    let socket = this.getSocket(id)
    if (!socket) { return Promise.resolve() }
    return Promise.fromCallback(fn => socket.leave(channel, fn))
  }

  disconnectSocket (id) {
    let socket = this.getSocket(id)
    if (socket) {
      socket.disconnect()
    }
    return Promise.resolve()
  }

}

module.exports = SocketIOTransport
