
Promise = require 'bluebird'
User = require './User'
_ = require 'lodash'


# @mixin
# API for a service state recovery.
RecoveryAPI =

  # @private
  # @nodoc
  checkSocketsAlive : (user) ->
    user.state.getSocketsToInstance()
    .then (sockets) =>
      Promise.each sockets, ({socket, instance}) =>
        if instance == @instanceUID and not @getSocketObject socket
          user.state.removeSocket socket
        else
          @state.getInstanceHeartbeat instance
          .then (ts) =>
            if ts is null or ts < _.now() + @heartbeatTimeout
              user.state.removeSocket socket

  # @private
  # @nodoc
  checkRoomJoined : (room) ->

  # @private
  # @nodoc
  checkRoomPermissions : (room) ->

  # Sync user to sockets associations.
  #
  # @param userName [String] User name.
  # @param cb [Callback] Optional callback.
  #
  # @return [Promise]
  userStateSync : (userName, cb) ->
    @state.getUser userName
    .then (user) =>
      @checkSocketsAlive user
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
      Promise.all [
        @checkRoomJoined room
        @checkRoomPermissions room
      ]
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


module.exports = RecoveryAPI
