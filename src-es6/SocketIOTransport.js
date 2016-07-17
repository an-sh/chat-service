
const ChatServiceError = require('./ChatServiceError')
const Promise = require('bluebird')
const RedisAdapter = require('socket.io-redis')
const SocketServer = require('socket.io')
const Transport = require('./Transport')
const _ = require('lodash')
const hasBinary = require('has-binary')
const { EventEmitter } = require('events')
const { debuglog, execHook, checkNameSymbols } = require('./utils')

// Cluster bus.
class ClusterBus extends EventEmitter {

  constructor (server, adapter) {
    super()
    this.server = server
    this.adapter = adapter
    this.channel = 'cluster:bus'
    this.intenalEvents = [ 'roomLeaveSocket',
                           'socketRoomLeft',
                           'disconnectUserSockets' ]
    this.types = [ 2, 5 ]
  }

  listen () {
    return Promise.fromCallback(cb => {
      return this.adapter.add(this.server.instanceUID, this.channel, cb)
    })
  }

  makeSocketRoomLeftName (id, roomName) {
    return `socketRoomLeft:${id}:${roomName}`
  }

  mergeEventName (ev, args) {
    switch (ev) {
      case 'socketRoomLeft':
        let [id, roomName, ...nargs] = args
        let nev = this.makeSocketRoomLeftName(id, roomName)
        return [nev, nargs]
      default:
        return [ev, args]
    }
  }

  // TODO: Use an API from socket.io if(when) it will be available.
  emit (ev, ...args) {
    let data = [ ev, ...args ]
    let packet = { type: (hasBinary(args) ? 5 : 2), data }
    let opts = { rooms: [ this.channel ] }
    return this.adapter.broadcast(packet, opts, false)
  }

  onPacket (packet) {
    let [ev, ...args] = packet.data
    if (_.includes(this.intenalEvents, ev)) {
      let [nev, nargs] = this.mergeEventName(ev, args)
      return super.emit(nev, ...nargs)
    } else {
      return super.emit(ev, ...args)
    }
  }
}

// Socket.io transport.
class SocketIOTransport extends Transport {

  constructor (server, options, adapterConstructor, adapterOptions) {
    super()
    this.server = server
    this.options = options
    this.adapterConstructor = adapterConstructor
    this.adapterOptions = adapterOptions
    this.hooks = this.server.hooks
    this.io = this.options.io
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
        this.io = new SocketServer(this.options.http)
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
    this.clusterBus = new ClusterBus(this.server, this.nsp.adapter)
    this.injectBusHook()
    this.attachBusListeners()
    this.server.clusterBus = this.clusterBus
    this.closed = false
  }

  broadcastHook (packet, opts) {
    let isBusCahnnel = _.indexOf(opts.rooms, this.clusterBus.channel) >= 0
    let isBusType = _.indexOf(this.clusterBus.types, packet.type) >= 0
    if (isBusCahnnel && isBusType) {
      this.clusterBus.onPacket(packet)
    }
  }

  // TODO: Use an API from socket.io if(when) it will be available.
  injectBusHook () {
    let broadcastHook = this.broadcastHook.bind(this)
    let { adapter } = this.nsp
    let orig = adapter.broadcast
    adapter.broadcast = function (...args) {
      broadcastHook(...args)
      orig.apply(adapter, args)
    }
  }

  attachBusListeners () {
    this.clusterBus.on('roomLeaveSocket', (id, roomName) => {
      return this.leaveChannel(id, roomName)
        .then(() => this.clusterBus.emit('socketRoomLeft', id, roomName))
        .catchReturn()
    })
    return this.clusterBus.on('disconnectUserSockets', userName => {
      return this.server.state.getUser(userName)
        .then(user => user.disconnectInstanceSockets())
        .catchReturn()
    })
  }

  rejectLogin (socket, error) {
    let { useRawErrorObjects } = this.server
    if ((error != null) && !(error instanceof ChatServiceError)) {
      debuglog(error)
    }
    if ((error != null) && !useRawErrorObjects) {
      error = error.toString()
    }
    socket.emit('loginRejected', error)
    return socket.disconnect()
  }

  confirmLogin (socket, userName, authData) {
    authData.id = socket.id
    socket.emit('loginConfirmed', userName, authData)
    return Promise.resolve()
  }

  addClient (socket, userName, authData = {}) {
    let { id } = socket
    return Promise.try(() => {
      if (!userName) {
        let { query } = socket.handshake
        userName = query && query.user
        if (!userName) {
          return Promise.reject(new ChatServiceError('noLogin'))
        }
      }
      return Promise.resolve()
    }).then(() => checkNameSymbols(userName))
      .then(() => this.server.state.getOrAddUser(userName))
      .then(user => user.registerSocket(id))
      .spread((user, nconnected) => {
        return this.joinChannel(id, user.echoChannel)
          .then(() => {
            user.socketConnectEcho(id, nconnected)
            return this.confirmLogin(socket, userName, authData)
          })
      }).catch(error => this.rejectLogin(socket, error))
  }

  setEvents () {
    if (this.hooks.middleware) {
      let middleware = _.castArray(this.hooks.middleware)
      for (let i = 0; i < middleware.length; i++) {
        let fn = middleware[i]
        this.nsp.use(fn)
      }
    }
    if (this.hooks.onConnect) {
      this.nsp.on('connection', socket => {
        return Promise.try(() => {
          return execHook(this.hooks.onConnect, this.server, socket.id)
        }).then(loginData => {
          loginData = _.castArray(loginData)
          return this.addClient(socket, ...loginData)
        }).catch(error => this.rejectLogin(socket, error))
      })
    } else {
      this.nsp.on('connection', this.addClient.bind(this))
    }
    return Promise.resolve()
  }

  waitCommands () {
    if (this.server.runningCommands > 0) {
      return Promise.fromCallback(cb => {
        return this.server.once('commandsFinished', cb)
      })
    } else {
      return Promise.resolve()
    }
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
        for (let id in this.nsp.connected) {
          let socket = this.nsp.connected[id]
          socket.disconnect()
        }
      }
    }).then(() => this.waitCommands())
      .timeout(this.server.closeTimeout)
  }

  bindHandler (id, name, fn) {
    let socket = this.getConnectionObject(id)
    if (socket) {
      socket.on(name, fn)
    }
  }

  getConnectionObject (id) {
    return this.nsp.connected[id]
  }

  emitToChannel (channel, messageName, ...messageData) {
    this.nsp.to(channel).emit(messageName, ...messageData)
  }

  sendToChannel (id, channel, messageName, ...messageData) {
    let socket = this.getConnectionObject(id)
    if (!socket) {
      this.emitToChannel(channel, messageName, ...messageData)
    } else {
      socket.to(channel).emit(messageName, ...messageData)
    }
  }

  joinChannel (id, channel) {
    let socket = this.getConnectionObject(id)
    if (!socket) {
      return Promise.reject(new ChatServiceError('invalidSocket', id))
    } else {
      return Promise.fromCallback(fn => socket.join(channel, fn))
    }
  }

  leaveChannel (id, channel) {
    let socket = this.getConnectionObject(id)
    if (!socket) { return Promise.resolve() }
    return Promise.fromCallback(fn => socket.leave(channel, fn))
  }

  disconnectClient (id) {
    let socket = this.getConnectionObject(id)
    if (socket) {
      socket.disconnect()
    }
    return Promise.resolve()
  }

}

module.exports = SocketIOTransport
