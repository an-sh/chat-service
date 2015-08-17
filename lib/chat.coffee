
socketIO = require 'socket.io'
_ = require 'lodash'
async = require 'async'
check = require 'check-types'


MemoryState = require('./state-memory.coffee').MemoryState
ErrorBuilder = require('./errors.coffee').ErrorBuilder
withEH = require('./errors.coffee').withEH
withErrorLog = require('./errors.coffee').withErrorLog


# @nodoc
serverMessages =
  directMessage : ''
  directMessageEcho : ''
  loginConfirmed: ''
  loginRejected : ''
  roomAccessRemoved : ''
  roomJoined : ''
  roomLeft : ''
  roomMessage : ''
  roomUserJoin : ''
  roomUserLeave : ''

# @nodoc
userCommands =
  directAddToList : ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  directGetAccessList : ->
    dataChecker arguments, [
      check.string
    ]
  directGetWhitelistMode : ->
    dataChecker arguments, [
    ]
  directMessage : ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  directRemoveFromList : ->
    dataChecker arguments, [
      check.string
      check.array.of.string
    ]
  directSetWhitelistMode : ->
    dataChecker arguments, [
      check.boolean
    ]
  disconnect : ->
    dataChecker arguments, [
      check.string
    ]
  listRooms : ->
    dataChecker arguments, [
    ]
  roomAddToList : ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  roomCreate : ->
    dataChecker arguments, [
      check.string
      check.boolean
    ]
  roomDelete : ->
    dataChecker arguments, [
      check.string
    ]
  roomGetAccessList : ->
    dataChecker arguments, [
      check.string
      check.string
    ]
  roomGetWhitelistMode : ->
    dataChecker arguments, [
      check.string
    ]
  roomHistory : ->
    dataChecker arguments, [
      check.string
    ]
  roomJoin : ->
    dataChecker arguments, [
      check.string
    ]
  roomLeave : ->
    dataChecker arguments, [
      check.string
    ]
  roomMessage : ->
    dataChecker arguments, [
      check.string
      checkMessage
    ]
  roomRemoveFromList : ->
    dataChecker arguments, [
      check.string
      check.string
      check.array.of.string
    ]
  roomSetWhitelistMode : ->
    dataChecker arguments, [
      check.string
      check.boolean
    ]


Object.freeze userCommands
Object.freeze serverMessages

# @nodoc
asyncLimit = 16

# @nodoc
processMessage = (author, msg) ->
  r = {}
  r.textMessage = msg?.textMessage?.toString() || ''
  r.timestamp = new Date().getTime()
  r.author = author
  return r

# @nodoc
checkMessage = (msg) ->
  r = check.map msg, { textMessage : check.string }
  if r then return Object.keys(msg).length == 1

# @nodoc
dataChecker = (args, checkers) ->
  if args.length != checkers.length
    return [ 'wrongArgumentsCount', checkers.length, args.length ]
  for checker, idx in checkers
    unless checker args[idx]
      return [ 'badArgument', idx, args[idx] ]
  return null


