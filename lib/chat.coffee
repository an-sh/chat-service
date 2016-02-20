
_ = require 'lodash'
RedisAdapter = require 'socket.io-redis'
SocketServer = require 'socket.io'
uid = require 'uid-safe'

ErrorBuilder = require('./utils.coffee').ErrorBuilder
MemoryState = require('./state-memory.coffee')
RedisState = require('./state-redis.coffee')
Room = require('./room.coffee')
User = require('./user.coffee')

# @note This class describes socket.io outgoing messages, not methods.
#
# List of server messages that are sent to a client.
#
# @example Socket.io client example
#   socket = ioClient.connect url, params
#   socket.on 'loginConfirmed', (username) ->
#     socket.on 'directMessage', (fromUser, msg) ->
#       # just the same as any event. no reply is required.
#
class ServerMessages

  # Direct message.
  # @param fromUser [String] Message sender.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessage : (fromUser, msg) ->

  # Direct message echo. If an user have several connections from
  # different sockets, and if one client sends
  # {UserCommands#directMessage}, others will receive a message echo.
  # @param toUser [String] Message receiver.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessageEcho : (toUser, msg) ->

  # Disconnected from a server.
  # @note Socket.io system event.
  # @param reason [Object] Socket.io disconnect info.
  disconnect : (reason) ->

  # Error events, like socket.io middleware error.
  # @param error [Object]
  error : (error) ->

  # Indicates a successful login.
  # @param username [String] Username.
  # @param data [Object] Additional login data with an id of the socket.
  # @option data [String] id Socket id.
  loginConfirmed : (username, data) ->

  # Indicates a login error.
  # @param error [Object] Error.
  loginRejected : (error) ->

  # Indicates that a user has lost a room access permission.
  # @param roomName [String] Room name.
  # @see UserCommands#roomAddToList
  # @see UserCommands#roomRemoveFromList
  roomAccessRemoved : (roomName) ->

  # Indicates room access list add.
  # @param roomName [String] Rooms name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] Usernames removed from the list.
  # @see UserCommands#roomAddToList
  roomAccessListAdded : (roomName, listName, usernames) ->

  # Indicates room access list remove.
  # @param roomName [String] Rooms name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] Usernames added to the list.
  # @see UserCommands#roomRemoveFromList
  roomAccessListRemoved : (roomName, listName, usernames) ->

  # Echoes room join from other user's connections.
  # @param roomName [String] Username.
  # @param id [String] Socket id.
  # @param njoined [Number] Number of sockets that are still joined.
  # @see UserCommands#roomJoin
  roomJoinedEcho : (roomName, id, njoined) ->

  # Echoes room leave from other user's connections.
  # @param roomName [String] Username.
  # @param id [String] Socket id.
  # @param njoined [Number] Number of sockets that are still joined.
  # @see UserCommands#roomLeave
  roomLeftEcho : (roomName, id, njoined) ->

  # Room message.
  # @param roomName [String] Rooms name.
  # @param userName [String] Message author.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#roomMessage
  roomMessage : (roomName, userName, msg) ->

  # Indicates that an another user has joined a room.
  # @param roomName [String] Rooms name.
  # @param userName [String] Username.
  # @see UserCommands#roomJoin
  roomUserJoined : (roomName, userName) ->

  # Indicates that an another user has left a room.
  # @param roomName [String] Rooms name.
  # @param userName [String] Username.
  # @see UserCommands#roomLeave
  roomUserLeft : (roomName, userName) ->


