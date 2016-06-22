
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect

{ cleanup
  clientConnect
  ChatService
  setCustomCleanup
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
    try
      chatService = startService { state : {} }, null
    catch error
      expect(error).ok
      process.nextTick -> done()

  it 'should check transport constructor type', (done) ->
    try
      chatService = startService { transport : {} }, null
    catch error
      expect(error).ok
      process.nextTick -> done()

  it 'should check adapter constructor type', (done) ->
    try
      chatService = startService { adapter : {} }, null
    catch error
      expect(error).ok
      process.nextTick -> done()

  it 'should rollback a failed room join', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        chatService.transport.joinChannel = ->
          throw new Error()
        socket1.emit 'roomJoin', roomName1, (error) ->
          expect(error).ok
          chatService.execUserCommand true, 'roomGetAccessList'
          , roomName1, 'userlist', (error, data) ->
            expect(error).not.ok
            expect(data).an('Array')
            expect(data).lengthOf(0)
            done()

  it 'should rollback a failed socket connect', (done) ->
    chatService = startService()
    chatService.transport.joinChannel = ->
      throw new Error()
    socket1 = clientConnect user1
    socket1.on 'loginRejected', (error) ->
      expect(error).ok
      chatService.execUserCommand user1, 'listOwnSockets', (error, data) ->
        expect(error).not.ok
        expect(data).empty
        done()

  it 'should rollback a disconnected socket connection', (done) ->
    chatService = startService()
    orig = chatService.state.addSocket
    chatService.state.addSocket = (id) ->
      orig.apply chatService.state, arguments
      .finally -> chatService.transport.disconnectClient id
    tst = chatService.transport.rejectLogin
    chatService.transport.rejectLogin = ->
      tst.apply chatService.transport, arguments
      chatService.execUserCommand user1, 'listOwnSockets', (error, data) ->
        expect(error).not.ok
        expect(data).empty
        done()
    socket1 = clientConnect user1

  it 'should not join a disconnected socket', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        chatService.transport.getSocketObject = (id) ->
          return null
        socket1.emit 'roomJoin', roomName1, (error, data) ->
          expect(error).ok
          done()

  it 'should emit closed on onStart hook error', (done) ->
    onStart = (chatService, cb) ->
      expect(chatService).instanceof(ChatService)
      cb new Error()
    chatService = startService null, { onStart }
    chatService.on 'closed', (error) ->
      expect(error).ok
      done()

  it 'should propagate transport close errors', (done) ->
    chatService = startService()
    orig = chatService.transport.close
    chatService.transport.close = ->
      orig.apply chatService.transport, arguments
      .then -> throw new Error()
    process.nextTick ->
      chatService.close()
      .catch (error) ->
        expect(error).ok
        done()

  it 'should propagate onClose errors', (done) ->
    onClose = (chatService, error, cb) ->
      expect(chatService).instanceof(ChatService)
      expect(error).not.ok
      cb new Error
    chatService = startService null, { onClose }
    process.nextTick ->
      chatService.close()
      .catch (error) ->
        expect(error).ok
        done()

  it 'should propagate transport close errors to onClose hook', (done) ->
    onClose = (chatService, error, cb) ->
      expect(error).ok
      cb error
    chatService = startService null, { onClose }
    orig = chatService.transport.close
    chatService.transport.close = ->
      orig.apply chatService.transport, arguments
      .then -> throw new Error()
    process.nextTick ->
      chatService.close()
      .catch (error) ->
        expect(error).ok
        done()

  it 'should cleanup instance data', (done) ->
    chatService = startService()
    uid = chatService.instanceUID
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket2 = clientConnect user2
          socket2.on 'loginConfirmed', ->
            chatService.instanceRecover uid, (error) ->
              expect(error).not.ok
              async.parallel [
                (cb) ->
                  chatService.execUserCommand user1, 'listOwnSockets'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                (cb) ->
                  chatService.execUserCommand user2, 'listOwnSockets'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                (cb) ->
                  chatService.execUserCommand true, 'roomGetAccessList'
                  , roomName1, 'userlist', (error, data) ->
                    expect(error).not.ok
                    cb()
              ] , done
