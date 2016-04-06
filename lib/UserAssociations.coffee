
Promise = require 'bluebird'
_ = require 'lodash'

{ asyncLimit } = require './utils.coffee'


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
      @consistencyFailure e, {roomName : channel, id, op : 'leaveChannel'}

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
      @consistencyFailure e, { roomName, id, op : 'removeSocketFromRoom' }
      return 1

  # @private
  rollbackRoomJoin : (error, id, room) ->
    roomName = room.name
    @removeSocketFromRoom id, roomName
    .then (njoined) =>
      unless njoined then @leaveRoom roomName, room
    .return error

  # @private
  leaveRoom : (roomName, room = null) ->
    Promise.try =>
      unless room
        @state.getRoom roomName
      else
        room
    .then (room) =>
      room.leave @userName
    .catch (e) =>
      @consistencyFailure e, { roomName, op : 'leaveRoom' }

  # @private
  joinSocketToRoom : (id, roomName) ->
    Promise.using @userState.lockToRoom(roomName, id), =>
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
            njoined
        .catch (e) =>
          @rollbackRoomJoin e, id, room

  # @private
  leaveSocketFromRoom : (id, roomName) ->
    Promise.using @userState.lockToRoom(roomName, id), =>
      @removeSocketFromRoom id, roomName
      .then (njoined) =>
        @leaveChannel id, roomName
        .then =>
          @socketLeftEcho id, roomName, njoined
          unless njoined
            @leaveRoom roomName
            .then =>
              @userLeftRoomReport @userName, roomName
              njoined
          else
            njoined

  # @private
  removeUserSocket : (id) ->
    @userState.removeSocket id
    .catch (e) =>
      @consistencyFailure e, { id, op : 'removeUserSocket' }

  # @private
  removeSocketFromServer : (id) ->
    @userState.setSocketDisconnecting id
    .then =>
      @removeUserSocket id
    .spread (roomsRemoved = [], joinedSockets = [], nconnected = 0) =>
      @socketLeaveChannels id, roomsRemoved
      .then =>
        for roomName, idx in roomsRemoved
          njoined = joinedSockets[idx]
          @socketLeftEcho id, roomName, njoined
          unless njoined then @userLeftRoomReport @userName, roomName
        @socketDisconnectEcho id, nconnected

  # @private
  removeUserSocketsFromRoom : (roomName) ->
    @userState.removeAllSocketsFromRoom roomName
    .catch (e) =>
      @consistencyFailure e, { roomName, op : 'removeUserSocketsFromRoom' }

  # @private
  removeFromRoom : (roomName) ->
    Promise.using @userState.lockToRoom(roomName), =>
      @removeUserSocketsFromRoom roomName
      .then (removedSockets = []) =>
        @channelLeaveSockets roomName, removedSockets
        .then =>
          if removedSockets.length
            @userRemovedReport @userName, roomName
          @leaveRoom roomName

  # @private
  removeUserFromRoom : (userName, roomName, attempt = 1, maxAttempts = 2) ->
    @state.getUser userName
    .then (user) =>
      user.removeFromRoom roomName
      .catch =>
        if attempt < maxAttempts
          Promise.delay(@lockTTL + @clockDrift).then =>
            @removeUserFromRoom userName, roomName, attempt+1, maxAttempts
    .catchReturn()

  # @private
  removeRoomUsers : (roomName, userNames = []) ->
    Promise.map userNames, (userName) =>
      @removeUserFromRoom userName, roomName
    , { concurrency : asyncLimit }


module.exports = UserAssociations
