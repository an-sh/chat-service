
Promise = require 'bluebird'
_ = require 'lodash'
expect = require('chai').expect
http = require 'http'
socketIO = require 'socket.io'

{ cleanup
  clientConnect
  closeInstance
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
      closeInstance chatService1
      .finally ->
        Promise.fromCallback (fn) ->
          app.close fn
        .catchReturn()
      .asCallback cb
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should integrate with an existing io', (done) ->
    io = socketIO port
    chatService1 = startService { transportOptions : { io } }
    setCustomCleanup (cb) ->
      closeInstance chatService1
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
    MemoryState = require '../src/MemoryState'
    chatService = startService { state : MemoryState }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should use a custom transport constructor', (done) ->
    Transport = require '../src/SocketIOTransport'
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

  it 'should update instance heartbeat', (done) ->
    chatService = startService { heartbeatRate : 500 }
    start = _.now()
    setTimeout ->
      chatService.getInstanceHeartbeat chatService.instanceUID
      .then (ts) ->
        expect(ts).within(start, start + 2000)
        done()
    , 1000
  .timeout 3000
  .slow 2500
