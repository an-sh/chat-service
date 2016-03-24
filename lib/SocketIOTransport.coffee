
_ = require 'lodash'
Promise = require 'bluebird'
RedisAdapter = require 'socket.io-redis'
SocketServer = require 'socket.io'


{ checkNameSymbols
  bindTE
} = require './utils.coffee'

# @private
# @nodoc
# Socket.io transport.
class SocketIOTransport

  # @private
  # @nodoc
  constructor : (@server, @options, @adapterConstructor, @adapterOptions) ->
    @hooks = @server.hooks
    @errorBuilder = @server.errorBuilder
    bindTE @
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
    @setLivecycle()

  # @private
  # @nodoc
  setLivecycle : ->
    @nclosing = 0
    @closeCB = null
    @finished = false

  # @private
  # @nodoc
  bind : (id, name, fn) ->
    socket = @getSocketObject id
    if socket
      socket.on name, fn

  # @private
  # @nodoc
  rejectLogin : (socket, error) ->
    socket.emit 'loginRejected', error
    socket.disconnect(true)

  # @private
  # @nodoc
  confirmLogin : (socket, userName, authData) ->
    if _.isObject(authData)
      authData.id = socket.id unless authData.id?
    socket.emit 'loginConfirmed', userName, authData

  # @private
  # @nodoc
  addClient : (error, socket, userName, authData = {}) ->
    if error then return @rejectLogin socket, error
    unless userName
      userName = socket.handshake.query?.user
      unless userName
        error = @errorBuilder.makeError 'noLogin'
        return @rejectLogin socket, error
    if checkNameSymbols userName
      error = @errorBuilder.makeError 'invalidName', userName
      return @rejectLogin socket, error
    @server.state.loginUserSocket @server.serverUID, userName, socket.id
    .spread (user, nconnected) =>
      socket.join user.echoChannel, @withTE (error) =>
        if error then return @rejectLogin socket, error
        user.socketConnectEcho socket.id, nconnected
        @confirmLogin socket, userName, authData
    , (error) ->
      @rejectLogin socket, error


  # @private
  # @nodoc
  checkShutdown : (socket, next) ->
    if @closeCB or @finished
      return socket.disconnect(true)
    next()

  # @private
  # @nodoc
  setEvents : ->
    if @hooks.middleware
      middleware = _.castArray @hooks.middleware
      for fn in middleware
        @nsp.use fn
    if @hooks.onConnect
      @nsp.on 'connection', (socket) =>
        @checkShutdown socket, =>
          @hooks.onConnect @server, socket.id, (error, userName, authData) =>
            @addClient error, socket, userName, authData
    else
      @nsp.on 'connection', (socket) =>
        @checkShutdown socket, =>
          @addClient null, socket

  # @private
  # @nodoc
  finish : () ->
    if @closeCB and not @finished
      @finished = true
      @closeCB()

  # @private
  # @nodoc
  startClientDisconnect : () ->
    unless @closeCB then @nclosing++

  # @private
  # @nodoc
  endClientDisconnect : () ->
    @nclosing--
    if @closeCB and @nclosing == 0
      process.nextTick => @finish()

  # @private
  # @nodoc
  close : (done = ->) ->
    @closeCB = (error) =>
      @closeCB = null
      unless @dontCloseIO
        @io.close()
      if @http
        @io.engine.close()
      done error
    closeStartingTime = _.now()
    closingTimeoutChecker = =>
      if @finished then return
      timeCurrent = _.now()
      if timeCurrent > closeStartingTime + @closeTimeout
        @finished = true
        @closeCB new Error 'Transport closing timeout.'
      else
        setTimeout closingTimeoutChecker, 100
    for sid, socket of @nsp.connected
      @nclosing++
      socket.disconnect()
    if @nclosing == 0
      process.nextTick => @closeCB()
    else
      closingTimeoutChecker()

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
      Promise.reject @errorBuilder.makeError 'serverError', 500
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


module.exports = SocketIOTransport
