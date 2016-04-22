
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

  it 'should create and delete rooms', (done) ->
    chatService = new ChatService { port : port
      , enableRoomsManagement : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      socket1.emit 'roomCreate', roomName1, false, ->
        socket1.emit 'roomJoin', roomName1, (error, data) ->
          expect(error).not.ok
          expect(data).equal(1)
          socket1.emit 'roomCreate', roomName1, false, (error, data) ->
            expect(error).ok
            expect(data).null
            socket1.emit 'roomDelete', roomName1
            socket1.on 'roomAccessRemoved', (r) ->
              expect(r).equal(roomName1)
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                expect(error).ok
                expect(data).null
                done()

  it 'should reject delete rooms for non-owners', (done) ->
    chatService = new ChatService { port : port
      , enableRoomsManagement : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      socket1.emit 'roomCreate', roomName1, false, ->
      socket2 = clientConnect user2
      socket2.on 'loginConfirmed', (u) ->
        socket2.emit 'roomDelete', roomName1, (error, data) ->
          expect(error).ok
          expect(data).null
          done()

  it 'should check for invalid room names', (done) ->
    chatService = new ChatService { port : port
      , enableRoomsManagement : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      socket1.emit 'roomCreate', 'room}1', false, (error, data) ->
        expect(error).ok
        expect(data).null
        done()

  it 'should reject room management when the option is disabled', (done) ->
    chatService = new ChatService { port : port }, null, state
    chatService.addRoom roomName2, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (u) ->
        socket1.emit 'roomCreate', roomName1, false, (error, data) ->
          expect(error).ok
          expect(data).null
          socket1.emit 'roomDelete', roomName2, (error, data) ->
            expect(error).ok
            expect(data).null
            done()

  it 'should send access removed on a room deletion', (done) ->
    chatService = new ChatService { port : port
      , enableRoomsManagement : true }
    , null, state
    chatService.addRoom roomName1, { owner : user1 }, ->
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
        async.parallel [
          (cb) ->
            socket1.emit 'roomDelete', roomName1, cb
          (cb) ->
            socket1.on 'roomAccessRemoved', (r) ->
              expect(r).equal(roomName1)
              cb()
          (cb) ->
            socket2.on 'roomAccessRemoved', (r) ->
              expect(r).equal(roomName1)
              cb()
        ], done