# Implements room messaging with permissions checking.
class Room

  # @param server [object] ChatService object
  # @param name [string] Room name
  constructor : (@server, @name) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.roomState
    @roomState = new state @server, @name, @server.historyMaxMessages

  # Resets room state according to the object.
  # @param state [object]
  # @param cb [callback]
  initState : (state, cb) ->
    @roomState.initState state, cb

  # @nodoc
  isAdmin : (userName, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      @roomState.hasInList 'adminlist', userName, withEH cb, (hasName) ->
        if owner == userName or hasName
          return cb null, true
        cb null, false

  # @nodoc
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

  # @nodoc
  hasAddChangedCurrentAccess : (userName, listName, cb) ->
    @roomState.hasInList 'userlist', userName, withEH cb, (hasUser) ->
      unless hasUser
        return cb null, false
      if listName == 'blacklist'
        return cb null, true
      cb null, false

  # @nodoc
  getModeChangedCurrentAccess : (value, cb) ->
    unless value
      process.nextTick -> cb null, false
    else
      @roomState.getCommonUsers cb

  # @nodoc
  checkList : (author, listName, cb) ->
    @roomState.hasInList 'userlist', author, withEH cb, (hasAuthor) =>
      unless hasAuthor
        return cb @errorBuilder.makeError 'notJoined', @name
      cb()

  # @nodoc
  checkListChange : (author, listName, name, cb) ->
    @checkList author, listName, withEH cb, =>
      @roomState.ownerGet withEH cb, (owner) =>
        if listName == 'userlist'
          return cb @errorBuilder.makeError 'notAllowed'
        if author == owner
          return cb()
        if name == owner
          return cb @errorBuilder.makeError 'notAllowed'
        @roomState.hasInList 'adminlist', name, withEH cb, (hasName) =>
          if hasName
            return cb @errorBuilder.makeError 'notAllowed'
          @roomState.hasInList 'adminlist', author, withEH cb, (hasAuthor) =>
            unless hasAuthor
              return cb @errorBuilder.makeError 'notAllowed'
            cb()

  # @nodoc
  checkListAdd : (author, listName, name, cb) ->
    @checkListChange author, listName, name, withEH cb, =>
      @roomState.hasInList listName, name, withEH cb, (hasName) =>
        if hasName
          return cb @errorBuilder.makeError 'nameInList', name, listName
        cb()

  # @nodoc
  checkListRemove : (author, listName, name, cb) ->
    @checkListChange author, listName, name, withEH cb, =>
      @roomState.hasInList listName, name, withEH cb, (hasName) =>
        unless hasName
          return cb @errorBuilder.makeError 'noNameInList', name, listName
        cb()

  # @nodoc
  checkModeChange : (author, value, cb) ->
    @isAdmin author, withEH cb, (admin) =>
      unless admin
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

  # @nodoc
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

  # @nodoc
  checkIsOwner : (author, cb) ->
    @roomState.ownerGet withEH cb, (owner) =>
      unless owner == author
        return cb @errorBuilder.makeError 'notAllowed'
      cb()

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
  getMode : (author, cb) ->
    @roomState.whitelistOnlyGet cb

  # @private
  changeMode : (author, mode, cb) ->
    @checkModeChange author, mode, withEH cb, =>
      whitelistOnly = if mode then true else false
      @roomState.whitelistOnlySet whitelistOnly, withEH cb, =>
        @getModeChangedCurrentAccess whitelistOnly, cb



# Implements user to user messaging with permissions checking.
class DirectMessaging

  # @param server [object] ChatService object
  # @param name [string] User name
  constructor : (@server, @username) ->
    @errorBuilder = @server.errorBuilder
    state = @server.chatState.directMessagingState
    @directMessagingState = new state @server, @username

  # Resets user direct messaging state according to the object.
  # @param state [object]
  # @param cb [callback]
  initState : (state, cb) ->
    @directMessagingState.initState state, cb

  # @nodoc
  checkUser : (author, cb) ->
    if author != @username
      error = @errorBuilder.makeError 'notAllowed'
    process.nextTick -> cb error

  # @nodoc
  checkList : (author, listName, cb) ->
    @checkUser author, withEH cb, =>
      unless @directMessagingState.hasList listName
        error = @errorBuilder.makeError 'noList', listName
      cb error

  # @nodoc
  hasListValue : (author, listName, name, cb) ->
    @checkList author, listName, withEH cb, =>
      if name == @username
        return cb @errorBuilder.makeError 'notAllowed'
      @directMessagingState.hasInList listName, name, cb

  # @nodoc
  checkListAdd : (author, listName, name, cb) ->
    @hasListValue author, listName, name, withEH cb, (hasName) =>
      if hasName
        return cb @errorBuilder.makeError 'nameInList', name, listName
      cb()

  # @nodoc
  checkListRemove : (author, listName, name, cb) ->
    @hasListValue author, listName, name, withEH cb, (hasName) =>
      unless hasName
        return cb @errorBuilder.makeError 'noNameInList', name, listName
      cb()

  # @nodoc
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


# Implements socket.io messages to function calls association.
class User extends DirectMessaging

  # @param server [object] ChatService object
  # @param name [string] User name
  constructor : (@server, @username) ->
    super @server, @username
    @chatState = @server.chatState
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    state = @server.chatState.userState
    @userState = new state @server, @username

  # @nodoc
  registerSocket : (socket, cb) ->
    @userState.socketAdd socket.id, withEH cb, =>
      for own cmd of userCommands
        @bindCommand socket, cmd, @[cmd]
      cb()

  # @nodoc
  wrapCommand : (name, fn) ->
    bname = name + 'Before'
    aname = name + 'After'
    cmd = (oargs..., cb, id) =>
      hooks = @server.hooks
      validator = @server.userCommands[name]
      beforeHook = hooks?[bname]
      afterHook = hooks?[aname]
      execCommand = (error, data, nargs...) =>
        if error or data then return cb error, data
        args = if nargs?.length then nargs else oargs
        argsAfter = args
        if args.length != oargs.length
          argsAfter = args.slice()
          args.length = oargs.length
        afterCommand = (error, data) =>
          if afterHook
            afterHook @, argsAfter..., cb or (->), id
          else if cb
            cb error, data
        fn.apply @
        , [ args...
          , afterCommand
          , id ]
      process.nextTick =>
        checkerError = validator oargs...
        if checkerError
          error = @server.errorBuilder.makeError checkerError...
          return cb error
        unless beforeHook
          execCommand()
        else
          beforeHook @, oargs..., execCommand, id
    return cmd

  # @nodoc
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
        error = null unless error
        data = null unless data
        cb error, data if cb
      cmd args..., ack, socket.id

  # @nodoc
  withRoom : (roomName, fn) ->
    @chatState.getRoom roomName, fn

  # @nodoc
  send : (id, args...) ->
    @server.nsp.in(id).emit args...

  # @nodoc
  sendAccessRemoved : (userNames, roomName, cb) ->
    async.eachLimit userNames, asyncLimit
    , (userName, fn) =>
      @chatState.getOnlineUser userName, withEH fn, (user) =>
        user.userState.roomRemove roomName, withEH fn, =>
          user.userState.socketsGetAll withEH fn, (sockets) =>
            for id in sockets
              @send id, 'roomAccessRemoved', roomName
            fn()
    , cb

  # @nodoc
  sendAllRoomsLeave : (cb) ->
    @userState.roomsGetAll withEH cb, (rooms) =>
      async.eachLimit rooms, asyncLimit
      , (roomName, fn) =>
        @chatState.getRoom roomName, withErrorLog @errorBuilder, (room) =>
          room.leave @username, withErrorLog @errorBuilder, =>
            if @enableUserlistUpdates
              @send roomName, 'roomUserLeave', roomName, @username
            fn()
       , =>
        @chatState.logoutUser @username, cb

  # @nodoc
  reportRoomConnections : (error, id, sid, roomName, msgName, cb) ->
    if error
      @errorBuilder.handleServerError error
      error = @errorBuilder.makeError serverError, '500'
    if sid == id
      cb error
    else unless error
      @send sid, msgName, roomName

  # @nodoc
  removeUser : (cb) ->
    @userState.socketsGetAll withEH cb, (sockets) =>
      async.eachLimit sockets, asyncLimit
      , (sid, fn) =>
        if @server.io.sockets.connected[sid]
          @server.io.sockets.connected[sid].disconnect(true)
          @sendAllRoomsLeave fn
        else
          # TODO all adapter sockets proper disconnection
          @send sid, 'disconnect'
          @server.nsp.adapter.delAll sid, => @sendAllRoomsLeave fn
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
  directMessage : (toUserName, msg, cb, id = null) ->
    unless @enableDirectMessages
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @chatState.getOnlineUser toUserName, withEH cb, (toUser) =>
      @chatState.getOnlineUser @username, withEH cb, (fromUser) =>
        msg = processMessage @username, msg
        toUser.message @username, msg, withEH cb, =>
          fromUser.userState.socketsGetAll withEH cb, (sockets) =>
            for sid in sockets
              if sid != id
                @send sid, 'directMessageEcho', toUserName, msg
            toUser.userState.socketsGetAll withEH cb, (sockets) =>
              for sid in sockets
                @send sid, 'directMessage', @username, msg
              cb()

  # @private
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @username, listName, values, cb

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, cb

  # @private
  disconnect : (reason, cb, id) ->
    # TODO lock user state
    @userState.socketRemove id, withEH cb, =>
      @userState.socketsGetAll withEH cb, (sockets) =>
        nsockets = sockets.lenght
        if nsockets > 0 then return cb()
        @sendAllRoomsLeave cb

  # @private
  listRooms : (cb) ->
    @chatState.listRooms cb

  # @private
  roomAddToList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.addToList @username, listName, values, withEH cb, (data) =>
        @sendAccessRemoved data, roomName, cb

  # @private
  roomCreate : (roomName, whitelistOnly, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @chatState.getRoom roomName, (error, room) =>
      if room
        error = @errorBuilder.makeError 'roomExists', roomName
        return cb error
      room = new Room @server, roomName
      room.initState { owner : @username, whitelistOnly : whitelistOnly }
      , withEH cb, => @chatState.addRoom room, cb

  # @private
  roomDelete : (roomName, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @withRoom roomName, withEH cb, (room) =>
      room.checkIsOwner @username, withEH cb, =>
        @chatState.removeRoom room.name, withEH cb, =>
          room.roomState.getList 'userlist', withEH cb, (list) =>
            @sendAccessRemoved list, roomName, cb

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
  roomJoin : (roomName, cb, id = null) ->
    @withRoom roomName, withEH cb, (room) =>
      room.join @username, withEH cb, =>
        @userState.roomAdd roomName, withEH cb, =>
          if @enableUserlistUpdates
            @send roomName, 'roomUserJoin', roomName, @username
          # TODO lock user sockets
          @userState.socketsGetAll withEH cb, (sockets) =>
            async.eachLimit sockets, asyncLimit, (sid, fn) =>
              @server.nsp.adapter.add sid, roomName
              , (error) =>
                @reportRoomConnections error, id, sid, roomName
                , 'roomJoined', cb
                fn()

  # @private
  roomLeave : (roomName, cb, id = null) ->
    @withRoom roomName, withEH cb, (room) =>
      room.leave @username, withEH cb, =>
        @userState.roomRemove roomName, withEH cb, =>
          if @enableUserlistUpdates
            @send roomName, 'roomUserLeave', roomName, @username
          # TODO lock user sockets
          @userState.socketsGetAll withEH cb, (sockets) =>
            async.eachLimit sockets, asyncLimit, (sid, fn) =>
              @server.nsp.adapter.del sid, roomName
              , (error) =>
                @reportRoomConnections error, id, sid, roomName
                , 'roomLeft', cb
                fn()

  # @private
  roomMessage : (roomName, msg, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.message @username, msg, withEH cb, =>
        msg = processMessage @username, msg
        @send roomName, 'roomMessage', roomName, @username, msg
        cb()

  # @private
  roomRemoveFromList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.removeFromList @username, listName, values, withEH cb, (data) =>
        @sendAccessRemoved data, roomName, cb

  # @private
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @username, mode, withEH cb, (data) =>
        @sendAccessRemoved data, roomName, cb


# Main object.
class ChatService

  # API
  constructor : (@options = {}, @hooks = {}, @state = 'memory') ->
    @setOptions()
    @setServer()
    if @hooks.onStart
      @hooks.onStart @, (error) =>
        if error then return @close null, error
        @setEvents()
    else
      @setEvents()

  # @nodoc
  setOptions : ->
    @namespace = @options.namespace || '/chat-service'
    @historyMaxMessages = @options.historyMaxMessages || 100
    @useRawErrorObjects = @options.useRawErrorObjects || false
    @enableUserlistUpdates = @options.enableUserlistUpdates || false
    @enableRoomsManagement = @options.enableRoomsManagement || false
    @enableDirectMessages = @options.enableDirectMessages || false
    @serverOptions = @options.serverOptions

  # @nodoc
  setServer : ->
    @io = @options.io
    @sharedIO = true if @io
    @http = @options.http unless @io
    state = switch @state
      when 'memory' then MemoryState
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
    @User = User
    @Room = Room
    @errorBuilder = new ErrorBuilder @useRawErrorObjects, @hooks.serverErrorHook
    @chatState = new state @

  # @nodoc
  setEvents : ->
    if @hooks.auth
      @nsp.use @hooks.auth
    if @hooks.onConnect
      @nsp.on 'connection', (socket) =>
        @hooks.onConnect @, socket, (error, userName, userState) =>
          @addClient error, socket, userName, userState
    else
      @nsp.on 'connection', (socket) =>
        @addClient null, socket

  # @nodoc
  addClient : (error, socket, userName, userState) ->
    if error then return socket.emit 'loginRejected', error
    unless userName
      userName = socket.handshake.query?.user
      unless userName
        error = @errorBuilder.makeError 'noLogin'
        return socket.emit 'loginRejected', error
    @chatState.loginUser userName, socket, (error, user) ->
      if error then return socket.emit 'loginRejected', error
      fn = -> socket.emit 'loginConfirmed', userName
      if userState then user.initState userState, fn
      else fn()

  # Closes server.
  # @param done [callback] Optional callback
  # @param error [object] Optional error vallue for done callback
  close : (done, error) ->
    cb = (error) =>
      unless @sharedIO or @http then @io.close()
      if done then process.nextTick -> done error
    if @hooks.onClose
      @hooks.onClose @, error, cb
    else
      cb()

module.exports = {
  ChatService
  User
  Room
}
