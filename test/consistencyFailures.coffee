
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect
rewire = require 'rewire'

{ cleanup
  clientConnect
} = require './testutils.coffee'

{ port
  user1
  user2
  user3
  roomName1
  roomName2
} = require './config.coffee'

module.exports = ->

  chatService = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEach (cb) ->
    cleanup chatService, [socket1, socket2, socket3], cb
    chatService = socket1 = socket2 = socket3 = null

  it 'should emit consistencyFailure on leaveChannel errors', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    orig = chatService.transport.leaveChannel
    chatService.transport.leaveChannel = ->
      orig.apply chatService.transport, arguments
      .then -> throw new Error()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, (error) ->
          expect(error).not.ok
          async.parallel [
            (cb) ->
              socket1.emit 'roomLeave', roomName1, (error) ->
                expect(error).not.ok
                cb()
            (cb) ->
              chatService.on 'consistencyFailure', (error, data) ->
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'roomName', 'userName', 'id', 'op'
                chatService.transport.leaveChannel = orig
                cb()
          ], done

  it 'should emit consistencyFailure on roomAccessCheck errors', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    chatService.addRoom roomName1, null, ->
      chatService.state.getRoom(roomName1).then (room) ->
        orig = room.roomState.hasInList
        room.roomState.hasInList = ->
          orig.apply room.roomState, arguments
          .then -> throw new Error()
        async.parallel [
          (cb) ->
            chatService.execUserCommand true
            , 'roomRemoveFromList', roomName1, 'whitelist', [user1]
            , (error) ->
              expect(error).not.ok
              cb()
          (cb) ->
            chatService.once 'consistencyFailure', (error, data) ->
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys 'roomName', 'userName', 'op'
              cb()
        ], (error) ->
          expect(error).not.ok
          async.parallel [
            (cb) ->
              chatService.execUserCommand true
              , 'roomAddToList', roomName1, 'whitelist', [user1]
              , (error) ->
                expect(error).not.ok
                cb()
            (cb) ->
              chatService.once 'consistencyFailure', (error, data) ->
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'roomName', 'userName', 'op'
                room.roomState.hasInList = orig
                cb()
          ], done

  it 'should emit consistencyFailure on removeSocketFromRoom errors', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getUser user1
          .then (user) ->
            orig = user.userState.removeSocketFromRoom
            user.userState.removeSocketFromRoom = ->
              orig.apply user.userState, arguments
              .then -> throw new Error()
            async.parallel [
              (cb) ->
                socket1.emit 'roomLeave', roomName1, (error, data) ->
                  expect(error).not.ok
                  cb()
              (cb) ->
                chatService.on 'consistencyFailure', (error, data) ->
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys 'roomName', 'userName', 'op', 'id'
                  user.userState.removeSocketFromRoom = orig
                  cb()
            ], done

  it 'should emit consistencyFailure on leaveRoom errors', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getRoom roomName1
          .then (room) ->
            orig = room.leave
            room.leave = ->
              orig.apply room, arguments
              .then -> throw new Error()
            async.parallel [
              (cb) ->
                socket1.emit 'roomLeave', roomName1, (error, data) ->
                  expect(error).not.ok
                  cb()
              (cb) ->
                chatService.on 'consistencyFailure', (error, data) ->
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys 'roomName', 'userName', 'op'
                  room.leave = orig
                  cb()
            ], done

  it 'should emit consistencyFailure on removeUserSocket errors', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getUser user1
          .then (user) ->
            orig = user.userState.removeSocket
            user.userState.removeSocket = ->
              orig.apply user.userState, arguments
              .then -> throw new Error()
            socket1.disconnect()
            chatService.on 'consistencyFailure', (error, data) ->
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys 'userName', 'op', 'id'
              user.userState.removeSocket = orig
              done()

  it 'should emit consistencyFailure on removeUserSocketsFromRoom errors'
  , (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.state.getUser user1
          .then (user) ->
            orig = user.userState.removeAllSocketsFromRoom
            user.userState.removeAllSocketsFromRoom = ->
              orig.apply user.userState, arguments
              .then -> throw new Error()
            chatService.execUserCommand true
            , 'roomAddToList', roomName1, 'blacklist', [user1]
            , (error) ->
              expect(error).not.ok
            chatService.on 'consistencyFailure', (error, data) ->
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys 'roomName', 'userName', 'op'
              user.userState.removeAllSocketsFromRoom = orig
              done()
