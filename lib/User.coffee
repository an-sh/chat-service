
_ = require 'lodash'
async = require 'async'

CommandBinder = require './CommandBinder'
DirectMessaging = require './DirectMessaging'
UserAssociations = require './UserAssociations'

{ asyncLimit
  checkNameSymbols
  extend
  withEH
  withoutData
} = require './utils.coffee'


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
    @logError = (error, data) =>
      data.userName = @userName unless data.userName
      @errorsLogger error, data if @errorsLogger

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
          , roomName, listName, values
        @removeRoomUsers roomName, userNames
        .then ->
          cb()
        , cb
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
        @removeRoomUsers roomName, userNames
      .then =>
        @state.removeRoom roomName
      .then ->
        room.removeState()
        .then -> cb()
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
      @joinSocketToRoom id, roomName
      .then (data) ->
        cb null, data
      , cb

  # @private
  roomLeave : (roomName, cb, id) ->
    @withRoom roomName, withEH cb, (room) =>
      @leaveSocketFromRoom id, room.name
      .then (data) ->
        cb null, data
      , cb

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
        @removeRoomUsers roomName, userNames
        .then ->
          cb()
        , cb
      , cb

  # @private
  roomSetWhitelistMode : (roomName, mode, cb) ->
    @withRoom roomName, withEH cb, (room) =>
      room.changeMode @userName, mode
      .spread (userNames, mode) =>
        if @enableAccessListsUpdates
          @transport.sendToChannel roomName, 'roomModeChanged', roomName, mode
        @removeRoomUsers roomName, userNames
        .then (data) ->
          cb null, data
        , cb
      .catch cb

  # @private
  systemMessage : (data, cb, id = null) ->
    @transport.sendToOthers id, @echoChannel, 'systemMessage', data
    cb()

module.exports = User
