
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
    if setTimestamp
      msg.timestamp = _.now() unless msg.timestamp?
    msg.author = @userName unless msg.author?
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
    .then -> Promise.resolve()

  # @private
  directGetAccessList : (listName) ->
    @getList @userName, listName

  # @private
  directGetWhitelistMode: () ->
    @getMode @userName

  # @private
  directMessage : (recipientName, msg, params) ->
    id = params.id || null
    unless @enableDirectMessages
      error = new ChatServiceError 'notAllowed'
      return Promise.reject error
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
        error = new ChatServiceError 'noUserOnline', recipient.userName
        return Promise.reject error
      @transport.sendToChannel channel, 'directMessage', msg
      @transport.sendToOthers id, @echoChannel, 'directMessageEcho'
        , recipientName, msg
      Promise.resolve msg

  # @private
  directRemoveFromList : (listName, values) ->
    @removeFromList @userName, listName, values
    .then -> Promise.resolve()

  # @private
  directSetWhitelistMode : (mode) ->
    @changeMode @userName, mode
    .then -> Promise.resolve()

  # @private
  disconnect : (reason, params) ->
    id = params.id || null
    @removeSocketFromServer id

  # @private
  listOwnSockets : () ->
    @userState.getSocketsToRooms()

  # @private
  roomAddToList : (roomName, listName, values) ->
    @state.getRoom roomName
    .then (room) =>
      room.addToList @userName, listName, values
    .then (userNames) =>
      if @enableAccessListsUpdates
        @transport.sendToChannel roomName, 'roomAccessListAdded'
        , roomName, listName, values
      @removeRoomUsers roomName, userNames
      .then -> Promise.resolve()

  # @private
  roomCreate : (roomName, whitelistOnly) ->
    unless @enableRoomsManagement
      error = new ChatServiceError 'notAllowed'
      return Promise.reject error
    checkNameSymbols roomName
    .then =>
      @state.addRoom roomName
      , { owner : @userName, whitelistOnly : whitelistOnly }
    .then -> Promise.resolve()

  # @private
  roomDelete : (roomName) ->
    unless @enableRoomsManagement
      error = new ChatServiceError 'notAllowed'
      return Promise.reject error
    @state.getRoom roomName
    .then (room) =>
      room.checkIsOwner @userName
      .then ->
        room.getUsers()
      .then (userNames) =>
        @removeRoomUsers roomName, userNames
      .then =>
        @state.removeRoom roomName
      .then ->
        room.removeState()
      .then -> Promise.resolve()

  # @private
  roomGetAccessList : (roomName, listName) ->
    @state.getRoom roomName
    .then (room) =>
      room.getList @userName, listName

  # @private
  roomGetOwner : (roomName) ->
    @state.getRoom roomName
    .then (room) =>
      room.getOwner @userName

  # @private
  roomGetWhitelistMode : (roomName) ->
    @state.getRoom roomName
    .then (room) =>
      room.getMode @userName

  # @private
  roomHistory : (roomName) ->
    @state.getRoom roomName
    .then (room) =>
      room.getRecentMessages @userName

  # @private
  roomHistoryLastId : (roomName) ->
    @state.getRoom roomName
    .then (room) =>
      room.getMessagesLastId @userName

  # @private
  roomHistorySync : (roomName, msgid) ->
    @state.getRoom roomName
    .then (room) =>
      room.getMessagesAfterId @userName, msgid

  # @private
  roomJoin : (roomName, params) ->
    id = params.id || null
    @state.getRoom roomName
    .then (room) =>
      @joinSocketToRoom id, roomName

  # @private
  roomLeave : (roomName, params) ->
    id = params.id || null
    @state.getRoom roomName
    .then (room) =>
      @leaveSocketFromRoom id, room.name

  # @private
  roomMessage : (roomName, msg) ->
    @state.getRoom roomName
    .then (room) =>
      @processMessage msg
      room.message @userName, msg
    .then (pmsg) =>
      @transport.sendToChannel roomName, 'roomMessage', roomName, pmsg
      Promise.resolve pmsg.id

  # @private
  roomRemoveFromList : (roomName, listName, values) ->
    @state.getRoom roomName
    .then (room) =>
      room.removeFromList @userName, listName, values
    .then (userNames) =>
      if @enableAccessListsUpdates
        @transport.sendToChannel roomName, 'roomAccessListRemoved',
        roomName, listName, values
      @removeRoomUsers roomName, userNames
    .then -> Promise.resolve()

  # @private
  roomSetWhitelistMode : (roomName, mode) ->
    @state.getRoom roomName
    .then (room) =>
      room.changeMode @userName, mode
    .spread (userNames, mode) =>
      if @enableAccessListsUpdates
        @transport.sendToChannel roomName, 'roomModeChanged', roomName, mode
      @removeRoomUsers roomName, userNames

  # @private
  systemMessage : (data, params) ->
    id = params.id || null
    @transport.sendToOthers id, @echoChannel, 'systemMessage', data


module.exports = User
