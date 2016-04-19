
ChatService = require('../index.js')
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect

{ cleanup
  clientConnect
  getState
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
  state = getState()

  afterEach (cb) ->
    cleanup chatService, [socket1, socket2, socket3], cb
    chatService = socket1 = socket2 = socket3 = null

  it 'should emit join and leave echo for all user\'s sockets', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port }, null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (u, data) ->
        sid1 = data.id
        socket2 = clientConnect user1
        socket2.on 'loginConfirmed', (u, data) ->
          sid2 = data.id
          socket2.emit 'roomJoin', roomName1
          socket1.on 'roomJoinedEcho', (room, id, njoined) ->
            expect(room).equal(roomName1)
            expect(id).equal(sid2)
            expect(njoined).equal(1)
            socket1.emit 'roomLeave', roomName1
            socket2.on 'roomLeftEcho', (room, id, njoined) ->
              expect(room).equal(roomName1)
              expect(id).equal(sid1)
              expect(njoined).equal(1)
              done()

  it 'should emit leave echo on disconnect', (done) ->
    sid1 = null
    sid2 = null
    chatService = new ChatService { port : port }, null, state
    chatService.addRoom roomName1, null, ->
      async.parallel [
        (cb) ->
          socket3 = clientConnect user1
          socket3.on 'loginConfirmed', -> cb()
        (cb) ->
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u, data) ->
            sid1 = data.id
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket2 = clientConnect user1
          socket2.on 'loginConfirmed', (u, data) ->
            sid2 = data.id
            socket2.emit 'roomJoin', roomName1, cb
      ], (error) ->
        expect(error).not.ok
        socket2.disconnect()
        async.parallel [
          (cb) ->
            socket1.once 'roomLeftEcho', (room, id, njoined) ->
              expect(room).equal(roomName1)
              expect(id).equal(sid2)
              expect(njoined).equal(1)
              cb()
          (cb) ->
            socket3.once 'roomLeftEcho', (room, id, njoined) ->
              expect(room).equal(roomName1)
              expect(id).equal(sid2)
              expect(njoined).equal(1)
              cb()
        ] , ->
          socket1.disconnect()
          socket3.on 'roomLeftEcho', (room, id, njoined) ->
            expect(room).equal(roomName1)
            expect(id).equal(sid1)
            expect(njoined).equal(0)
            done()

  it 'should broadcast join and leave room messages', (done) ->
    chatService = new ChatService { port : port
      , enableUserlistUpdates : true }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, (error, njoined) ->
          expect(error).not.ok
          expect(njoined).equal(1)
          socket2 = clientConnect user2
          socket2.on 'loginConfirmed', ->
            socket2.emit 'roomJoin', roomName1
            socket1.on 'roomUserJoined', (room, user) ->
              expect(room).equal(roomName1)
              expect(user).equal(user2)
              socket2.emit 'roomLeave', roomName1
              socket1.on 'roomUserLeft', (room, user) ->
                expect(room).equal(roomName1)
                expect(user).equal(user2)
                done()

  it 'should store and send room history', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port }, null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomMessage', roomName1, message, (error, data) ->
            expect(error).not.ok
            expect(data).a('Number')
            socket1.emit 'roomHistory', roomName1, (error, data) ->
              expect(error).not.ok
              expect(data).length(1)
              expect(data[0]).include.keys 'textMessage', 'author'
              , 'timestamp', 'id'
              expect(data[0].textMessage).equal(txt)
              expect(data[0].author).equal(user1)
              expect(data[0].timestamp).a('Number')
              expect(data[0].id).equal(1)
              done()

  it 'should send room messages to all joined users', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port }, null, state
    chatService.addRoom roomName1, null, ->
      async.parallel [
        (cb) ->
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket2 = clientConnect user2
          socket2.on 'loginConfirmed', ->
            socket2.emit 'roomJoin', roomName1, cb
        ], (error) ->
          expect(error).not.ok
          socket1.emit 'roomMessage', roomName1, message
          async.parallel [
            (cb) ->
              socket1.on 'roomMessage', (room, msg) ->
                expect(room).equal(roomName1)
                expect(msg.author).equal(user1)
                expect(msg.textMessage).equal(txt)
                expect(msg).ownProperty('timestamp')
                expect(msg).ownProperty('id')
                cb()
            (cb) ->
              socket2.on 'roomMessage', (room, msg) ->
                expect(room).equal(roomName1)
                expect(msg.author).equal(user1)
                expect(msg.textMessage).equal(txt)
                expect(msg).ownProperty('timestamp')
                expect(msg).ownProperty('id')
                cb()
          ], done

  it 'should drop history if limit is zero', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port, defaultHistoryLimit : 0 }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomMessage', roomName1, message, ->
            socket1.emit 'roomHistory', roomName1, (error, data) ->
              expect(error).not.ok
              expect(data).empty
              done()

  it 'should not send history if get limit is zero', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port, historyMaxGetMessages : 0 }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomMessage', roomName1, message, (error, data) ->
            socket1.emit 'roomHistory', roomName1, (error, data) ->
              expect(error).not.ok
              expect(data).empty
              done()

  it 'should send room history maximum size', (done) ->
    sz = 1000
    chatService = new ChatService { port : port, defaultHistoryLimit : sz }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomHistorySyncInfo', roomName1, (error, data) ->
            expect(error).not.ok
            expect(data.historyMaxSize).equal(sz)
            done()

  it 'should truncate long history', (done) ->
    txt1 = 'Test message 1.'
    message1 = { textMessage : txt1 }
    txt2 = 'Test message 2.'
    message2 = { textMessage : txt2 }
    chatService = new ChatService { port : port , defaultHistoryLimit : 1 }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomMessage', roomName1, message1
          , (error, data) ->
            socket1.emit 'roomMessage', roomName1, message2
            , (error, data) ->
              socket1.emit 'roomHistory', roomName1, (error, data) ->
                expect(error).not.ok
                expect(data).length(1)
                expect(data[0]).include.keys 'textMessage', 'author'
                , 'timestamp', 'id'
                expect(data[0].textMessage).equal(txt2)
                expect(data[0].author).equal(user1)
                expect(data[0].timestamp).a('Number')
                expect(data[0].id).equal(2)
                done()

  it 'should sync history', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port } , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      async.series [
        (cb) ->
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
      ], (error) ->
        expect(error).not.ok
        async.parallel [
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 0
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0]).include.keys 'textMessage', 'author'
              , 'timestamp', 'id'
              expect(data[0].textMessage).equal(txt)
              expect(data[0].author).equal(user1)
              expect(data[0].timestamp).a('Number')
              expect(data[0].id).equal(2)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 1
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0].id).equal(2)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 2
            , (error, data) ->
              expect(error).not.ok
              expect(data).empty
              cb()
        ], done

  it 'should sync history with respect to the max get', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port, historyMaxGetMessages : 2 }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      async.series [
        (cb) ->
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
      ], (error) ->
        expect(error).not.ok
        async.parallel [
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 0
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(2)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 1
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(3)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 2
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0].id).equal(3)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 3
            , (error, data) ->
              expect(error).not.ok
              expect(data).empty
              cb()
        ], done

  it 'should sync history with respect to a history size', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port , defaultHistoryLimit : 2 }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      async.series [
        (cb) ->
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
        (cb) ->
          socket1.emit 'roomMessage', roomName1, message, cb
      ], (error) ->
        expect(error).not.ok
        async.parallel [
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 0
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(3)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 1
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(3)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 2
            , (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0].id).equal(3)
              cb()
          (cb) ->
            socket1.emit 'roomHistorySync', roomName1, 3
            , (error, data) ->
              expect(error).not.ok
              expect(data).empty
              cb()
        ], done

  it 'should return and update room sync info', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port }
    , null, state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomHistorySyncInfo', roomName1, (error, data) ->
            expect(error).not.ok
            expect(data).ownProperty('historyMaxGetMessages')
            expect(data).ownProperty('historyMaxSize')
            expect(data).ownProperty('historySize')
            expect(data).ownProperty('lastMessageId')
            expect(data.lastMessageId).equal(0)
            expect(data.historySize).equal(0)
            socket1.emit 'roomMessage', roomName1, message, ->
              socket1.emit 'roomHistorySyncInfo', roomName1, (error, data) ->
                expect(error).not.ok
                expect(data.lastMessageId).equal(1)
                expect(data.historySize).equal(1)
                done()

  it 'should list own sockets with rooms', (done) ->
    chatService = new ChatService { port : port }, null, state
    { sid1, sid2, sid3 } = {}
    chatService.addRoom roomName1, null, ->
      chatService.addRoom roomName2, null, ->
        async.parallel [
          (cb) ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', (u, data) ->
              sid1 = data.id
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomJoin', roomName2, cb
          (cb) ->
            socket2 = clientConnect user1
            socket2.on 'loginConfirmed', (u, data)->
              sid2 = data.id
              socket2.emit 'roomJoin', roomName1, cb
          (cb) ->
            socket3 = clientConnect user1
            socket3.on 'loginConfirmed', (u, data)->
              sid3 = data.id
              cb()
        ], (error) ->
          expect(error).not.ok
          socket2.emit 'listOwnSockets', (error, data) ->
            expect(error).not.ok
            expect(data[sid1]).lengthOf(2)
            expect(data[sid2]).lengthOf(1)
            expect(data[sid3]).lengthOf(0)
            expect(data[sid1]).include
            .members([roomName1, roomName2])
            expect(data[sid1]).include(roomName1)
            done()