# @note This class describes socket.io incoming messages, not methods.
#
# List of server messages that are sent from a client. Result is sent
# back as a socket.io ack with in the standard (error, data) callback
# parameters format. Error is ether a string or an object, depending
# on {ChatService} `useRawErrorObjects` option. See {ErrorBuilder} for
# an error object format description. Some messages will echo
# {ServerMessages} to other user's sockets or trigger sending
# {ServerMessages} to other users.
#
# @example Socket.io client example
#   socket = ioClient.connect url, params
#   socket.on 'loginConfirmed', (username, authData) ->
#     socket.emit 'roomJoin', roomName, (error, data) ->
#       # this is a socket.io ack waiting callback.
#       # socket is joined the room, or an error occurred. we get here
#       # only when the server has finished message processing.
#
class UserCommands

  # Adds usernames to user's direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param usernames [Array<String>] Usernames to add to the list.
  # @param cb [Function<error, null>] Send ack with an error or an
  #   empty data.
  directAddToList : (listName, usernames, cb) ->

  # Gets direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param cb [Function<error, Array<String>>] Sends ack with an error or
  #   the requested list.
  directGetAccessList : (listName, cb) ->

  # Gets direct messaging whitelist only mode. If it is true then
  # direct messages are allowed only for users that are in the
  # whitelist. Otherwise direct messages are accepted from all
  # users that are not in the blacklist.
  # @param cb [Function<error, Boolean>] Sends ack with an error or
  #   the user's whitelist only mode.
  directGetWhitelistMode : (cb) ->

  # Sends {ServerMessages#directMessage} to an another user, if
  # {ChatService} `enableDirectMessages` option is true. Also sends
  # {ServerMessages#directMessageEcho} to other senders's sockets.
  # @see ServerMessages#directMessage
  # @see ServerMessages#directMessageEcho
  # @param toUser [String] Message receiver.
  # @param msg [Object<textMessage : String>] Message.
  # @param cb [Function<error, Object<textMessage:String,
  #   timestamp:Number, author:String>>>] Sends ack with an error or
  #   a processed message.
  directMessage : (toUser, msg, cb) ->

  # Removes usernames from user's direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param usernames [Array<String>] User names to remove from the list.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  directRemoveFromList : (listName, usernames, cb) ->

  # Sets direct messaging whitelist only mode.
  # @see UserCommands#directGetWhitelistMode
  # @param mode [Boolean]
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  directSetWhitelistMode : (mode, cb) ->

  # Emitted when a socket disconnects from the server.
  # @note Can't be send by client as a socket.io message, use
  #   socket.disconnect() instead.
  # @param reason [String] Reason.
  # @param cb [Function<error, null>] Callback.
  disconnect : (reason, cb) ->

  # Gets a list of all joined rooms with corresponding socket
  # ids. This returns information about all user's sockets.
  # @param cb [Function<error, Object<Hash>>] Sends ack with an error
  #   or an object, where rooms are keys and array of socket ids are
  #   values.
  # @see ServerMessages#roomJoinedEcho
  # @see ServerMessages#roomLeftEcho
  listJoinedRooms : (cb) ->

  # Gets a list of all rooms on the server.
  # @param cb [Function<error, Array<String>>] Sends ack with an error
  #   or a list of rooms.
  listRooms : (cb) ->

  # Adds usernames to room's blacklist, adminlist and whitelist. Also
  # removes users that have lost an access permission in the result of
  # an operation, sending {ServerMessages#roomAccessRemoved}. Also
  # sends {ServerMessages#roomAccessListAdded} to all room users if
  # {ChatService} `enableAccessListsUpdates` option is true.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] User names to add to the list.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  # @see ServerMessages#roomAccessRemoved
  # @see ServerMessages#roomAccessListAdded
  roomAddToList : (roomName, listName, usernames, cb) ->

  # Creates a room if {ChatService} `enableRoomsManagement` option is true.
  # @param roomName [String] Rooms name.
  # @param mode [bool] Room mode.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  roomCreate : (roomName, mode, cb) ->

  # Deletes a room if {ChatService} `enableRoomsManagement` is true
  # and the user has an owner status. Sends
  # {ServerMessages#roomAccessRemoved} to all room users.
  # @param roomName [String] Rooms name.
  # @param cb [Function<error, null>] Sends ack with an error or an empty data.
  roomDelete : (roomName, cb) ->

  # Gets room messaging userlist, blacklist, adminlist and whitelist.
  # @param roomName [String] Room name.
  # @param listName [String] 'userlist', 'blacklist', 'adminlist', 'whitelist'.
  # @param cb [Function<error, Array<String>>] Sends ack with an error
  #   or the requested list.
  roomGetAccessList : (roomName, listName, cb) ->

  # Gets a room messaging whitelist only mode. If it is true, then
  # join is allowed only for users that are in the
  # whitelist. Otherwise all users that are not in the blacklist can
  # join.
  # @param roomName [String] Room name.
  # @param cb [Function<error, Boolean>] Sends ack with an error or
  #   whitelist only mode.
  roomGetWhitelistMode : (roomName, cb) ->

  # Gets latest room messages. The maximum size is set by
  # {ChatService} `historyMaxMessages` option.
  # @param roomName [String] Room name.
  # @param cb [Function<error, Array<Objects>>] Sends ack with an
  #   error or array of messages.
  # @see UserCommands#roomMessage
  roomHistory : (roomName, cb)->

  # Joins room, an user must join the room to receive messages or
  # execute room commands. Sends {ServerMessages#roomJoinedEcho} to other
  # user's sockets. Also sends {ServerMessages#roomUserJoined} to other
  # room users if {ChatService} `enableUserlistUpdates` option is
  # true.
  # @see ServerMessages#roomJoinedEcho
  # @see ServerMessages#roomUserJoined
  # @param roomName [String] Room name.
  # @param cb [Function<error, Number>] Sends ack with an error or a
  #   number of joined user's sockets.
  roomJoin : (roomName, cb) ->

  # Leaves room. Sends {ServerMessages#roomLeftEcho} to other user's
  # sockets. Also sends {ServerMessages#roomUserLeft} to other room
  # users if {ChatService} `enableUserlistUpdates` option is true.
  # @see ServerMessages#roomLeftEcho
  # @see ServerMessages#roomUserLeft
  # @param roomName [String] Room name.
  # @param cb [Function<error, Number>] Sends ack with an error or a
  #   number of joined user's sockets.
  roomLeave : (roomName, cb) ->

  # Sends {ServerMessages#roomMessage} to all room users.
  # @see ServerMessages#roomMessage
  # @param roomName [String] Room name.
  # @param msg [Object<textMessage : String>] Message.
  # @param cb [Function<error, Object<textMessage:String,
  #   timestamp:Number, author:String>>] Sends ack with an error or
  #   a processed message.
  roomMessage : (roomName, msg, cb) ->

  # Removes usernames from room's blacklist, adminlist and
  # whitelist. Also removes users that have lost an access permission
  # in the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}. Also sends
  # {ServerMessages#roomAccessListRemoved} to all room users if
  # {ChatService} `enableAccessListsUpdates` option is true.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] Usernames to remove from the list.
  # @param cb [Function<error, null>] Sends ack with an error or an
  #   empty data.
  # @see ServerMessages#roomAccessRemoved
  # @see ServerMessages#roomAccessListRemoved
  roomRemoveFromList : (roomName, listName, usernames, cb) ->

  # Sets room messaging whitelist only mode. Also removes users that
  # have lost an access permission in the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}.
  # @see UserCommands#roomGetWhitelistMode
  # @see ServerMessages#roomAccessRemoved
  # @param roomName [String] Room name.
  # @param mode [Boolean]
  # @param cb [Function<error, null>] Sends ack with an error or an
  #   empty data.
  roomSetWhitelistMode : (roomName, mode, cb) ->


