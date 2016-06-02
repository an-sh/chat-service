
ChatServiceError = require './ChatServiceError'
EventEmitter = require('events').EventEmitter
Promise = require 'bluebird'
RedisAdapter = require 'socket.io-redis'
SocketServer = require 'socket.io'
_ = require 'lodash'
hasBinary = require 'has-binary'

{ checkNameSymbols } = require './utils'


# @private
# @nodoc
# Cluster bus.
class ClusterBus extends EventEmitter

  # @private
  constructor : (@server, @adapter) ->
    @channel = 'cluster:bus'
    @intenalEvents = ['disconnectSocket', 'socketDisconnected'
    , 'roomLeaveSocket', 'socketRoomLeft']
    @types = [ 2, 5 ]
    @customMessageName = 'custom'
    @adapter.add @server.instanceUID, @channel

  # @private
  emit : (ev, args...) ->
    packet = type : (if hasBinary(args) then 5 else 2)
    , data : [ @customMessageName, @server.instanceUID, ev, args... ]
    opts = rooms : [ @channel ]
    @adapter.broadcast packet, opts, false

  # @private
  onPacket : (packet) ->
    [ev, uid, args...] = packet.data
    if uid == @server.instanceUID then return
    emit = @.constructor.__super__.emit.bind @
    if _.find ev, @intenalEvents
      return emit ev, args...
    if ev == @customMessageName
      return emit args...


# @private
# @nodoc
# Socket.io transport.
class SocketIOTransport

  # @private
  constructor : (@server, @options, @adapterConstructor, @adapterOptions) ->
    @hooks = @server.hooks
    @io = @options.io
    @namespace = @options.namespace || '/chat-service'
    Adapter = switch true
      when @adapterConstructor == 'memory' then null
      when @adapterConstructor == 'redis' then RedisAdapter
      when _.isFunction @adapterConstructor then @adapterConstructor
      else throw new Error "Invalid transport adapter: #{@adapterConstructor}"
    unless @io
      @ioOptions = @options.ioOptions
      @http = @options.http
      if @http
        @dontCloseIO = true
        @io = new SocketServer @options.http
      else
        @io = new SocketServer @server.port, @ioOptions
      if Adapter
        @adapter = new Adapter @adapterOptions...
        @io.adapter @adapter
    else
      @dontCloseIO = true
    @nsp = @io.of @namespace
    @server.io = @io
    @server.nsp = @nsp
    @clusterBus = new ClusterBus @server, @nsp.adapter
    @injectBusHook()
    @server.clusterBus = @clusterBus
    @closed = false

  # @private
  broadcastHook : (packet, opts) ->
    if( _.indexOf(opts.rooms, @clusterBus.channel) >= 0 and
    _.indexOf(@clusterBus.types, packet.type) >= 0 )
      @clusterBus.onPacket packet

  # @private
  # TODO: Use an API from socket.io if(when) it will be available.
  injectBusHook : ->
    broadcastHook = @broadcastHook.bind @
    adapter = @nsp.adapter
    orig = adapter.broadcast
    adapter.broadcast = (args...) ->
      broadcastHook args...
      orig.apply adapter, args

  # @private
  rejectLogin : (socket, error) ->
    useRawErrorObjects = @server.useRawErrorObjects
    unless useRawErrorObjects
      error = error?.toString?()
    socket.emit 'loginRejected', error
    socket.disconnect()

  # @private
  confirmLogin : (socket, userName, authData) ->
    authData.id = socket.id
    socket.emit 'loginConfirmed', userName, authData
    Promise.resolve()

  # @private
  addClient : (error, socket, userName, authData = {}) ->
    id = socket.id
    Promise.try ->
      if error then Promise.reject error
    .then ->
      unless userName
        userName = socket.handshake.query?.user
        unless userName
          Promise.reject new ChatServiceError 'noLogin'
    .then ->
      checkNameSymbols userName
    .then =>
      @server.state.getOrAddUser userName
    .then (user) ->
      user.registerSocket id
    .spread (user, nconnected) =>
      @joinChannel id, user.echoChannel
      .then =>
        user.socketConnectEcho id, nconnected
        @confirmLogin socket, userName, authData
    .catch (error) =>
      @rejectLogin socket, error

  # @private
  setEvents : ->
    if @hooks.middleware
      middleware = _.castArray @hooks.middleware
      for fn in middleware
        @nsp.use fn
    if @hooks.onConnect
      @nsp.on 'connection', (socket) =>
        @hooks.onConnect @server, socket.id, (error, userName, authData) =>
          @addClient error, socket, userName, authData
    else
      @nsp.on 'connection', (socket) =>
        @addClient null, socket

  # @private
  waitCommands : ->
    if @server.runningCommands > 0
      Promise.fromCallback (cb) =>
        @server.once 'commandsFinished', cb

  # @private
  close : ->
    @closed = true
    @nsp.removeAllListeners 'connection'
    Promise.try =>
      unless @dontCloseIO
        @io.close()
      else if @http
        @io.engine.close()
      else
        for id, socket of @nsp.connected
          socket.disconnect()
      return
    .then =>
      @waitCommands()
    .timeout @server.closeTimeout

  # @private
  bindHandler : (id, name, fn) ->
    socket = @getSocketObject id
    if socket
      socket.on name, fn

  # @private
  getSocketObject : (id) ->
    @nsp.connected[id]

  # @private
  # getSocketRooms : (id) ->
  #   socket = @getSocketObject id
  #   unless socket then return
  #   return socket.rooms()

  # @private
  sendToChannel : (channel, args...) ->
    @nsp.to(channel).emit args...
    return

  # @private
  sendToOthers : (id, channel, args...) ->
    socket = @getSocketObject id
    unless socket
      @sendToChannel channel, args...
    else
      socket.to(channel).emit args...
    return

  # @private
  joinChannel : (id, channel) ->
    socket = @getSocketObject id
    unless socket
      Promise.reject new ChatServiceError 'invalidSocket', id
    else
      Promise.fromCallback (fn) ->
        socket.join channel, fn

  # @private
  leaveChannel : (id, channel) ->
    socket = @getSocketObject id
    unless socket then return Promise.resolve()
    Promise.fromCallback (fn) ->
      socket.leave channel, fn

  # @private
  disconnectClient : (id) ->
    socket = @getSocketObject id
    if socket
      socket.disconnect()
    Promise.resolve()


module.exports = SocketIOTransport
