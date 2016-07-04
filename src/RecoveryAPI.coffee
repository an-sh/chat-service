
Promise = require 'bluebird'
User = require './User'
_ = require 'lodash'


# @mixin
# API for a service state recovery.
RecoveryAPI =

  # @private
  # @nodoc
  checkUserSockets : (user) ->
    userName = user.userName
    user.userState.getSocketsToInstance()
    .then (sockets) =>
      Promise.each _.toPairs(sockets), ([socket, instance]) =>
        if instance == @instanceUID and ! @transport.getConnectionObject socket
          user.userState.removeSocket socket
    .then ->
      user.userState.getSocketsToRooms()
    .then (data) ->
      args = _.values data
      _.intersection args...
    .then (rooms) =>
      Promise.each rooms, (roomName) =>
        @state.getRoom roomName
        .then (room) ->
          room.roomState.hasInList 'userlist', userName
        .then (isPresent) ->
          unless isPresent
            user.removeFromRoom roomName
        .catchReturn()

  # @private
  # @nodoc
  checkRoomJoined : (room) ->
    roomName = room.roomName
    room.getList null, 'userlist', true
    .then (userlist) =>
      Promise.each userlist, (userName) =>
        @state.getUser userName
        .then (user) ->
          user.userState.getRoomToSockets roomName
          .then (sockets) ->
            unless sockets?.length
              user.removeFromRoom roomName
          .catchReturn()
          .then ->
            room.checkAcess userName
          .catch ->
            user.removeFromRoom roomName
        .catchReturn()

  # Sync user to sockets associations.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  userStateSync : (userName, cb) ->
    @state.getUser userName
    .then (user) =>
      @checkUserSockets user
    .asCallback cb

  # Sync room to users associations.
  #
  # @param roomName [String] Room name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  roomStateSync : (roomName, cb) ->
    @state.getRoom roomName
    .then (room) =>
      @checkRoomJoined room
    .asCallback cb

  # Fix instance data after an incorrect service shutdown.
  #
  # @param id [String] Instance id.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  instanceRecovery : (id, cb) ->
    @state.getInstanceSockets id
    .then (sockets) =>
      Promise.each _.toPairs(sockets), ([id, userName]) =>
        @execUserCommand {userName, id}, 'disconnect', 'instance recovery'
    .asCallback cb

  # Get instance heartbeat.
  #
  # @param id [String] Instance id.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise<Number>] Heartbeat timestamp.
  getInstanceHeartbeat : (id, cb) ->
    @state.getInstanceHeartbeat id
    .asCallback cb


module.exports = RecoveryAPI
