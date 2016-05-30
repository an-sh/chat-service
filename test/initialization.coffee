
ChatService = require('../index.js')
Promise = require 'bluebird'
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect
http = require 'http'
socketIO = require 'socket.io'

{ cleanup
  clientConnect
  setCustomCleanup
  startService
} = require './testutils.coffee'

{ port
  user1
  user2
  user3
  roomName1
  roomName2
  redisConnect
} = require './config.coffee'

module.exports = ->

  chatService = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEach (cb) ->
    cleanup chatService, [socket1, socket2, socket3], cb
    chatService = socket1 = socket2 = socket3 = null

  it 'should integrate with a provided http server', (done) ->
    app = http.createServer (req, res) -> res.end()
    chatService1 = startService { transportOptions : { http : app } }
    app.listen port
    setCustomCleanup (cb) ->
      chatService1.close()
      .finally ->
        Promise.fromCallback (fn) ->
          app.close fn
      .asCallback cb
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should integrate with an existing io', (done) ->
    io = socketIO port
    chatService1 = startService { transportOptions : { io } }
    setCustomCleanup (cb) ->
      chatService1.close()
      .finally ->
        io.close()
      .asCallback cb
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should spawn a new io server', (done) ->
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should use a custom state constructor', (done) ->
    MemoryState = require '../lib/MemoryState'
    chatService = startService { state : MemoryState }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should use a custom transport constructor', (done) ->
    Transport = require '../lib/SocketIOTransport'
    chatService = startService { transport : Transport }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should use a custom adapter constructor', (done) ->
    Adapter = require 'socket.io-redis'
    chatService = startService { adapter : Adapter
      , adapterOptions : redisConnect }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()
