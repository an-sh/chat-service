
_ = require 'lodash'
async = require 'async'

DirectMessaging = require './DirectMessaging'

{withEH, bindFailLog, extend, asyncLimit, withoutData} =
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
CommandBinder =

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
# Transport Helpers for User class.
TransportHelpers =

  # @private
  sendToChannel : (channel, args...) ->
    @server.nsp.to(channel)?.emit args...

  # @private
  getSocketObject : (id) ->
    @server.nsp.connected[id]

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


# @private
# @nodoc
# @mixin
#
# Associations for User class.
UserAssociations =

  # @private
  withRoom : (roomName, fn) ->
    @state.getRoom roomName, fn

  # @private
  userJoinRoomReport : (userName, roomName) ->
    @sendToChannel roomName, 'roomUserJoined', roomName, userName

  # @private
  userLeftRoomReport : (userName, roomName) ->
    @sendToChannel roomName, 'roomUserLeft', roomName, userName

  # @private
  userRemovedReport : (userName, roomName) ->
    echoChannel = @userState.makeEchoChannelName userName
    @sendToChannel echoChannel, 'roomAccessRemoved', roomName
    @userLeftRoomReport userName, roomName

  # @private
  socketOpEcho : (op, id, num, roomName) ->
    echoChannel = @userState.echoChannel
    if roomName
      @sendToChannel echoChannel, op, roomName, id, num
    else
      @sendToChannel echoChannel, op, id, num

  # @private
  socketJoinEcho : (id, roomName, njoined) ->
    @socketOpEcho 'roomJoinedEcho', id, njoined, roomName

  # @private
  socketLeftEcho : (id, roomName, njoined) ->
    @socketOpEcho 'roomLeftEcho', id, njoined, roomName

  # @private
  socketConnectEcho : (id, nconnected) ->
    @socketOpEcho 'socketConnectEcho', id, nconnected

  # @private
  socketDisconnectEcho : (id, nconnected) ->
    @socketOpEcho 'socketDisconnectEcho', id, nconnected

  # @private
  leaveChannelWithLog : (id, channel, cb) ->
    data = { username : @username, room : channel, id : id }
    data.op = 'socketLeaveChannel'
    @leaveChannel id, channel, @withFailLog data, cb

  # @private
  socketLeaveChannels : (id, channels, cb) ->
    async.eachLimit channels, asyncLimit, (channel, fn) =>
      @leaveChannelWithLog id, channel, fn
    , cb

  # @private
  channelLeaveSockets : (channel, ids, cb) ->
    async.eachLimit ids, asyncLimit, (id, fn) =>
      @leaveChannelWithLog id, channel, fn
    , cb

  # @private
  rollbackRoomJoin : (error, room, cb) ->
    data = { username : @username, room : room.name }
    data.op = 'joinSocketToRoom'
    @errorsLogger error, data
    async.parallel [
      (fn) =>
        d = _.clone data
        d.op = 'RollbackUserJoinRoom'
        room.leave @username, @withFailLog d, fn
      (fn) =>
        d = _.clone data
        d.op = 'RollbackSocketJoinRoom'
        @userState.removeSocketFromRoom id, roomName, @withFailLog d, fn
      (fn) =>
        d = _.clone data
        d.op 'RollbackSocketJoinChannel'
        @leaveChannel id, roomName, @withFailLog d, fn
      ] , =>
        cb @errorBuilder.makeError 'serverError', 500

  # @private
  leaveRoom : (roomName, cb) ->
    data = { username : @username, room : roomName }
    data.op = 'UserLeaveRoom'
    @withRoom roomName, @withFailLog data, (room) =>
      room.leave @username, @withFailLog data, cb

  # @private
  removeRoomUser : (userName, roomName, cb) ->
    @userState.removeAllSocketsFromRoom roomName, withEH cb
    , (removedSockets) =>
      if removedSockets?.length
        @channelLeaveSockets roomName, removedSockets, =>
          @userRemovedReport userName, roomName
          @leaveRoom roomName, cb
      else
        @leaveRoom roomName, cb

  # @private
  joinSocketToRoom : (id, roomName, cb) ->
    @userState.lockSocketRoom id, roomName, withEH cb, (lock, israce) =>
      unlock = @userState.bindUnlock lock
      , 'joinSocketToRoom', @username, id, cb
      if israce
        return unlock @errorBuilder.makeError 'serverError', 500
      @withRoom roomName, withEH unlock, (room) =>
        room.join @username, withEH unlock, =>
          rollback = (error) =>
            @rollbackRoomJoin error, room, unlock
          @userState.addSocketToRoom id, roomName, withEH rollback, (njoined) =>
            @joinChannel id, roomName, withEH rollback, =>
              if njoined == 1
                @userJoinRoomReport @username, roomName
              @socketJoinEcho id, roomName, njoined
              cb null, njoined

  # @private
  leaveSocketFromRoom : (id, roomName, cb) ->
    @userState.lockSocketRoom id, roomName, withEH cb, (lock, israce) =>
      unlock = @userState.bindUnlock lock
      , 'leaveSocketFromRoom', @username, id, cb
      if israce
        return unlock @errorBuilder.makeError 'serverError', 500
      @userState.removeSocketFromRoom id, roomName, withEH unlock
      , (njoined) =>
        @leaveChannelWithLog id, roomName, =>
          @socketLeftEcho id, roomName, njoined
          unless njoined
            @leaveRoom roomName, =>
              @userLeftRoomReport @username, roomName
              unlock null, 0
          else
            unlock null, njoined

  # @private
  removeUserFromRoom : (userName, roomName, cb) ->
    task = (fn) =>
      @userState.lockSocketRoom null, roomName, withEH fn, (lock) =>
        unlock = @userState.bindUnlock lock
        , 'removeUserFromRoom', userName, null, fn
        @removeRoomUser userName, roomName, unlock
    data = { username : userName, room : roomName }
    data.op = 'removeUserFromRoom'
    async.retry { times : 2, interval : @lockTTL }, task, @withFailLog data, cb

  # @private
  removeSocketFromServer : (id, cb) ->
    @userState.setSocketDisconnecting id, withEH cb, =>
      @userState.removeSocket id, withEH cb
      , (roomsRemoved, joinedSockets, nconnected) =>
        if roomsRemoved?.length
          @socketLeaveChannels id, roomsRemoved, =>
            for roomName, idx in roomsRemoved
              njoined = joinedSockets[idx]
              @socketLeftEcho id, roomName, njoined
              unless njoined then @userLeftRoomReport @username, roomName
            @socketDisconnectEcho id, nconnected
            cb null, nconnected
        else
          @socketDisconnectEcho id, nconnected
          cb null, nconnected

  # @private
  removeRoomUsers : (room, usernames, cb) ->
    roomName = room.name
    async.eachLimit usernames, asyncLimit, (userName, fn) =>
      @removeUserFromRoom userName, roomName, fn
    , -> cb()


