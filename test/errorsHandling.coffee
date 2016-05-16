
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
