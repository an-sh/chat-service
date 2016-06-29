
_ = require 'lodash'
expect = require('chai').expect

{
  ChatService
  cleanup
  clientConnect
  nextTick
  parallel
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

  it 'should send auth data with id', (done) ->
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u, data) ->
      expect(u).equal(user1)
      expect(data).include.keys('id')
      done()

  it 'should reject an empty user query', (done) ->
    chatService = startService()
    socket1 = clientConnect()
    socket1.on 'loginRejected', ->
      done()

  it 'should reject user names with illegal characters', (done) ->
    chatService = startService()
    socket1 = clientConnect 'user}1'
    socket1.on 'loginRejected', ->
      done()

  it 'should execute socket.io middleware', (done) ->
    reason = 'some error'
    auth = (socket, cb) ->
      nextTick cb, new Error reason
    chatService = startService null, { middleware : auth }
    socket1 = clientConnect()
    socket1.on 'error', (e) ->
      expect(e).deep.equal(reason)
      done()

  it 'should use onConnect hook username and data', (done) ->
    name = 'someUser'
    data = { token : 'token' }
    onConnect = (server, id, cb) ->
      expect(server).instanceof(ChatService)
      expect(id).a('string')
      nextTick cb, null, name, data
    chatService = startService null, { onConnect }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u, d) ->
      expect(u).equal(name)
      expect(d).include.keys('id')
      expect(d.token).equal(data.token)
      done()

  it 'should reject login if onConnect hook passes error', (done) ->
    err = null
    onConnect = (server, id, cb) ->
      expect(server).instanceof(ChatService)
      expect(id).a('string')
      err = new ChatService.ChatServiceError 'some error'
      throw err
    chatService = startService null, { onConnect }
    socket1 = clientConnect user1
    socket1.on 'loginRejected', (e) ->
      expect(e).deep.equal(err.toString())
      done()

  it 'should support multiple sockets per user', (done) ->
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket2 = clientConnect user1
      sid2 = null
      sid2e = null
      parallel [
        (cb) ->
          socket1.on 'socketConnectEcho', (id, nconnected) ->
            sid2e = id
            expect(nconnected).equal(2)
            cb()
        (cb) ->
          socket2.on 'loginConfirmed', (u, data) ->
            sid2 = data.id
            cb()
      ], ->
        expect(sid2e).equal(sid2)
        socket2.disconnect()
        socket1.on 'socketDisconnectEcho', (id, nconnected) ->
          expect(id).equal(sid2)
          expect(nconnected).equal(1)
          done()

  it 'should disconnect all users on a server shutdown', (done) ->
    chatService1 = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      parallel [
        (cb) ->
          chatService1.close cb
        (cb) ->
          socket1.on 'disconnect', -> cb()
      ], done
