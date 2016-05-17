
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

  it 'should check state constructor type', (done) ->
    ChatService = rewire '../index.js'
    try
      chatService = new ChatService { port, state : {} }
    catch error
      expect(error).ok
      process.nextTick -> done()

  it 'should check transport constructor type', (done) ->
    ChatService = rewire '../index.js'
    try
      chatService = new ChatService { port, transport : {} }
    catch error
      expect(error).ok
      process.nextTick -> done()

  it 'should check adapter constructor type', (done) ->
    ChatService = rewire '../index.js'
    try
      chatService = new ChatService { port, adapter : {} }
    catch error
      expect(error).ok
      process.nextTick -> done()

  it 'should rollback a failed room join', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    orig = chatService.transport.joinChannel
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        chatService.transport.joinChannel = ->
          orig.apply chatService.transport, arguments
          .then -> throw new Error()
        socket1.emit 'roomJoin', roomName1, (error) ->
          expect(error).ok
          chatService.execUserCommand true, 'roomGetAccessList'
          , roomName1, 'userlist', (error, data) ->
            expect(error).not.ok
            expect(data).an('Array')
            expect(data).lengthOf(0)
            chatService.close done

  it 'should rollback a failed socket connect', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    orig = chatService.transport.joinChannel
    chatService.transport.joinChannel = ->
      orig.apply chatService.transport, arguments
      .then -> throw new Error()
    socket1 = clientConnect user1
    socket1.on 'loginRejected', (error) ->
      expect(error).ok
      chatService.execUserCommand user1, 'listOwnSockets', (error, data) ->
        expect(error).not.ok
        expect(data).empty
        done()

  it 'should rollback a disconnected socket connection', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    orig = chatService.state.addSocket
    chatService.state.addSocket = (id) ->
      orig.apply chatService.state, arguments
      .finally -> chatService.transport.disconnectClient id
    socket1 = clientConnect user1
    socket1.on 'disconnect', ->
      chatService.execUserCommand user1, 'listOwnSockets', (error, data) ->
        expect(error).not.ok
        expect(data).empty
        done()

  it 'should not join a disconnected socket', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        orig = chatService.transport.getSocketObject
        chatService.transport.getSocketObject = (id) ->
          return null
        socket1.emit 'roomJoin', roomName1, (error, data) ->
          expect(error).ok
          done()

  it 'should emit onStartError on onStart hook error', (done) ->
    ChatService = rewire '../index.js'
    onStart = (chatService, cb) ->
      expect(chatService).instanceof(ChatService)
      cb new Error()
    chatService = new ChatService { port }, { onStart }
    chatService.on 'onStartError', (error) ->
      expect(error).ok
      done()

  it 'should propagate transport close errors', (done) ->
    ChatService = rewire '../index.js'
    chatService = new ChatService { port }
    orig = chatService.transport.close
    chatService.transport.close = ->
      orig.apply chatService.transport, arguments
      .then -> throw new Error()
    process.nextTick ->
      chatService.close()
      .catch  (error) ->
        expect(error).ok
        done()

  it 'should propagate onClose errors', (done) ->
    ChatService = rewire '../index.js'
    onClose = (chatService, error, cb) ->
      expect(chatService).instanceof(ChatService)
      expect(error).not.ok
      cb new Error
    chatService = new ChatService { port }, { onClose }
    process.nextTick ->
      chatService.close()
      .catch (error) ->
        expect(error).ok
        done()

  it 'should propagate transport close errors to onClose hook', (done) ->
    ChatService = rewire '../index.js'
    onClose = (chatService, error, cb) ->
      expect(error).ok
      cb error
    chatService = new ChatService { port }, { onClose }
    orig = chatService.transport.close
    chatService.transport.close = ->
      orig.apply chatService.transport, arguments
      .then -> throw new Error()
    process.nextTick ->
      chatService.close()
      .catch  (error) ->
        expect(error).ok
        done()
