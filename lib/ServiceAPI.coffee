
Promise = require 'bluebird'
_ = require 'lodash'

{ checkNameSymbols, possiblyCallback } = require './utils.coffee'

User = require './User'

# @mixin
# @note Use either a callback or use promises returned from methods.
# API for server side operations.
ServiceAPI =

  # Executes command as an user.
  #
  # @param params [String or Object] Is either a user name or an
  #   options hash.
  # @param command [String] Command name.
  # @param args [Rest...] Command arguments with an optional callback.
  #
  # @option params [String] username User name.
  # @option params [String] id Socket id, it is required for
  #   'disconnect', 'roomJoin', 'roomLeave' commands.
  # @option params [Boolean] bypassHooks If `false` executes command with
  #   before and after hooks, default is `false`.
  # @option params [Boolean] bypassPermissions If `true` executes
  #   command without checking permissions for rooms commands, default
  #   is `false`.
  #
  # @return [Promise]
  execUserCommand : (params, command, args...) ->
    if _.isObject params
      userName = params.userName
    else
      userName = params
      params = null
    [args, cb] = possiblyCallback args
    @state.getUser userName
    .then (user) ->
      user.exec command, params, args...
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
  #   whitelistOnly mode.
  #
  # @return [Promise]
  addUser : (userName, state, cb) ->
    checkNameSymbols userName
    .then =>
      @state.addUser userName, state
    .asCallback cb

  # Gets user direct messaging mode.
  #
  # @param userName [String] User name.
  # @param cb [Callback<error, Boolean>] Optional callback with an error
  #   or the user mode.
  #
  # @return [Promise]
  getUserMode : (userName, cb) ->
    @state.getUser userName
    .then (user) ->
      user.directMessagingState.whitelistOnlyGet()
    .asCallback cb

  # Gets an user list.
  #
  # @param userName [String] User name.
  # @param listName [String] List name.
  # @param cb [Callback<error, Array<String>>] Optional callback with an
  #   error or the requested user list.
  #
  # @return [Promise]
  getUserList : (userName, listName, cb)  ->
    @state.getUser userName
    .then (user) ->
      user.directMessagingState.getList listName
    .asCallback cb

  # Disconnects all user sockets for this instance.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  disconnectUserSockets : (userName, cb) ->
    @state.getUser userName
    .then (user) ->
      user.disconnectInstanceSockets cb
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
  # @option state [Boolean] whitelistOnly Room whitelistOnly mode.
  # @option state [String] owner Room owner.
  #
  # @return [Promise]
  addRoom : (roomName, state, cb) ->
    checkNameSymbols roomName
    .then =>
      @state.addRoom roomName, state
    .asCallback cb

  # Removes all room data, and removes joined user from the room.
  #
  # @param roomName [String] User name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  deleteRoom : (roomName, cb) ->
    user = new User @
    @state.getRoom roomName
    .then (room) =>
      room.getUsers()
      .then (usernames) ->
        user.removeRoomUsers roomName, usernames
      .then =>
        @state.removeRoom room.name
      .then ->
        room.removeState()
    .asCallback cb

  # Gets a room owner.
  #
  # @param roomName [String] Room name.
  # @param cb [Callback<error, String>] Optional callback with an error
  #   or the room owner.
  # @return [Promise]
  getRoomOwner : (roomName, cb) ->
    @state.getRoom roomName
    .then (room) ->
      room.roomState.ownerGet()
    .asCallback cb

  # Gets a room mode.
  #
  # @param roomName [String] Room mode.
  # @param cb [Callback<error, Boolean>] Optional callback with an error
  #   or the room mode.
  #
  # @return [Promise]
  getRoomMode : (roomName, cb) ->
    @state.getRoom roomName
    .then (room) ->
      room.roomState.whitelistOnlyGet()
    .asCallback cb

  # Gets a room list.
  #
  # @param roomName [String] Room name.
  # @param listName [String] List name.
  # @param cb [Callback<error, Array<String>>] Optional callback with an
  #   error or the requested room list.
  #
  # @return [Promise]
  getRoomList : (roomName, listName, cb) ->
    @state.getRoom roomName
    .then (room) ->
      room.roomState.getList listName
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
    .asCallback cb


module.exports = ServiceAPI
