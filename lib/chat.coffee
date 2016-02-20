
RedisAdapter = require 'socket.io-redis'
SocketServer = require 'socket.io'
_ = require 'lodash'
async = require 'async'
check = require 'check-types'
uid = require 'uid-safe'

MemoryState = require('./state-memory.coffee').MemoryState
RedisState = require('./state-redis.coffee').RedisState
ErrorBuilder = require('./utils.coffee').ErrorBuilder
withEH = require('./utils.coffee').withEH
extend = require('./utils.coffee').extend
asyncLimit = require('./utils.coffee').asyncLimit
bindUnlock = require('./utils.coffee').bindUnlock

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


# @private
# @nodoc
processMessage = (author, msg) ->
  r = {}
  r.textMessage = msg?.textMessage?.toString() || ''
  r.timestamp = new Date().getTime()
  r.author = author
  return r


# @private
# @nodoc
checkMessage = (msg) ->
  passed = check.object msg
  unless passed then return false
  return check.map msg, { textMessage : check.string }

# @private
# @nodoc
dataChecker = (args, checkers) ->
  if args.length != checkers.length
    return [ 'wrongArgumentsCount', checkers.length, args.length ]
  for checker, idx in checkers
    unless checker args[idx]
      return [ 'badArgument', idx, args[idx] ]
  return null

