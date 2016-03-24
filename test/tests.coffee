
ChatService = require('../index.js')
expect = require('chai').expect
ioClient = require 'socket.io-client'
socketIO = require 'socket.io'
http = require 'http'
async = require 'async'
Redis = require 'ioredis'
_ = require 'lodash'

describe 'Chat service.', ->

  port = 8000
  url = "http://localhost:#{port}/chat-service"

  states = [
    { state : 'memory', adapter : 'memory' }
    # { state : 'redis', adapter : 'redis' }
  ]

  makeParams = (userName) ->
    params =
      'query' : "user=#{userName}"
      'multiplex' : false
      'reconnection' : false
      'transports' : [ 'websocket' ]
    unless userName
      delete params.query
    return params

  clientConnect = (name) ->
    ioClient.connect url, makeParams(name)

  user1 = 'userName1'
  user2 = 'userName2'
  user3 = 'userName3'
  roomName1 = 'room1'
  roomName2 = 'room2'

  redis = new Redis
  chatServer = null
  socket1 = null
  socket2 = null
  socket3 = null

  cleanup = null

  afterEachFn = (done) ->
    endcb = (error) ->
      if error then return done error
      redis.flushall done
    socket1?.disconnect()
    socket1 = null
    socket2?.disconnect()
    socket2 = null
    socket3?.disconnect()
    socket3 = null
    if cleanup
      cleanup endcb
      cleanup = null
    else if chatServer
      chatServer.close endcb
      chatServer = null
    else
      endcb()

  before (done) ->
    redis.dbsize (error, data) ->
      if error then return done error
      if data then return done new Error 'Unclean Redis DB'
      done()

  states.forEach (state) ->

    describe "State #{state.state} with #{state.adapter} adapter.", ->

      @timeout 1000

      afterEach afterEachFn

      describe 'Initialization', ->

        it 'should integrate with a provided http server', (done) ->
          app = http.createServer (req, res) -> res.end()
          s = _.clone state
          s.transportOptions = { http : app }
          chatServer1 = new ChatService null, null, s
          app.listen port
          cleanup = (cb) ->
            chatServer1.close (error) ->
              if error then cb error
              app.close cb
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            done()

        it 'should integrate with an existing io', (done) ->
          io = socketIO port
          s = _.clone state
          s.transportOptions = { io : io }
          chatServer1 = new ChatService null, null, s
          cleanup = (cb) ->
            chatServer1.close (error) ->
              if error then cb error
              io.close()
              cb()
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            done()

        it 'should spawn a new io server', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            done()

        it 'should use a custom state constructor', (done) ->
          MemoryState = require '../lib/MemoryState.coffee'
          chatServer = new ChatService { port : port }, null
          , { state : MemoryState }
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            done()

        it 'should use a custom transport constructor', (done) ->
          Transport = require '../lib/SocketIOTransport.coffee'
          chatServer = new ChatService { port : port }, null
          , { transport : Transport }
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            done()

        it 'should use a custom adapter constructor', (done) ->
          Adapter = require 'socket.io-redis'
          chatServer = new ChatService { port : port }, null
          , { adapter : Adapter, adapterOptions : "localhost:6379" }
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            done()


      describe 'Connection', ->

        it 'should send auth data with id', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u, data) ->
            expect(u).equal(user1)
            expect(data).include.keys('id')
            done()

        it 'should reject an empty user query', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect()
          socket1.on 'loginRejected', ->
            done()

        it 'should reject user names with illegal characters', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect 'user}1'
          socket1.on 'loginRejected', ->
            done()

        it 'should execute socket.io middleware', (done) ->
          reason = 'some error'
          auth = (socket, cb) ->
            cb( new Error reason )
          chatServer = new ChatService { port : port }
          , { middleware : auth }, state
          socket1 = clientConnect()
          socket1.on 'error', (e) ->
            expect(e).deep.equal(reason)
            done()

        it 'should reject login if onConnect hook passes error', (done) ->
          err = { someField : 'some reason' }
          onConnect = (server, id, cb) ->
            expect(server).instanceof(ChatService)
            expect(id).a('string')
            cb err
          chatServer = new ChatService { port : port }
            , { onConnect : onConnect }, state
          socket1 = clientConnect user1
          socket1.on 'loginRejected', (e) ->
            expect(e).deep.equal(err)
            done()

        it 'should support multiple sockets per user', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket2 = clientConnect user1
            sid2 = null
            sid2e = null
            async.parallel [
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
          chatServer1 = new ChatService { port : port }, null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            async.parallel [
              (cb) ->
                socket1.on 'disconnect', -> cb()
              (cb) ->
                chatServer1.close cb
            ], done


      describe 'Room management', ->

        it 'should create and delete rooms', (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', roomName1, false, ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                expect(error).not.ok
                expect(data).equal(1)
                socket1.emit 'roomCreate', roomName1, false, (error, data) ->
                  expect(error).ok
                  expect(data).null
                  socket1.emit 'roomDelete', roomName1
                  socket1.on 'roomAccessRemoved', (r) ->
                    expect(r).equal(roomName1)
                    socket1.emit 'roomJoin', roomName1, (error, data) ->
                      expect(error).ok
                      expect(data).null
                      done()

        it 'should check for invalid room names', (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', 'room}1', false, (error, data) ->
              expect(error).ok
              expect(data).null
              done()

        it 'should reject room management when the option is disabled'
        , (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName2, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', (u) ->
              socket1.emit 'roomCreate', roomName1, false, (error, data) ->
                expect(error).ok
                expect(data).null
                socket1.emit 'roomDelete', roomName2, (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

        it 'should send access removed on a room deletion', (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          chatServer.addRoom roomName1, { owner : user1 }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, ->
                    socket1.emit 'roomDelete', roomName1
                    async.parallel [
                      (cb) ->
                        socket1.on 'roomAccessRemoved', (r) ->
                          expect(r).equal(roomName1)
                          cb()
                      (cb) ->
                        socket2.on 'roomAccessRemoved', (r) ->
                          expect(r).equal(roomName1)
                          cb()
                    ], done


      describe 'Room messaging', ->

        it 'should emit join and leave echo for all user\'s sockets', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', (u, data) ->
              sid1 = data.id
              socket2 = clientConnect user1
              socket2.on 'loginConfirmed', (u, data) ->
                sid2 = data.id
                socket2.emit 'roomJoin', roomName1
                socket1.on 'roomJoinedEcho', (room, id, njoined) ->
                  expect(room).equal(roomName1)
                  expect(id).equal(sid2)
                  expect(njoined).equal(1)
                  socket1.emit 'roomLeave', roomName1
                  socket2.on 'roomLeftEcho', (room, id, njoined) ->
                    expect(room).equal(roomName1)
                    expect(id).equal(sid1)
                    expect(njoined).equal(1)
                    done()

        it 'should emit leave echo on disconnect', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket3 = clientConnect user1
            socket3.on 'loginConfirmed', ->
              socket1 = clientConnect user1
              socket1.on 'loginConfirmed', (u, data) ->
                sid1 = data.id
                socket1.emit 'roomJoin', roomName1, ->
                  socket2 = clientConnect user1
                  socket2.on 'loginConfirmed', (u, data) ->
                    sid2 = data.id
                    socket2.emit 'roomJoin', roomName1, ->
                      socket2.disconnect()
                      async.parallel [
                        (cb) ->
                          socket1.once 'roomLeftEcho', (room, id, njoined) ->
                            expect(room).equal(roomName1)
                            expect(id).equal(sid2)
                            expect(njoined).equal(1)
                            cb()
                        (cb) ->
                          socket3.once 'roomLeftEcho', (room, id, njoined) ->
                            expect(room).equal(roomName1)
                            expect(id).equal(sid2)
                            expect(njoined).equal(1)
                            cb()
                      ] , ->
                        socket1.disconnect()
                        socket3.on 'roomLeftEcho', (room, id, njoined) ->
                          expect(room).equal(roomName1)
                          expect(id).equal(sid1)
                          expect(njoined).equal(0)
                          done()

        it 'should broadcast join and leave room messages', (done) ->
          chatServer = new ChatService { port : port
            , enableUserlistUpdates : true }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, njoined) ->
                expect(error).not.ok
                expect(njoined).equal(1)
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1
                  socket1.on 'roomUserJoined', (room, user) ->
                    expect(room).equal(roomName1)
                    expect(user).equal(user2)
                    socket2.emit 'roomLeave', roomName1
                    socket1.on 'roomUserLeft', (room, user) ->
                      expect(room).equal(roomName1)
                      expect(user).equal(user2)
                      done()

        it 'should store and send room history', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomMessage', roomName1, message, (error, data) ->
                  expect(error).not.ok
                  expect(data).a('Number')
                  socket1.emit 'roomHistory', roomName1, (error, data) ->
                    expect(error).not.ok
                    expect(data).length(1)
                    expect(data[0]).include.keys 'textMessage', 'author'
                    , 'timestamp', 'id'
                    expect(data[0].textMessage).equal(txt)
                    expect(data[0].author).equal(user1)
                    expect(data[0].timestamp).a('Number')
                    expect(data[0].id).equal(1)
                    done()

        it 'should send room messages to all joined users', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, ->
                    socket1.emit 'roomMessage', roomName1, message
                    async.parallel [
                      (cb) ->
                        socket1.on 'roomMessage', (room, msg) ->
                          expect(room).equal(roomName1)
                          expect(msg.author).equal(user1)
                          expect(msg.textMessage).equal(txt)
                          expect(msg).ownProperty('timestamp')
                          cb()
                      (cb) ->
                        socket2.on 'roomMessage', (room, msg) ->
                          expect(room).equal(roomName1)
                          expect(msg.author).equal(user1)
                          expect(msg.textMessage).equal(txt)
                          expect(msg).ownProperty('timestamp')
                          cb()
                    ], done

        it 'should drop history if limit is zero', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port, historyMaxMessages : 0 }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomMessage', roomName1, message, ->
                  socket1.emit 'roomHistory', roomName1, (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    done()

        it 'should not send history if get limit is zero', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , historyMaxGetMessages : 0 }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomMessage', roomName1, message, (error, data) ->
                  socket1.emit 'roomHistory', roomName1, (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    done()

        it 'should truncate long history', (done) ->
          txt1 = 'Test message 1.'
          message1 = { textMessage : txt1 }
          txt2 = 'Test message 2.'
          message2 = { textMessage : txt2 }
          chatServer = new ChatService { port : port
            , historyMaxMessages : 1 }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomMessage', roomName1, message1
                , (error, data) ->
                  socket1.emit 'roomMessage', roomName1, message2
                  , (error, data) ->
                    socket1.emit 'roomHistory', roomName1, (error, data) ->
                      expect(error).not.ok
                      expect(data).length(1)
                      expect(data[0]).include.keys 'textMessage', 'author'
                      , 'timestamp', 'id'
                      expect(data[0].textMessage).equal(txt2)
                      expect(data[0].author).equal(user1)
                      expect(data[0].timestamp).a('Number')
                      expect(data[0].id).equal(2)
                      done()

        it 'should sync history', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port } , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomMessage', roomName1, message, ->
                  socket1.emit 'roomMessage', roomName1, message, ->
                    async.parallel [
                      (cb) ->
                        socket1.emit 'roomHistorySync', roomName1, 0
                        , (error, data) ->
                          expect(error).not.ok
                          expect(data).lengthOf(2)
                          expect(data[0]).include.keys 'textMessage', 'author'
                          , 'timestamp', 'id'
                          expect(data[0].textMessage).equal(txt)
                          expect(data[0].author).equal(user1)
                          expect(data[0].timestamp).a('Number')
                          expect(data[0].id).equal(2)
                          cb()
                      (cb) ->
                        socket1.emit 'roomHistorySync', roomName1, 1
                        , (error, data) ->
                          expect(error).not.ok
                          expect(data).lengthOf(1)
                          expect(data[0].id).equal(2)
                          cb()
                      (cb) ->
                        socket1.emit 'roomHistorySync', roomName1, 2
                        , (error, data) ->
                          expect(error).not.ok
                          expect(data).empty
                          cb()
                    ], done

        it 'should sync history with respect to the max get', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , historyMaxGetMessages : 2 }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomMessage', roomName1, message, ->
                  socket1.emit 'roomMessage', roomName1, message, ->
                    socket1.emit 'roomMessage', roomName1, message, ->
                      async.parallel [
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 0
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).lengthOf(2)
                            expect(data[0].id).equal(2)
                            cb()
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 1
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).lengthOf(2)
                            expect(data[0].id).equal(3)
                            cb()
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 2
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).lengthOf(1)
                            expect(data[0].id).equal(3)
                            cb()
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 3
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).empty
                            cb()
                      ], done

        it 'should sync history with respect to a history size', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , historyMaxMessages : 2 }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomMessage', roomName1, message, ->
                  socket1.emit 'roomMessage', roomName1, message, ->
                    socket1.emit 'roomMessage', roomName1, message, ->
                      async.parallel [
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 0
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).lengthOf(2)
                            expect(data[0].id).equal(3)
                            cb()
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 1
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).lengthOf(2)
                            expect(data[0].id).equal(3)
                            cb()
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 2
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).lengthOf(1)
                            expect(data[0].id).equal(3)
                            cb()
                        (cb) ->
                          socket1.emit 'roomHistorySync', roomName1, 3
                          , (error, data) ->
                            expect(error).not.ok
                            expect(data).empty
                            cb()
                      ], done

        it 'should return the latest room history id', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomHistoryLastId', roomName1, (error, data) ->
                  expect(error).not.ok
                  expect(data).equal(0)
                  socket1.emit 'roomMessage', roomName1, message, ->
                    socket1.emit 'roomHistoryLastId', roomName1
                    , (error, data) ->
                      expect(error).not.ok
                      expect(data).equal(1)
                      done()


      describe 'Room permissions', ->

        it 'should reject room messages from not joined users', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomMessage', roomName1, message, (error, data) ->
                expect(error).ok
                expect(data).null
                socket1.emit 'roomHistory', roomName1, (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

        it 'should send a whitelistonly mode', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { whitelistOnly : true }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomGetWhitelistMode', roomName1, (error, data) ->
                expect(error).not.ok
                expect(data).true
                done()

        it 'should send lists to room users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomGetAccessList', roomName1, 'userlist'
                , (error, data) ->
                  expect(error).not.ok
                  expect(data).an('array')
                  expect(data).include(user1)
                  done()

        it 'should reject send lists to not joined users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomGetAccessList', roomName1, 'userlist'
              , (error, data) ->
                expect(error).ok
                expect(data).null
                done()

        it 'should ckeck room list names', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomGetAccessList', roomName1, 'nolist'
                , (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

        it 'should allow duplicate adding to lists', (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', roomName1, false, ->
              socket1.emit 'roomJoin',  roomName1, ->
                socket1.emit 'roomAddToList', roomName1, 'adminlist', [user2]
                , (error, data) ->
                  expect(error).not.ok
                  expect(data).null
                  socket1.emit 'roomAddToList', roomName1, 'adminlist', [user2]
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).null
                    done()

        it 'should allow not existing deleting from lists', (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', roomName1, false, ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomRemoveFromList', roomName1, 'adminlist'
                , [user2], (error, data) ->
                  expect(error).not.ok
                  expect(data).null
                  done()

        it 'should send access list changed messages', (done) ->
          chatServer = new ChatService { port : port
            , enableAccessListsUpdates : true }
          , null, state
          chatServer.addRoom roomName1, { owner : user1 }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin',  roomName1, ->
                socket1.emit 'roomAddToList', roomName1, 'adminlist', [user3]
                socket1.on 'roomAccessListAdded', (r, l, us) ->
                  expect(r).equal(roomName1)
                  expect(l).equal('adminlist')
                  expect(us[0]).equal(user3)
                  socket1.emit 'roomRemoveFromList', roomName1, 'adminlist'
                  , [user3]
                  socket1.on 'roomAccessListRemoved', (r, l, us) ->
                    expect(r).equal(roomName1)
                    expect(l).equal('adminlist')
                    expect(us[0]).equal(user3)
                    done()

        it 'should send mode changed messages', (done) ->
          chatServer = new ChatService { port : port
            , enableAccessListsUpdates : true }
          , null, state
          chatServer.addRoom roomName1
          , { owner : user1, whitelistOnly : true }
          , ->
            socket1 = clientConnect user1
            socket1.emit 'roomJoin',  roomName1, ->
              socket1.emit 'roomSetWhitelistMode', roomName1, false
              socket1.on 'roomModeChanged', (roomName, mode) ->
                expect(roomName).equal(roomName1)
                expect(mode).false
                done()

        it 'should allow wl and bl modifications for admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { adminlist : [user1] }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin',  roomName1, ->
                socket1.emit 'roomAddToList', roomName1, 'whitelist', [user2]
                , (error, data) ->
                  expect(error).not.ok
                  expect(data).null
                  socket1.emit 'roomGetAccessList', roomName1, 'whitelist'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).include(user2)
                    socket1.emit 'roomRemoveFromList', roomName1, 'whitelist'
                    , [user2], (error, data) ->
                      expect(error).not.ok
                      expect(data).null
                      socket1.emit 'roomGetAccessList', roomName1, 'whitelist'
                      , (error, data) ->
                        expect(error).not.ok
                        expect(data).not.include(user2)
                        done()

        it 'should reject adminlist modifications for admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { adminlist : [user1, user2] }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin',  roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin',  roomName1, ->
                    socket1.emit 'roomRemoveFromList', roomName1, 'adminlist'
                    , [user2] , (error, data) ->
                      expect(error).ok
                      expect(data).null
                      done()

        it 'should reject list modifications with owner for admins'
        , (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomCreate', roomName1, false, ->
              socket1.emit 'roomJoin',  roomName1, ->
                socket1.emit 'roomAddToList', roomName1, 'adminlist', [user2],
                (error, data) ->
                  expect(error).not.ok
                  expect(data).null
                  socket2 = clientConnect user2
                  socket2.on 'loginConfirmed', ->
                    socket2.emit 'roomJoin',  roomName1, ->
                      socket2.emit 'roomAddToList', roomName1, 'whitelist'
                      , [user1], (error, data) ->
                        expect(error).ok
                        expect(data).null
                        done()

        it 'should reject direct userlist modifications', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { adminlist : [user1] }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin',  roomName1, ->
                socket1.emit 'roomAddToList', roomName1, 'userlist', [user2]
                , (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

        it 'should reject any lists modifications for non-admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomAddToList', roomName1, 'whitelist', [user2]
                , (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

        it 'should reject mode changes for non-admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomSetWhitelistMode', roomName1, true
                , (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

        it 'should check room permissions', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { blacklist : [user1] }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                expect(error).ok
                expect(data).null
                done()

        it 'should check room permissions in whitelist mode', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1
          , { whitelist : [user2], whitelistOnly : true }
          , ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                expect(error).ok
                expect(data).null
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, (error, data) ->
                    expect(error).not.ok
                    expect(data).equal(1)
                    done()

        it 'should remove users on permissions changes', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { adminlist: [user1, user3] }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, ->
                    socket3 = clientConnect user3
                    socket3.on 'loginConfirmed', ->
                      socket3.emit 'roomJoin', roomName1, ->
                        socket1.emit 'roomAddToList', roomName1, 'blacklist'
                        , [user2, user3, 'nouser']
                        async.parallel [
                          (cb) ->
                            socket2.on 'roomAccessRemoved', (r) ->
                              expect(r).equal(roomName1)
                              cb()
                          (cb) ->
                            cb()
                            socket1.on 'roomUserLeft', (r, u) ->
                              expect(r).equal(roomName1)
                              expect(u).equal(user2)
                              cb()
                        ], done

        it 'should remove affected users on mode changes', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { adminlist : [user1] }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, ->
                    socket1.emit 'roomSetWhitelistMode', roomName1, true
                    socket2.on 'roomAccessRemoved', (r) ->
                      expect(r).equal(roomName1)
                      done()

        it 'should remove users on permissions changes in whitelist mode'
        , (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1
          , { adminlist : [user1, user3] , whitelist : [user2]
            , whitelistOnly: true }
          , ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, ->
                    socket3 = clientConnect user3
                    socket3.on 'loginConfirmed', ->
                      socket3.emit 'roomJoin', roomName1, ->
                        socket1.emit 'roomRemoveFromList', roomName1
                        , 'whitelist', [user2, user3, 'nouser']
                        socket2.on 'roomAccessRemoved', (r) ->
                          expect(r).equal(roomName1)
                          done()

        it 'should remove disconnected users' , (done) ->
          chatServer = new ChatService { port : port
            , enableUserlistUpdates : true }
          , null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, ->
                    socket2.disconnect()
                    socket1.on 'roomUserLeft', (r,u) ->
                      expect(r).equal(roomName1)
                      expect(u).equal(user2)
                      done()

        it 'should list own sockets with rooms', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            chatServer.addRoom roomName2, null, ->
              socket1 = clientConnect user1
              socket1.on 'loginConfirmed', (u, data) ->
                sid1 = data.id
                socket1.emit 'roomJoin', roomName1, ->
                  socket1.emit 'roomJoin', roomName2, ->
                    socket2 = clientConnect user1
                    socket2.on 'loginConfirmed', (u, data)->
                      sid2 = data.id
                      socket2.emit 'roomJoin', roomName1, ->
                        socket3 = clientConnect user1
                        socket3.on 'loginConfirmed', (u, data)->
                          sid3 = data.id
                          socket2.emit 'listOwnSockets', (error, data) ->
                            expect(error).not.ok
                            expect(data[sid1]).lengthOf(2)
                            expect(data[sid2]).lengthOf(1)
                            expect(data[sid3]).lengthOf(0)
                            expect(data[sid1]).include
                            .members([roomName1, roomName2])
                            expect(data[sid1]).include(roomName1)
                            done()


      describe 'Direct messaging', ->

        it 'should send direct messages', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
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

        it 'should not send direct messages when the option is disabled'
        , (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }
          , null, state
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
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directMessage', user1, message, (error, data) ->
              expect(error).ok
              expect(data).null
              done()

        it 'should not send direct messages to offline users', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
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
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
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
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket2 = clientConnect user1
            socket2.on 'loginConfirmed', ->
              socket1.emit 'systemMessage', data
              socket2.on 'systemMessage', (d) ->
                expect(d).equal(data)
                done()


      describe 'Direct permissions', ->

        it 'should check user permissions', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket2 = clientConnect user2
            socket2.on 'loginConfirmed', ->
              socket2.emit 'directAddToList', 'blacklist', [user1]
              , (error, data) ->
                expect(error).not.ok
                expect(data).null
                socket1.emit 'directMessage', user2, message
                , (error, data) ->
                  expect(error).ok
                  expect(data).null
                  done()

        it 'should check user permissions in whitelist mode', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket2 = clientConnect user2
            socket2.on 'loginConfirmed', ->
              socket2.emit 'directAddToList', 'whitelist', [user1]
              , (error, data) ->
                expect(error).not.ok
                expect(data).null
                socket2.emit 'directSetWhitelistMode', true, (error, data) ->
                  expect(error).not.ok
                  expect(data).null
                  socket1.emit 'directMessage', user2, message
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data.textMessage).equal(txt)
                    socket2.emit 'directRemoveFromList', 'whitelist', [user1]
                    , (error, data) ->
                      expect(error).not.ok
                      expect(data).null
                      socket1.emit 'directMessage', user2, message
                      , (error, data) ->
                        expect(error).ok
                        expect(data).null
                        done()

        it 'should allow an user to modify own lists', (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directAddToList', 'blacklist', [user2]
            , (error, data) ->
              expect(error).not.ok
              expect(data).null
              socket1.emit 'directGetAccessList', 'blacklist'
              , (error, data) ->
                expect(error).not.ok
                expect(data).include(user2)
                socket1.emit 'directRemoveFromList', 'blacklist', [user2]
                , (error, data) ->
                  expect(error).not.ok
                  expect(data).null
                  socket1.emit 'directGetAccessList', 'blacklist'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).not.include(user2)
                    done()

        it 'should reject to add user to own lists', (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directAddToList', 'blacklist', [user1]
            , (error, data) ->
              expect(error).ok
              expect(data).null
              done()

        it 'should check user list names', (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directAddToList', 'nolist', [user2]
            , (error, data) ->
              expect(error).ok
              expect(data).null
              done()

        it 'should allow duplicate adding to lists' , (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directAddToList', 'blacklist', [user2]
            , (error, data) ->
              expect(error).not.ok
              expect(data).null
              socket1.emit 'directAddToList', 'blacklist', [user2]
              , (error, data) ->
                expect(error).not.ok
                expect(data).null
                done()

        it 'should allow not existing deleting from lists' , (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directRemoveFromList', 'blacklist', [user2]
            , (error, data) ->
              expect(error).not.ok
              expect(data).null
              done()

        it 'should allow an user to modify own mode', (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directSetWhitelistMode', true, (error, data) ->
              expect(error).not.ok
              expect(data).null
              socket1.emit 'directGetWhitelistMode', (error, data) ->
                expect(error).not.ok
                expect(data).true
                done()

      describe 'Hooks', ->

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
          chatServer = new ChatService { port : port }
          , { onStart : onStart }, state

        it 'should exectute onClose hook', (done) ->
          closeHook = (server, error, cb) ->
            expect(server).instanceof(ChatService)
            expect(error).not.ok
            cb()
          chatServer1 = new ChatService { port : port }
          , { onClose : closeHook }, state
          chatServer1.close done

        it 'should execute before and after hooks', (done) ->
          someData = 'data'
          before = null
          after = null
          sid = null
          beforeHook = (server, userName, id, args, cb) ->
            [ name , mode ] = args
            expect(server).instanceof(ChatService)
            expect(userName).equal(user1)
            expect(id).equal(sid)
            expect(name).a('string')
            expect(mode).a('boolean')
            expect(cb).instanceof(Function)
            before = true
            cb()
          afterHook = (server, userName, id, args, results, cb) ->
            [ name , mode ] = args
            [ error, data ] = results
            expect(server).instanceof(ChatService)
            expect(userName).equal(user1)
            expect(id).equal(sid)
            expect(args).instanceof(Array)
            expect(name).a('string')
            expect(mode).a('boolean')
            expect(cb).instanceof(Function)
            after = true
            cb null, someData
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true}
          , { 'roomCreateBefore' : beforeHook, 'roomCreateAfter' : afterHook }
          , state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u, data) ->
            sid = data.id
            socket1.emit 'roomCreate', roomName1, true, (error, data) ->
              expect(before).true
              expect(after).true
              expect(error).not.ok
              expect(data).equal(someData)
              done()

        it 'should support changing arguments in before hooks', (done) ->
          beforeHook = (server, userName, id, args, cb) ->
            cb null, null, roomName2
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true}
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
          afterHook = (server, userName, id, args, results, cb) ->
            cb null, null, true
          chatServer = new ChatService { port : port }
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

        it 'should send errors if new arguments have a different length'
        , (done) ->
          beforeHook = (server, userName, id, args, cb) ->
            cb null, null, roomName2
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true}
          , { 'roomCreateBefore' : beforeHook }
          , state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomCreate', roomName1, true, (error) ->
              expect(error).ok
              done()

        it 'should execute disconnect After and Before hooks', (done) ->
          before = false
          disconnectBefore = (server, userName, id, args, cb) ->
            before = true
            cb()
          disconnectAfter = (server, userName, id, args, results, cb) ->
            expect(before).true
            cb()
            done()
          chatServer1 = new ChatService { port : port }
          , { disconnectAfter : disconnectAfter
            , disconnectBefore : disconnectBefore }
          , state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            chatServer1.close()

        it 'should stop commands on before hook error or data', (done) ->
          err = 'error'
          beforeHook = (server, userName, id, args, cb) ->
            cb err
          chatServer = new ChatService { port : port }
          , { 'listOwnSocketsBefore' : beforeHook }, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'listOwnSockets', (error, data) ->
              expect(error).equal(err)
              expect(data).null
              done()

        it 'should accept custom direct messages with a hook', (done) ->
          html = '<b>HTML message.</b>'
          message = { htmlMessage : html }
          directMessagesChecker = (msg, cb) ->
            cb()
          chatServer =
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
          chatServer = new ChatService { port : port }
          , { roomMessagesChecker : roomMessagesChecker }
          , state
          chatServer.addRoom roomName1, null, ->
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


      describe 'API', ->

        it 'should support a server side user disconnection', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            socket2 = clientConnect user1
            socket2.on 'loginConfirmed', (u) ->
              expect(u).equal(user1)
              chatServer.disconnectUserSockets user1
              async.parallel [
                (cb) ->
                  socket1.on 'disconnect', ->
                    expect(socket1.connected).not.ok
                    cb()
                (cb) ->
                  socket2.on 'disconnect', ->
                    expect(socket2.connected).not.ok
                    cb()
              ], done

        it 'should support adding users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addUser user1, { whitelistOnly : true }, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'directGetWhitelistMode', (error, data) ->
                expect(error).not.ok
                expect(data).true
                done()

        it 'should check user names before adding', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addUser 'user:1', null, (error, data) ->
            expect(error).ok
            expect(data).not.ok
            done()

        it 'should check existing users before adding new ones', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addUser user1, null, ->
            chatServer.addUser user1, null, (error, data) ->
              expect(error).ok
              expect(data).not.ok
              done()

        it 'should get a user mode', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addUser user1, { whitelistOnly : true }, ->
            chatServer.getUserMode user1, (error, data) ->
              expect(error).not.ok
              expect(data).true
              done()

        it 'should get a user list', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addUser user1, { whitelist : [user2] }, ->
            chatServer.getUserList user1, 'whitelist', (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0]).equal(user2)
              done()

        it 'should check room names before adding', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom 'room:1', null, (error, data) ->
            expect(error).ok
            expect(data).not.ok
            done()

        it 'should support removing rooms with users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket2 = clientConnect user2
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, ->
                    async.parallel [
                      (cb) ->
                        chatServer.removeRoom roomName1, (error, data) ->
                          expect(error).not.ok
                          expect(data).not.ok
                          cb()
                      (cb) ->
                        socket1.on 'roomAccessRemoved', (r) ->
                          expect(r).equal(roomName1)
                          cb()
                      (cb) ->
                        socket2.on 'roomAccessRemoved', (r) ->
                          expect(r).equal(roomName1)
                          cb()
                    ], done

        it 'should check existing rooms before adding new ones', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, null, (error, data) ->
            expect(error).not.ok
            expect(data).not.ok
            chatServer.addRoom roomName1, null, (error, data) ->
              expect(error).ok
              expect(data).not.ok
              done()

        it 'should check existing rooms before removing a room', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.removeRoom roomName1, (error, data) ->
            expect(error).ok
            expect(data).not.ok
            done()

        it 'should support changing room owner', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, {owner : user1}, ->
            socket1 = clientConnect user1
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                chatServer.changeRoomOwner roomName1, user2, (error, data) ->
                  expect(error).not.ok
                  expect(data).not.ok
                  socket1.emit 'roomGetOwner', roomName1, (error, data) ->
                    expect(error).not.ok
                    expect(data).equal(user2)
                    chatServer.getRoomOwner roomName1, (error, owner) ->
                      expect(error).not.ok
                      expect(owner).equal(user2)
                      done()

        it 'should get a room mode', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { whitelistOnly : true }, ->
            chatServer.getRoomMode roomName1, (error, data) ->
              expect(error).not.ok
              expect(data).true
              done()

        it 'should get a room list', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, { whitelist : [user2] }, ->
            chatServer.getRoomList roomName1, 'whitelist', (error, data) ->
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0]).equal(user2)
              done()

        it 'should send system messages to all user sockets.', (done) ->
          data = 'some data.'
          chatServer = new ChatService { port : port }, null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket2 = clientConnect user1
            socket2.on 'loginConfirmed', ->
              chatServer.execUserCommand user1, 'systemMessage', data
              async.parallel [
                (cb) ->
                  socket1.on 'systemMessage', (d) ->
                    expect(d).equal(data)
                    cb()
                (cb) ->
                  socket2.on 'systemMessage', (d) ->
                    expect(d).equal(data)
                    cb()
              ], done

        it 'should execute commands with hooks.', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, {owner : user1}, ->
            chatServer.addUser user2, null, ->
              socket1 = clientConnect user1
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin', roomName1, ->
                  chatServer.execUserCommand {userName : user1, useHooks : true}
                  , 'roomAddToList', roomName1, 'whitelist', [user1]
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).null
                    done()

        it 'should check commands names.', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addUser user1, null, ->
            chatServer.execUserCommand user1, 'nocmd', (error) ->
              expect(error).ok
              done()

        it 'should check for socket ids if required.', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addUser user1, null, ->
            chatServer.execUserCommand user1, 'roomJoin', (error) ->
              expect(error).ok
              done()

        it 'should check commands arguments.', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.addRoom roomName1, {owner : user1}, ->
            chatServer.addUser user2, null, ->
              socket1 = clientConnect user1
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin', roomName1, ->
                  chatServer.execUserCommand user1
                  , 'roomAddToList', 'whitelist', [user1]
                  , (error, data) ->
                    expect(error).ok
                    expect(data).null
                    chatServer.execUserCommand user1
                    , 'roomAddToList', roomName1, 1, [user1]
                    , (error, data) ->
                      expect(error).ok
                      expect(data).null
                      done()


      describe 'Validation and errors', ->

        it 'should return raw error objects', (done) ->
          chatServer = new ChatService { port : port
          , useRawErrorObjects : true },
          null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomGetAccessList', roomName1, 'nolist', (error) ->
              expect(error.name).equal('noRoom')
              expect(error.args).length.above(0)
              expect(error.args[0]).equal('room1')
              done()

        it 'should validate message argument types', (done) ->
          chatServer = new ChatService {port : port
            , enableRoomsManagement : true},
          null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', null, false, (error, data) ->
              expect(error).ok
              expect(data).not.ok
              done()

        it 'should have a message validator instance', (done) ->
          chatServer = new ChatService {port : port}, null, state
          chatServer.validator.checkArguments 'roomGetAccessList'
            , roomName1, 'userlist', (error) ->
              expect(error).not.ok
              done()

        it 'should check for unknown commands', (done) ->
          chatServer = new ChatService {port : port}, null, state
          chatServer.validator.checkArguments 'cmd', (error) ->
            expect(error).ok
            done()

        it 'should validate a message argument count', (done) ->
          chatServer = new ChatService {port : port
            , enableRoomsManagement : true},
          null, state
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', (error, data) ->
              expect(error).ok
              expect(data).not.ok
              done()

        it 'should have a server messages and user commands fields', (done) ->
          chatServer = new ChatService {port : port}, null, state
          for k, fn of chatServer.serverMessages
            fn()
          for k, fn of chatServer.userCommands
            fn()
          process.nextTick -> done()
