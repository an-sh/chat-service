
ChatService = require('../index.js')
Promise = require 'bluebird'
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect
http = require 'http'
socketIO = require 'socket.io'

{ cleanup
  clientConnect
  getState
  setCustomCleanup
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

  it 'should integrate with a provided http server', (done) ->
    app = http.createServer (req, res) -> res.end()
    s = _.clone state
    s.transportOptions = { http : app }
    chatService1 = new ChatService null, null, s
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
    s = _.clone state
    s.transportOptions = { io : io }
    chatService1 = new ChatService null, null, s
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
    chatService = new ChatService { port : port }, null, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should use a custom state constructor', (done) ->
    MemoryState = require '../lib/MemoryState.coffee'
    chatService = new ChatService { port : port }, null
    , { state : MemoryState }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should use a custom transport constructor', (done) ->
    Transport = require '../lib/SocketIOTransport.coffee'
    chatService = new ChatService { port : port }, null
    , { transport : Transport }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should use a custom adapter constructor', (done) ->
    Adapter = require 'socket.io-redis'
    chatService = new ChatService { port : port }, null
    , { adapter : Adapter, adapterOptions : "localhost:6379" }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()
