
_ = require 'lodash'
expect = require('chai').expect

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

  it 'should send direct messages', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = startService { enableDirectMessages : true }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket2 = clientConnect user2
      socket2.on 'loginConfirmed', ->
        socket1.emit 'directMessage', user2, message
        socket2.on 'directMessage', (msg) ->
          expect(msg).include.keys 'textMessage', 'author', 'timestamp'
          expect(msg.textMessage).equal(txt)
          expect(msg.author).equal(user1)
          expect(msg.timestamp).a('Number')
          done()

  it 'should not send direct messages when the option is disabled', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket2 = clientConnect user2
      socket2.on 'loginConfirmed', ->
        socket1.emit 'directMessage', user2, message, (error, data) ->
          expect(error).ok
          expect(data).null
          done()

  it 'should not send self-direct messages', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = startService { enableDirectMessages : true }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directMessage', user1, message, (error, data) ->
        expect(error).ok
        expect(data).null
        done()

  it 'should not send direct messages to offline users', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = startService { enableDirectMessages : true }
    socket2 = clientConnect user2
    socket2.on 'loginConfirmed', ->
      socket2.disconnect()
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'directMessage', user2, message, (error, data) ->
          expect(error).ok
          expect(data).null
          done()

  it 'should echo direct messages to user\'s sockets', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = startService { enableDirectMessages : true }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket3 = clientConnect user1
      socket3.on 'loginConfirmed', ->
        socket2 = clientConnect user2
        socket2.on 'loginConfirmed', ->
          socket1.emit 'directMessage', user2, message
          socket3.on 'directMessageEcho', (u, msg) ->
            expect(u).equal(user2)
            expect(msg).include.keys 'textMessage', 'author', 'timestamp'
            expect(msg.textMessage).equal(txt)
            expect(msg.author).equal(user1)
            expect(msg.timestamp).a('Number')
            done()

  it 'should echo system messages to user\'s sockets', (done) ->
    data = 'some data.'
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket2 = clientConnect user1
      socket2.on 'loginConfirmed', ->
        socket1.emit 'systemMessage', data
        socket2.on 'systemMessage', (d) ->
          expect(d).equal(data)
          done()
