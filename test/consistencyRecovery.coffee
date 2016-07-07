
Promise = require 'bluebird'
_ = require 'lodash'
expect = require('chai').expect

{ cleanup
  clientConnect
  closeInstance
  nextTick
  parallel
  setCustomCleanup
  startService
} = require './testutils.coffee'

{ cleanupTimeout
  port
  user1
  user2
  user3
  roomName1
  roomName2
} = require './config.coffee'

module.exports = ->

  instance1 = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEach (cb) ->
    @timeout cleanupTimeout
    cleanup [instance1], [socket1, socket2, socket3], cb
    instance1 = socket1 = socket2 = socket3 = null

  it 'should recover from rollback room join errors', (done) ->
    instance1 = startService()
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        instance1.state.getUser user1
        .then (user) ->
          orig1 = user.userState.removeSocketFromRoom
          orig2 = user.userState.addSocketToRoom
          setCustomCleanup (cb) ->
            user.userState.__proto__.removeSocketFromRoom = orig1
            user.userState.__proto__.addSocketToRoom = orig2
            closeInstance(instance1).asCallback(cb)
          user.userState.__proto__.removeSocketFromRoom = ->
            Promise.reject new Error()
          user.userState.__proto__.addSocketToRoom = ->
            Promise.reject new Error 'This is an error mockup for testing.'
          parallel [
            (cb) ->
              socket1.emit 'roomJoin', roomName1, (error, data) ->
                expect(error).ok
                cb()
            (cb) ->
              instance1.on 'storeConsistencyFailure', (error, data) ->
                nextTick ->
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys 'roomName', 'userName', 'opType'
                  expect(data.roomName).equal(roomName1)
                  expect(data.userName).equal(user1)
                  expect(data.opType).equal('userRooms')
                cb()
          ], (error) ->
            expect(error).not.ok
            user.userState.__proto__.removeSocketFromRoom =  orig1
            user.userState.__proto__.addSocketToRoom = orig2
            instance1.roomStateSync roomName1
            .then ->
              Promise.join instance1.execUserCommand(user1, 'listOwnSockets')
                , instance1.execUserCommand(true, 'roomGetAccessList'
                  , roomName1, 'userlist')
                , (sockets, [list]) ->
                  expect(sockets[id]).an.array
                  expect(sockets[id]).empty
                  expect(list).empty
              .asCallback done

  it 'should recover from leave room errors', (done) ->
    instance1 = startService()
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed',(userName, { id })  ->
        socket1.emit 'roomJoin', roomName1, ->
          instance1.state.getRoom roomName1
          .then (room) ->
            orig = room.leave
            setCustomCleanup (cb) ->
              room.__proto__.leave = orig
              closeInstance(instance1).asCallback(cb)
            room.__proto__.leave = ->
              Promise.reject new Error()
            parallel [
              (cb) ->
                socket1.emit 'roomLeave', roomName1, (error, data) ->
                  expect(error).not.ok
                  cb()
              (cb) ->
                instance1.on 'storeConsistencyFailure', (error, data) ->
                  nextTick ->
                    expect(error).ok
                    expect(data).an('Object')
                    expect(data).include.keys 'roomName', 'userName', 'opType'
                    expect(data.roomName).equal(roomName1)
                    expect(data.userName).equal(user1)
                    expect(data.opType).equal('roomUserlist')
                    cb()
            ], (error) ->
              expect(error).not.ok
              room.__proto__.leave = orig
              instance1.roomStateSync roomName1
              .then ->
                Promise.join instance1.execUserCommand(user1, 'listOwnSockets')
                  , instance1.execUserCommand(true, 'roomGetAccessList'
                    , roomName1, 'userlist')
                  , ([sockets], [list]) ->
                    expect(sockets[id]).an.array
                    expect(sockets[id]).empty
                    expect(list).empty
                .asCallback done

  it 'should recover from remove socket errors', (done) ->
    instance1 = startService()
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        socket1.emit 'roomJoin', roomName1, ->
          instance1.state.getUser user1
          .then (user) ->
            orig = user.userState.removeSocket
            setCustomCleanup (cb) ->
              user.userState.__proto__.removeSocket = orig
              closeInstance(instance1).asCallback(cb)
            user.userState.__proto__.removeSocket = ->
              Promise.reject new Error()
            socket1.disconnect()
            instance1.on 'storeConsistencyFailure', (error, data) ->
              nextTick ->
                user.userState.__proto__.removeSocket = orig
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'userName', 'id', 'opType'
                expect(data.userName).equal(user1)
                expect(data.id).equal(id)
                expect(data.opType).equal('userSockets')
                instance1.userStateSync user1
                .then ->
                  instance1.execUserCommand user1, 'listOwnSockets'
                .spread (sockets) ->
                  expect(sockets).empty
                .asCallback done

  it 'should recover from remove from room errors', (done) ->
    instance1 = startService()
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        socket1.emit 'roomJoin', roomName1, ->
          instance1.state.getUser user1
          .then (user) ->
            orig = user.userState.removeAllSocketsFromRoom
            setCustomCleanup (cb) ->
              user.userState.__proto__.removeAllSocketsFromRoom = orig
              closeInstance(instance1).asCallback(cb)
            user.userState.__proto__.removeAllSocketsFromRoom = ->
              Promise.reject new Error()
            instance1.execUserCommand true
            , 'roomAddToList', roomName1, 'blacklist', [user1]
            , (error) ->
              expect(error).not.ok
            instance1.on 'storeConsistencyFailure', (error, data) ->
              nextTick ->
                user.userState.__proto__.removeAllSocketsFromRoom = orig
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'roomName', 'userName', 'opType'
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.opType).equal('roomUserlist')
                instance1.userStateSync user1
                .then ->
                  Promise.join instance1.execUserCommand(user1,'listOwnSockets')
                  , instance1.execUserCommand(true, 'roomGetAccessList'
                    , roomName1, 'userlist')
                  , ([sockets], [list]) ->
                    expect(sockets[id]).an.array
                    expect(sockets[id]).empty
                    expect(list).empty
                .asCallback done

  it 'should recover from room access check errors', (done) ->
    instance1 = startService()
    instance1.addRoom roomName1, null, ->
      instance1.state.getRoom(roomName1).then (room) ->
        socket1 = clientConnect user1
        socket1.on 'loginConfirmed', (userName, { id }) ->
          socket1.emit 'roomJoin', roomName1, ->
            orig = room.roomState.hasInList
            room.roomState.__proto__.hasInList = ->
              Promise.reject new Error()
            setCustomCleanup (cb) ->
              room.roomState.__proto__.hasInList = orig
              closeInstance(instance1).asCallback(cb)
            parallel [
              (cb) ->
                instance1.execUserCommand true
                , 'roomAddToList', roomName1, 'blacklist', [user1]
                , (error) ->
                  expect(error).not.ok
                  cb()
              (cb) ->
                instance1.once 'storeConsistencyFailure', (error, data) ->
                  nextTick ->
                    room.roomState.__proto__.hasInList = orig
                    expect(error).ok
                    expect(data).an('Object')
                    expect(data).include.keys 'roomName', 'userName', 'opType'
                    expect(data.roomName).equal(roomName1)
                    expect(data.userName).equal(user1)
                    expect(data.opType).equal('roomUserlist')
                    instance1.roomStateSync roomName1
                    .then ->
                      instance1.execUserCommand true, 'roomGetAccessList'
                      , roomName1, 'userlist'
                    .spread (list) ->
                      expect(list).an('Array')
                      expect(list).empty
                    .asCallback cb
              ], done

  it 'should emit consistencyFailure on leave channel errors', (done) ->
    instance1 = startService()
    orig = instance1.transport.leaveChannel
    instance1.transport.__proto__.leaveChannel = ->
      Promise.reject new Error()
    setCustomCleanup (cb) ->
      instance1.transport.__proto__.leaveChannel = orig
      closeInstance(instance1).asCallback(cb)
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        socket1.emit 'roomJoin', roomName1, (error) ->
          expect(error).not.ok
          parallel [
            (cb) ->
              socket1.emit 'roomLeave', roomName1, (error) ->
                expect(error).not.ok
                cb()
            (cb) ->
              instance1.on 'transportConsistencyFailure', (error, data) ->
                nextTick ->
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys 'roomName', 'userName'
                  , 'id', 'opType'
                  expect(data.roomName).equal(roomName1)
                  expect(data.userName).equal(user1)
                  expect(data.id).equal(id)
                  expect(data.opType).equal('transportChannel')
                cb()
          ], done
