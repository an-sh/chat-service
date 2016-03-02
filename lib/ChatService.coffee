
_ = require 'lodash'
uid = require 'uid-safe'

ArgumentsValidator = require './ArgumentsValidator.coffee'
ErrorBuilder = require './ErrorBuilder.coffee'
MemoryState = require './MemoryState.coffee'
RedisState = require './RedisState.coffee'
Room = require './Room.coffee'
ServiceAPI = require './ServiceAPI.coffee'
SocketIOTransport = require './SocketIOTransport.coffee'
User = require './User.coffee'

{ extend } = require './utils.coffee'

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
  directMessage : (msg) ->

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
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#roomMessage
  roomMessage : (roomName, msg) ->

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

  # Indicates connection of an another socket with the same user.
  # @param id [String] Socket id.
  # @param nconnected [Number] Total number of users's sockets.
  socketConnectEcho : (id, nconnected) ->

  # Indicates disconnection of an another socket with the same user.
  # @param id [String] Socket id.
  # @param nconnected [Number] Total number of users's sockets.
  socketDisconnectEcho : (id, nconnected) ->


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

  # Gets a list of all sockets with corresponding joined rooms. This
  # returns information about all user's sockets.
  # @param cb [Function<error, Object<Hash>>] Sends ack with an error
  #   or an object, where sockets are keys and arrays of rooms are
  #   values.
  # @see ServerMessages#roomJoinedEcho
  # @see ServerMessages#roomLeftEcho
  listJoinedSockets : (cb) ->

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

  # Gets the room owner.
  # @param roomName [String] Room name.
  # @param cb [Function<error, String>] Sends ack with an error or
  #   the room owner.
  roomGetOwner : (roomName, cb) ->

  # Gets the room messaging whitelist only mode. If it is true, then
  # join is allowed only for users that are in the
  # whitelist. Otherwise all users that are not in the blacklist can
  # join.
  # @param roomName [String] Room name.
  # @param cb [Function<error, Boolean>] Sends ack with an error or
  #   whitelist only mode.
  roomGetWhitelistMode : (roomName, cb) ->

  # Gets latest room messages. The maximum size is set by
  # {ChatService} `historyMaxGetMessages` option.
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
  # @param cb [Function<error, null>] Sends ack with an error or
  #   empty data.
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


