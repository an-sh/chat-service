
_ = require 'lodash'
async = require 'async'

DirectMessaging = require './DirectMessaging'

{ withEH, bindUnlock, extend, asyncLimit, withoutData } =
  require './utils.coffee'


# @private
# @nodoc
processMessage = (author, msg) ->
  msg.timestamp = new Date().getTime() unless msg.timestamp?
  msg.author = author unless msg.author?
  return msg


# @private
# @mixin
# @nodoc
#
# Implements command implementation functions binding and wrapping.
# Required existence of server in extented classes.
CommandBinders =

  # @private
  wrapCommand : (name, fn) ->
    errorBuilder = @server.errorBuilder
    cmd = (oargs..., cb, id) =>
      validator = @server.validator
      beforeHook = @server.hooks?["#{name}Before"]
      afterHook = @server.hooks?["#{name}After"]
      execCommand = (error, data, nargs...) =>
        if error or data
          return cb error, data
        args = if nargs.length then nargs else oargs
        if args.length != oargs.length
          return cb errorBuilder.makeError 'serverError', 'hook nargs error.'
        afterCommand = (error, data) =>
          reportResults = (nerror = error, ndata = data) ->
            cb nerror, ndata
          if afterHook
            afterHook @server, @username, id, error, data, args, reportResults
          else
            reportResults()
        fn.apply @, [ args..., afterCommand, id ]
      validator.checkArguments name, oargs, (error) =>
        if error
          return cb errorBuilder.makeError error...
        unless beforeHook
          execCommand()
        else
          beforeHook @server, @username, id, oargs, execCommand
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
#
# Helpers for User class.
UserHelpers =

  # @private
  withRoom : (roomName, fn) ->
    @state.getRoom roomName, fn

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
  socketsInRoomCount : (roomName, cb) ->
    @userState.getRoomSockets roomName, withEH cb, (sockets) ->
      cb null, sockets?.length || 0


