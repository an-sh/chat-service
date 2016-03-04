
{ checkNameSymbols
  withEH
  withoutData
} = require './utils.coffee'

User = require './User'

# @mixin
# API for server side operations.
ServiceAPI =
  # Disconnects all user sockets for this instance.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  disconnectUserSockets : (userName, cb = ->) ->
    @state.getUser userName, withEH cb, (user) ->
      user.disconnectInstanceSockets cb

  # Executes command as user.
  #
  # @param params [String or Object] Is either a user name or an
  #   options hash.
  # @param name [String] Command name.
  # @param args [Rest] Command arguments.
  # @param cb [Callback] Optional callback.
  #
  # @option params [String] username User name.
  # @option params [String] id Socket id, it is required for
  #   'disconnect', 'roomJoin', 'roomLeave' commands.
  # @option params [Boolean] useHooks If `true` executes command with
  #   before and after hooks, default is `false`
  execCommand : (params, name, args..., cb = ->) ->
    if _.isObject params
      id = params.id || null
      useHooks = params.useHooks || false
      username = params.username
    else
      id = null
      useHooks = false
      username = params
    user = new User @, username
    user.exec name, useHooks, id, args..., cb

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
    @state.addUser userName, state, withoutData cb

  # Removes all room data, and removes joined user from the room.
  #
  # @param roomName [String] User name.
  # @param cb [Callback] Optional callback.
  removeRoom : (roomName, cb = ->) ->
    #TODO
    user = new User @
    user.withRoom roomName, withEH cb, (room) =>
      room.getUsers withEH cb, (usernames) =>
        user.removeRoomUsers room, usernames, =>
          @state.removeRoom room.name, ->
            room.removeState withoutData cb

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
      return cb error
    @state.addRoom roomName, state, withoutData cb

module.exports = ServiceAPI