# Service object.
# @extend ServiceAPI
class ChatService

  extend @, ServiceAPI

  # Crates an object and starts a new server instance.
  #
  # @option options [String] namespace
  #   io namespace, default is '/chat-service'.
  #
  # @option options [Integer] historyMaxMessages
  #   room history size, default is 10000.
  #
  # @option options [Integer] historyMaxGetMessages
  #   room history size available via
  #   {UserCommands#roomHistory} , default is 100.
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
  # @param options [Object] Options.
  #
  # @option hooks [Function or Array<Function>] middleware Socket.io
  #   middleware functions to run on all messages in the
  #   namespace. Look in the socket.io documentation.
  #
  # @option hooks [Function(<ChatService>, <Socket>,
  #   <Function(<Error>, <String>, <Object>)>)] onConnect Client
  #   connection hook. Must call a callback with either error or user
  #   name and auth data. User name and auth data are send back with
  #   `loginConfirmed` message. Error is sent as `loginRejected`
  #   message.
  #
  # @option hooks [Function(<ChatService>, <Function(<Error>)>)] onStart
  #   Executes when server is started. Must call a callback.
  #
  # @option hooks [Function(<ChatService>, <Error>, <Function(<Error>)>)]
  #   onClose Executes when server is closed. Must call a callback.
  #
  # @option hooks [Function(Object, <Function(<Error>)>)]
  #   directMessageChecker Validator for {UserCommands#directMessage}
  #   message objects. When is set allow a custom content in direct
  #   messages.
  #
  # @option hooks [Function(Object, <Function(<Error>)>)]
  #   roomMessageChecker Validator for {UserCommands#roomMessage}
  #   message objects. When is set allow a custom content in room
  #   messages.
  #
  # @option hooks [Function(ChatService, String, String, Array,
  #   <Function(<Error, Data, Array...>)>)] {command}Before Before
  #   hooks are available for all {UserCommands} and all have the same
  #   arguments: ChatService object, user name, socket id, array of
  #   command arguments and a callback. Callback may be called without
  #   arguments to continue command execution, or with non-falsy Error
  #   or Data to stop execution and return error or result
  #   respectively to the command issuer, or with falsy Error and Data
  #   and rest arguments as the new command arguments to continue with
  #   (Note: new arguments count and types must be the same as the
  #   original command requires). Also note that before hooks are run
  #   only after a successful arguments types validation.
  #
  # @option hooks [Function(ChatService, String, String, Array, Array,
  #   <Function(<Error, Data>)>)] {command}After After hooks are
  #   available for all {UserCommands} and all have the same
  #   arguments: ChatService object, user name, socket id, Array of
  #   command arguments, Array of command results and a
  #   callback. Error or Data is the command's execution result or
  #   error respectively. Callback may be without arguments to return
  #   unchanged result or error to the command issuer, or with new
  #   Error or Data object to alter the result values.
  #
  # @param hooks [Object] Hooks. Every `UserCommand` is wrapped with
  #   the corresponding Before and After hooks. So a hook name will
  #   look like `roomCreateBefore`. Before hook is ran after arguments
  #   validation, but before an actual server command
  #   processing. After hook is executed after a server has finshed
  #   the command processing.
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
  # @option stateOptions [Integer] lockTTL
  #   lockTTL option, default is 2000.
  constructor : (@serviceOptions = {}, @hooks = {}, @integrationOptions = {}) ->
    @setOptions()
    @setServer()
    @startServer()

  # @private
  # @nodoc
  setOptions : ->
    @serverUID = uid.sync 18
    @historyMaxMessages = @serviceOptions.historyMaxMessages || 100
    @historyMaxGetMessages = @serviceOptions.historyMaxGetMessages || 10000
    @useRawErrorObjects = @serviceOptions.useRawErrorObjects || false
    @enableUserlistUpdates = @serviceOptions.enableUserlistUpdates || false
    @enableAccessListsUpdates= @serviceOptions.enableAccessListsUpdates || false
    @enableRoomsManagement = @serviceOptions.enableRoomsManagement || false
    @enableDirectMessages = @serviceOptions.enableDirectMessages || false
    @closeTimeout = @serviceOptions.closeTimeout || 5000
    @stateConstructor = @integrationOptions.state
    @stateOptions = @integrationOptions.stateOptions
    @transportConstructor = @integrationOptions.transport
    @transportOptions = @integrationOptions.transportOptions

  # @private
  # @nodoc
  setServer : ->
    State = switch @stateConstructor
      when 'memory' then MemoryState
      when 'redis' then RedisState
      when _.isFunction @stateConstructor then @stateConstructor
      else throw new Error "Invalid state: #{@stateConstructor}"
    Transport = @transportConstructor || SocketIOTransport
    @errorBuilder = new ErrorBuilder @useRawErrorObjects
    @userCommands = new UserCommands()
    @serverMessages = new ServerMessages()
    @validator = new ArgumentsValidator @
    @state = new State @, @stateOptions
    @transport = new Transport @, @transportOptions, @hooks
    @makeUser = (args...) =>
      new User @, args...
    @makeRoom = (args...) =>
      new Room @, args...

  # @private
  # @nodoc
  startServer : ->
    if @hooks.onStart
      @hooks.onStart @, (error) =>
        if error then throw error
        else @transport.setEvents()
    else
      @transport.setEvents()

  # Returns messaging transport.
  # @return [Object] Transport.
  # @see SocketIOTransport
  getTransport : ->
    @transport

  # Returns ErrorBuilder.
  # @return [Object] ErrorBuilder.
  # @see ErrorBuilder
  getErrorBuilder : ->
    @errorBuilder

  # Closes server.
  # @param done [callback] Optional callback.
  close : (done = ->) ->
    @transport.close (error) =>
      closeDB = (error) =>
        if error
          @state.close()
          done error
        else
          @state.close done
      if @hooks.onClose
        @hooks.onClose @, error, closeDB
      else
        closeDB error


module.exports = ChatService
