
ChatServiceError = require './ChatServiceError.coffee'
CommandBinder = require './CommandBinder'
DirectMessaging = require './DirectMessaging'
Promise = require 'bluebird'
UserAssociations = require './UserAssociations'
_ = require 'lodash'

{ asyncLimit
  ensureMultipleArguments
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
    @lockTTL = @userState.lockTTL
    @echoChannel = @userState.echoChannel
    @errorsLogger = @server.errorsLogger
    @logError = (error, data) =>
      data.userName = @userName unless data.userName
      @errorsLogger error, data if @errorsLogger

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
      throw new ChatServiceError 'noCommand', command
    if not id and command in [ 'disconnect', 'roomJoin' ,'roomLeave' ]
      throw new ChatServiceError 'noSocket', command
    fn = @[command]
    cmd = @makeCommand command, fn
    Promise.fromCallback (cb) ->
      cmd args..., options, ensureMultipleArguments cb
    , {multiArgs: true}

  # @private
  checkOnline : ->
    @userState.getAllSockets()
    .then (sockets) =>
      unless sockets?.length
        Promise.reject new ChatServiceError 'noUserOnline', @userName
      else
        Promise.resolve()

  # @private
  revertRegisterSocket : (id) ->
    @userState.removeSocket id
    # TODO
    Promise.resolve()

  # @private
  registerSocket : (id) ->
    @userState.addSocket id
    .then (nconnected) =>
      unless @transport.getSocketObject id
        return @revertRegisterSocket id
      for cmd of @server.userCommands
        @bindCommand id, cmd, @[cmd]
      Promise.resolve [ @, nconnected ]

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
    .then (user) =>
      recipient = user
      channel = recipient.echoChannel
      recipient.message @userName, msg, bypassPermissions
      .then ->
        recipient.checkOnline()
      .then (recipientSockets) =>
        @transport.sendToChannel channel, 'directMessage', msg
        @transport.sendToOthers id, @echoChannel, 'directMessageEcho'
        , recipientName, msg
        Promise.resolve msg

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
  roomHistory : (roomName, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getRecentMessages @userName, bypassPermissions

  # @private
  roomHistoryLastId : (roomName, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getMessagesLastId @userName, bypassPermissions

  # @private
  roomHistorySync : (roomName, msgid, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      room.getMessagesAfterId @userName, msgid, bypassPermissions

  # @private
  roomJoin : (roomName, {id}) ->
    @state.getRoom roomName
    .then (room) =>
      @joinSocketToRoom id, roomName

  # @private
  roomLeave : (roomName, {id}) ->
    @state.getRoom roomName
    .then (room) =>
      @leaveSocketFromRoom id, room.name

  # @private
  roomMessage : (roomName, msg, {bypassPermissions}) ->
    @state.getRoom roomName
    .then (room) =>
      @processMessage msg
      room.message @userName, msg, bypassPermissions
    .then (pmsg) =>
      @transport.sendToChannel roomName, 'roomMessage', roomName, pmsg
      Promise.resolve pmsg.id

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


module.exports = User