# An instance creates a new chat service.
class ChatService
  # Crates an object and starts a new server instance.
  #
  # @option options [String] namespace
  #   io namespace, default is '/chat-service'.
  #
  # @option options [Integer] historyMaxMessages
  #   room history size, default is 100.
  #
  # @option options [Boolean] useRawErrorObjects
  #   Send error objects (see {ErrorBuilder}) instead of strings,
  #   default is false.
  #
  # @option options [Boolean] enableUserlistUpdates
  #   Enables {ServerMessages#roomUserJoined} and
  #   {ServerMessages#roomUserLeft} messages, default is false.
  #
  # @option options [Boolean] enableAccessListsUpdates
  #   Enables {ServerMessages#roomAccessListAdded} and
  #   {ServerMessages#roomAccessListRemoved} messages, default is false.
  #
  # @option options [Boolean] enableDirectMessages
  #   Enables user to user {UserCommands#directMessage}, default is false.
  #
  # @option options [Object] socketIoServerOptions
  #   Options that are passed to socket.io if server creation is required.
  #
  # @option options [Object] io
  #   Socket.io instance that should be used by ChatService.
  #
  # @option options [Object] http
  #   Use socket.io http server integration.
  #
  # @option hooks [Function] auth Socket.io middleware function to run
  #   on all messages in the namespace. Look in the socket.io
  #   documentation.
  #
  # @option hooks [Function(<ChatService>, <Socket>,
  #   <Function(<Error>, <String>, <Object>)>)] onConnect Client
  #   connection hook. Must call a callback with either error or user
  #   name and auth data. User name and auth data are send back with
  #   `loginConfirmed` message. Error is sent as `loginRejected`
  #   message.
  #
  # @option hooks [Function(<ChatService>, <Error>, <Function(<Error>)>)]
  #   onClose Executes when server is closed. Must call a callback.
  #
  # @option hooks [Function(<ChatService>, <Function(<Error>)>)] onStart
  #   Executes when server is started. Must call a callback.
  #
  # @param options [Object] Options.
  #
  # @param hooks [Object] Hooks. Every `UserCommand` is wrapped with
  #   the corresponding Before and After hooks. So a hook name will
  #   look like `roomCreateBefore`. Before hook is ran after arguments
  #   validation, but before an actual server command processing. After
  #   hook is executed after a server has finshed command processing.
  #   Check Hooks unit tests section in the `test` directory for
  #   more details and hooks usage examples.
  #
  # @option storageOptions [String or Constructor] state Chat state.
  #   Can be either 'memory' or 'redis' for built-in state storages, or a
  #   custom state constructor function that implements the same API.
  #
  # @option storageOptions [String or Constructor] adapter Socket.io
  #   adapter, used if no io object is passed.  Can be either 'memory'
  #   or 'redis' for built-in state storages, or a custom state
  #   constructor function that implements the Socket.io adapter API.
  #
  # @option storageOptions [Object] socketIoAdapterOptions
  #   Options that are passed to socket.io adapter if adapter creation
  #   is required.
  #
  # @option storageOptions [Object] stateOptions Options that are
  #   passed to a service state. 'memory' state has no options,
  #   'redis' state options are listed below.
  #
  # @param storageOptions [Object] Selects state and socket.io adapter.
  #
  # @option stateOptions [Object] redisOptions
  #   ioredis constructor options.
  #
  # @option stateOptions [Object] redisClusterHosts
  #   ioredis cluster constructor hosts, overrides `redisOptions`.
  #
  # @option stateOptions [Object] redisClusterOptions
  #   ioredis cluster constructor options.
  #
  # @option stateOptions [Object] redlockOptions
  #   redlock constructor options.
  #
  # @option stateOptions [Integer] redlockTTL
  #   redlock TTL option, default is 2000.
  #
  constructor : (@options = {}, @hooks = {}, @storageOptions = {}) ->
    @setOptions()
    @setServer()
    if @hooks.onStart
      @hooks.onStart @, (error) =>
        if error then throw error
        else @setEvents()
    else
      @setEvents()

  # @private
  # @nodoc
  setOptions : ->
    @namespace = @options.namespace || '/chat-service'
    @historyMaxMessages = @options.historyMaxMessages || 100
    @useRawErrorObjects = @options.useRawErrorObjects || false
    @enableUserlistUpdates = @options.enableUserlistUpdates || false
    @enableAccessListsUpdates = @options.enableAccessListsUpdates || false
    @enableRoomsManagement = @options.enableRoomsManagement || false
    @enableDirectMessages = @options.enableDirectMessages || false
    @closeTimeout = @options.closeTimeout || 5000
    @socketIoServerOptions = @options.socketIoServerOptions
    @state = @storageOptions.state
    @adapter = @storageOptions.adapter
    @socketIoAdapterOptions = @storageOptions.socketIoAdapterOptions
    @storageOptions = @options.stateOptions
    @serverUID = uid.sync 18

  # @private
  # @nodoc
  setServer : ->
    @io = @options.io
    @sharedIO = true if @io
    @http = @options.http unless @io
    @nclosing = 0
    @closeCB = null
    state = switch @state
      when 'memory' then MemoryState
      when 'redis' then RedisState
      when typeof @state == 'function' then @state
      else throw new Error "Invalid state: #{@state}"
    Adapter = switch @adapter
      when 'memory' then null
      when 'redis' then RedisAdapter
      when typeof @state == 'function' then @adapter
      else throw new Error "Invalid adapter: #{@adapter}"
    unless @io
      if @http
        @io = new SocketServer @http, @socketIoServerOptions
      else
        port = @socketIoServerOptions?.port || 8000
        @io = new SocketServer port, @socketIoServerOptions
      if Adapter
        @ioAdapter = new Adapter @socketIoAdapterOptions
        @io.adapter @ioAdapter
    @nsp = @io.of @namespace
    userCommands = new UserCommands
    serverMessages = new ServerMessages
    @User = (args...) =>
      new User @, args...
    @Room = (args...) =>
      new Room @, args...
    @errorBuilder = new ErrorBuilder @useRawErrorObjects
    @chatState = new state @, @stateOptions

  # @private
  # @nodoc
  setEvents : ->
    if @hooks.auth
      @nsp.use @hooks.auth
    if @hooks.onConnect
      @nsp.on 'connection', (socket) =>
        @hooks.onConnect @, socket, (error, userName, authData) =>
          @addClient error, socket, userName, authData
    else
      @nsp.on 'connection', (socket) =>
        @addClient null, socket

  # @private
  # @nodoc
  rejectLogin : (socket, error) ->
    socket.emit 'loginRejected', error
    socket.disconnect(true)

  # @private
  # @nodoc
  confirmLogin : (socket, userName, authData) ->
    if _.isObject(authData) and !authData.id
      authData.id = socket.id
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
    @chatState.loginUser @serverUID, userName, socket, (error) =>
      if error
        @rejectLogin socket, error
      else
        @confirmLogin socket, userName, authData

  # @private
  # @nodoc
  finish : () ->
    if @closeCB and !@finished
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

  # Remove all user data and closes all user connections
  # @param userName [String] User name.
  # @param cb [callback] Optional callback.
  removeUser : (userName, cb = ->) ->
    @chatState.removeUser userName, cb

  # Closes server.
  # @param done [callback] Optional callback.
  close : (done = ->) ->
    @closeCB = (error) =>
      @closeCB = null
      unless @sharedIO or @http
        @io.close()
      if @hooks.onClose
        @hooks.onClose @, error, done
      else
        done error
    closeStartingTime = new Date().getTime()
    closingTimeoutChecker = =>
      if @finished then return
      timeCurrent = new Date().getTime()
      if timeCurrent > closeStartingTime + @closeTimeout
        @finished = true
        @closeCB new Error 'Server closing timeout.'
      else
        setTimeout closingTimeoutChecker, 100
    for sid, socket of @nsp.connected
      @nclosing++
      socket.disconnect(true)
    if @nclosing == 0
      process.nextTick => @closeCB()
    else
      closingTimeoutChecker()


module.exports = {
  ChatService
  User
  Room
}
