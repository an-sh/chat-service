
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
            cb nerror, ndata, moredata...
          if afterHook
            results = _.slice arguments
            afterHook @server, @userName, id, args, results, reportResults
          else
            reportResults()
        fn.apply @, [ args..., afterCommand, id ]
      validator.checkArguments name, oargs..., (errors) =>
        if errors
          return cb errorBuilder.makeError errors...
        unless beforeHook
          execCommand()
        else
          beforeHook @server, @userName, id, oargs, execCommand
    return cmd

  # @private
  bindAck : (cb) ->
    (error, data, rest...) ->
      error = null unless error?
      data = null unless data?
      cb error, data, rest... if cb

  # @private
  bindCommand : (id, name, fn) ->
    cmd = @wrapCommand name, fn
    @transport.bind id, name, =>
      cb = _.last arguments
      if _.isFunction cb
        args = _.slice arguments, 0, -1
      else
        cb = null
        args = arguments
      ack = @bindAck cb
      cmd args..., ack, id


# @private
# @nodoc
# @mixin
#
# Associations for User class.
UserAssociations =

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
    roomName = room.name
    data = { room : roomName, id : id }
    (error) =>
      async.parallel [
        (fn) =>
          unless isNewJoin then return fn()
          d = _.clone data
          d.op = 'RollbackUserJoinRoom'
          room.leave @userName
          .then (data) ->
            cb null, data
          , @withFailLog fn
        (fn) =>
          d = _.clone data
          d.op = 'RollbackSocketJoinRoom'
          @userState.removeSocketFromRoom id, roomName
          .then ->
            fn()
          , fn #TODO
        ] , =>
          cb @errorBuilder.makeError 'serverError', error

  # @private
  leaveRoom : (roomName, cb) ->
    data = { userName : @userName, room : roomName }
    data.op = 'UserLeaveRoom'
    @withRoom roomName, @withFailLog data, (room) =>
      room.leave @userName
      .then (data) ->
        cb null, data
      , @withFailLog cb

  # @private
  joinSocketToRoom : (id, roomName, cb) ->
    @userState.lockToRoom id, roomName
    .then (lock) =>
      unlock = @userState.bindUnlock lock, 'joinSocketToRoom', id, cb
      @withRoom roomName, withEH unlock, (room) =>
        room.join @userName
        .then (isNewJoin) =>
          rollback = @makeRollbackRoomJoin id, room, isNewJoin, unlock
          @userState.addSocketToRoom id, roomName
          .then (njoined) =>
            @transport.joinChannel id, roomName, withEH rollback, =>
              if njoined == 1
                @userJoinRoomReport @userName, roomName
              @socketJoinEcho id, roomName, njoined
              cb null, njoined
          , rollback
        , unlock
    , cb

  # @private
  leaveSocketFromRoom : (id, roomName, cb) ->
    @userState.lockToRoom id, roomName
    .then (lock) =>
      unlock = @userState.bindUnlock lock, 'leaveSocketFromRoom', id, cb
      @userState.removeSocketFromRoom id, roomName
      .then (njoined) =>
        @leaveChannel id, roomName, =>
          @socketLeftEcho id, roomName, njoined
          unless njoined
            @leaveRoom roomName, =>
              @userLeftRoomReport @userName, roomName
              unlock null, 0
          else
            unlock null, njoined
      , unlock
    , cb

  # @private
  removeSocketFromServer : (id, cb) ->
    @userState.setSocketDisconnecting id
    .then =>
      @userState.removeSocket id
      .spread (roomsRemoved, joinedSockets, nconnected) =>
        if roomsRemoved?.length
          @socketLeaveChannels id, roomsRemoved, =>
            for roomName, idx in roomsRemoved
              njoined = joinedSockets[idx]
              @socketLeftEcho id, roomName, njoined
              unless njoined then @userLeftRoomReport @userName, roomName
            @socketDisconnectEcho id, nconnected
            cb null, nconnected
        else
          @socketDisconnectEcho id, nconnected
          cb null, nconnected
    , cb

  # @private
  removeFromRoom : (roomName, cb) ->
    @userState.lockToRoom null, roomName
    .then (lock) =>
      unlock = @userState.bindUnlock lock, 'removeUserFromRoom', null, cb
      @userState.removeAllSocketsFromRoom roomName
      .then (removedSockets) =>
        if removedSockets?.length
          @channelLeaveSockets roomName, removedSockets, =>
            @userRemovedReport @userName, roomName
            @leaveRoom roomName, unlock
        else
          @leaveRoom roomName, unlock
      , unlock
    , cb

  # @private
  removeUserFromRoom : (userName, roomName, cb) ->
    task = (fn) =>
      @state.getUser userName
      .then (user) ->
        user.removeFromRoom roomName, fn
      , fn
    async.retry { times : 2, interval : @lockTTL }, task, cb

  # @private
  removeRoomUsers : (room, userNames, cb) ->
    roomName = room.name
    async.eachLimit userNames, asyncLimit, (userName, fn) =>
      @removeUserFromRoom userName, roomName, fn
    , -> cb()