# @private
# @nodoc
#
# Client commands implementation.
class User extends DirectMessaging

  extend @, TransportHelpers, CommandBinder, UserAssociations

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
    @errorsLogger = @server.errorsLogger
    @lockTTL = @userState.lockTTL
    @echoChannel = @userState.echoChannel
    bindFailLog @, @errorsLogger

  # @private
  registerSocket : (socket, cb) ->
    id = socket.id
    @userState.addSocket id, withEH cb, (nconnected) =>
      for cmd of @server.userCommands
        @bindCommand socket, cmd, @[cmd]
      @socketConnectEcho id, nconnected
      cb null, @

  # @private
  disconnectInstanceSockets : (cb) ->
    @userState.getAllSockets withEH cb, (sockets) =>
      async.eachLimit sockets, asyncLimit, (sid, fn) =>
        if @server.nsp.connected[sid]
          @server.nsp.connected[sid].disconnect()
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
    # TODO simplify getUser, use echoChannels
    @server.state.getUser toUserName, withEH cb, (toUser) =>
      pmsg = processMessage @username, msg
      toUser.message @username, pmsg, withEH cb, =>
        @userState.getAllSockets withEH cb, (fromSockets) =>
          toUser.userState.getAllSockets withEH cb, (toSockets) =>
            unless toSockets?.length
              return cb @errorBuilder.makeError 'noUserOnline', toUser
            for sid in fromSockets
              if sid != id
                @sendToChannel sid, 'directMessageEcho', toUserName, pmsg
            for sid in toSockets
              @sendToChannel sid, 'directMessage', pmsg
            cb null, pmsg

  # @private
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @username, listName, values, withoutData cb

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, withoutData cb

  # @private
  disconnect : (reason, cb, id) ->
    @server.startClientDisconnect()
    endDisconnect = (error, args...) =>
      if error
        data = { username : @username, id : id }
        data.op = 'SocketDisconnect'
        @errorsLogger data
      @server.endClientDisconnect()
      cb error, args...
    @removeSocketFromServer id, endDisconnect

  # @private
  listJoinedSockets : (cb) ->
    @userState.getSocketsToRooms cb

  # @private
  listRooms : (cb) ->
    @state.listRooms cb

  # @private
  roomAddToList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.addToList @username, listName, values, withEH cb, (usernames) =>
        if @enableAccessListsUpdates
          @sendToChannel roomName, 'roomAccessListAdded', roomName, listName
          , values
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
    @withRoom roomName, withEH cb, (room) =>
      @joinSocketToRoom id, room.name, cb

  # @private
  roomLeave : (roomName, cb, id) ->
    @withRoom roomName, withEH cb, (room) =>
      @leaveSocketFromRoom id, room.name, cb

  # @private
  roomMessage : (roomName, msg, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      pmsg = processMessage @username, msg
      room.message @username, pmsg, withEH cb, =>
        @sendToChannel roomName, 'roomMessage', roomName, pmsg
        cb()

  # @private
  roomRemoveFromList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.removeFromList @username, listName, values, withEH cb, (usernames) =>
        if @enableAccessListsUpdates
          @sendToChannel roomName, 'roomAccessListRemoved', roomName, listName
          , values
        @removeRoomUsers room, usernames, cb

  # @private
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @username, mode, withEH cb, (usernames) =>
        @removeRoomUsers room, usernames, cb


module.exports = User
