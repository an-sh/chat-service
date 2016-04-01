
ChatServiceError = require './ChatServiceError.coffee'
Promise = require 'bluebird'
RedisAdapter = require 'socket.io-redis'
Set = require 'collections/fast-set'
SocketServer = require 'socket.io'
_ = require 'lodash'
EventEmitter = require('events').EventEmitter

{ checkNameSymbols } = require './utils.coffee'


# @private
# @nodoc
# Socket.io transport.
class SocketIOTransport

  # @private
  # @nodoc
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
    @disconnectNotify = new EventEmitter()
    @closing = new Set()
    @closed = false

  # @private
  # @nodoc
  rejectLogin : (socket, error) ->
    useRawErrorObjects = @server.useRawErrorObjects
    unless useRawErrorObjects
      error = error?.toString()
    socket.emit 'loginRejected', error
    socket.disconnect()

  # @private
  # @nodoc
  confirmLogin : (socket, userName, authData) ->
    if _.isObject(authData)
      authData.id = socket.id unless authData.id?
    socket.emit 'loginConfirmed', userName, authData
    Promise.resolve()

  # @private
  # @nodoc
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
      @server.state.loginUserSocket @server.serverUID, userName, id
    .spread (user, nconnected) =>
      @joinChannel id, user.echoChannel
      .then =>
        user.socketConnectEcho id, nconnected
        @confirmLogin socket, userName, authData
    .catch (error) =>
      @rejectLogin socket, error

  # @private
  # @nodoc
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
  # @nodoc
  startClientDisconnect : (id) ->
    wasDisconnecting = @closing.has id
    @closing.add id
    return wasDisconnecting

  # @private
  # @nodoc
  endClientDisconnect : (id) ->
    @closing.delete id
    @disconnectNotify.emit 'endClientDisconnect', @closing.length
    return

  # @private
  # @nodoc
  waitDisconnectAll : ->
    if @closing.length > 0
      Promise.fromCallback (cb) =>
        @disconnectNotify.on 'endClientDisconnect', (n) =>
          if n == 0
            @disconnectNotify.removeAllListeners 'endClientDisconnect'
            cb()

  # @private
  # @nodoc
  close : (done) ->
    if @closed
      return Promise.resolve().asCallback done
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
      @waitDisconnectAll()
    .timeout 5000
    .asCallback done

  # @private
  # @nodoc
  bind : (id, name, fn) ->
    socket = @getSocketObject id
    if socket
      socket.on name, fn

  # @private
  # @nodoc
  getSocketObject : (id) ->
    @nsp.connected[id]

  # @private
  # @nodoc
  sendToChannel : (channel, args...) ->
    @nsp.to(channel).emit args...
    Promise.resolve()

  # @private
  # @nodoc
  sendToOthers : (id, channel, args...) ->
    socket = @getSocketObject id
    unless socket
      @sendToChannel channel, args...
    else
      socket.to(channel).emit args...
      Promise.resolve()

  # @private
  # @nodoc
  joinChannel : (id, channel) ->
    socket = @getSocketObject id
    unless socket
      Promise.reject new ChatServiceError 'serverError', 500
    else
      Promise.fromCallback (fn) ->
        socket.join channel, fn

  # @private
  # @nodoc
  leaveChannel : (id, channel) ->
    socket = @getSocketObject id
    unless socket then return Promise.resolve()
    Promise.fromCallback (fn) ->
      socket.leave channel, fn

  # @private
  # @nodoc
  disconnectClient : (id) ->
    socket = @getSocketObject id
    if socket
      socket.disconnect()
    Promise.resolve()


module.exports = SocketIOTransport