# @private
# @nodoc
#
# Client commands implementation.
class User extends DirectMessaging

  extend @, CommandBinder, UserAssociations

  # @private
  constructor : (@server, @userName) ->
    super @server, @userName
    @state = @server.state
    @transport = @server.transport
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableAccessListsUpdates = @server.enableAccessListsUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    State = @server.state.UserState
    @userState = new State @server, @userName
    @lockTTL = @userState.lockTTL
    @echoChannel = @userState.echoChannel
    @errorsLogger = @server.errorsLogger
    @withFailLog = (data, cb) =>
      (error, args...) =>
        data.userName = @userName unless data.userName
        @errorsLogger error, data if error and @errorsLogger
        cb args...
        return Promise.resolve() #TODO

  # @private
  withRoom : (roomName, cb) ->
    @state.getRoom roomName
    .then (room) ->
      cb null, room
    , cb

  # @private
  processMessage : (msg, setTimestamp = false) ->
    if setTimestamp
      msg.timestamp = _.now() unless msg.timestamp?
    msg.author = @userName unless msg.author?
    return msg

  # @private
  exec : (command, useHooks, id, args..., cb) ->
    ack = @bindAck cb
    unless @server.userCommands[command]
      return process.nextTick =>
        ack @errorBuilder.makeError 'noCommand', command
    if not id and command in [ 'disconnect', 'roomJoin' ,'roomLeave' ]
      return process.nextTick =>
        ack @errorBuilder.makeError 'noSocket', command
    if useHooks
      cmd = @[command]
      fn = @wrapCommand command, cmd
      fn args..., ack, id
    else
      validator = @server.validator
      validator.checkArguments command, args..., (errors) =>
        if errors then return ack @errorBuilder.makeError errors...
        @[command] args..., ack, id

  # @private
  revertRegisterSocket : (id) ->
    @userState.removeSocket id

  # @private
  registerSocket : (id, cb) ->
    @userState.addSocket id
    .then (nconnected) =>
      # Client disconnected before callbacks have been set.
      unless @transport.getSocketObject id
        @revertRegisterSocket id
        cb()
      for cmd of @server.userCommands
        @bindCommand id, cmd, @[cmd]
      @bindCommand id, 'disconnect', => @transport.startClientDisconnect()
      cb null, @, nconnected
    , cb

  # @private
  disconnectInstanceSockets : (cb) ->
    @userState.getAllSockets()
    .then (sockets) =>
      async.eachLimit sockets, asyncLimit, (sid, fn) =>
        @transport.disconnectClient sid
        fn()
      , cb
    , cb

  # @private
  directAddToList : (listName, values, cb) ->
    @addToList @userName, listName, values
    .then ->
      cb()
    , cb

  # @private
  directGetAccessList : (listName, cb) ->
    @getList @userName, listName
    .then (data) ->
      cb null, data
    , cb

  # @private
  directGetWhitelistMode: (cb) ->
    @getMode @userName
    .then (data) ->
      cb null, data
    , cb

  # @private
  directMessage : (recipientName, msg, cb, id = null) ->
    unless @enableDirectMessages
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    recipient = null
    channel = null
    @processMessage msg, true
    @server.state.getUser recipientName
    .then (user) =>
      recipient = user
      channel = recipient.echoChannel
      recipient.message @userName, msg
    .then ->
      recipient.userState.getAllSockets() #TODO
    .then (recipientSockets) =>
      unless recipientSockets?.length
        return Promise.reject @errorBuilder.makeError 'noUserOnline', recipient
      @transport.sendToChannel channel, 'directMessage', msg
      @transport.sendToOthers id, @echoChannel, 'directMessageEcho'
        , recipientName, msg
      Promise.resolve msg
    .then (data) ->
      cb null, data
    , cb

  # @private
  directRemoveFromList : (listName, values, cb) ->
    @removeFromList @userName, listName, values
    .then ->
      cb()
    , cb

  # @private
  directSetWhitelistMode : (mode, cb) ->
    @changeMode @userName, mode
    .then ->
      cb()
    , cb

  # @private
  disconnect : (reason, cb, id) ->
    @removeSocketFromServer id
    .then (data) ->
      cb null, data
    , cb

  # @private
  listOwnSockets : (cb) ->
    @userState.getSocketsToRooms()
    .then (data) ->
      cb null, data
    , cb

  # @private
  roomAddToList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.addToList @userName, listName, values
      .then (userNames) =>
        if @enableAccessListsUpdates
          @transport.sendToChannel roomName, 'roomAccessListAdded'
          , roomName, listName , values
        @removeRoomUsers room, userNames, cb
      , cb

  # @private
  roomCreate : (roomName, whitelistOnly, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    if checkNameSymbols roomName
      error = @errorBuilder.makeError 'invalidName', roomName
      return cb error
    @state.addRoom roomName
      , { owner : @userName, whitelistOnly : whitelistOnly }
      .then ->
        cb()
      , cb

  # @private
  roomDelete : (roomName, cb) ->
    unless @enableRoomsManagement
      error = @errorBuilder.makeError 'notAllowed'
      return cb error
    @withRoom roomName, withEH cb, (room) =>
      room.checkIsOwner @userName
      .then ->
        room.getUsers()
      .then (userNames) =>
        @removeRoomUsers room, userNames, =>
          @state.removeRoom room.name
          .then ->
            room.removeState()
            .then ->
              cb()
            , cb
          , cb
      .catch cb

  # @private
  roomGetAccessList : (roomName, listName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getList @userName, listName
      .then (data) ->
        cb null, data
      , cb

  # @private
  roomGetOwner : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getOwner @userName
      .then (data) ->
        cb null, data
      , cb

  # @private
  roomGetWhitelistMode : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMode @userName
      .then (data) ->
        cb null, data
      , cb

  # @private
  roomHistory : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getRecentMessages @userName
      .then (data) ->
        cb null, data
      , cb

  # @private
  roomHistoryLastId : (roomName, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMessagesLastId @userName
      .then (data) ->
        cb null, data
      , cb

  # @private
  roomHistorySync : (roomName, id, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.getMessagesAfterId @userName, id
      .then (data) ->
        cb null, data
      , cb

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
      room.message @userName, msg
      .then (pmsg) =>
        @transport.sendToChannel roomName, 'roomMessage', roomName, pmsg
        cb null, pmsg.id
      , cb

  # @private
  roomRemoveFromList : (roomName, listName, values, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.removeFromList @userName, listName, values
      .then (userNames) =>
        if @enableAccessListsUpdates
          @transport.sendToChannel roomName, 'roomAccessListRemoved',
          roomName, listName, values
        @removeRoomUsers room, userNames, cb
      , cb

  # @private
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @userName, mode
      .spread (userNames, mode) =>
        if @enableAccessListsUpdates
          @transport.sendToChannel roomName, 'roomModeChanged', roomName, mode
        @removeRoomUsers room, userNames, cb
      .catch cb

  # @private
  systemMessage : (data, cb, id = null) ->
    @transport.sendToOthers id, @echoChannel, 'systemMessage', data
    cb()

module.exports = User
