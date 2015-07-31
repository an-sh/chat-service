
ChatService = require('../index.js').ChatService
User = require('../index.js').User
Room = require('../index.js').Room
expect = require('chai').expect
ioClient = require 'socket.io-client'
socketIO = require 'socket.io'
http = require 'http'
enableDestroy = require 'server-destroy'
async = require 'async'


describe 'Chat service', ->

  makeParams = (userName) ->
    return query : "user=#{userName}"
    , 'multiplex' : false
    , 'transports' : [ 'websocket' ]

  user1 = 'userName1'
  user2 = 'userName2'
  user3 = 'userName3'
  roomName1 = 'room1'
  roomName2 = 'room2'

  id = 100
  chatServer = null
  socket1 = null
  socket2 = null
  socket3 = null

  port = 8000
  host = 'localhost'
  namespace = '/chat-service'
  url1 = "http://#{host}:#{port}#{namespace}"

  afterEach (done) ->
    id = 100
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
      chatServer.close done
      chatServer = null
    else
      done()

  it 'should integrate with a http server', (done) ->
    httpInst = http.createServer (req, res) -> res.end()
    enableDestroy httpInst
    chatServer1 = new ChatService { http : httpInst }
    httpInst.listen port
    cleanup = (err) ->
      chatServer1.close ->
        httpInst.destroy done, err
    process.once 'uncaughtException', cleanup
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      process.removeListener 'uncaughtException', cleanup
      cleanup()

  it 'should integrate with an existing io', (done) ->
    io = socketIO port
    chatServer1 = new ChatService { io : io }
    cleanup =  (err) ->
      chatServer1.close ->
        chatServer1.close()
        io.close()
        done err
    process.once 'uncaughtException', cleanup
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      process.removeListener 'uncaughtException', cleanup
      cleanup()


  it 'should spawn a new io server', (done) ->
    chatServer = new ChatService { port : port }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      done()

  it 'should disconnect on server shutdown', (done) ->
    chatServer = new ChatService { port : port }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.on 'disconnect', () ->
        done()
      chatServer.close()
      chatServer = null

  it 'should reject empty user query', (done) ->
    chatServer = new ChatService { port : port }
    socket1 = ioClient.connect url1
    socket1.on 'loginRejected', ->
      done()

  it 'should use an user object from onConnect hook', (done) ->
    user = null
    userState = { whitelist : ['user2'] , blacklist : ['user0'] }
    onConnect = (server, socket, cb) ->
      user = new User server, 'user1'
      user.initState userState, ->
        cb null, user
    chatServer = new ChatService { port : port }, { onConnect : onConnect }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal('user1')
      usr = chatServer.userManager.getUser 'user1'
      expect(usr.username).eql(user.username)
      async.parallel [ (cb) ->
        usr.directMessagingState.blacklistHas 'user0', cb
      , (cb) ->
        usr.directMessagingState.whitelistHas 'user2', cb
      ] , done

  it 'should restore room state from onStart hook', (done) ->
    room = null
    onStart = (server, cb) ->
      room = new Room server, 'roomName', 'ownerName'
      room.setState { whitelist : [ user1 ] }
      server.roomManager.addRoom room
      cb null, room
    chatServer = new ChatService { port : port }, { onStart : onStart }
    r = chatServer.roomManager.getRoom 'roomName'
    expect(r).eql(room)
    expect(r.whitelist.get user1).ok
    done()

  it 'should support multiple sockets per user', (done) ->
    chatServer = new ChatService { port : port }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', (u) ->
      socket2 = ioClient.connect url1, makeParams(user1)
      socket2.on 'loginConfirmed', (u) ->
        user = chatServer.userManager.getUser(user1)
        user.userState.socketsCount (err, nsockets) ->
          expect(nsockets).equal(2)
          done()

  it 'should create and delete rooms', (done) ->
    chatServer = new ChatService { port : port, enableRoomsManagement : true }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', (u) ->
      socket1.once 'success', (idcmd, data) ->
        expect(idcmd).equal(id)
        expect(chatServer.roomManager.getRoom roomName1).ok
        expect(chatServer.roomManager.listRooms()).length(1)
        id++
        socket1.emit 'roomCreate', id, roomName1, false
      socket1.once 'fail', (idcmd, err) ->
        expect(idcmd).equal(id)
        expect(err).ok
        socket1.once 'success', (idcmd) ->
          expect(idcmd).equal(id)
          expect(chatServer.roomManager.listRooms()).empty
          done()
        id++
        socket1.emit 'roomDelete', id, roomName1
      socket1.emit 'roomCreate', id, roomName1, false

  it 'should reject room management without enableRoomsManagement option'
  , (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName2, user1
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', (u) ->
      socket1.emit 'roomCreate', id, roomName1, false
      socket1.once 'fail', (idcmd, err) ->
        expect(err).ok
        socket1.emit 'roomDelete', id, roomName2
        socket1.once 'fail', (idcmd, err) ->
          expect(err).ok
          done()

  it 'should join and leave room for all user sockets', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket2 = ioClient.connect url1, makeParams(user1)
      socket2.on 'loginConfirmed', ->
        user = chatServer.userManager.getUser(user1)
        socket2.emit 'roomJoin', id, roomName1
        async.parallel [ (cb) ->
          socket2.on 'roomJoined', (room) ->
            expect(room).equal(roomName1)
            cb()
        , (cb) ->
          socket1.on 'roomJoined', (room) ->
            expect(room).equal(roomName1)
            cb()
        , (cb) ->
          socket2.once 'success', (idcmd) ->
            expect(idcmd).equal(id)
            cb()
        ]
        , ->
          room = chatServer.roomManager.getRoom roomName1
          expect(room.userlist.length).equal(1)
          socket1.emit 'roomLeave', id, roomName1
          async.parallel [ (cb) ->
            socket2.on 'roomLeft', (room) ->
              expect(room).equal(roomName1)
              cb()
            , (cb) ->
              socket1.on 'roomLeft', (room) ->
              expect(room).equal(roomName1)
              cb()
            , (cb) ->
              socket1.once 'success', (idcmd) ->
              expect(idcmd).equal(id)
              cb()
          ]
          , ->
            expect(room.userlist.length).equal(0)
            done()

  it 'should broadcast join and leave room messages', (done) ->
    chatServer = new ChatService { port : port, enableUserlistUpdates : true }
    room = new Room chatServer, roomName1, 'admin'
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        expect(idcmd).equal(id)
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket2.emit 'roomJoin', id, roomName1
          socket1.on 'roomUserJoin', (room, user) ->
            expect(room).equal(roomName1)
            expect(user).equal(user2)
            socket2.emit 'roomLeave', id, roomName1
            socket1.on 'roomUserLeave', (room, user) ->
              expect(room).equal(roomName1)
              expect(user).equal(user2)
              done()

  it 'should store and send room history', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket1.emit 'roomMessage', id, roomName1, message
        socket1.once 'success', ->
          socket1.emit 'roomHistory', id, roomName1
          socket1.once 'success', (idcmd, data) ->
            expect(data[0].message.textMessage).eql(txt)
            done()

  it 'should send room messages to all users', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket2.emit 'roomJoin', id, roomName1
          socket2.once 'success', (idcmd) ->
            socket1.emit 'roomMessage', id, roomName1, message
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
            , (cb) ->
              socket1.once 'success', (idcmd) ->
                cb()
            ]
            , -> done()

  it 'should list non-whitelistonly rooms', (done) ->
    chatServer = new ChatService { port : port }
    room1 = new Room chatServer, roomName1, 'admin', true
    room2 = new Room chatServer, roomName2, 'admin'
    chatServer.roomManager.addRoom room1
    chatServer.roomManager.addRoom room2
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'listRooms', id
      socket1.once 'success', (idcmd, data) ->
        expect(idcmd).equal(id)
        expect(data).an('array')
        expect(data).include(roomName2)
        expect(data).not.include(roomName1)
        done()

  it 'should send whitelistonly mode', (done) ->
    chatServer = new ChatService { port : port }
    room1 = new Room chatServer, roomName1, 'admin', true
    chatServer.roomManager.addRoom room1
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomGetWhitelistMode', id, roomName1
      socket1.once 'success', (idcmd, data) ->
        expect(data).ok
        done()

  it 'should send lists to room users', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket1.emit 'roomGetAccessList', id, roomName1, 'userlist'
        socket1.once 'success', (idcmd, data) ->
          expect(data).an('array')
          expect(data).include(user1)
          done()

  it 'should reject send lists to not joined users', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomGetAccessList', id, roomName1, 'userlist'
      socket1.once 'fail', (idcmd, error) ->
        expect(error).ok
        done()

  it 'should allow list modify for admins', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    room.adminlist.add user1
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket1.emit 'roomAddToList', id, roomName1, 'whitelist', [user2]
        socket1.once 'success', (idcmd) ->
          expect(room.whitelist.get(user2)).ok
          socket1.emit 'roomRemoveFromList', id, roomName1, 'whitelist', [user2]
          socket1.once 'success', (idcmd) ->
            expect(room.whitelist.get(user2)).not.ok
            done()

  it 'should reject list modify for users', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket1.emit 'roomAddToList', id, roomName1, 'adminlist', [user2]
        socket1.once 'fail', (idcmd, error) ->
          expect(error).ok
          done()

  it 'should check room permissions', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin'
    room.blacklist.add user1
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'fail', (idcmd, error) ->
        expect(error).ok
        done()

  it 'should check room permissions in whitelist mode', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, 'admin', true
    room.whitelist.add user2
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'fail', (idcmd, error) ->
        expect(error).ok
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket2.emit 'roomJoin', id, roomName1
          socket2.once 'success', (idcmd) ->
            done()

  it 'should remove users on permission changes', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, user1
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket2.emit 'roomJoin', id, roomName1
          socket2.once 'success', (idcmd) ->
            socket1.emit 'roomAddToList', id, roomName1, 'blacklist', [user2]
            socket2.on 'roomAccessRemoved', (r) ->
              expect(r).equal(roomName1)
              done()

  it 'should remove users on mode changes', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, user1
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket2.emit 'roomJoin', id, roomName1
          socket2.once 'success', (idcmd) ->
            socket1.emit 'roomSetWhitelistMode', id, roomName1, true
            socket2.on 'roomAccessRemoved', (r) ->
              expect(r).equal(roomName1)
              done()

  it 'should remove users on permission changes in whitelist mode', (done) ->
    chatServer = new ChatService { port : port }
    room = new Room chatServer, roomName1, user1, true
    room.whitelist.add user2
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket2.emit 'roomJoin', id, roomName1
          socket2.once 'success', (idcmd) ->
            socket1.emit 'roomRemoveFromList', id, roomName1
            , 'whitelist', [user2]
            socket2.on 'roomAccessRemoved', (r) ->
              expect(r).equal(roomName1)
              done()

  it 'should send access remove on room delete', (done) ->
    chatServer = new ChatService { port : port, enableRoomsManagement : true }
    room = new Room chatServer, roomName1, user1
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket1.emit 'roomDelete', id, roomName1
        socket1.once 'roomAccessRemoved', (r) ->
          expect(r).equal(roomName1)
          done()

  it 'should remove disconnected users' , (done) ->
    chatServer = new ChatService { port : port, enableUserlistUpdates : true }
    room = new Room chatServer, roomName1, user1, true
    room.whitelist.add user2
    chatServer.roomManager.addRoom room
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomJoin', id, roomName1
      socket1.once 'success', (idcmd) ->
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket2.emit 'roomJoin', id, roomName1
          socket2.once 'success', (idcmd) ->
            socket2.disconnect()
            socket1.once 'roomUserLeave', (r,u) ->
              expect(r).equal(roomName1)
              expect(u).equal(user2)
              done()

  it 'should send direct messages', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatServer = new ChatService { port : port, enableDirectMessages : true }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket2 = ioClient.connect url1, makeParams(user2)
      socket2.on 'loginConfirmed', ->
        socket1.emit 'directMessage', id, user2, message
        socket2.on 'directMessage', (u, msg) ->
          expect(u).equal(user1)
          expect(msg?.textMessage).equal(txt)
          expect(msg).ownProperty('timestamp')
          done()

  it 'should echo direct messges to user sockets', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatServer = new ChatService { port : port, enableDirectMessages : true }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket3 = ioClient.connect url1, makeParams(user1)
      socket3.on 'loginConfirmed', ->
        socket2 = ioClient.connect url1, makeParams(user2)
        socket2.on 'loginConfirmed', ->
          socket1.emit 'directMessage', id, user2, message
          socket3.on 'directMessageEcho', (u, msg) ->
            expect(u).equal(user2)
            expect(msg?.textMessage).equal(txt)
            done()

  it 'should check user permission', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatServer = new ChatService { port : port, enableDirectMessages : true }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket2 = ioClient.connect url1, makeParams(user2)
      socket2.on 'loginConfirmed', ->
        user = chatServer.userManager.getUser(user2)
        user.directMessagingState.blacklistAdd [user1], ->
          socket1.emit 'directMessage', id, user2, message
          socket1.on 'fail', (idcmd, err) ->
            expect(err).ok
            done()

  it 'should check user permission in whitelist mode', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatServer = new ChatService { port : port, enableDirectMessages : true }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket2 = ioClient.connect url1, makeParams(user2)
      socket2.on 'loginConfirmed', ->
        user = chatServer.userManager.getUser(user2)
        user.directMessagingState.whitelistOnlySet true, ->
          user.directMessagingState.whitelistAdd [user1], ->
            socket1.emit 'directMessage', id, user2, message
            socket1.on 'success', (idcmd) ->
              done()

  it 'should allow user to modify own lists', (done) ->
    chatServer = new ChatService { port : port, enableDirectMessages : true }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directAddToList', id , 'blacklist', [user2]
      socket1.once 'success', ->
        socket1.emit 'directGetAccessList', id , 'blacklist'
        socket1.once 'success', (idcmd, data) ->
          expect(data).include(user2)
          socket1.emit 'directRemoveFromList', id , 'blacklist', [user2]
          socket1.once 'success', (idcmd, data) ->
            socket1.emit 'directGetAccessList', id , 'blacklist'
            socket1.once 'success', (idcmd, data) ->
              expect(data).not.include(user2)
              done()

  it 'should allow user to modify own mode', (done) ->
    chatServer = new ChatService { port : port, enableDirectMessages : true }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'directSetWhitelistMode', id , true
      socket1.once 'success', ->
        socket1.emit 'directGetWhitelistMode', id
        socket1.once 'success', (idcmd, data) ->
          expect(data).true
          done()

  it 'should execute before and after messages hooks', (done) ->
    before = null
    after = null
    beforeHook = (server, socket, idcmd, cb) ->
      before = true
      cb()
    afterHook = (server, socket, idcmd, cb) ->
      after = true
      cb()
    chatServer = new ChatService { port : port }
    , { 'listRoomsBefore' : beforeHook, 'listRoomsAfter' : afterHook }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'listRooms', id
      socket1.once 'success', (idcmd, data) ->
        process.nextTick ->
          expect(before).true
          expect(after).true
          done()

  it 'should stop commands on before hook error or data', (done) ->
    error = 'error'
    beforeHook = (server, socket, idcmd, cb) ->
      cb error
    chatServer = new ChatService { port : port }
    , { 'listRoomsBefore' : beforeHook }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'listRooms', id
      socket1.once 'fail', (idcmd, err) ->
        expect(err).eql(error)
        done()

  it 'should allow new arguments from before hook', (done) ->
    data = 'data'
    beforeHook = (server, socket, idcmd, cb) ->
      cb null, null, data
    afterHook = (server, socket, idcmd, cb, d) ->
      expect(d).eql(data)
      cb()
    chatServer = new ChatService { port : port }
    , { 'listRoomsBefore' : beforeHook, 'listRoomsAfter' : afterHook }
    socket1 = ioClient.connect url1, makeParams(user1)
    socket1.on 'loginConfirmed', ->
      socket1.emit 'listRooms', id
      socket1.once 'success', ->
        process.nextTick ->
          done()