# @private
# @mixin
# @nodoc
#
# Cleanup functions for User class.
UserCleanups =

  # @private
  removeRoomUsers : (room, userNames, cb) ->
    roomName = room.name
    async.eachLimit userNames, asyncLimit
    , (userName, fn) =>
      @state.lockUser userName, withEH fn, (lock) =>
        unlock = bindUnlock lock, fn
        room.leave userName, withEH unlock, =>
          @state.getUser userName, withEH unlock, (user, isOnline) =>
            user.userState.removeAllSocketsFromRoom roomName, withEH unlock, =>
              user.userState.getAllSockets withEH unlock, (sockets) =>
                for id in sockets
                  @send id, 'roomAccessRemoved', roomName
                  socket = @getSocketObject id
                  socket?.leave roomName
                unlock()
    , -> cb()

  # @private
  removeRoomSocket : (id, allsockets, roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      @userState.removeSocketFromRoom roomName, id, withEH cb, =>
        @socketsInRoomCount roomName, withEH cb, (njoined) =>
          sendEcho = =>
            for sid in allsockets
              @send sid, 'roomLeftEcho', roomName, id, njoined
          sendLeave = =>
            if @enableUserlistUpdates
              @send roomName, 'roomUserLeft', roomName, @username
          if njoined == 0
            room.leave @username, withEH cb, ->
              sendLeave()
              sendEcho()
              cb()
          else
            sendEcho()
            cb()

  # @private
  processDisconnect : (id, cb) ->
    @userState.getAllRooms withEH cb, (rooms) =>
      @userState.getAllSockets withEH cb, (sockets) =>
        nsockets = sockets.length
        end = =>
          @state.removeSocket @state.serverUID, id, withEH cb, =>
            for sid in sockets
              @send sid, 'socketDisconnectEcho', id, nsockets
            cb()
        async.eachLimit rooms, asyncLimit
        , (roomName, fn) =>
          @removeRoomSocket id, sockets, roomName, fn
        , =>
          if nsockets == 0
            @state.setUserOffline @username, end
          else
            end()


# @private
# @nodoc
#
# Client commands implementation.
class User extends DirectMessaging

  extend @, CommandBinders, UserHelpers, UserCleanups

  # @private
  constructor : (@server, @username) ->
    super @server, @username
    @state = @server.state
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableAccessListsUpdates = @server.enableAccessListsUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    State = @server.state.UserState
    @userState = new State @server, @username

  # @private
  initState : (state, cb) ->
    super state, cb

  # @private
  registerSocket : (socket, cb) ->
    id = socket.id
    @userState.addSocket id, withEH cb, =>
      for cmd of @server.userCommands
        @bindCommand socket, cmd, @[cmd]
      @userState.getAllSockets withEH cb, (sockets) =>
        nsockets = sockets.length
        for sid in sockets
          if sid != id
            @send sid, 'socketConnectEcho', id, nsockets
      cb null, @

  # @private
  disconnectSockets : (cb) ->
    @userState.getAllSockets withEH cb, (sockets) =>
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
    @addToList @username, listName, values, withoutData cb

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
    @state.getOnlineUser toUserName, withEH cb, (toUser) =>
      @state.getOnlineUser @username, withEH cb, (fromUser) =>
        pmsg = processMessage @username, msg
        toUser.message @username, pmsg, withEH cb, =>
          fromUser.userState.getAllSockets withEH cb, (sockets) =>
            for sid in sockets
              if sid != id
                @send sid, 'directMessageEcho', toUserName, pmsg
            toUser.userState.getAllSockets withEH cb, (sockets) =>
              for sid in sockets
                @send sid, 'directMessage', pmsg
              cb null, msg

  # @private
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @username, listName, values, withoutData cb

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, withoutData cb

  # @private
  disconnect : (reason, cb, id) ->
    @server.startClientDisconnect()
    endDisconnect = (args...) =>
      @server.endClientDisconnect()
      cb args...
    @state.lockUser @username, withEH endDisconnect, (lock) =>
      unlock = bindUnlock lock, endDisconnect
      @userState.removeSocket id, withEH unlock, =>
        @processDisconnect id, unlock

  # @private
  listJoinedRooms : (cb) ->
    result = {}
    @state.lockUser @username, withEH cb, (lock) =>
      unlock = bindUnlock lock, cb
      @userState.getAllRooms withEH unlock, (rooms) =>
        async.eachLimit rooms, asyncLimit
        , (roomName, fn) =>
          @userState.getRoomSockets roomName, withEH fn, (sockets) ->
            result[roomName] = sockets
            fn()
        , withEH unlock, ->
          unlock null, result

  # @private
  listRooms : (cb) ->
    @state.listRooms cb

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
    @state.addRoom roomName
      , { owner : @username, whitelistOnly : whitelistOnly }
      , withoutData cb

  # @private
  roomDelete : (roomName, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @withRoom roomName, withEH cb, (room) =>
      room.checkIsOwner @username, withEH cb, =>
        room.getUsers withEH cb, (usernames) =>
          @removeRoomUsers room, usernames, =>
            @state.removeRoom room.name, ->
              room.removeState withoutData cb

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
      @state.lockUser @username, withEH cb, (lock) =>
        unlock = bindUnlock lock, cb
        room.join @username, withEH unlock, =>
          @userState.addSocketToRoom roomName, id, withEH unlock, =>
            socket.join roomName, withEH unlock, =>
              @userState.getAllSockets withEH unlock, (sockets) =>
                @userState.getRoomSockets roomName, withEH unlock
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
      @state.lockUser @username, withEH cb, (lock) =>
        unlock = bindUnlock lock, cb
        socket.leave roomName, withEH unlock, =>
          @userState.removeSocketFromRoom roomName, id, withEH unlock, =>
            @userState.getAllSockets withEH unlock, (sockets) =>
              @userState.getRoomSockets roomName, withEH unlock
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
        @send roomName, 'roomMessage', roomName, pmsg
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
