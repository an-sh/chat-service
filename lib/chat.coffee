
socketIO = require 'socket.io'
_ = require 'lodash'
async = require 'async'
check = require 'check-types'
MemoryState = require('./state-memory.coffee').MemoryState
RedisState = require('./state-redis.coffee').RedisState
ErrorBuilder = require('./errors.coffee').ErrorBuilder
withEH = require('./errors.coffee').withEH

# @private
# @nodoc
extend = (c, mixins...) ->
  for mixin in mixins
    for name, method of mixin
      unless c::[name]
        c::[name] = method
  return

# @note This class describes socket.io outgoing messages, not methods.
#
# List of server messages that are sent to a client.
#
# @example Socket.io client example
#   socket = ioClient.connect url, params
#   socket.on 'loginConfirmed', (username) ->
#     socket.on 'directMessage', (fromUser, msg) ->
#       # just the same as any event. no reply required.
#
class ServerMessages
  # Direct message.
  # @param fromUser [String] Message sender.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessage : (fromUser, msg) ->
  # Direct message echo. If an user have several connections from
  # different clients, and if one client sends
  # {UserCommands#directMessage}, others will receive a message
  # echo.
  # @param toUser [String] Message receiver.
  # @param msg [Object<textMessage:String, timestamp:Number, author:String>]
  #   Message.
  # @see UserCommands#directMessage
  directMessageEcho : (toUser, msg) ->
  # Disconnected from a server.
  # @param reason [Object] Socket.io disconnect type.
  disconnect : (reason) ->
  # Error events, like socket.io middleware error.
  # @param error [Object]
  error : (error) ->
  # Indicates a successful login.
  # @param username [String] Username.
  # @param data [Object] Additional login data.
  loginConfirmed : (username, data) ->
  # Indicates a login error.
  # @param error [Object] Error.
  loginRejected : (error) ->
  # Indicates that a user has lost a room access permission.
  # @param roomName [String] Room name.
  roomAccessRemoved : (roomName) ->
  # Indicates room admin list add.
  # @param roomName [String] Rooms name.
  # @param userName [String] Username.
  # @see UserCommands#roomAddToList
  roomAdminAdded : (roomName, userName) ->
  # Indicates room admin list remove.
  # @param roomName [String] Rooms name.
  # @param userName [String] Username.
  # @see UserCommands#roomRemoveFromList
  roomAdminRemoved : (roomName, userName) ->
  # Echoes room join from other user's connections.
  # @param userName [String] Username.
  # @param njoined [Number] Number of sockets that are still joined.
  # @see UserCommands#roomJoin
  roomJoinedEcho : (roomName, njoined) ->
  # Echoes room leave from other user's connections.
  # @param userName [String] Username.
  # @param njoined [Number] Number of sockets that are still joined.
  # @see UserCommands#roomLeave
  roomLeftEcho : (roomName, njoined) ->
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
  # @return [error, null] Sends ack: error, null.
  directAddToList : (listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  # Gets direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @return [error, Array<String>] Sends ack: error, requested list.
  directGetAccessList : (listName) ->
    dataChecker arguments, [
      check.string
    ]
  # Gets direct messaging whitelist only mode. If it is true then
  # direct messages are allowed only for users that are it the
  # whitelist. Otherwise direct messages are accepted from all
  # users, that are not in the blacklist.
  # @return [error, Boolean] Sends ack: error, whitelist only mode.
  directGetWhitelistMode : () ->
    dataChecker arguments, [
    ]
  # Sends {ServerMessages#directMessage} to an another user, if
  # {ChatService} `enableDirectMessages` option is true. Also sends
  # {ServerMessages#directMessageEcho} to other user's sockets.
  # @see ServerMessages#directMessage
  # @see ServerMessages#directMessageEcho
  # @param toUser [String] Message receiver.
  # @param msg [Object<textMessage : String>] Message.
  # @return
  #   [error, Object<textMessage:String, timestamp:Number, author:String>]
  #   Sends ack: error, message.
  directMessage : (toUser, msg) ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  # Removes usernames from user's direct messaging blacklist or whitelist.
  # @param listName [String] 'blacklist' or 'whitelist'.
  # @param usernames [Array<String>] User names to add to the list.
  # @return [error, null] Sends ack: error, null.
  directRemoveFromList : (listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  # Sets direct messaging whitelist only mode.
  # @see UserCommands#directGetWhitelistMode
  # @param mode [Boolean]
  # @return [error, null] Sends ack: error, null.
  directSetWhitelistMode : (mode) ->
    dataChecker arguments, [
      check.boolean
    ]
  # Disconnects from server.
  # @param reason [String] Socket.io disconnect type.
  disconnect : (reason) ->
    dataChecker arguments, [
      check.string
    ]
  # Gets a list of public rooms on a server.
  # @return [error, Array<String>] Sends ack: error, public rooms.
  listRooms : () ->
    dataChecker arguments, [
    ]
  # Adds usernames to room's blacklist, adminlist and whitelist. Also
  # removes users that have lost an access permission in the result of an
  # operation, sending {ServerMessages#roomAccessRemoved}.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] User names to add to the list.
  # @return [error, null] Sends ack: error, null.
  # @see ServerMessages#roomAccessRemoved
  roomAddToList : (roomName, listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  # Creates a room if {ChatService} `enableRoomsManagement` option is true.
  # @param roomName [String] Rooms name.
  # @param mode [bool] Room mode.
  # @return [error, null] Sends ack: error, null.
  roomCreate : (roomName, mode) ->
    dataChecker arguments, [
      check.string
      check.boolean
    ]
  # Deletes a room if {ChatService} `enableRoomsManagement` is true
  # and the user has an owner status. Sends
  # {ServerMessages#roomAccessRemoved} to all room users.
  # @param roomName [String] Rooms name.
  # @return [error, null] Sends ack: error, null.
  roomDelete : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # Gets room messaging userlist, blacklist, adminlist and whitelist.
  # @param roomName [String] Room name.
  # @param listName [String] 'userlist', 'blacklist', 'adminlist', 'whitelist'.
  # @return [error, Array<String>] Sends ack: error, requested list.
  roomGetAccessList : (roomName, listName) ->
    dataChecker arguments, [
      check.string
      check.string
    ]
  # Gets a room messaging whitelist only mode. If it is true, then
  # join is allowed only for users that are in the
  # whitelist. Otherwise all users that are not in the blacklist can
  # join.
  # @return [error, Boolean] Sends ack: error, whitelist only mode.
  roomGetWhitelistMode : () ->
    dataChecker arguments, [
      check.string
    ]
  # Gets latest room messages. The maximum size is set by
  # {ChatService} `historyMaxMessages` option.
  # @param roomName [String] Room name.
  # @return [error, Array<Objects>] Sends ack: error, array of messages.
  # @see UserCommands#roomMessage
  roomHistory : (roomName)->
    dataChecker arguments, [
      check.string
    ]
  # Joins room, an user must join the room to receive messages or
  # execute room commands. Sends {ServerMessages#roomJoinedEcho} to other
  # user's sockets. Also sends {ServerMessages#roomUserJoined} to other
  # room users if {ChatService} `enableUserlistUpdates` option is
  # true.
  # @see ServerMessages#roomJoinedEcho
  # @see ServerMessages#roomUserJoined
  # @param roomName [String] Room name.
  # @return [error, Number] Sends ack: error, number of joined user sockets.
  roomJoin : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # Leaves room. Sends {ServerMessages#roomLeftEcho} to other user's
  # sockets. Also sends {ServerMessages#roomUserLeft} to other room
  # users if {ChatService} `enableUserlistUpdates` option is true.
  # @see ServerMessages#roomLeftEcho
  # @see ServerMessages#roomUserLeft
  # @param roomName [String] Room name.
  # @return [error, Number] Sends ack: error, number of joined user sockets.
  roomLeave : (roomName) ->
    dataChecker arguments, [
      check.string
    ]
  # Sends {ServerMessages#roomMessage} to a room.
  # @see ServerMessages#roomMessage
  # @param roomName [String] Room name.
  # @param msg [Object<textMessage : String>] Message.
  # @return
  #   [error, Object<textMessage:String, timestamp:Number, author:String>]
  #   Sends ack: error, message.
  roomMessage : (roomName, msg) ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  # Removes usernames from room's blacklist, adminlist and
  # whitelist. Also removes users that have lost an access permission in
  # the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}.
  # @param roomName [String] Room name.
  # @param listName [String] 'blacklist', 'adminlist' or 'whitelist'.
  # @param usernames [Array<String>] Usernames to remove from the list.
  # @return [error, null] Sends ack: error, null.
  # @see ServerMessages#roomAccessRemoved
  roomRemoveFromList : (roomName, listName, usernames) ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  # Sets room messaging whitelist only mode. Also removes users that
  # have lost an access permission in the result of an operation, sending
  # {ServerMessages#roomAccessRemoved}.
  # @see UserCommands#roomGetWhitelistMode
  # @see ServerMessages#roomAccessRemoved
  # @param roomName [String] Room name.
  # @param mode [Boolean]
  # @return [error, null] Sends ack: error, null.
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
asyncLimit = 16

# @private
# @nodoc
processMessage = (author, msg) ->
  r = {}
  r.textMessage = msg?.textMessage?.toString() || ''
  r.timestamp = new Date().getTime()
  r.author = author
  return r


# @private
# @mixin
# @nodoc
RoomHelpers =

  # @private
  isUser : (userName, cb) ->
    @roomState.hasInList 'userlist', userName, cb

  # @private
  isAdmin : (userName, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      @roomState.hasInList 'adminlist', userName, withEH cb, (hasName) ->
        if owner == userName or hasName
          return cb null, true
        cb null, false

  # @private
  hasRemoveChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) =>
      unless hasUser
        return cb null, false
      @isAdmin userName, withEH cb, (admin) =>
        if admin
          return cb null, false
        if listName == 'whitelist'
          @roomState.whitelistOnlyGet withEH cb, (whitelistOnly) ->
            cb null, whitelistOnly
        else
          cb null, false

  # @private
  hasAddChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) ->
      unless hasUser
        return cb null, false
      if listName == 'blacklist'
        return cb null, true
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
  checkListChange : (author, listName, name, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.ownerGet withEH cb, (owner) =>
        if listName == 'userlist'
          return cb @errorBuilder.makeError 'notAllowed'
        if author == owner
          return cb()
        if name == owner
          return cb @errorBuilder.makeError 'notAllowed'
        if listName == 'adminlist'
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.hasInList 'adminlist', author, withEH cb, (hasAuthor) =>
          unless hasAuthor
            return cb @errorBuilder.makeError 'notAllowed'
          cb()

  # @private
  checkListAdd : (author, listName, name, cb) ->
    @checkListChange author, listName, name, withEH cb, =>
      @roomState.hasInList listName, name, withEH cb, (hasName) =>
        if hasName
          return cb @errorBuilder.makeError 'nameInList', name, listName
        cb()

  # @private
  checkListRemove : (author, listName, name, cb) ->
    @checkListChange author, listName, name, withEH cb, =>
      @roomState.hasInList listName, name, withEH cb, (hasName) =>
        unless hasName
          return cb @errorBuilder.makeError 'noNameInList', name, listName
        cb()

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


# Implements room messaging with permissions checking.
# @extend RoomHelpers
class Room

  extend @, RoomHelpers

  # @param server [Object] ChatService object.
  # @param name [String] Room name.
  constructor : (@server, @name) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.roomState
    @roomState = new state @server, @name, @server.historyMaxMessages

  # Resets room state according to the object.
  # @param state [Object]
  # @param cb [Callback]
  # @option state [Array<String>] whitelist
  # @option state [Array<String>] blacklist
  # @option state [Array<String>] adminlist
  # @option state [Array<Object>] lastMessages
  # @option state [Boolean] whitelistOnly
  # @option state [String] owner
  initState : (state, cb) ->
    @roomState.initState state, cb

  # @private
  # @nodoc
  leave : (userName, cb) ->
    @roomState.removeFromList 'userlist', [userName], cb

  # @private
  # @nodoc
  join : (userName, cb) ->
    @checkAcess userName, withEH cb, =>
      @roomState.addToList 'userlist', [userName], cb

  # @private
  # @nodoc
  message : (author, msg, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messageAdd msg, cb

  # @private
  # @nodoc
  getList : (author, listName, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.getList listName, cb

  # @private
  # @nodoc
  getLastMessages : (author, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      @roomState.messagesGet cb

  # @private
  # @nodoc
  addToList : (author, listName, values, cb) ->
    async.eachLimit values, asyncLimit, (val, fn) =>
      @checkListAdd author, listName, val, fn
    , withEH cb, =>
      data = []
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @hasAddChangedCurrentAccess val, listName, withEH fn, (changed) ->
          if changed then data.push val
          fn()
      , withEH cb, =>
        @roomState.addToList listName, values, (error) ->
          cb error, data

  # @private
  # @nodoc
  removeFromList : (author, listName, values, cb) ->
    async.eachLimit values, asyncLimit, (val, fn) =>
      @checkListRemove author, listName, val, fn
    , withEH cb, =>
      data = []
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @hasRemoveChangedCurrentAccess val, listName, withEH fn, (changed) ->
          if changed then data.push val
          fn()
      , withEH cb, =>
        @roomState.removeFromList listName, values, (error) ->
          cb error, data

  # @private
  # @nodoc
  getMode : (author, cb) ->
    @roomState.whitelistOnlyGet cb

  # @private
  # @nodoc
  changeMode : (author, mode, cb) ->
    @checkModeChange author, mode, withEH cb, =>
      whitelistOnly = if mode then true else false
      @roomState.whitelistOnlySet whitelistOnly, withEH cb, =>
        @getModeChangedCurrentAccess whitelistOnly, cb


# @private
# @mixin
# @nodoc
DirectMessagingHelpers =

  # @private
  checkUser : (author, cb) ->
    if author != @username
      error = @errorBuilder.makeError 'notAllowed'
    process.nextTick -> cb error

  # @private
  checkList : (author, listName, cb) ->
    @checkUser author, withEH cb, =>
      unless @directMessagingState.hasList listName
        error = @errorBuilder.makeError 'noList', listName
      cb error

  # @private
  hasListValue : (author, listName, name, cb) ->
    @checkList author, listName, withEH cb, =>
      if name == @username
        return cb @errorBuilder.makeError 'notAllowed'
      @directMessagingState.hasInList listName, name, cb

  # @private
  checkListAdd : (author, listName, name, cb) ->
    @hasListValue author, listName, name, withEH cb, (hasName) =>
      if hasName
        return cb @errorBuilder.makeError 'nameInList', name, listName
      cb()

  # @private
  checkListRemove : (author, listName, name, cb) ->
    @hasListValue author, listName, name, withEH cb, (hasName) =>
      unless hasName
        return cb @errorBuilder.makeError 'noNameInList', name, listName
      cb()

  # @private
  checkAcess : (userName, cb) ->
    if userName == @username
      return process.nextTick -> cb @errorBuilder.makeError 'notAllowed'
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


# Implements user to user messaging with permissions checking.
# @private
# @nodoc
class DirectMessaging

  extend @, DirectMessagingHelpers

  # @param server [Object] ChatService object.
  # @param name [String] User name.
  constructor : (@server, @username) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.directMessagingState
    @directMessagingState = new state @server, @username

  # Resets user direct messaging state according to the object.
  # @param state [Object]
  # @param cb [Callback]
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
    @checkList author, listName, withEH cb, =>
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @checkListAdd author, listName, val, fn
      , withEH cb, =>
        @directMessagingState.addToList listName, values, cb

  # @private
  removeFromList : (author, listName, values, cb) ->
    @checkList author, listName, withEH cb, =>
      async.eachLimit values, asyncLimit
      , (val, fn) =>
        @checkListRemove author, listName, val, fn
      , withEH cb, =>
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
CommandBinders =

  # @private
  wrapCommand : (name, fn) ->
    bname = name + 'Before'
    aname = name + 'After'
    cmd = (oargs..., cb, id) =>
      hooks = @server.hooks
      errorBuilder = @server.errorBuilder
      validator = @server.userCommands[name]
      beforeHook = hooks?[bname]
      afterHook = hooks?[aname]
      execCommand = (error, data) =>
        if error or data then return cb error, data
        afterCommand = (error, data) =>
          reportResults = (nerror = error, ndata = data) ->
            cb nerror, ndata
          if afterHook
            afterHook @, error, data, oargs, reportResults, id
          else
            reportResults()
        fn.apply @
        , [ oargs...
          , afterCommand
          , id ]
      process.nextTick =>
        checkerError = validator oargs...
        if checkerError
          error = errorBuilder.makeError checkerError...
          return cb error
        unless beforeHook
          execCommand()
        else
          beforeHook @, oargs..., execCommand, id
    return cmd

  # @private
  bindCommand : (socket, name, fn) ->
    cmd = @wrapCommand name, fn
    socket.on name, () ->
      cb = _.last arguments
      if typeof cb == 'function'
        args = Array.prototype.slice.call arguments, 0, -1
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
    @server.nsp.in(id)?.emit args...

  broadcast : (id, roomName, args...) ->
    @server.nsp.connected[id]?.broadcast.in(roomName)?.emit args...

  # @private
  isInRoom : (id, roomName) ->
    @server.nsp.adapter.rooms?[roomName]?[id]

  # @private
  socketsInRoom : (sockets, roomName) ->
    sockets.reduce (count, socket) =>
      if @isInRoom socket, roomName then count+1 else count
    , 0

  # @private
  removeUsers : (userNames, roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      async.eachLimit userNames, asyncLimit
      , (userName, fn) =>
        room.leave userName, withEH fn, =>
          @chatState.getUser userName, withEH fn, (user, isOnline) =>
            user.userState.roomRemove roomName, withEH fn, =>
              user.userState.socketsGetAll withEH fn, (sockets) =>
                for id in sockets
                  @send id, 'roomAccessRemoved', roomName
                  @server.nsp.adapter.del id, roomName, ->
                fn()
      , -> cb()

  # @private
  processDisconnect : (id, cb) ->
    @userState.roomsGetAll withEH cb, (rooms) =>
      @userState.socketsGetAll withEH cb, (sockets) =>
        nsockets = sockets.length
        async.eachLimit rooms, asyncLimit
        , (roomName, fn) =>
          @withRoom roomName, withEH fn, (room) =>
            fin = =>
              for sid in sockets
                @send sid, 'roomLeftEcho', roomName, njoined
              fn()
            njoined = @socketsInRoom sockets, roomName
            if njoined == 0
              room.leave @username, withEH fn, =>
                @userState.roomRemove roomName, withEH fn, =>
                  if @enableUserlistUpdates
                    @send roomName, 'roomUserLeft', roomName, @username
                  fin()
            else fin()
        , =>
          if nsockets == 0 then @chatState.logoutUser @username, cb
          else cb()


# Implements a chat user.
# @extend CommandBinders
# @extend UserHelpers
class User extends DirectMessaging

  extend @, CommandBinders, UserHelpers

  # @param server [Object] ChatService object
  # @param name [String] User name
  constructor : (@server, @username) ->
    super @server, @username
    @chatState = @server.chatState
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableAdminlistUpdates = @server.enableAdminlistUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    state = @server.chatState.userState
    @userState = new state @server, @username

  # Resets user direct messaging state according to the object.
  # @param state [Object]
  # @param cb [Callback]
  # @option state [Array<String>] whitelist
  # @option state [Array<String>] blacklist
  # @option state [Boolean] whitelistOnly
  initState : (state, cb) ->
    super state, cb

  # @private
  # @nodoc
  registerSocket : (socket, cb) ->
    @userState.socketAdd socket.id, withEH cb, =>
      for cmd of userCommands
        @bindCommand socket, cmd, @[cmd]
      cb null, @

  # @private
  # @nodoc
  disconnectUser : (cb) ->
    @userState.socketsGetAll withEH cb, (sockets) =>
      async.eachLimit sockets, asyncLimit
      , (sid, fn) =>
        if @server.io.sockets.connected[sid]
          @server.io.sockets.connected[sid].disconnect(true)
          fn()
        else
          # TODO all adapter sockets proper disconnection
          @send sid, 'disconnect'
          @server.nsp.adapter.delAll sid, fn
      , cb

  # @private
  # @nodoc
  directAddToList : (listName, values, cb) ->
    @addToList @username, listName, values, cb

  # @private
  # @nodoc
  directGetAccessList : (listName, cb) ->
    @getList @username, listName, cb

  # @private
  # @nodoc
  directGetWhitelistMode: (cb) ->
    @getMode @username, cb

  # @private
  # @nodoc
  directMessage : (toUserName, msg, cb, id = null) ->
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
  # @nodoc
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @username, listName, values, cb

  # @private
  # @nodoc
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, cb

  # @private
  # @nodoc
  disconnect : (reason, cb, id) ->
    @server.startClientDisconnect()
    endDisconnect = (args...) =>
      @server.endClientDisconnect()
      cb args...
    @chatState.lockUser @username, withEH endDisconnect, (lock) =>
      unlock = (args...) ->
        lock.unlock()
        endDisconnect args...
      @userState.socketRemove id, withEH unlock, =>
        @processDisconnect id, unlock

  # @private
  # @nodoc
  listRooms : (cb) ->
    @chatState.listRooms cb

  # @private
  # @nodoc
  roomAddToList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.addToList @username, listName, values, withEH cb, (data) =>
        if @enableAdminlistUpdates
          for name in values
            @send roomName, 'roomAdminAdded', roomName, name
        @removeUsers data, roomName, cb

  # @private
  # @nodoc
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
  # @nodoc
  roomDelete : (roomName, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @withRoom roomName, withEH cb, (room) =>
      room.checkIsOwner @username, withEH cb, =>
        room.roomState.getList 'userlist', withEH cb, (list) =>
          @removeUsers list, roomName, =>
            @chatState.removeRoom room.name, ->
              room.roomState.removeState cb

  # @private
  # @nodoc
  roomGetAccessList : (roomName, listName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getList @username, listName, cb

  # @private
  # @nodoc
  roomGetWhitelistMode : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMode @username, cb

  # @private
  # @nodoc
  roomHistory : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getLastMessages @username, cb

  # @private
  # @nodoc
  roomJoin : (roomName, cb, id = null) ->
    @withRoom roomName, withEH cb, (room) =>
      room.join @username, withEH cb, =>
        @userState.roomAdd roomName, withEH cb, =>
          @server.nsp.adapter.add id, roomName, withEH cb, =>
            @userState.socketsGetAll withEH cb, (sockets) =>
              njoined = @socketsInRoom sockets, roomName
              for sid in sockets
                if sid != id
                  @send sid, 'roomJoinedEcho', roomName, njoined
              if @enableUserlistUpdates and njoined == 1
                @broadcast id, roomName, 'roomUserJoined', roomName, @username
              cb null, njoined

  # @private
  # @nodoc
  roomLeave : (roomName, cb, id = null) ->
    @withRoom roomName, withEH cb, (room) =>
      @server.nsp.adapter.del id, roomName, withEH cb, =>
        @userState.socketsGetAll withEH cb, (sockets) =>
          njoined = @socketsInRoom sockets, roomName
          report = =>
            for sid in sockets
              if sid != id
                @send sid, 'roomLeftEcho', roomName, njoined
            if @enableUserlistUpdates and njoined == 0
              @broadcast id, roomName, 'roomUserLeft', roomName, @username
            cb null, njoined
          if njoined == 0
            room.isUser @username, withEH cb, (isRoomUser) =>
              if isRoomUser
                room.leave @username, withEH cb, =>
                  @userState.roomRemove roomName, withEH cb, report
              else cb @errorBuilder.makeError 'notJoined', roomName
          else report()

  # @private
  # @nodoc
  roomMessage : (roomName, msg, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      pmsg = processMessage @username, msg
      room.message @username, pmsg, withEH cb, =>
        @send roomName, 'roomMessage', roomName, @username, pmsg
        cb null, msg

  # @private
  # @nodoc
  roomRemoveFromList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.removeFromList @username, listName, values, withEH cb, (data) =>
        if @enableAdminlistUpdates
          for name in values
            @send roomName, 'roomAdminRemoved', roomName, name
        @removeUsers data, roomName, cb

  # @private
  # @nodoc
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @username, mode, withEH cb, (data) =>
        @removeUsers data, roomName, cb


# An instance creates a new chat service.
class ChatService
  # Server creation/integration.
  # @option options [String] namespace
  #   io namespace, default is '/chat-service'.
  # @option options [Integer] historyMaxMessages
  #   room history size, default is 100.
  # @option options [Boolean] useRawErrorObjects
  #   Send error objects (see {ErrorBuilder}) instead of strings,
  #   default is false.
  # @option options [Boolean] enableUserlistUpdates
  #   Enables {ServerMessages#roomUserJoined} and
  #   {ServerMessages#roomUserLeft} messages, default is false.
  # @option options [Boolean] enableAdminlistUpdates
  #   Enables {ServerMessages#roomAdminAdded} and
  #   {ServerMessages#roomAdminRemoved} messages, default is false.
  # @option options [Boolean] enableDirectMessages
  #   Enables user to user {UserCommands#directMessage}, default is false.
  # @option options [Boolean] serverOptions
  #   Options that are passed to socket.io if server creation is required.
  # @option options [Boolean] stateOptions
  #   Options that are passed to a service state.
  # @option options [Object] io
  #   Socket.io instance that should be used by ChatService.
  # @option options [Object] http
  #   Use socket.io http server integration.
  # @option hooks [Function] auth Socket.io auth hook. Look in the
  #   socket.io documentation.
  # @option hooks
  #   [Function(<ChatService>, <Socket>, <Function(<Error>, <String>, <Object>, <Object>)>)]
  #   onConnect Client connection hook. Must call a callback with
  #   either error or user name, auth data and user state. User name
  #   and auth data are send back with `loginConfirmed` message. Error
  #   is sent as `loginRejected` message. User state is the same as
  #   {User#initState}.
  # @option hooks [Function(<ChatService>, <Error>, <Function(<Error>)>)]
  #   onClose Executes when server is closed. Must call a callback.
  # @option hooks [Function(<ChatService>, <Function(<Error>)>)] onStart
  #   Executes when server is started. Must call a callback.
  # @param options [Object] Options.
  # @param hooks [Object] Hooks. Every `UserCommand` is wrapped with
  #   the corresponding Before and After hooks. So a hook name will
  #   look like `roomCreateBefore`. Before hook is ran after arguments
  #   validation, but before an actual server command processing. After
  #   hook is executed after a server has finshed command processing.
  #   Check Hooks unit tests section in the `test` directory for
  #   more details and hooks usage examples.
  # @param state [String or Constructor] Chat state. Can be either
  #   'memory' or 'redis' for built-in state storage, or a custom state
  #   constructor function that implements the same API.
  constructor : (@options = {}, @hooks = {}, @state = 'memory') ->
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
    @enableAdminlistUpdates = @options.enableAdminlistUpdates || false
    @enableRoomsManagement = @options.enableRoomsManagement || false
    @enableDirectMessages = @options.enableDirectMessages || false
    @closeTimeout = @options.closeTimeout || 5000
    @serverOptions = @options.serverOptions
    @stateOptions = @options.stateOptions

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
    unless @io
      if @http
        @io = socketIO @http, @serverOptions
      else
        port = @serverOptions?.port || 8000
        @io = socketIO port, @serverOptions
    @nsp = @io.of @namespace
    @userCommands = userCommands
    @serverMessages = serverMessages
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
        @hooks.onConnect @, socket, (error, userName, authData, userState) =>
          @addClient error, socket, userName, authData, userState
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
  addClient : (error, socket, userName, authData = {}, userState = null) ->
    if error then return @rejectLogin socket, error
    unless userName
      userName = socket.handshake.query?.user
      unless userName
        error = @errorBuilder.makeError 'noLogin'
        return @rejectLogin socket, error
    @chatState.loginUser userName, socket, (error, user) =>
      if error then return @rejectLogin socket, error
      fn = -> socket.emit 'loginConfirmed', userName, authData
      if userState then user.initState userState, fn
      else fn()

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
