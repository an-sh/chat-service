
{ withEH, withoutData } = require './utils.coffee'

# @mixin
# API for server side operations.
ServiceAPI =
  # Remove all user data and closes all connections.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  removeUser : (userName, cb = ->) ->
    @state.removeUser userName, withoutData cb

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
    user = @makeUser()
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
  # @option state [Array<Object>] lastMessages Room lastMessages
  #   history.
  # @option state [Boolean] whitelistOnly Room whitelistOnly mode.
  # @option state [String] owner Room owner.
  addRoom : (roomName, state, cb = ->) ->
    @state.addRoom roomName, state, withoutData cb

module.exports = ServiceAPI
