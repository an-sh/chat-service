
Promise = require 'bluebird'
_ = require 'lodash'

{ asyncLimit } = require './utils'


# @private
# @nodoc
# @mixin
#
# Associations for User class.
UserAssociations =

  # @private
  userJoinRoomReport : (userName, roomName) ->
    @transport.sendToChannel roomName, 'roomUserJoined', roomName, userName

  # @private
  userLeftRoomReport : (userName, roomName) ->
    @transport.sendToChannel roomName, 'roomUserLeft', roomName, userName

  # @private
  userRemovedReport : (userName, roomName) ->
    @transport.sendToChannel @echoChannel, 'roomAccessRemoved', roomName
    @userLeftRoomReport userName, roomName

  # @private
  socketJoinEcho : (id, roomName, njoined) ->
    @transport.sendToOthers id, @echoChannel, 'roomJoinedEcho'
    , roomName, id, njoined

  # @private
  socketLeftEcho : (id, roomName, njoined) ->
    @transport.sendToOthers id, @echoChannel, 'roomLeftEcho'
    , roomName, id, njoined

  # @private
  socketConnectEcho : (id, nconnected) ->
    @transport.sendToOthers id, @echoChannel, 'socketConnectEcho', id
    , nconnected

  # @private
  socketDisconnectEcho : (id, nconnected) ->
    @transport.sendToOthers id, @echoChannel, 'socketDisconnectEcho', id
    , nconnected

  # @private
  leaveChannel : (id, channel) ->
    @transport.leaveChannel id, channel
    .catch (e) =>
      @consistencyFailure e, {roomName : channel, id, type : 'transportChannel'}

  # @private
  socketLeaveChannels : (id, channels) ->
    Promise.map channels, (channel) =>
      @leaveChannel id, channel
    , { concurrency : asyncLimit }

  # @private
  channelLeaveSockets : (channel, ids) ->
    Promise.map ids, (id) =>
      @leaveChannel id, channel
    , { concurrency : asyncLimit }

  # @private
  removeSocketFromRoom : (id, roomName) ->
    @userState.removeSocketFromRoom id, roomName
    .catch (e) =>
      @consistencyFailure e, { roomName, id, type : 'userSockets' }
      return 1

  # @private
  rollbackRoomJoin : (error, id, room) ->
    roomName = room.roomName
    @removeSocketFromRoom id, roomName
    .then (njoined) =>
      unless njoined then @leaveRoom roomName
    .then ->
      Promise.reject error

  # @private
  leaveRoom : (roomName) ->
    Promise.try =>
      @state.getRoom roomName, true
    .then (room) =>
      room.leave @userName
    .catch (e) =>
      @consistencyFailure e, { roomName, type : 'roomUserlist' }

  # @private
  joinSocketToRoom : (id, roomName) ->
    Promise.using @userState.lockToRoom(roomName, @lockTTL), =>
      @state.getRoom roomName
      .then (room) =>
        room.join @userName
        .then =>
          @userState.addSocketToRoom id, roomName
          .then (njoined) =>
            @transport.joinChannel id, roomName
            .then =>
              if njoined == 1
                @userJoinRoomReport @userName, roomName
              @socketJoinEcho id, roomName, njoined
            .return njoined
          .catch (e) =>
            @rollbackRoomJoin e, id, room

  # @private
  leaveSocketFromRoom : (id, roomName) ->
    Promise.using @userState.lockToRoom(roomName, @lockTTL), =>
      @removeSocketFromRoom id, roomName
      .then (njoined) =>
        @leaveChannel id, roomName
        .then =>
          @socketLeftEcho id, roomName, njoined
          unless njoined
            @leaveRoom roomName
            .then =>
              @userLeftRoomReport @userName, roomName
        .return njoined

  # @private
  removeUserSocket : (id) ->
    @userState.removeSocket id
    .spread (roomsRemoved = [], joinedSockets = [], nconnected = 0) =>
      @socketLeaveChannels id, roomsRemoved
      .then =>
        Promise.map roomsRemoved, (roomName, idx) =>
          njoined = joinedSockets[idx]
          @socketLeftEcho id, roomName, njoined
          unless njoined
            @leaveRoom roomName
            .then =>
              @userLeftRoomReport @userName, roomName
        , { concurrency : asyncLimit }
        .then =>
          @socketDisconnectEcho id, nconnected
    .then =>
      @state.removeSocket id

  # @private
  removeSocketFromServer : (id) ->
    @removeUserSocket id
    .catch (e) =>
      @consistencyFailure e, { id, type : 'userSockets' }

  # @private
  removeUserSocketsFromRoom : (roomName) ->
    @userState.removeAllSocketsFromRoom roomName
    .catch (e) =>
      @consistencyFailure e, { roomName, type : 'userSockets' }

  # @private
  removeFromRoom : (roomName) ->
    Promise.using @userState.lockToRoom(roomName, @lockTTL), =>
      @removeUserSocketsFromRoom roomName
      .then (removedSockets = []) =>
        @channelLeaveSockets roomName, removedSockets
        .then =>
          if removedSockets.length
            @userRemovedReport @userName, roomName
          @leaveRoom roomName

  # @private
  removeRoomUsers : (roomName, userNames = []) ->
    Promise.map userNames, (userName) =>
      @state.getUser userName
      .then (user) ->
        user.removeFromRoom roomName
      .catch ->
    , { concurrency : asyncLimit }


module.exports = UserAssociations
