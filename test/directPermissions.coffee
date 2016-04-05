
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

  it 'should check user permissions', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket2 = clientConnect user2
      socket2.on 'loginConfirmed', ->
        socket2.emit 'directAddToList', 'blacklist', [user1]
        , (error, data) ->
          expect(error).not.ok
          expect(data).null
          socket1.emit 'directMessage', user2, message
          , (error, data) ->
            expect(error).ok
            expect(data).null
            done()

  it 'should check user permissions in whitelist mode', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket2 = clientConnect user2
      socket2.on 'loginConfirmed', ->
        socket2.emit 'directAddToList', 'whitelist', [user1]
        , (error, data) ->
          expect(error).not.ok
          expect(data).null
          socket2.emit 'directSetWhitelistMode', true, (error, data) ->
            expect(error).not.ok
            expect(data).null
            socket1.emit 'directMessage', user2, message
            , (error, data) ->
              expect(error).not.ok
              expect(data.textMessage).equal(txt)
              socket2.emit 'directRemoveFromList', 'whitelist', [user1]
              , (error, data) ->
                expect(error).not.ok
                expect(data).null
                socket1.emit 'directMessage', user2, message
                , (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

  it 'should allow an user to modify own lists', (done) ->
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directAddToList', 'blacklist', [user2]
      , (error, data) ->
        expect(error).not.ok
        expect(data).null
        socket1.emit 'directGetAccessList', 'blacklist'
        , (error, data) ->
          expect(error).not.ok
          expect(data).include(user2)
          socket1.emit 'directRemoveFromList', 'blacklist', [user2]
          , (error, data) ->
            expect(error).not.ok
            expect(data).null
            socket1.emit 'directGetAccessList', 'blacklist'
            , (error, data) ->
              expect(error).not.ok
              expect(data).not.include(user2)
              done()

  it 'should reject to add user to own lists', (done) ->
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directAddToList', 'blacklist', [user1]
      , (error, data) ->
        expect(error).ok
        expect(data).null
        done()

  it 'should check user list names', (done) ->
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directAddToList', 'nolist', [user2]
      , (error, data) ->
        expect(error).ok
        expect(data).null
        done()

  it 'should allow duplicate adding to lists' , (done) ->
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directAddToList', 'blacklist', [user2]
      , (error, data) ->
        expect(error).not.ok
        expect(data).null
        socket1.emit 'directAddToList', 'blacklist', [user2]
        , (error, data) ->
          expect(error).not.ok
          expect(data).null
          done()

  it 'should allow not existing deleting from lists' , (done) ->
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directRemoveFromList', 'blacklist', [user2]
      , (error, data) ->
        expect(error).not.ok
        expect(data).null
        done()

  it 'should allow an user to modify own mode', (done) ->
    chatService = new ChatService { port : port
      , enableDirectMessages : true }
    , null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directSetWhitelistMode', true, (error, data) ->
        expect(error).not.ok
        expect(data).null
        socket1.emit 'directGetWhitelistMode', (error, data) ->
          expect(error).not.ok
          expect(data).true
          done()
