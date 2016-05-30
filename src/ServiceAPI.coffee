
Promise = require 'bluebird'
_ = require 'lodash'

{ checkNameSymbols, possiblyCallback } = require './utils.coffee'

User = require './User'

# @mixin
# API for server side operations.
ServiceAPI =

  # Executes {UserCommands}.
  #
  # @param context [String or Boolean or Object] Is a `userName` if
  #   String, or a `bypassPermissions` if Boolean, or an options hash if
  #   Object.
  # @param command [String] Command name.
  # @param args [Rest...] Command arguments with an optional callback.
  #
  # @option context [String] userName User name.
  # @option context [String] id Socket id, it is required for
  #   {UserCommands#disconnect}, {UserCommands#roomJoin},
  #   {UserCommands#roomLeave} commands.
  # @option context [Boolean] bypassHooks If `false` executes command
  #   without before and after hooks, default is `false`.
  # @option context [Boolean] bypassPermissions If `true` executes
  #   command (except {UserCommands#roomJoin}) bypassing any
  #   permissions checking, default is `false`.
  #
  # @return [Promise<Array>] Array of command results.
  execUserCommand : (context, command, args...) ->
    if _.isObject context
      userName = context.userName
    else if _.isBoolean context
      context = {bypassPermissions : context}
    else
      userName = context
      context = null
    [args, cb] = possiblyCallback args
    Promise.try =>
      if userName
        @state.getUser userName
      else
        new User @
    .then (user) ->
      user.exec command, context, args...
    .asCallback cb, { spread : true }

  # Adds an user with a state.
  #
  # @param userName [String] User name.
  # @param state [Object] User state.
  # @param cb [Callback] Optional callback.
  #
  # @option state [Array<String>] whitelist User direct messages whitelist.
  # @option state [Array<String>] blacklist User direct messages blacklist.
  # @option state [Boolean] whitelistOnly User direct messages
  #   whitelistOnly mode, default is `false`.
  #
  # @return [Promise]
  addUser : (userName, state, cb) ->
    checkNameSymbols userName
    .then =>
      @state.addUser userName, state
    .return()
    .asCallback cb

  # Deletes an offline user. Will raise an error if user has online
  # sockets.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  deleteUser : (userName, cb) ->
    @state.getUser userName
    .then (user) =>
      user.listOwnSockets()
      .then (sockets) =>
        if sockets and _.size(sockets) > 0
          Promise.reject new ChatServiceError 'userOnline', userName
        else
          Promise.all [
            user.removeState()
            @state.removeUser userName
          ]
    .return()
    .asCallback cb

  # Checks user existence, returns false on errors.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise<Boolean>]
  hasUser : (userName, cb) ->
    @state.getUser userName
    .then -> true
    .catch -> false
    .asCallback cb

  # Checks for a name existence in an user list.
  #
  # @param userName [String] User name.
  # @param listName [String] List name.
  # @param item [String] List element.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise<Boolean>]
  userHasInList : (userName, listName, item, cb) ->
    @state.getUser userName
    .then (user) ->
      user.directMessagingState.hasInList listName, item
    .asCallback cb

  # Disconnects user's sockets for this service instance.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  disconnectUserSockets : (userName, cb) ->
    @state.getUser userName
    .then (user) ->
      user.disconnectInstanceSockets()
    .return()
    .asCallback cb

  # Adds a room with a state.
  #
  # @param roomName [String] Room name.
  # @param state [Object] Room state.
  # @param cb [Callback] Optional callback.
  #
  # @option state [Array<String>] whitelist Room whitelist.
  # @option state [Array<String>] blacklist Room blacklist
  # @option state [Array<String>] adminlist Room adminlist.
  # @option state [Boolean] whitelistOnly Room whitelistOnly mode,
  #   default is `false`.
  # @option state [String] owner Room owner.
  # @option state [Integer] historyMaxSize Room history maximum size.
  #
  # @return [Promise]
  addRoom : (roomName, state, cb) ->
    checkNameSymbols roomName
    .then =>
      @state.addRoom roomName, state
    .return()
    .asCallback cb

  # Removes all room data, and removes joined user from the room.
  #
  # @param roomName [String] Room name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  deleteRoom : (roomName, cb) ->
    @execUserCommand true, 'roomDelete', roomName
    .return()
    .asCallback cb

  # Checks room existence, returns false on errors.
  #
  # @param roomName [String] Room name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise<Boolean>]
  hasRoom : (roomName, cb) ->
    @state.getRoom roomName
    .then -> true
    .catch -> false
    .asCallback cb

  # Checks for a name existence in a room list.
  #
  # @param roomName [String] Room name.
  # @param listName [String] List name.
  # @param item [String] List element.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise<Boolean>]
  roomHasInList : (roomName, listName, item, cb) ->
    @state.getRoom roomName
    .then (room) ->
      room.roomState.hasInList listName, item
    .asCallback cb

  # Changes a room owner.
  #
  # @param roomName [String] Room name.
  # @param owner [String] Owner user name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  changeRoomOwner : (roomName, owner, cb) ->
    @state.getRoom roomName
    .then (room) ->
      room.roomState.ownerSet owner
    .return()
    .asCallback cb

  # Changes a room history size.
  #
  # @param roomName [String] Room name.
  # @param size [Integer] Room history size.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  changeRoomHistoryMaxSize : (roomName, size, cb) ->
    @state.getRoom roomName
    .then (room) ->
      room.roomState.historyMaxSizeSet size
    .return()
    .asCallback cb


module.exports = ServiceAPI
