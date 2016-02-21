
_ = require 'lodash'
async = require 'async'
check = require 'check-types'

{ withEH, bindUnlock, extend, asyncLimit } =
  require('./utils.coffee')

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
# Commands arguments type and count validation functions.
ArgumentsValidators =
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
# @mixin
# @nodoc
#
# Implements direct messaging permissions checks.
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
# Implements direct messaging state manipulations with the respect to
# user's permissions.
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
      validator = ArgumentsValidators[name]
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
      for cmd of ArgumentsValidators
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
    @addToList @username, listName, values, (error) -> cb error

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
    @removeFromList @username, listName, values, (error) -> cb error

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, (error) -> cb error

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
    room = @server.makeRoom roomName
    @chatState.addRoom room, withEH cb, (nadded) =>
      if nadded != 1
        error = @errorBuilder.makeError 'roomExists', roomName
        return cb error
      room.initState { owner : @username, whitelistOnly : whitelistOnly }
      , (error) -> cb error

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
              room.removeState (error) -> cb error

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
        cb()

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

module.exports = User
