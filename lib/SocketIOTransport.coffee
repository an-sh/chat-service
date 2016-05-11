
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'
RedisAdapter = require 'socket.io-redis'
SocketServer = require 'socket.io'
_ = require 'lodash'
EventEmitter = require('events').EventEmitter

{ checkNameSymbols } = require './utils.coffee'


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
    @closed = false

  # @private
  rejectLogin : (socket, error) ->
    useRawErrorObjects = @server.useRawErrorObjects
    unless useRawErrorObjects
      error = error?.toString()
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
        @server.once 'close', cb

  # @private
  close : () ->
    if @closed then return Promise.resolve()
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
    .timeout 5000

  # @private
  bind : (id, name, fn) ->
    socket = @getSocketObject id
    if socket
      socket.on name, fn

  # @private
  getSocketObject : (id) ->
    @nsp.connected[id]

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
      Promise.reject new ChatServiceError 'serverError', 500
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
