
ChatServiceError = require './ChatServiceError'
EventEmitter = require('events').EventEmitter
Promise = require 'bluebird'
RedisAdapter = require 'socket.io-redis'
SocketServer = require 'socket.io'
Transport = require './Transport'
_ = require 'lodash'
hasBinary = require 'has-binary'

{ debuglog, execHook, checkNameSymbols } = require './utils'


# @private
# @nodoc
# Cluster bus.
class ClusterBus extends EventEmitter

  # @private
  constructor : (server, adapter) ->
    super()
    @server = server
    @adapter = adapter
    @channel = 'cluster:bus'
    @intenalEvents = ['roomLeaveSocket', 'socketRoomLeft'
      , 'disconnectUserSockets']
    @types = [ 2, 5 ]

  # @private
  listen : ->
    Promise.fromCallback (cb) =>
      @adapter.add @server.instanceUID, @channel, cb

  # @private
  makeSocketRoomLeftName : (id, roomName) ->
    "socketRoomLeft:#{id}:#{roomName}"

  # @private
  mergeEventName : (ev, args) ->
    switch ev
      when 'socketRoomLeft'
        [ id, roomName, nargs... ] = args
        nev = @makeSocketRoomLeftName id, roomName
        [nev, nargs]
      else
        [ev, args]

  # @private
  # TODO: Use an API from socket.io if(when) it will be available.
  emit : (ev, args...) ->
    data = [ ev, args... ]
    packet = type : (if hasBinary(args) then 5 else 2)
    , data : data
    opts = rooms : [ @channel ]
    @adapter.broadcast packet, opts, false

  # @private
  onPacket : (packet) ->
    [ev, args...] = packet.data
    emit = @.constructor.__super__.emit.bind @
    if _.includes @intenalEvents, ev
      [nev, nargs] = @mergeEventName ev, args
      emit nev, nargs...
    else
      emit ev, args...


# @private
# @nodoc
# Socket.io transport.
class SocketIOTransport extends Transport

  # @private
  constructor : (server, options, adapterConstructor, adapterOptions) ->
    super
    @server = server
    @options = options
    @adapterConstructor = adapterConstructor
    @adapterOptions = adapterOptions
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
    @attachBusListeners()
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
  attachBusListeners : ->
    @clusterBus.on 'roomLeaveSocket', (id, roomName) =>
      @leaveChannel id, roomName
      .then =>
        @clusterBus.emit 'socketRoomLeft', id, roomName
      .catchReturn()
    @clusterBus.on 'disconnectUserSockets', (userName) =>
      @server.state.getUser userName
      .then (user) ->
        user.disconnectInstanceSockets()
      .catchReturn()

  # @private
  rejectLogin : (socket, error) ->
    useRawErrorObjects = @server.useRawErrorObjects
    if error? and not (error instanceof ChatServiceError)
      debuglog error
    if error? and not useRawErrorObjects
      error = error.toString()
    socket.emit 'loginRejected', error
    socket.disconnect()

  # @private
  confirmLogin : (socket, userName, authData) ->
    authData.id = socket.id
    socket.emit 'loginConfirmed', userName, authData
    Promise.resolve()

  # @private
  addClient : (socket, userName, authData = {}) ->
    id = socket.id
    Promise.try ->
      unless userName
        query = socket.handshake.query
        userName = query and query.user
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
        Promise.try =>
          execHook @hooks.onConnect, @server, socket.id
        .then (loginData) =>
          loginData = _.castArray loginData
          @addClient socket, loginData...
        .catch (error) =>
          @rejectLogin socket, error
    else
      @nsp.on 'connection', @addClient.bind @
    Promise.resolve()

  # @private
  waitCommands : ->
    if @server.runningCommands > 0
      Promise.fromCallback (cb) =>
        @server.once 'commandsFinished', cb

  # @private
  close : ->
    @closed = true
    @nsp.removeAllListeners 'connection'
    @clusterBus.removeAllListeners()
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
    socket = @getConnectionObject id
    if socket
      socket.on name, fn

  # @private
  getConnectionObject : (id) ->
    super
    @nsp.connected[id]

  # @private
  emitToChannel : (channel, messageName, messageData...) ->
    super
    @nsp.to(channel).emit messageName, messageData...
    return

  # @private
  sendToChannel : (id, channel, messageName, messageData...) ->
    super
    socket = @getConnectionObject id
    unless socket
      @emitToChannel channel, messageName, messageData...
    else
      socket.to(channel).emit messageName, messageData...
    return

  # @private
  joinChannel : (id, channel) ->
    socket = @getConnectionObject id
    unless socket
      Promise.reject new ChatServiceError 'invalidSocket', id
    else
      Promise.fromCallback (fn) ->
        socket.join channel, fn

  # @private
  leaveChannel : (id, channel) ->
    socket = @getConnectionObject id
    unless socket then return Promise.resolve()
    Promise.fromCallback (fn) ->
      socket.leave channel, fn

  # @private
  disconnectClient : (id) ->
    socket = @getConnectionObject id
    if socket
      socket.disconnect()
    Promise.resolve()


module.exports = SocketIOTransport
