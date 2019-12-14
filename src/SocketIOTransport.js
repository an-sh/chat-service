'use strict'

const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const RedisAdapter = require('socket.io-redis')
const SocketIOClusterBus = require('./SocketIOClusterBus')
const SocketServer = require('socket.io')
const eventToPromise = require('event-to-promise')
const _ = require('lodash')
const { possiblyCallback, run } = require('./utils')

// Socket.io transport.
class SocketIOTransport {
  constructor (server, options) {
    this.server = server
    this.options = options
    this.adapterConstructor = this.options.adapterConstructor
    this.adapterOptions = this.options.adapterOptions
    this.port = this.server.port
    this.io = this.options.io
    this.middleware = this.options.middleware
    this.namespace = this.options.namespace || '/chat-service'
    let Adapter
    if (this.adapterConstructor === 'memory') {
    } else if (this.adapterConstructor === 'redis') {
      Adapter = RedisAdapter
    } else if (_.isFunction(this.adapterConstructor)) {
      Adapter = this.adapterConstructor
    } else {
      throw new Error(`Invalid transport adapter: ${this.adapterConstructor}`)
    }
    if (!this.io) {
      this.ioOptions = this.options.ioOptions
      this.http = this.options.http
      if (this.http) {
        this.io = new SocketServer(this.options.http, this.ioOptions)
      } else {
        this.io = new SocketServer(this.port, this.ioOptions)
      }
      if (Adapter) {
        this.adapter = new Adapter(...this.adapterOptions)
        this.io.adapter(this.adapter)
      }
    }
    this.nsp = this.io.of(this.namespace)
    this.server.io = this.io
    this.server.nsp = this.nsp
    this.clusterBus = new SocketIOClusterBus(this.server, this)
    this.closed = false
  }

  resultsTransform (cb) {
    if (!cb) { return }
    return (error, data, ...rest) => {
      error = this.server.convertError(error)
      if (error == null) { error = null }
      if (data == null) { data = null }
      cb(error, data, ...rest)
    }
  }

  rejectLogin (socket, error) {
    error = this.server.convertError(error)
    socket.emit('loginRejected', error)
    socket.disconnect()
  }

  confirmLogin (socket, userName, authData) {
    authData.id = socket.id
    socket.emit('loginConfirmed', userName, authData)
  }

  setEvents () {
    if (this.middleware) {
      const middleware = _.castArray(this.middleware)
      for (const fn of middleware) {
        this.nsp.use(fn)
      }
    }
    this.nsp.on('connection', socket => {
      return run(this, function * () {
        const id = socket.id
        const [userName, authData = {}] = yield this.server.onConnect(id)
        if (!userName) {
          return Promise.reject(new ChatServiceError('noLogin'))
        }
        yield this.server.registerClient(userName, id)
        this.confirmLogin(socket, userName, authData)
      }).catch(error => this.rejectLogin(socket, error))
    })
  }

  close () {
    this.closed = true
    this.nsp.removeAllListeners('connection')
    this.clusterBus.removeAllListeners()
    return Promise.fromCallback(cb => this.io.close(cb))
      .then(() => {
        return this.server.runningCommands === 0
          ? Promise.resolve()
          : eventToPromise(this.server, 'commandsFinished')
      })
      .then(() => {
        if (this.adapter) {
          if (this.adapter.pubClient) {
            this.adapter.pubClient.quit()
          }
          if (this.adapter.subClient) {
            this.adapter.subClient.quit()
          }
        }
      })
  }

  bindHandler (id, name, fn) {
    const socket = this.getSocket(id)
    if (socket) {
      socket.on(name, (...oargs) => {
        const [args, cb] = possiblyCallback(oargs)
        const ack = this.resultsTransform(cb)
        fn(...args).asCallback(ack, { spread: true })
      })
    }
  }

  getServer () {
    return this.io
  }

  getSocket (id) {
    return this.nsp.connected[id]
  }

  emitToChannel (channel, eventName, ...eventData) {
    this.nsp.to(channel).emit(eventName, ...eventData)
  }

  sendToChannel (id, channel, eventName, ...eventData) {
    const socket = this.getSocket(id)
    if (!socket) {
      this.emitToChannel(channel, eventName, ...eventData)
    } else {
      socket.to(channel).emit(eventName, ...eventData)
    }
  }

  getHandshakeData (id) {
    const res = { isConnected: false, query: {}, headers: {} }
    const socket = this.getSocket(id)
    if (!socket) { return res }
    res.isConnected = true
    res.query = socket.handshake.query
    res.headers = socket.handshake.headers
    return res
  }

  joinChannel (id, channel) {
    const socket = this.getSocket(id)
    if (!socket) {
      return Promise.reject(new ChatServiceError('invalidSocket', id))
    } else {
      return Promise.fromCallback(fn => socket.join(channel, fn))
    }
  }

  leaveChannel (id, channel) {
    const socket = this.getSocket(id)
    if (!socket) { return Promise.resolve() }
    return Promise.fromCallback(fn => socket.leave(channel, fn))
  }

  disconnectSocket (id) {
    const socket = this.getSocket(id)
    if (socket) {
      socket.disconnect()
    }
    return Promise.resolve()
  }
}

module.exports = SocketIOTransport
