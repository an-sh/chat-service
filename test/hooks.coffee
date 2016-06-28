
Promise = require 'bluebird'
_ = require 'lodash'
expect = require('chai').expect

{ cleanup
  clientConnect
  nextTick
  ChatService
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

  it 'should execute onStart hook', (done) ->
    onStart = (server, cb) ->
      expect(server).instanceof(ChatService)
      server.addRoom roomName1
      , { whitelist : [ user1 ], owner : user2 }
      , cb
    chatService = startService null, { onStart }
    chatService.on 'ready', ->
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

  it 'should exectute onClose hook', (done) ->
    onClose = (server, error, cb) ->
      expect(server).instanceof(ChatService)
      expect(error).not.ok
      nextTick cb
    chatService1 = startService null, { onClose }
    chatService1.close done

  it 'should execute before and after hooks', (done) ->
    someData = 'data'
    before = null
    after = null
    sid = null
    roomCreateBefore = (execInfo, cb) ->
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
      nextTick cb
    roomCreateAfter = (execInfo, cb) ->
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
      nextTick cb, null, someData
    chatService = startService { enableRoomsManagement : true }
      , { roomCreateBefore, roomCreateAfter }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u, data) ->
      sid = data.id
      socket1.emit 'roomCreate', roomName1, true, (error, data) ->
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        done()

  it 'should execute hooks with promises', (done) ->
    someData = 'data'
    before = null
    after = null
    sid = null
    roomCreateBefore = (execInfo, cb) ->
      before = true
      Promise.resolve()
    roomCreateAfter = (execInfo, cb) ->
      after = true
      Promise.resolve someData
    chatService = startService { enableRoomsManagement : true }
      , { roomCreateBefore, roomCreateAfter }
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
    listOwnSocketsAfter = (execInfo, cb) ->
      { restArgs } = execInfo
      expect(restArgs).instanceof(Array)
      expect(restArgs).lengthOf(1)
      expect(restArgs[0]).true
      nextTick cb
    chatService = startService null, { listOwnSocketsAfter }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u, data) ->
      sid = data.id
      socket1.emit 'listOwnSockets', true, (error, data) ->
        expect(error).not.ok
        done()

  it 'should support changing arguments in before hooks', (done) ->
    roomGetWhitelistModeBefore = (execInfo, cb) ->
      execInfo.args = [roomName2]
      nextTick cb
    chatService = startService { enableRoomsManagement : true }
      , { roomGetWhitelistModeBefore }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed',  ->
      socket1.emit 'roomCreate', roomName2, false, ->
        socket1.emit 'roomCreate', roomName1, true, ->
          socket1.emit 'roomGetWhitelistMode', roomName1, (error, data) ->
            expect(error).not.ok
            expect(data).false
            done()

  it 'should support more arguments in after hooks', (done) ->
    listOwnSocketsAfter = (execInfo, cb) ->
      nextTick cb, null, execInfo.results..., true
    chatService = startService null, { listOwnSocketsAfter }
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
      nextTick cb
    disconnectAfter = (execInfo, cb) ->
      expect(before).true
      nextTick ->
        cb()
        done()
    chatService1 = startService null, { disconnectAfter, disconnectBefore }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      chatService1.close()

  it 'should stop commands on before hook data', (done) ->
    val = 'asdf'
    listOwnSocketsBefore = (execInfo, cb) ->
      nextTick cb, null, val
    chatService = startService null, { listOwnSocketsBefore }
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
      nextTick cb
    chatService =
      startService { enableDirectMessages : true }, { directMessagesChecker }
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
      nextTick cb
    chatService = startService null, { roomMessagesChecker }
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

  it 'should correctly send room messages with binary data', (done) ->
    data = new Buffer [5]
    message = { data : data }
    roomMessagesChecker = (msg, cb) ->
      nextTick cb
    chatService = startService null, { roomMessagesChecker }
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomMessage', roomName1, message
          socket1.on 'roomMessage', (room, msg) ->
            expect(room).equal(roomName1)
            expect(msg).include.keys 'data', 'author'
            , 'timestamp', 'id'
            expect(msg.data).deep.equal(data)
            expect(msg.author).equal(user1)
            expect(msg.timestamp).a('Number')
            expect(msg.id).equal(1)
            socket1.emit 'roomRecentHistory', roomName1, (error, data) ->
              expect(error).not.ok
              expect(data[0]).deep.equal(msg)
              done()