# @private
# @nodoc
class ArgumentsValidators
  # @private
  directAddToList : (listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  # @private
  directGetAccessList : (listName) ->
    dataChecker arguments, [
      check.string
    ]
  # @private
  directGetWhitelistMode : () ->
    dataChecker arguments, [
    ]
  # @private
  directMessage : (toUser, msg) ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  # @private
  directRemoveFromList : (listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  # @private
  directSetWhitelistMode : (mode) ->
    dataChecker arguments, [
      check.boolean
    ]
  # @private
  disconnect : (reason) ->
    dataChecker arguments, [
      check.string
    ]
  # @private
  listJoinedRooms : () ->
    dataChecker arguments, [
    ]
  # @private
  listRooms : () ->
    dataChecker arguments, [
    ]
  # @private
  roomAddToList : (roomName, listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  # @private
  roomCreate : (roomName, mode) ->
    dataChecker arguments, [
      check.string
      check.boolean
    ]
  # @private
  roomDelete : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # @private
  roomGetAccessList : (roomName, listName) ->
    dataChecker arguments, [
      check.string
      check.string
    ]
  # @private
  roomGetWhitelistMode : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # @private
  roomHistory : (roomName)->
    dataChecker arguments, [
      check.string
    ]
  # @private
  roomJoin : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # @private
  roomLeave : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # @private
  roomMessage : (roomName, msg) ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  # @private
  roomRemoveFromList : (roomName, listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  # @private
  roomSetWhitelistMode : (roomName, mode) ->
    dataChecker arguments, [
      check.string
      check.boolean
    ]

# @private
# @nodoc
userCommands = new UserCommands

# @private
# @nodoc
serverMessages = new ServerMessages

# @private
# @nodoc
argumentsValidators = new ArgumentsValidators


# @private
# @mixin
# @nodoc
RoomPermissions =

  # @private
  isAdmin : (userName, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      if owner == userName
        return cb null, true
      @roomState.hasInList 'adminlist', userName, withEH cb, (hasName) ->
        if hasName
          return cb null, true
        cb null, false

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) =>
        if admin
          cb null, false
        else if listName == 'whitelist'
          @roomState.whitelistOnlyGet withEH cb, (whitelistOnly) ->
            cb null, whitelistOnly
        else
          cb null, false

  # @private
  hasAddChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) ->
        if admin
          cb null, false
        else if listName == 'blacklist'
          cb null, true
        else
          cb null, false

  # @private
  getModeChangedCurrentAccess : (value, cb) ->
    unless value
      process.nextTick -> cb null, false
    else
      @roomState.getCommonUsers cb

  # @private
  checkList : (author, listName, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      cb()

  # @private
  checkListChanges : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.ownerGet withEH cb, (owner) =>
        if listName == 'userlist'
          return cb @errorBuilder.makeError 'notAllowed'
        if author == owner
          return cb()
        if listName == 'adminlist'
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.hasInList 'adminlist', author, withEH cb, (hasAuthor) =>
          unless hasAuthor
            return cb @errorBuilder.makeError 'notAllowed'
          for name in values
            if name == owner
              return cb @errorBuilder.makeError 'notAllowed'
          cb()

  # @private
  checkListAdd : (author, listName, values, cb) ->
    @checkListChanges author, listName, values, cb

  # @private
  checkListRemove : (author, listName, values, cb) ->
    @checkListChanges author, listName, values, cb

  # @private
  checkModeChange : (author, value, cb) ->
    @isAdmin author, withEH cb, (admin) =>
      unless admin
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

  # @private
  checkAcess : (userName, cb) ->
    @isAdmin userName, withEH cb, (admin) =>
      if admin
        return cb()
      @roomState.hasInList 'blacklist', userName, withEH cb, (inBlacklist) =>
        if inBlacklist
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.whitelistOnlyGet withEH cb, (whitelistOnly) =>
          @roomState.hasInList 'whitelist', userName
          , withEH cb, (inWhitelist) =>
            if whitelistOnly and not inWhitelist
              return cb @errorBuilder.makeError 'notAllowed'
            cb()

  # @private
  checkIsOwner : (author, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      unless owner == author
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

# @private
# @nodoc
class Room

  extend @, RoomPermissions

  # @private
  constructor : (@server, @name) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.roomState
    @roomState = new state @server, @name, @server.historyMaxMessages

  # @private
  initState : (state, cb) ->
    @roomState.initState state, cb

  # @private
  removeState : (cb) ->
    @roomState.removeState cb

  # @private
  getUsers: (cb) ->
    @roomState.getList 'userlist', cb

  # @private
  leave : (userName, cb) ->
    @roomState.removeFromList 'userlist', [userName], cb

  # @private
  join : (userName, cb) ->
    @checkAcess userName, withEH cb, =>
      @roomState.addToList 'userlist', [userName], cb

  # @private
  message : (author, msg, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messageAdd msg, cb

  # @private
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.getList listName, cb

  # @private
  getLastMessages : (author, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messagesGet cb

  # @private
  addToList : (author, listName, values, cb) ->
    @checkListAdd author, listName, values, withEH cb, =>
      @roomState.addToList listName, values, withEH cb, =>
        data = []
        async.eachLimit values, asyncLimit
        , (val, fn) =>
          @hasAddChangedCurrentAccess val, listName, withEH fn, (changed) ->
            if changed then data.push val
            fn()
        , (error) -> cb error, data

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkListRemove author, listName, values, withEH cb, =>
      @roomState.removeFromList listName, values, withEH cb, =>
        data = []
        async.eachLimit values, asyncLimit
        , (val, fn) =>
          @hasRemoveChangedCurrentAccess val, listName, withEH fn, (changed) ->
            if changed then data.push val
            fn()
        , (error) -> cb error, data

  # @private
  getMode : (author, cb) ->
    @roomState.whitelistOnlyGet cb

  # @private
  changeMode : (author, mode, cb) ->
    @checkModeChange author, mode, withEH cb, =>
      whitelistOnly = if mode then true else false
      @roomState.whitelistOnlySet whitelistOnly, withEH cb, =>
        @getModeChangedCurrentAccess whitelistOnly, cb


# @private
# @mixin
# @nodoc
#
# Implements permissions checks.
# Required existence of username, directMessagingState and
# errorBuilder in extented classes.
DirectMessagingPermissions =

  # @private
  checkUser : (author, cb) ->
    process.nextTick -> cb()

  # @private
  checkList : (author, listName, cb) ->
    @checkUser author, withEH cb, =>
      unless @directMessagingState.hasList listName
        error = @errorBuilder.makeError 'noList', listName
      cb error

  # @private
  checkListValues : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      for name in values
        if name == @username
          return cb @errorBuilder.makeError 'notAllowed'
      cb()

  # @private
  checkListAdd : (author, listName, values, cb) ->
    @checkListValues author, listName, values, cb

  # @private
  checkListRemove : (author, listName, values, cb) ->
    @checkListValues author, listName, values, cb

  # @private
  checkAcess : (userName, cb) ->
    if userName == @username
      return process.nextTick => cb @errorBuilder.makeError 'notAllowed'
    @directMessagingState.hasInList 'blacklist', userName
    , withEH cb, (blacklisted) =>
      if blacklisted
        return cb @errorBuilder.makeError 'noUserOnline'
      @directMessagingState.whitelistOnlyGet withEH cb, (whitelistOnly) =>
        @directMessagingState.hasInList 'whitelist', userName
        , withEH cb, (hasWhitelist) =>
          if whitelistOnly and not hasWhitelist
            return cb @errorBuilder.makeError 'notAllowed'
          cb()


# @private
# @nodoc
#
# @extend DirectMessagingPermissions
# Implements DirectMessaging state manipulations with the respect to a
# users permission.
class DirectMessaging

  extend @, DirectMessagingPermissions

  # @private
  constructor : (@server, @username) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.directMessagingState
    @directMessagingState = new state @server, @username

  # @private
  initState : (state, cb) ->
    @directMessagingState.initState state, cb

  # @private
  removeState : (cb) ->
    @directMessagingState.removeState cb

  # @private
  message : (author, msg, cb) ->
    @checkAcess author, cb

  # @private
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @directMessagingState.getList listName, cb

  # @private
  addToList : (author, listName, values, cb) ->
    @checkListAdd author, listName, values, withEH cb, =>
      @directMessagingState.addToList listName, values, cb

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkListRemove author, listName, values, withEH cb, =>
      @directMessagingState.removeFromList listName, values, cb

  # @private
  getMode : (author, cb) ->
    @checkUser author, withEH cb, =>
      @directMessagingState.whitelistOnlyGet cb

  # @private
  changeMode : (author, mode, cb) ->
    @checkUser author, withEH cb, =>
      m = if mode then true else false
      @directMessagingState.whitelistOnlySet m, cb


# @private
# @mixin
# @nodoc
#
# Implements command implementation functions binding and wrapping.
# Required existence of server in extented classes.
CommandBinders =

  # @private
  wrapCommand : (name, fn) ->
    bname = name + 'Before'
    aname = name + 'After'
    cmd = (oargs..., cb, id) =>
      hooks = @server.hooks
      errorBuilder = @server.errorBuilder
      validator = @server.argumentsValidators[name]
      beforeHook = hooks?[bname]
      afterHook = hooks?[aname]
      execCommand = (error, data) =>
        if error or data then return cb error, data
        afterCommand = (error, data) =>
          reportResults = (nerror = error, ndata = data) ->
            cb nerror, ndata
          if afterHook
            afterHook @, id, error, data, oargs, reportResults
          else
            reportResults()
        fn.apply @, [ oargs..., afterCommand, id ]
      process.nextTick =>
        checkerError = validator oargs...
        if checkerError
          error = errorBuilder.makeError checkerError...
          return cb error
        unless beforeHook
          execCommand()
        else
          beforeHook @, id, oargs, execCommand
    return cmd

  # @private
  bindCommand : (socket, name, fn) ->
    cmd = @wrapCommand name, fn
    socket.on name, () ->
      cb = _.last arguments
      if typeof cb == 'function'
        args = _.slice arguments, 0, -1
      else
        cb = null
        args = arguments
      ack = (error, data) ->
        error = null unless error?
        data = null unless data?
        cb error, data if cb
      cmd args..., ack, socket.id


# @private
# @mixin
# @nodoc
UserHelpers =

  # @private
  withRoom : (roomName, fn) ->
    @chatState.getRoom roomName, fn

  # @private
  send : (id, args...) ->
    @server.nsp.to(id)?.emit args...

  # @private
  getSocketObject : (id) ->
    @server.nsp.connected[id]

  # @private
  broadcast : (id, roomName, args...) ->
    @getSocketObject(id)?.to(roomName)?.emit args...

  # @private
  socketsInRoom : (roomName, cb) ->
    @userState.getRoomSockets roomName, withEH cb, (sockets) ->
      cb null, sockets?.length || 0

  # @private
  removeRoomUsers : (room, userNames, cb) ->
    roomName = room.name
    async.eachLimit userNames, asyncLimit
    , (userName, fn) =>
      @chatState.lockUser userName, withEH fn, (lock) =>
        unlock = bindUnlock lock, fn
        room.leave userName, withEH unlock, =>
          @chatState.getUser userName, withEH unlock, (user, isOnline) =>
            user.userState.roomRemoveAll roomName, withEH unlock, =>
              user.userState.socketsGetAll withEH unlock, (sockets) =>
                for id in sockets
                  @send id, 'roomAccessRemoved', roomName
                  socket = @getSocketObject id
                  socket?.leave roomName
                unlock()
    , -> cb()

  # @private
  removeRoomSocket : (id, allsockets, roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      @socketsInRoom roomName, withEH cb, (njoined) =>
        sendEcho = =>
          for sid in allsockets
            @send sid, 'roomLeftEcho', roomName, id, njoined
        sendLeave = =>
          if @enableUserlistUpdates
            @send roomName, 'roomUserLeft', roomName, @username
        if njoined == 0
          room.leave @username, withEH cb, =>
            @userState.roomRemoveAll roomName, withEH cb, ->
              sendLeave()
              sendEcho()
              cb()
        else
          sendEcho()
          cb()

  # @private
  processDisconnect : (id, cb) ->
    @chatState.removeSocket @chatState.serverUID, id, withEH cb, =>
      @userState.roomsGetAll withEH cb, (rooms) =>
        @userState.socketsGetAll withEH cb, (sockets) =>
          nsockets = sockets.length
          async.eachLimit rooms, asyncLimit
          , (roomName, fn) =>
            @removeRoomSocket id, sockets, roomName, fn
          , =>
            if nsockets == 0
              @chatState.setUserOffline @username, cb
            else
              cb()


# @private
# @nodoc
class User extends DirectMessaging

  extend @, CommandBinders, UserHelpers

  # @private
  constructor : (@server, @username) ->
    super @server, @username
    @chatState = @server.chatState
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableAccessListsUpdates = @server.enableAccessListsUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    state = @server.chatState.userState
    @userState = new state @server, @username

  # @private
  initState : (state, cb) ->
    super state, cb

  # @private
  registerSocket : (socket, cb) ->
    @userState.socketAdd socket.id, withEH cb, =>
      for cmd of userCommands
        @bindCommand socket, cmd, @[cmd]
      cb null, @

  # @private
  disconnectSockets : (cb) ->
    @userState.socketsGetAll withEH cb, (sockets) =>
      async.eachLimit sockets, asyncLimit
      , (sid, fn) =>
        if @server.nsp.connected[sid]
          @server.nsp.connected[sid].disconnect()
        else
          @send sid, 'disconnect'
        fn()
      , cb

  # @private
  directAddToList : (listName, values, cb) ->
    @addToList @username, listName, values, cb

  # @private
  directGetAccessList : (listName, cb) ->
    @getList @username, listName, cb

  # @private
  directGetWhitelistMode: (cb) ->
    @getMode @username, cb

  # @private
  directMessage : (toUserName, msg, cb, id) ->
    unless @enableDirectMessages
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @chatState.getOnlineUser toUserName, withEH cb, (toUser) =>
      @chatState.getOnlineUser @username, withEH cb, (fromUser) =>
        pmsg = processMessage @username, msg
        toUser.message @username, pmsg, withEH cb, =>
          fromUser.userState.socketsGetAll withEH cb, (sockets) =>
            for sid in sockets
              if sid != id
                @send sid, 'directMessageEcho', toUserName, pmsg
            toUser.userState.socketsGetAll withEH cb, (sockets) =>
              for sid in sockets
                @send sid, 'directMessage', @username, pmsg
              cb null, msg

  # @private
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @username, listName, values, cb

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, cb

  # @private
  disconnect : (reason, cb, id) ->
    @server.startClientDisconnect()
    endDisconnect = (args...) =>
      @server.endClientDisconnect()
      cb args...
    @chatState.lockUser @username, withEH endDisconnect, (lock) =>
      unlock = bindUnlock lock, endDisconnect
      @userState.socketRemove id, withEH unlock, =>
        @processDisconnect id, unlock

  # @private
  listJoinedRooms : (cb) ->
    result = {}
    @chatState.lockUser @username, withEH cb, (lock) =>
      unlock = bindUnlock lock, cb
      @userState.roomsGetAll withEH unlock, (rooms) =>
        async.eachLimit rooms, asyncLimit
        , (roomName, fn) =>
          @userState.getRoomSockets roomName, withEH fn, (sockets) ->
            result[roomName] = sockets
            fn()
        , withEH unlock, ->
          unlock null, result

  # @private
  listRooms : (cb) ->
    @chatState.listRooms cb

  # @private
  roomAddToList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.addToList @username, listName, values, withEH cb, (usernames) =>
        if @enableAccessListsUpdates
          @send roomName, 'roomAccessListAdded', roomName, listName, values
        @removeRoomUsers room, usernames, cb

  # @private
  roomCreate : (roomName, whitelistOnly, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    room = new Room @server, roomName
    @chatState.addRoom room, withEH cb, (nadded) =>
      if nadded != 1
        error = @errorBuilder.makeError 'roomExists', roomName
        return cb error
      room.initState { owner : @username, whitelistOnly : whitelistOnly }
      , cb

  # @private
  roomDelete : (roomName, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @withRoom roomName, withEH cb, (room) =>
      room.checkIsOwner @username, withEH cb, =>
        room.getUsers withEH cb, (usernames) =>
          @removeRoomUsers room, usernames, =>
            @chatState.removeRoom room.name, ->
              room.removeState cb

  # @private
  roomGetAccessList : (roomName, listName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getList @username, listName, cb

  # @private
  roomGetWhitelistMode : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMode @username, cb

  # @private
  roomHistory : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getLastMessages @username, cb

  # @private
  roomJoin : (roomName, cb, id) ->
    socket = @getSocketObject id
    @withRoom roomName, withEH cb, (room) =>
      @chatState.lockUser @username, withEH cb, (lock) =>
        unlock = bindUnlock lock, cb
        room.join @username, withEH unlock, =>
          @userState.roomAdd roomName, id, withEH unlock, =>
            socket.join roomName, withEH unlock, =>
              @userState.socketsGetAll withEH unlock, (sockets) =>
                @userState.filterRoomSockets sockets, roomName, withEH unlock
                , (roomSockets) =>
                  njoined = roomSockets?.length
                  for sid in sockets
                    if sid != id
                      @send sid, 'roomJoinedEcho', roomName, id, njoined
                  if @enableUserlistUpdates and njoined == 1
                    @broadcast id, roomName, 'roomUserJoined'
                    , roomName, @username
                  unlock null, njoined

  # @private
  roomLeave : (roomName, cb, id) ->
    socket = @getSocketObject id
    @withRoom roomName, withEH cb, (room) =>
      @chatState.lockUser @username, withEH cb, (lock) =>
        unlock = bindUnlock lock, cb
        socket.leave roomName, withEH unlock, =>
          @userState.roomRemove roomName, id, withEH unlock, =>
            @userState.socketsGetAll withEH unlock, (sockets) =>
              @userState.filterRoomSockets sockets, roomName, withEH unlock
              , (roomSockets) =>
                njoined = roomSockets?.length
                for sid in sockets
                  if sid != id
                    @send sid, 'roomLeftEcho', roomName, id, njoined
                if @enableUserlistUpdates and njoined == 0
                  @broadcast id, roomName, 'roomUserLeft'
                  , roomName, @username
                unlock null, njoined

  # @private
  roomMessage : (roomName, msg, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      pmsg = processMessage @username, msg
      room.message @username, pmsg, withEH cb, =>
        @send roomName, 'roomMessage', roomName, @username, pmsg
        cb null, msg

  # @private
  roomRemoveFromList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.removeFromList @username, listName, values, withEH cb, (usernames) =>
        if @enableAccessListsUpdates
          @send roomName, 'roomAccessListRemoved', roomName, listName, values
        @removeRoomUsers room, usernames, cb

  # @private
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @username, mode, withEH cb, (usernames) =>
        @removeRoomUsers room, usernames, cb


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
    @userCommands = userCommands
    @serverMessages = serverMessages
    @argumentsValidators = argumentsValidators
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
