
ChatService = require('../index.js').ChatService
User = require('../index.js').User
Room = require('../index.js').Room
expect = require('chai').expect
ioClient = require 'socket.io-client'
socketIO = require 'socket.io'
http = require 'http'
enableDestroy = require 'server-destroy'
async = require 'async'
Redis = require 'ioredis'


describe 'Chat service.', ->

  states  = [ 'memory' , 'redis' ]

  makeParams = (userName) ->
    q = 'query' : "user=#{userName}"
    , 'multiplex' : false
    , 'reconnection' : false
    , 'transports' : [ 'websocket' ]
    unless userName
      delete q.query
    return q

  user1 = 'userName1'
  user2 = 'userName2'
  user3 = 'userName3'
  roomName1 = 'room1'
  roomName2 = 'room2'
  port = 8000
  url1 = "http://localhost:#{port}/chat-service"

  redis = new Redis
  chatServer = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEachFn = (done) ->
    endcb = -> redis.flushall done
    if socket1
      socket1.disconnect()
      socket1 = null
    if socket2
      socket2.disconnect()
      socket2 = null
    if socket3
      socket3.disconnect()
      socket3 = null
    if chatServer
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

    describe "State: #{state}.", ->

      afterEach afterEachFn


      describe 'Initialization', ->

        it 'should integrate with a provided http server', (done) ->
          httpInst = http.createServer (req, res) -> res.end()
          enableDestroy httpInst
          chatServer1 = new ChatService { http : httpInst }, null, state
          httpInst.listen port
          cleanup = (error) ->
            chatServer1.close ->
              httpInst.destroy done, error
          process.once 'uncaughtException', cleanup
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            process.removeListener 'uncaughtException', cleanup
            cleanup()

        it 'should integrate with an existing io', (done) ->
          io = socketIO port
          chatServer1 = new ChatService { io : io }, null, state
          cleanup =  (error) ->
            chatServer1.close ->
              chatServer1.close()
              io.close()
              done error
          process.once 'uncaughtException', cleanup
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            process.removeListener 'uncaughtException', cleanup
            cleanup()


        it 'should spawn a new io server', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            done()


      describe 'User management', ->

        it 'should support a server side user disconnection', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            expect(u).equal(user1)
            socket2 = ioClient.connect url1, makeParams(user1)
            socket2.on 'loginConfirmed', (u) ->
              expect(u).equal(user1)
              chatServer.chatState.removeUser user1
              async.parallel [ (cb) ->
                socket1.on 'disconnect', ->
                  expect(socket1.connected).not.ok
                  cb()
              , (cb) ->
                socket2.on 'disconnect', ->
                  expect(socket2.connected).not.ok
                  cb()
              ], done

        it 'should disconnect only connected users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            chatServer.chatState.removeUser user2, (error, data) ->
              expect(error).ok
              done()

        it 'should support adding and removing users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.chatState.addUser user1, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', (u) ->
              chatServer.chatState.getOnlineUser user1, (error, user) ->
                expect(error).not.ok
                user.directMessagingState.whitelistOnlyGet (error, wl) ->
                  expect(wl).true
                  chatServer.chatState.removeUser user1, ->
                    async.parallel [ (cb) ->
                      chatServer.chatState.getUser user1
                      , (error, user, isOnline) ->
                        expect(user).not.ok
                        expect(isOnline).not.ok
                        cb()
                    , (cb) ->
                      chatServer.chatState.getOnlineUser user1, (error, user) ->
                        expect(error).ok
                        cb()
                    ], done
          , { whitelistOnly : true }

        it 'should check existing users before adding new ones', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.chatState.addUser user1, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', (u) ->
              expect(u).equal(user1)
              chatServer.chatState.addUser user1, (error, data) ->
                expect(error).ok
                done()


      describe 'Connection', ->

        it 'should reject an empty user query', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = ioClient.connect url1, makeParams()
          socket1.on 'loginRejected', ->
            done()

        it 'should execute an auth hook', (done) ->
          reason = 'some reason'
          auth = (socket, cb) ->
            cb( new Error reason )
          chatServer = new ChatService { port : port }, { auth : auth }, state
          socket1 = ioClient.connect url1, makeParams()
          socket1.on 'error', (e) ->
            expect(e).deep.equal(reason)
            done()

        it 'should reject login if onConnect hook passes error', (done) ->
          err = { someField : 'some reason' }
          onConnect = (server, socket, cb) ->
            cb err
          chatServer = new ChatService { port : port }
            , { onConnect : onConnect }
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginRejected', (e) ->
            expect(e).deep.equal(err)
            done()

        it 'should support multiple sockets per user', (done) ->
          chatServer = new ChatService { port : port }, null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            socket2 = ioClient.connect url1, makeParams(user1)
            socket2.on 'loginConfirmed', (u) ->
              chatServer.chatState.getOnlineUser user1, (error, user) ->
                user.userState.socketsGetAll (error, sockets) ->
                  expect(sockets).length(2)
                  done()

        it 'should disconnect all users on a server shutdown', (done) ->
          chatServer1 = new ChatService { port : port }, null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            async.parallel [ (cb) ->
              socket1.on 'disconnect', ->
                cb()
            , (cb) ->
              chatServer1.close cb
            ], done


      describe 'Room management', ->

        it 'should create and delete rooms', (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', roomName1, false, (error, data) ->
              chatServer.chatState.listRooms (error, data) ->
                expect(data).length(1)
                expect(data[0]).equal(roomName1)
                socket1.emit 'roomCreate', roomName1, false, (error, data) ->
                  expect(error).ok
                  socket1.emit 'roomDelete', roomName1, (error, data) ->
                    expect(error).not.ok
                    chatServer.chatState.listRooms (error, data) ->
                      expect(data).empty
                      done()

        it 'should check existing rooms before adding new ones', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.chatState.addRoom roomName1, ->
            chatServer.chatState.addRoom roomName1, (error, data) ->
              expect(error).ok
              done()

        it 'should check existing rooms before removing a room', (done) ->
          chatServer = new ChatService { port : port }, null, state
          chatServer.chatState.removeRoom roomName1, (error, data) ->
            expect(error).ok
            done()

        it 'should reject room management when the option is disabled'
        , (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName2
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', (u) ->
              socket1.emit 'roomCreate', roomName1, false, (error, data) ->
                expect(error).ok
                socket1.emit 'roomDelete', roomName2, (error, data) ->
                  expect(error).ok
                  done()

        it 'should list all rooms', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room1 = new Room chatServer, roomName1
          room1.initState { whitelistOnly : true }, ->
            room2 = new Room chatServer, roomName2
            chatServer.chatState.addRoom room1, ->
              chatServer.chatState.addRoom room2, ->
                socket1 = ioClient.connect url1, makeParams(user1)
                socket1.on 'loginConfirmed', ->
                  socket1.emit 'listRooms', (error, data) ->
                    expect(data).an('array')
                    expect(data).include(roomName2)
                    expect(data).include(roomName1)
                    done()

        it 'should send access removed on a room deletion', (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          room = new Room chatServer, roomName1
          room.roomState.ownerSet user1, ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin', roomName1, (error, data) ->
                  socket1.emit 'roomDelete', roomName1
                  socket1.once 'roomAccessRemoved', (r) ->
                    expect(r).equal(roomName1)
                    done()


      describe 'Room messaging', ->

        it 'should emit join and leave for all user\'s sockets', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket2 = ioClient.connect url1, makeParams(user1)
              socket2.on 'loginConfirmed', ->
                socket2.emit 'roomJoin', roomName1
                socket1.on 'roomJoinedEcho', (room, njoined) ->
                  expect(room).equal(roomName1)
                  expect(njoined).equal(1)
                  socket1.emit 'roomLeave', roomName1
                  socket2.on 'roomLeftEcho', (room, njoined) ->
                    expect(room).equal(roomName1)
                    expect(njoined).equal(1)
                    socket1.emit 'roomMessage', roomName1, message
                    , (error, data) ->
                      expect(error).not.ok
                      done()

        it 'should emit leave echo on disconnect', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket3 = ioClient.connect url1, makeParams(user1)
            socket3.on 'loginConfirmed', ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin', roomName1, ->
                  socket2 = ioClient.connect url1, makeParams(user1)
                  socket2.on 'loginConfirmed', ->
                    socket2.emit 'roomJoin', roomName1, ->
                      socket2.disconnect()
                      async.parallel [
                        (cb) ->
                          socket1.once 'roomLeftEcho', (room, njoined) ->
                            expect(room).equal(roomName1)
                            expect(njoined).equal(1)
                            cb()
                        (cb) ->
                          socket3.once 'roomLeftEcho', (room, njoined) ->
                            expect(room).equal(roomName1)
                            expect(njoined).equal(1)
                            cb()
                      ] , ->
                        socket1.disconnect()
                        socket3.once 'roomLeftEcho', (room, njoined) ->
                          expect(room).equal(roomName1)
                          expect(njoined).equal(0)
                          done()

        it 'should broadcast join and leave room messages', (done) ->
          chatServer = new ChatService { port : port
            , enableUserlistUpdates : true }
          , null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, njoined) ->
                expect(njoined).equal(1)
                socket2 = ioClient.connect url1, makeParams(user2)
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
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                socket1.emit 'roomMessage', roomName1, message, (error, data) ->
                  socket1.emit 'roomHistory', roomName1, (error, data) ->
                    expect(data?[0].textMessage).equal(txt)
                    done()

        it 'should send room messages to all joined users', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                socket2 = ioClient.connect url1, makeParams(user2)
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, (error, data) ->
                    socket1.emit 'roomMessage', roomName1, message
                    async.parallel [ (cb) ->
                      socket1.on 'roomMessage', (room, user, msg) ->
                        expect(room).equal(roomName1)
                        expect(user).equal(user1)
                        expect(msg.textMessage).equal(txt)
                        expect(msg).ownProperty('timestamp')
                        cb()
                    , (cb) ->
                      socket2.on 'roomMessage', (room, user, msg) ->
                        expect(room).equal(roomName1)
                        expect(user).equal(user1)
                        expect(msg.textMessage).equal(txt)
                        expect(msg).ownProperty('timestamp')
                        cb()
                    ]
                    , -> done()


      describe 'Room permissions', ->

        it 'should reject room messages from not joined users', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomMessage', roomName1, message, (error, data) ->
                expect(error).ok
                socket1.emit 'roomHistory', roomName1, (error, data) ->
                  expect(error).ok
                  done()

        it 'should send a whitelistonly mode', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room1 = new Room chatServer, roomName1
          room1.initState { whitelistOnly : true }, ->
            chatServer.chatState.addRoom room1, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomGetWhitelistMode', roomName1, (error, data) ->
                  expect(data).true
                  done()

        it 'should send lists to room users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomGetAccessList', roomName1, 'userlist'
                , (error, data) ->
                  expect(data).an('array')
                  expect(data).include(user1)
                  done()

        it 'should reject send lists to not joined users', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomGetAccessList', roomName1, 'userlist'
              , (error, data) ->
                expect(error).ok
                done()

        it 'should ckeck room list names', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, ->
                socket1.emit 'roomGetAccessList', roomName1, 'nolist'
                , (error, data) ->
                  expect(error).ok
                  done()

        it 'should check existing user names on adding' , (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', roomName1, false, (error, data) ->
              socket1.emit 'roomJoin',  roomName1, (error, data) ->
                socket1.emit 'roomAddToList', roomName1, 'adminlist', [user2]
                , (error, data) ->
                  socket1.emit 'roomAddToList', roomName1, 'adminlist', [user2]
                  , (error, data) ->
                    expect(error).ok
                    done()

        it 'should check existing user names on deleting' , (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', roomName1, false, (error, data) ->
              socket1.emit 'roomJoin',  roomName1, (error, data) ->
                socket1.emit 'roomRemoveFromList', roomName1, 'adminlist'
                , [user2], (error, data) ->
                  expect(error).ok
                  done()

        it 'should send admin list changed messages', (done) ->
          chatServer = new ChatService { port : port
            , enableAdminlistUpdates : true }
          , null, state
          room = new Room chatServer, roomName1
          room.roomState.ownerSet user1, ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin',  roomName1, (error, data) ->
                  socket1.emit 'roomAddToList', roomName1, 'adminlist', [user3]
                  socket1.on 'roomAdminAdded', (r, u) ->
                    expect(r).equal(roomName1)
                    expect(u).equal(user3)
                    socket1.emit 'roomRemoveFromList', roomName1, 'adminlist'
                    , [user3]
                    socket1.on 'roomAdminRemoved', (r, u) ->
                      expect(r).equal(roomName1)
                      expect(u).equal(user3)
                      done()

        it 'should allow wl and bl modifications for admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.addToList 'adminlist', [user1], ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin',  roomName1, (error, data) ->
                  socket1.emit 'roomAddToList', roomName1, 'whitelist', [user2]
                  , (error, data) ->
                    room.roomState.getList 'whitelist', (error, data) ->
                      expect(data).include(user2)
                      socket1.emit 'roomRemoveFromList', roomName1, 'whitelist'
                      , [user2], (error, data) ->
                        room.roomState.getList 'whitelist', (error, data) ->
                          expect(data).not.include(user2)
                          done()

        it 'should reject adminlist modifications for admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.addToList 'adminlist', [user1,user2], ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin',  roomName1, (error, data) ->
                  socket2 = ioClient.connect url1, makeParams(user2)
                  socket2.on 'loginConfirmed', ->
                    socket2.emit 'roomJoin',  roomName1, (error, data) ->
                      socket1.emit 'roomRemoveFromList', roomName1, 'adminlist'
                      , [user2] , (error, data) ->
                        expect(error).ok
                        done()

        it 'should reject list modifications with owner for admins'
        , (done) ->
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', roomName1, false, (error, data) ->
              socket1.emit 'roomJoin',  roomName1, (error, data) ->
                socket1.emit 'roomAddToList', roomName1, 'adminlist', [user2],
                (error, data) ->
                  socket2 = ioClient.connect url1, makeParams(user2)
                  socket2.on 'loginConfirmed', ->
                    socket2.emit 'roomJoin',  roomName1, (error, data) ->
                      socket2.emit 'roomAddToList', roomName1, 'whitelist'
                      , [user1], (error, data) ->
                        expect(error).ok
                        done()

        it 'should reject userlist modifications', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.addToList 'adminlist', [user1], ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin',  roomName1, (error, data) ->
                  socket1.emit 'roomAddToList', roomName1, 'userlist', [user2]
                  , (error, data) ->
                    expect(error).ok
                    done()

        it 'should reject lists modifications for non-admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                socket1.emit 'roomAddToList', roomName1, 'whitelist', [user2]
                , (error, data) ->
                  expect(error).ok
                  done()

        it 'should reject mode changes for non-admins', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                socket1.emit 'roomSetWhitelistMode', roomName1, true
                , (error, data) ->
                  expect(error).ok
                  done()

        it 'should check room permissions', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.addToList 'blacklist', [user1], ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin', roomName1, (error, data) ->
                  expect(error).ok
                  done()

        it 'should check room permissions in whitelist mode', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.whitelistOnlySet true, ->
            room.roomState.addToList 'whitelist', [user2], ->
              chatServer.chatState.addRoom room, ->
                socket1 = ioClient.connect url1, makeParams(user1)
                socket1.on 'loginConfirmed', ->
                  socket1.emit 'roomJoin', roomName1, (error, data) ->
                    expect(error).ok
                    socket2 = ioClient.connect url1, makeParams(user2)
                    socket2.on 'loginConfirmed', ->
                      socket2.emit 'roomJoin', roomName1, (error, data) ->
                        done()

        it 'should remove users on permissions changes', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.addToList 'adminlist', [user1], ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin', roomName1, (error, data) ->
                  socket2 = ioClient.connect url1, makeParams(user2)
                  socket2.on 'loginConfirmed', ->
                    socket2.emit 'roomJoin', roomName1, (error, data) ->
                      socket1.emit 'roomAddToList', roomName1, 'blacklist'
                      , [user2]
                      socket2.on 'roomAccessRemoved', (r) ->
                        expect(r).equal(roomName1)
                        done()

        it 'should remove users on mode changes', (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.addToList 'adminlist', [user1], ->
            chatServer.chatState.addRoom room, ->
              socket1 = ioClient.connect url1, makeParams(user1)
              socket1.on 'loginConfirmed', ->
                socket1.emit 'roomJoin', roomName1, (error, data) ->
                  socket2 = ioClient.connect url1, makeParams(user2)
                  socket2.on 'loginConfirmed', ->
                    socket2.emit 'roomJoin', roomName1, (error, data) ->
                      socket1.emit 'roomSetWhitelistMode', roomName1, true
                      socket2.on 'roomAccessRemoved', (r) ->
                        expect(r).equal(roomName1)
                        done()

        it 'should remove users on permissions changes in whitelist mode'
        , (done) ->
          chatServer = new ChatService { port : port }, null, state
          room = new Room chatServer, roomName1
          room.roomState.addToList 'adminlist', [user1], ->
            room.roomState.addToList 'whitelist', [user2], ->
              room.roomState.whitelistOnlySet true, ->
                chatServer.chatState.addRoom room, ->
                  socket1 = ioClient.connect url1, makeParams(user1)
                  socket1.on 'loginConfirmed', ->
                    socket1.emit 'roomJoin', roomName1, (error, data) ->
                      socket2 = ioClient.connect url1, makeParams(user2)
                      socket2.on 'loginConfirmed', ->
                        socket2.emit 'roomJoin', roomName1, (error, data) ->
                          socket1.emit 'roomRemoveFromList', roomName1
                          , 'whitelist', [user2]
                          socket2.on 'roomAccessRemoved', (r) ->
                            expect(r).equal(roomName1)
                            done()

        it 'should remove disconnected users' , (done) ->
          chatServer = new ChatService { port : port
            , enableUserlistUpdates : true }
          , null, state
          room = new Room chatServer, roomName1
          chatServer.chatState.addRoom room, ->
            socket1 = ioClient.connect url1, makeParams(user1)
            socket1.on 'loginConfirmed', ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                socket2 = ioClient.connect url1, makeParams(user2)
                socket2.on 'loginConfirmed', ->
                  socket2.emit 'roomJoin', roomName1, (error, data) ->
                    socket2.disconnect()
                    socket1.on 'roomUserLeft', (r,u) ->
                      expect(r).equal(roomName1)
                      expect(u).equal(user2)
                      done()


      describe 'Direct messaging', ->

        it 'should send direct messages', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket2 = ioClient.connect url1, makeParams(user2)
            socket2.on 'loginConfirmed', ->
              socket1.emit 'directMessage', user2, message
              socket2.on 'directMessage', (u, msg) ->
                expect(u).equal(user1)
                expect(msg?.textMessage).equal(txt)
                expect(msg).ownProperty('timestamp')
                done()

        it 'should not send direct messages when the option is disabled'
        , (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket2 = ioClient.connect url1, makeParams(user2)
            socket2.on 'loginConfirmed', ->
              socket1.emit 'directMessage', user2, message, (error, data) ->
                expect(error).ok
                done()

        it 'should echo direct messges to user\'s sockets', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket3 = ioClient.connect url1, makeParams(user1)
            socket3.on 'loginConfirmed', ->
              socket2 = ioClient.connect url1, makeParams(user2)
              socket2.on 'loginConfirmed', ->
                socket1.emit 'directMessage', user2, message
                socket3.on 'directMessageEcho', (u, msg) ->
                  expect(u).equal(user2)
                  expect(msg?.textMessage).equal(txt)
                  done()


      describe 'Direct permissions', ->

        it 'should check user permissions', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket2 = ioClient.connect url1, makeParams(user2)
            socket2.on 'loginConfirmed', ->
              chatServer.chatState.getOnlineUser user2, (error, user) ->
                user.directMessagingState.addToList 'blacklist', [user1], ->
                  socket1.emit 'directMessage', user2, message
                  , (error, data) ->
                    expect(error).ok
                    done()

        it 'should check user permissions in whitelist mode', (done) ->
          txt = 'Test message.'
          message = { textMessage : txt }
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket2 = ioClient.connect url1, makeParams(user2)
            socket2.on 'loginConfirmed', ->
              chatServer.chatState.getOnlineUser user2, (error, user) ->
                user.directMessagingState.whitelistOnlySet true, ->
                  user.directMessagingState.addToList 'whitelist', [user1], ->
                    socket1.emit 'directMessage', user2, message
                    , (error, data) ->
                      expect(error).not.ok
                      expect(data.textMessage).equal(txt)
                      user.directMessagingState.removeFromList 'whitelist'
                      , [user1], ->
                        socket1.emit 'directMessage', user2, message
                        ,(error, data) ->
                          expect(error).ok
                          done()

        it 'should allow an user to modify own lists', (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directAddToList', 'blacklist', [user2]
            , (error, data) ->
              expect(error).not.ok
              socket1.emit 'directGetAccessList', 'blacklist'
              , (error, data) ->
                expect(data).include(user2)
                socket1.emit 'directRemoveFromList', 'blacklist', [user2]
                , (error, data) ->
                  expect(error).not.ok
                  socket1.emit 'directGetAccessList', 'blacklist'
                  , (error, data) ->
                    expect(data).not.include(user2)
                    done()

        it 'should check user list names', (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directAddToList', 'nolist', [user2]
            , (error, data) ->
              expect(error).ok
              done()

        it 'should check existing user names on deleting' , (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directRemoveFromList', 'blacklist', [user2]
            , (error, data) ->
              expect(error).ok
              done()

        it 'should check existing list names on adding' , (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directAddToList', 'blacklist', [user2]
            , (error, data) ->
              expect(error).not.ok
              socket1.emit 'directAddToList', 'blacklist', [user2]
              , (error, data) ->
                expect(error).ok
                done()

        it 'should allow an user to modify own mode', (done) ->
          chatServer = new ChatService { port : port
            , enableDirectMessages : true }
          , null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket1.emit 'directSetWhitelistMode', true, (error, data) ->
              expect(error).not.ok
              socket1.emit 'directGetWhitelistMode', (error, data) ->
                expect(data).true
                done()

      describe 'Hooks', ->

        it 'should restore an user state from onConnect hook', (done) ->
          userName = 'user'
          authData = 'somedata'
          onConnect = (server, socket, cb) ->
            cb null, userName, authData, { whitelistOnly : true }
          chatServer = new ChatService { port : port }
          , { onConnect : onConnect }
          , state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u, d) ->
            expect(u).equal(userName)
            expect(d).equal(authData)
            chatServer.chatState.getOnlineUser userName, (error, u) ->
              expect(u.username).equal(userName)
              u.directMessagingState.whitelistOnlyGet (error, data) ->
                expect(data).true
                done()

        it 'should restore a room state from onStart hook', (done) ->
          room = null
          msg1 = { author : user1, textMessage : "message", timestamp : 0 }
          fn = ->
            chatServer.chatState.getRoom 'roomName', (error, r) ->
              expect(r.name).equal(room.name)
              r.roomState.getList 'whitelist', (error, list) ->
                expect(list).include(user1)
                r.roomState.messagesGet (error, data) ->
                  expect(data).instanceof(Array)
                  expect(data[0]).deep.equal(msg1)
                  done()
          onStart = (server, cb) ->
            expect(server).instanceof(ChatService)
            room = new Room server, 'roomName'
            room.initState { whitelist : [ user1 ]
              , owner : user2
              , lastMessages : [ msg1 ] }
            , ->
              server.chatState.addRoom room, ->
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

        it 'should execute before and after messages hooks', (done) ->
          someData = 'data'
          before = null
          after = null
          beforeHook = (user, name, mode, cb) ->
            expect(user).instanceof(User)
            expect(name).a('string')
            expect(mode).a('boolean')
            expect(cb).instanceof(Function)
            before = true
            cb()
          afterHook = (user, error, data, args, cb) ->
            expect(user).instanceof(User)
            expect(args).instanceof(Array)
            expect(cb).instanceof(Function)
            after = true
            cb null, someData
          chatServer = new ChatService { port : port
            , enableRoomsManagement : true}
          , { 'roomCreateBefore' : beforeHook, 'roomCreateAfter' : afterHook }
          , state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomCreate', roomName1, true, (error, data) ->
              expect(before).true
              expect(after).true
              expect(error).not.ok
              expect(data).equal(someData)
              done()

        it 'should stop commands on before hook error or data', (done) ->
          err = 'error'
          beforeHook = (user, cb) ->
            cb err
          chatServer = new ChatService { port : port }
          , { 'listRoomsBefore' : beforeHook }, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', ->
            socket1.emit 'listRooms', (error, data) ->
              expect(error).equal(err)
              done()

      describe 'Various', ->

        it 'should return raw error objects', (done) ->
          chatServer = new ChatService { port : port
          , useRawErrorObjects : true },
          null, state
          socket1 = ioClient.connect url1, makeParams(user1)
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
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', null, false, (error, data) ->
              expect(error).ok
              done()

        it 'should validate a message argument count', (done) ->
          chatServer = new ChatService {port : port
            , enableRoomsManagement : true},
          null, state
          socket1 = ioClient.connect url1, makeParams(user1)
          socket1.on 'loginConfirmed', (u) ->
            socket1.emit 'roomCreate', (error, data) ->
              expect(error).ok
              done()

        it 'should have a server messages field', (done) ->
          chatServer = new ChatService {port : port}, null, state
          for k, fn of chatServer.serverMessages
            fn()
          process.nextTick -> done()
