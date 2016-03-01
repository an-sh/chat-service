
_ = require 'lodash'
SocketServer = require 'socket.io'


# @private
# @nodoc
#
# Implements message transport.
class SocketIOTransport

  # @private
  constructor : (@server, @options = {}, @hooks = {}) ->
    @errorBuilder = @server.errorBuilder

    @namespace = @options.namespace || '/chat-service'
    @sharedIO = true if @io
    @http = @options.http unless @io
    @adapterConstructor = @options.adapter || 'memory'
    @adapterOptions = @options.adapterOptions
    Adapter = switch @adapterConstructor
      when 'memory' then null
      when 'redis' then RedisAdapter
      when _.isFunction @adapterConstructor then @adapterConstructor
      else throw new Error "Invalid adapter: #{@adapterConstructor}"
    unless @io
      if @http
        @io = new SocketServer @http, @socketIoServerOptions
      else
        @port = @options.port || 8000
        @io = new SocketServer @port, @socketIoServerOptions
      if Adapter
        @adapter = new Adapter @adapterOptions
        @io.adapter @adapter
    @nsp = @io.of @namespace
    @setLivecycle()

  # @private
  setLivecycle : ->
    @nclosing = 0
    @closeCB = null
    @finished = false

  # @private
  getSocketObject : (id) ->
    @nsp.connected[id]

  # @private
  bind : (id, name, fn) ->
    socket = @getSocketObject id
    if socket
      socket.on name, fn

  # @private
  rejectLogin : (socket, error) ->
    socket.emit 'loginRejected', error
    socket.disconnect(true)

  # @private
  confirmLogin : (socket, userName, authData) ->
    if _.isObject(authData)
      authData.id = socket.id unless authData.id?
    socket.emit 'loginConfirmed', userName, authData

  # @private
  addClient : (error, socket, userName, authData = {}) ->
    if error then return @rejectLogin socket, error
    unless userName
      userName = socket.handshake.query?.user
      unless userName
        error = @errorBuilder.makeError 'noLogin'
        return @rejectLogin socket, error
    # TODO watch for disconnect
    @server.state.loginUserSocket @server.serverUID, userName, socket.id
    , (error, user) =>
      if error
        @rejectLogin socket, error
      else
        socket.join user.echoChannel, =>
          socket.on 'disconnect', => @startClientDisconnect()
          @confirmLogin socket, userName, authData

  # @private
  disconnectClient : (id) ->
    socket = @getSocketObject id
    if socket
      socket.disconnect()

  # @private
  checkShutdown : (socket, next) ->
    if @closeCB or @finished
      return socket.disconnect(true)
    next()

  # @private
  setEvents : ->
    @directMessageChecker = @hooks.directMessageChecker
    @roomMessageChecker = @hooks.roomMessageChecker
    if @hooks.middleware
      if _.isFunction @hooks.middleware
        @nsp.use @hooks.middleware
      else
        for fn in @hooks.middleware
          @nsp.use fn
    if @hooks.onConnect
      @nsp.on 'connection', (socket) =>
        @checkShutdown socket, =>
          @hooks.onConnect @, socket.id, (error, userName, authData) =>
            @addClient error, socket, userName, authData
    else
      @nsp.on 'connection', (socket) =>
        @checkShutdown socket, =>
          @addClient null, socket

  # @private
  finish : () ->
    if @closeCB and !@finished
      @finished = true
      @closeCB()

  # @private
  startClientDisconnect : () ->
    unless @closeCB then @nclosing++

  # @private
  endClientDisconnect : () ->
    @nclosing--
    if @closeCB and @nclosing == 0
      process.nextTick => @finish()

  # @private
  close : (done = ->) ->
    @closeCB = (error) =>
      @closeCB = null
      unless @sharedIO
        @io.close()
      if @http
        @io.engine.close()
      if @hooks.onClose
        @hooks.onClose @server, error, done
      else
        done error
    closeStartingTime = new Date().getTime()
    closingTimeoutChecker = =>
      if @finished then return
      timeCurrent = new Date().getTime()
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
  sendToChannel : (channel, args...) ->
    @nsp.to(channel).emit args...

  # @private
  sendToOthers : (id, channel, args...) ->
    socket = @getSocketObject id
    unless socket
      @sendToChannel channel, args...
    else
      socket.to(channel).emit args...

  # @private
  sendToClient : (id, args...) ->
    socket = @getSocketObject id
    unless socket then return
    socket.emit args...

  # @private
  joinChannel : (id, channel, cb) ->
    socket = @getSocketObject id
    unless socket
      return cb @errorBuilder.makeError 'serverError', 500
    socket.join channel, cb

  # @private
  leaveChannel : (id, channel, cb) ->
    socket = @getSocketObject id
    unless socket then return cb()
    socket.leave channel, cb


module.exports = SocketIOTransport
