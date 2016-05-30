
_ = require 'lodash'
async = require 'async'
expect = require('chai').expect

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

  it 'should reject room messages from not joined users', (done) ->
    txt = 'Test message.'
    message = { textMessage : txt }
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomMessage', roomName1, message, (error, data) ->
          expect(error).ok
          expect(data).null
          socket1.emit 'roomRecentHistory', roomName1, (error, data) ->
            expect(error).ok
            expect(data).null
            done()

  it 'should send a whitelistonly mode', (done) ->
    chatService = startService()
    chatService.addRoom roomName1
    , { whitelistOnly : true, whitelist : [user1] }
    , ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomGetWhitelistMode', roomName1, (error, data) ->
            expect(error).not.ok
            expect(data).true
            done()

  it 'should send lists to room users', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, null, ->
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
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomGetAccessList', roomName1, 'userlist'
        , (error, data) ->
          expect(error).ok
          expect(data).null
          done()

  it 'should ckeck room list names', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomGetAccessList', roomName1, 'nolist'
          , (error, data) ->
            expect(error).ok
            expect(data).null
            done()

  it 'should allow duplicate adding to lists', (done) ->
    chatService = startService { enableRoomsManagement : true }
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

  it 'should allow not added deleting from lists', (done) ->
    chatService = startService { enableRoomsManagement : true }
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
    chatService = startService { enableAccessListsUpdates : true }
    chatService.addRoom roomName1, { owner : user1 }, ->
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
    chatService = startService { enableAccessListsUpdates : true }
    chatService.addRoom roomName1
    , { owner : user1, whitelistOnly : true }
    , ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin',  roomName1, ->
          socket1.emit 'roomSetWhitelistMode', roomName1, false
          socket1.on 'roomModeChanged', (roomName, mode) ->
            expect(roomName).equal(roomName1)
            expect(mode).false
            done()

  it 'should allow wl and bl modifications for admins', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, { adminlist : [user1] }, ->
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
    chatService = startService()
    chatService.addRoom roomName1, { adminlist : [user1, user2] }, ->
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
    chatService = startService { enableRoomsManagement : true }
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
    chatService = startService()
    chatService.addRoom roomName1, { adminlist : [user1] }, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin',  roomName1, ->
          socket1.emit 'roomAddToList', roomName1, 'userlist', [user2]
          , (error, data) ->
            expect(error).ok
            expect(data).null
            done()

  it 'should reject any lists modifications for non-admins', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomAddToList', roomName1, 'whitelist', [user2]
          , (error, data) ->
            expect(error).ok
            expect(data).null
            done()

  it 'should reject mode changes for non-admins', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket1.emit 'roomSetWhitelistMode', roomName1, true
          , (error, data) ->
            expect(error).ok
            expect(data).null
            done()

  it 'should check room permissions', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, { blacklist : [user1] }, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, (error, data) ->
          expect(error).ok
          expect(data).null
          done()

  it 'should check room permissions in whitelist mode', (done) ->
    chatService = startService()
    chatService.addRoom roomName1
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
    chatService = startService()
    chatService.addRoom roomName1, { adminlist: [user1, user3] }, ->
      async.parallel [
        (cb) ->
          socket1 = clientConnect user1
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket2 = clientConnect user2
          socket2.on 'loginConfirmed', ->
            socket2.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket3 = clientConnect user3
          socket3.on 'loginConfirmed', ->
            socket3.emit 'roomJoin', roomName1, cb
      ], (error) ->
        expect(error).not.ok
        socket3.on 'roomAccessRemoved', ->
          done new Error 'Wrong user removed.'
        async.parallel [
          (cb) ->
            socket1.emit 'roomAddToList', roomName1, 'blacklist'
            , [user2, user3, 'nouser'], cb
          (cb) ->
            socket2.on 'roomAccessRemoved', (r) ->
              expect(r).equal(roomName1)
              cb()
          (cb) ->
            socket1.on 'roomUserLeft', (r, u) ->
              expect(r).equal(roomName1)
              expect(u).equal(user2)
              cb()
        ], done

  it 'should remove affected users on mode changes', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, { adminlist : [user1] }, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket2 = clientConnect user2
          socket2.on 'loginConfirmed', ->
            socket2.emit 'roomJoin', roomName1, ->
              socket1.emit 'roomSetWhitelistMode', roomName1, true
              socket1.on 'roomAccessRemoved', ->
                done new Error 'Wrong user removed.'
              socket2.on 'roomAccessRemoved', (r) ->
                expect(r).equal(roomName1)
                done()

  it 'should remove users on permissions changes in whitelist mode'
  , (done) ->
    chatService = startService()
    chatService.addRoom roomName1
    , { adminlist : [user1, user3]
      , whitelist : [user2]
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
                  socket3.on 'roomAccessRemoved', ->
                    done new Error 'Wrong user removed.'
                  socket2.on 'roomAccessRemoved', (r) ->
                    expect(r).equal(roomName1)
                    done()

  it 'should remove disconnected users' , (done) ->
    chatService = startService { enableUserlistUpdates : true }
    chatService.addRoom roomName1, null, ->
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
