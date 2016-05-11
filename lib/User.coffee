
ChatServiceError = require './ChatServiceError.coffee'
CommandBinder = require './CommandBinder'
DirectMessaging = require './DirectMessaging'
Promise = require 'bluebird'
UserAssociations = require './UserAssociations'
_ = require 'lodash'

{ asyncLimit
  checkNameSymbols
  extend
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
    @validator = @server.validator
    @hooks = @server.hooks
    @enableUserlistUpdates = @server.enableUserlistUpdates
    @enableAccessListsUpdates = @server.enableAccessListsUpdates
    @enableRoomsManagement = @server.enableRoomsManagement
    @enableDirectMessages = @server.enableDirectMessages
    State = @server.state.UserState
    @userState = new State @server, @userName
    @lockTTL = @state.lockTTL
    @clockDrift = @state.clockDrift
    @echoChannel = @userState.echoChannel

  # @private
  processMessage : (msg, setTimestamp = false) ->
    delete msg.id
    delete msg.timestamp
    if setTimestamp
      msg.timestamp = _.now()
    msg.author = @userName || msg.author
    return msg

  # @private
  exec : (command, options = {}, args...) ->
    id = options.id
    unless @server.userCommands[command]
      error = new ChatServiceError 'noCommand', command
      return Promise.reject error
    if not id and command in [ 'disconnect', 'roomJoin' ,'roomLeave' ]
      error = new ChatServiceError 'noSocket', command
      return Promise.reject error
    fn = @[command]
    cmd = @makeCommand command, fn
    Promise.fromCallback (cb) ->
      cmd args..., options, cb
    , {multiArgs: true}

  # @private
  checkOnline : ->
    @userState.getAllSockets()
    .then (sockets) =>
      unless sockets?.length
        Promise.reject new ChatServiceError 'noUserOnline', @userName

  # @private
  consistencyFailure : (error, operationInfo = {}) ->
    operationInfo.userName = @userName
    @server.emit 'consistencyFailure', error, operationInfo
    return

  # @private
  registerSocket : (id) ->
    @state.addSocket id
    .then =>
      @userState.addSocket id, @userName
    .then (nconnected) =>
      unless @transport.getSocketObject id
        @removeUserSocket id
        return Promise.reject new ChatServiceError 'noSocket', 'connection'
      for cmd of @server.userCommands
        @bindCommand id, cmd, @[cmd]
      [ @, nconnected ]

  # @private
  disconnectInstanceSockets : () ->
    @userState.getAllSockets()
    .then (sockets) =>
      Promise.map sockets, (sid) =>
        @transport.disconnectClient sid
      , { concurrency : asyncLimit }

  # @private
  directAddToList : (listName, values) ->
    @addToList @userName, listName, values
    .return()

  # @private
  directGetAccessList : (listName) ->
    @getList @userName, listName

  # @private
  directGetWhitelistMode: () ->
    @getMode @userName

  # @private
  directMessage : (recipientName, msg, {id, bypassPermissions}) ->
    unless @enableDirectMessages
      error = new ChatServiceError 'notAllowed'
      return Promise.reject error
    @processMessage msg, true
    @server.state.getUser recipientName
    .then (recipient) =>
      channel = recipient.echoChannel
      recipient.message @userName, msg, bypassPermissions
      .then ->
        recipient.checkOnline()
      .then (recipientSockets) =>
        @transport.sendToChannel channel, 'directMessage', msg
        @transport.sendToOthers id, @echoChannel, 'directMessageEcho'
        , recipientName, msg
        msg

  # @private
  directRemoveFromList : (listName, values) ->
    @removeFromList @userName, listName, values
    .return()

  # @private
  directSetWhitelistMode : (mode) ->
    @changeMode @userName, mode
    .return()

  # @private
  disconnect : (reason, {id}) ->
    @removeSocketFromServer id

  # @private
  listOwnSockets : () ->
    @userState.getSocketsToRooms()

  # @private
  roomAddToList : (roomName, listName, values, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.addToList @userName, listName, values, bypassPermissions
    .then (userNames) =>
      if @enableAccessListsUpdates
        @transport.sendToChannel roomName, 'roomAccessListAdded'
        , roomName, listName, values
      @removeRoomUsers roomName, userNames
      .return()

  # @private
  roomCreate : (roomName, whitelistOnly, {bypassPermissions}) ->
    if not @enableRoomsManagement and not bypassPermissions
      error = new ChatServiceError 'notAllowed'
      return Promise.reject error
    checkNameSymbols roomName
    .then =>
      @state.addRoom roomName
      , { owner : @userName, whitelistOnly : whitelistOnly }
    .return()

  # @private
  roomDelete : (roomName, {bypassPermissions}) ->
    if not @enableRoomsManagement and not bypassPermissions
      error = new ChatServiceError 'notAllowed'
      return Promise.reject error
    @state.getRoom roomName
    .then (room) =>
      room.checkIsOwner @userName, bypassPermissions
      .then ->
        room.startRemoving()
      .then ->
        room.getUsers()
      .then (userNames) =>
        @removeRoomUsers roomName, userNames
      .then =>
        @state.removeRoom roomName
      .then ->
        room.removeState()
      .return()

  # @private
  roomGetAccessList : (roomName, listName, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getList @userName, listName, bypassPermissions

  # @private
  roomGetOwner : (roomName, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getOwner @userName, bypassPermissions

  # @private
  roomGetWhitelistMode : (roomName, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getMode @userName, bypassPermissions

  # @private
  roomRecentHistory : (roomName, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getRecentMessages @userName, bypassPermissions

  # @private
  roomHistoryGet : (roomName, msgid, limit, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getMessages @userName, msgid, limit, bypassPermissions

  # @private
  roomHistoryInfo : (roomName, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getHistoryInfo @userName, bypassPermissions

  # @private
  roomJoin : (roomName, {id}) ->
    @state.getRoom roomName
    .then (room) =>
      @joinSocketToRoom id, roomName

  # @private
  roomLeave : (roomName, {id}) ->
    @state.getRoom roomName
    .then (room) =>
      @leaveSocketFromRoom id, room.roomName

  # @private
  roomMessage : (roomName, msg, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      @processMessage msg
      room.message @userName, msg, bypassPermissions
    .then (pmsg) =>
      @transport.sendToChannel roomName, 'roomMessage', roomName, pmsg
      pmsg.id

  # @private
  roomRemoveFromList : (roomName, listName, values, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.removeFromList @userName, listName, values, bypassPermissions
    .then (userNames) =>
      if @enableAccessListsUpdates
        @transport.sendToChannel roomName, 'roomAccessListRemoved',
        roomName, listName, values
      @removeRoomUsers roomName, userNames
    .return()

  # @private
  roomSetWhitelistMode : (roomName, mode, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.changeMode @userName, mode, bypassPermissions
    .spread (userNames, mode) =>
      if @enableAccessListsUpdates
        @transport.sendToChannel roomName, 'roomModeChanged', roomName, mode
      @removeRoomUsers roomName, userNames

  # @private
  systemMessage : (data, {id}) ->
    @transport.sendToOthers id, @echoChannel, 'systemMessage', data
    Promise.resolve()


module.exports = User
