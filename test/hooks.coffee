
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

  it 'should execute onStart hook', (done) ->
    fn = ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomGetAccessList', roomName1, 'whitelist'
          , (error, list) ->
            expect(error).not.ok
            expect(list).include(user1)
            socket1.emit 'roomGetOwner', roomName1, (error, data) ->
              expect(error).not.ok
              expect(data).equal(user2)
              done()
    onStart = (server, cb) ->
      expect(server).instanceof(ChatService)
      server.addRoom roomName1
      , { whitelist : [ user1 ], owner : user2 }
      , ->
        cb()
        fn()
    chatService = new ChatService { port : port }
    , { onStart : onStart }, state

  it 'should exectute onClose hook', (done) ->
    closeHook = (server, error, cb) ->
      expect(server).instanceof(ChatService)
      expect(error).not.ok
      cb()
    chatService1 = new ChatService { port : port }
    , { onClose : closeHook }, state
    chatService1.close done

  it 'should execute before and after hooks', (done) ->
    someData = 'data'
    before = null
    after = null
    sid = null
    beforeHook = (execInfo, cb) ->
      { server, userName, id, args } = execInfo
      [ name , mode ] = args
      expect(server).instanceof(ChatService)
      expect(userName).equal(user1)
      expect(id).equal(sid)
      expect(args).instanceof(Array)
      expect(name).a('string')
      expect(mode).a('boolean')
      expect(cb).instanceof(Function)
      before = true
      cb()
    afterHook = (execInfo, cb) ->
      { server, userName, id, args, results, error } = execInfo
      [ name , mode ] = args
      expect(server).instanceof(ChatService)
      expect(userName).equal(user1)
      expect(id).equal(sid)
      expect(args).instanceof(Array)
      expect(name).a('string')
      expect(mode).a('boolean')
      expect(results).instanceof(Array)
      expect(error).null
      expect(cb).instanceof(Function)
      after = true
      cb null, someData
    chatService = new ChatService { port : port
      , enableRoomsManagement : true}
    , { 'roomCreateBefore' : beforeHook, 'roomCreateAfter' : afterHook }
    , state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u, data) ->
      sid = data.id
      socket1.emit 'roomCreate', roomName1, true, (error, data) ->
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        done()

  it 'should allow commands rest arguments', (done) ->
    afterHook = (execInfo, cb) ->
      { restArgs } = execInfo
      expect(restArgs).instanceof(Array)
      expect(restArgs).lengthOf(1)
      expect(restArgs[0]).true
      cb()
    chatService = new ChatService { port : port }
    , { 'listOwnSocketsAfter' : afterHook }
    , state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u, data) ->
      sid = data.id
      socket1.emit 'listOwnSockets', true, (error, data) ->
        expect(error).not.ok
        done()

  it 'should support changing arguments in before hooks', (done) ->
    beforeHook = (execInfo, cb) ->
      execInfo.args = [roomName2]
      cb()
    chatService = new ChatService { port : port, enableRoomsManagement : true }
    , { 'roomGetWhitelistModeBefore' : beforeHook }
    , state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed',  ->
      socket1.emit 'roomCreate', roomName2, false, ->
        socket1.emit 'roomCreate', roomName1, true, ->
          socket1.emit 'roomGetWhitelistMode', roomName1, (error, data) ->
            expect(error).not.ok
            expect(data).false
            done()

  it 'should support more arguments in after hooks', (done) ->
    afterHook = (execInfo, cb) ->
      cb null, execInfo.results..., true
    chatService = new ChatService { port : port }
    , { 'listOwnSocketsAfter' : afterHook }
    , state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u, data) ->
      sid = data.id
      socket1.emit 'listOwnSockets', (error, data, moredata) ->
        expect(error).not.ok
        expect(data[sid]).exits
        expect(data[sid]).empty
        expect(moredata).true
        done()

  it 'should execute disconnect Before and After hooks', (done) ->
    before = false
    disconnectBefore = (execInfo, cb) ->
      before = true
      cb()
    disconnectAfter = (execInfo, cb) ->
      expect(before).true
      cb()
      done()
    chatService1 = new ChatService { port : port }
    , { disconnectAfter : disconnectAfter
      , disconnectBefore : disconnectBefore }
    , state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      chatService1.close()

  it 'should stop commands on before hook data', (done) ->
    val = 'asdf'
    beforeHook = (execInfo, cb) ->
      cb null, val
    chatService = new ChatService { port : port }
    , { 'listOwnSocketsBefore' : beforeHook }, state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'listOwnSockets', (error, data) ->
        expect(error).null
        expect(data).equal(val)
        done()

  it 'should accept custom direct messages with a hook', (done) ->
    html = '<b>HTML message.</b>'
    message = { htmlMessage : html }
    directMessagesChecker = (msg, cb) ->
      cb()
    chatService =
      new ChatService { port : port, enableDirectMessages : true }
        , { directMessagesChecker : directMessagesChecker }
        , state
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket2 = clientConnect user2
      socket2.on 'loginConfirmed', ->
        socket1.emit 'directMessage', user2, message
        socket2.on 'directMessage', (msg) ->
          expect(msg).include.keys 'htmlMessage', 'author', 'timestamp'
          expect(msg.htmlMessage).equal(html)
          expect(msg.author).equal(user1)
          expect(msg.timestamp).a('Number')
          done()

  it 'should accept custom room messages with a hook', (done) ->
    html = '<b>HTML message.</b>'
    message = { htmlMessage : html }
    roomMessagesChecker = (msg, cb) ->
      cb()
    chatService = new ChatService { port : port }
    , { roomMessagesChecker : roomMessagesChecker }
    , state
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomMessage', roomName1, message
          socket1.on 'roomMessage', (room, msg) ->
            expect(room).equal(roomName1)
            expect(msg).include.keys 'htmlMessage', 'author'
            , 'timestamp', 'id'
            expect(msg.htmlMessage).equal(html)
            expect(msg.author).equal(user1)
            expect(msg.timestamp).a('Number')
            expect(msg.id).equal(1)
            done()
