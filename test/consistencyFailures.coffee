
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect
rewire = require 'rewire'

{ cleanup
  clientConnect
  startService
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
            chatService.on 'consistencyFailure', (error, data) ->
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys 'roomName', 'userName', 'op'
              room.roomState.hasInList = orig
              cb()
        ], done
