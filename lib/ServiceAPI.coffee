
_ = require 'lodash'

{ checkNameSymbols
  withEH
  withoutData
} = require './utils.coffee'

User = require './User'

# @mixin
# API for server side operations.
ServiceAPI =

  # Executes command as an user.
  #
  # @param params [String or Object] Is either a user name or an
  #   options hash.
  # @param command [String] Command name.
  # @param args [Rest] Command arguments with an optional callback.
  #
  # @option params [String] username User name.
  # @option params [String] id Socket id, it is required for
  #   'disconnect', 'roomJoin', 'roomLeave' commands.
  # @option params [Boolean] useHooks If `true` executes command with
  #   before and after hooks, default is `false`.
  execUserCommand : (params, command, args...) ->
    if _.isObject params
      id = params.id || null
      useHooks = params.useHooks || false
      userName = params.userName
    else
      id = null
      useHooks = false
      userName = params
    cb = _.last args
    if _.isFunction cb
      args = _.slice args, 0, -1
    else
      cb = ->
    @state.getUser userName, withEH cb, (user) ->
      user.exec command, useHooks, id, args..., cb

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
  addUser : (userName, state, cb = ->) ->
    if checkNameSymbols userName
      error = @errorBuilder.makeError 'invalidName', userName
      return process.nextTick -> cb error
    @state.addUser userName, state, withoutData cb

  # TODO
  getUserInfo : (userName, cb = ->) ->
    @state.getUser userName, withEH cb, (user, sockets) ->
      user.getMode withEH cb, (mode) ->
        cb null, mode, sockets

  # TODO
  getUserList : (userName, listName, cb = ->)  ->
    @state.getUser userName, withEH cb, (user) ->
      user.directGetAccessList listName, cb

  # Disconnects all user sockets for this instance.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  disconnectUserSockets : (userName, cb = ->) ->
    @state.getUser userName, withEH cb, (user) ->
      user.disconnectInstanceSockets cb

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
  addRoom : (roomName, state, cb = ->) ->
    if checkNameSymbols roomName
      error = @errorBuilder.makeError 'invalidName', roomName
      return process.nextTick -> cb error
    @state.addRoom roomName, state, withoutData cb

  # Removes all room data, and removes joined user from the room.
  #
  # @param roomName [String] User name.
  # @param cb [Callback] Optional callback.
  removeRoom : (roomName, cb = ->) ->
    user = new User @
    user.withRoom roomName, withEH cb, (room) =>
      room.getUsers withEH cb, (usernames) =>
        user.removeRoomUsers room, usernames, =>
          @state.removeRoom room.name, ->
            room.removeState withoutData cb

  # TODO
  getRoomInfo : (roomName, cb = ->) ->
    user = new User @
    user.withRoom roomName, withEH cb, (room) ->
      room.roomState.whitelistOnlyGet withEH cb, (mode) ->
        room.roomState.ownerGet withEH cb, (owner) ->
          cb null, mode, owner

  # TODO
  getRoomList : (roomName, listName, cb) ->
    user = new User @
    user.withRoom roomName, withEH cb, (room) ->
      room.roomState.getList withEH cb, (list) ->
        cb null, list

  # Changes room owner.
  #
  # @param roomName [String] Room name.
  # @param owner [String] Owner user name.
  # @param cb [Callback] Optional callback.
  changeRoomOwner : (roomName, owner, cb = ->) ->
    user = new User @
    user.withRoom roomName, withEH cb, (room) ->
      room.roomState.ownerSet owner, cb


module.exports = ServiceAPI
