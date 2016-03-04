
_ = require 'lodash'
async = require 'async'

DirectMessaging = require './DirectMessaging'

{ asyncLimit
  checkNameSymbols
  extend
  withEH
  withoutData
} = require './utils.coffee'


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
      transport = @server.transport
      beforeHook = @server.hooks?["#{name}Before"]
      afterHook = @server.hooks?["#{name}After"]
      execCommand = (error, data, nargs...) =>
        if error or data
          return cb error, data
        args = if nargs.length then nargs else oargs
        if args.length != oargs.length
          return cb errorBuilder.makeError 'serverError', 'hook nargs error.'
        afterCommand = (error, data) =>
          reportResults = (nerror = error, ndata = data, moredata...) ->
            if name == 'disconnect'
              transport.endClientDisconnect()
            else
              cb nerror, ndata, moredata...
          if afterHook
            results = _.slice arguments
            afterHook @server, @username, id, args, results, reportResults
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
  bindCommand : (id, name, fn) ->
    cmd = @wrapCommand name, fn
    @transport.bind id, name, ->
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
      cmd args..., ack, id


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
    @transport.sendToChannel roomName, 'roomUserJoined', roomName, userName

  # @private
  userLeftRoomReport : (userName, roomName) ->
    @transport.sendToChannel roomName, 'roomUserLeft', roomName, userName

  # @private
  userRemovedReport : (userName, roomName) ->
    echoChannel = @userState.makeEchoChannelName userName
    @transport.sendToChannel echoChannel, 'roomAccessRemoved', roomName
    @userLeftRoomReport userName, roomName

  # @private
  socketJoinEcho : (id, roomName, njoined) ->
    echoChannel = @userState.echoChannel
    @transport.sendToOthers id, echoChannel, 'roomJoinedEcho'
    , roomName, id, njoined

  # @private
  socketLeftEcho : (id, roomName, njoined) ->
    echoChannel = @userState.echoChannel
    @transport.sendToOthers id, echoChannel, 'roomLeftEcho'
    , roomName, id, njoined

  # @private
  socketConnectEcho : (id, nconnected) ->
    echoChannel = @userState.echoChannel
    @transport.sendToOthers id, echoChannel, 'socketConnectEcho', id, nconnected

  # @private
  socketDisconnectEcho : (id, nconnected) ->
    echoChannel = @userState.echoChannel
    @transport.sendToOthers id, echoChannel, 'socketDisconnectEcho', id
    , nconnected

  # @private
  leaveChannel : (id, channel, cb) ->
    data = { room : channel, id : id }
    data.op = 'socketLeaveChannel'
    @transport.leaveChannel id, channel, @withFailLog data, cb

  # @private
  socketLeaveChannels : (id, channels, cb) ->
    async.eachLimit channels, asyncLimit, (channel, fn) =>
      @leaveChannel id, channel, fn
    , cb

  # @private
  channelLeaveSockets : (channel, ids, cb) ->
    async.eachLimit ids, asyncLimit, (id, fn) =>
      @leaveChannel id, channel, fn
    , cb

  # @private
  makeRollbackRoomJoin : (id, room, isNewJoin, cb) ->
    data = { room : room.name, id : id }
    data.op = 'joinSocketToRoom'
    @withFailLog data, =>
      async.parallel [
        (fn) =>
          unless isNewJoin then return fn()
          d = _.clone data
          d.op = 'RollbackUserJoinRoom'
          room.leave @username, @withFailLog d, fn
        (fn) =>
          d = _.clone data
          d.op = 'RollbackSocketJoinRoom'
          @userState.removeSocketFromRoom id, roomName, @withFailLog d, fn
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
      unlock = @userState.bindUnlockSelf lock, 'joinSocketToRoom', id, cb
      if israce
        return unlock @errorBuilder.makeError 'serverError', 500
      @withRoom roomName, withEH unlock, (room) =>
        room.join @username, withEH unlock, (isNewJoin) =>
          rollback = @makeRollbackRoomJoin id, room, isNewJoin, unlock
          @userState.addSocketToRoom id, roomName, withEH rollback, (njoined) =>
            @transport.joinChannel id, roomName, withEH rollback, =>
              if njoined == 1
                @userJoinRoomReport @username, roomName
              @socketJoinEcho id, roomName, njoined
              cb null, njoined

  # @private
  leaveSocketFromRoom : (id, roomName, cb) ->
    @userState.lockSocketRoom id, roomName, withEH cb, (lock, israce) =>
      unlock = @userState.bindUnlockSelf lock, 'leaveSocketFromRoom', id, cb
      if israce
        return unlock @errorBuilder.makeError 'serverError', 500
      @userState.removeSocketFromRoom id, roomName, withEH unlock
      , (njoined) =>
        @leaveChannel id, roomName, =>
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
        unlock = @userState.bindUnlockOthers lock, 'removeUserFromRoom'
        , userName, fn
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

  extend @, CommandBinder, UserAssociations

  # @private
  constructor : (@server, @username) ->
    super @server, @username
    @state = @server.state
    @transport = @server.transport
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableAccessListsUpdates = @server.enableAccessListsUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    State = @server.state.UserState
    @userState = new State @server, @username
    @lockTTL = @userState.lockTTL
    @echoChannel = @userState.echoChannel
    @errorsLogger = @server.errorsLogger
    @withFailLog = (data, cb) =>
      (error, args...) =>
        data.username = @username unless data.username
        @errorsLogger error, data if error and @errorsLogger
        cb args...

  # @private
  processMessage : (msg, setTimestamp = false) ->
    if setTimestamp
      msg.timestamp = _.now() unless msg.timestamp?
    msg.author = @username unless msg.author?
    return msg

  # @private
  exec : (command, useHooks, id, args..., cb) ->
    unless command in @server.userCommands
      return process.nextTick =>
        @errorBuilder.makeError 'noCommand', command
    if not id and command in [ 'disconnect', 'roomJoin' ,'roomLeave' ]
      return process.nextTick =>
        @errorBuilder.makeError 'noSocket', command
    if useHooks
      cmd = @server.userCommands[command]
      fn = @wrapCommand command, cmd
      fn args..., cb, id
    else
      @[command] args..., cb, id

  # @private
  registerSocket : (id, cb) ->
    @userState.addSocket id, withEH cb, (nconnected) =>
      for cmd of @server.userCommands
        @bindCommand id, cmd, @[cmd]
      @socketConnectEcho id, nconnected
      cb null, @

  # @private
  disconnectInstanceSockets : (cb) ->
    @userState.getAllSockets withEH cb, (sockets) =>
      async.eachLimit sockets, asyncLimit, (sid, fn) =>
        @transport.disconnectClient sid
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
  directMessage : (toUserName, msg, cb, id = null) ->
    unless @enableDirectMessages
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @processMessage msg, true
    @server.state.getUser toUserName, withEH cb, (toUser) =>
      toUser.message @username, msg, withEH cb, =>
        toUser.userState.getAllSockets withEH cb, (toSockets) =>
          unless toSockets?.length
            return cb @errorBuilder.makeError 'noUserOnline', toUser
          @transport.sendToChannel toUser.echoChannel, 'directMessage', msg
          @transport.sendToOthers id, @echoChannel, 'directMessageEcho'
          , toUserName, msg
          cb null, msg

  # @private
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @username, listName, values, withoutData cb

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @username, mode, withoutData cb

  # @private
  disconnect : (reason, cb, id) ->
    @removeSocketFromServer id, cb

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
          @transport.sendToChannel roomName, 'roomAccessListAdded'
          , roomName, listName , values
        @removeRoomUsers room, usernames, cb

  # @private
  roomCreate : (roomName, whitelistOnly, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    if checkNameSymbols roomName
      error = @errorBuilder.makeError 'invalidName', roomName
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
  roomGetOwner : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getOwner @username, cb

  # @private
  roomGetWhitelistMode : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMode @username, cb

  # @private
  roomHistory : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getRecentMessages @username, cb

  # @private
  roomHistoryLastId : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMessagesLastId @username, cb

  # @private
  roomHistorySync : (roomName, id, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMessagesAfterId @username, id, cb

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
      @processMessage msg
      room.message @username, msg, withEH cb, (pmsg) =>
        @transport.sendToChannel roomName, 'roomMessage', roomName, pmsg
        cb()

  # @private
  roomRemoveFromList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.removeFromList @username, listName, values, withEH cb, (usernames) =>
        if @enableAccessListsUpdates
          @transport.sendToChannel roomName, 'roomAccessListRemoved',
          roomName, listName, values
        @removeRoomUsers room, usernames, cb

  # @private
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @username, mode, withEH cb, (usernames) =>
        @removeRoomUsers room, usernames, cb


module.exports = User
