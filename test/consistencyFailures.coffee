
Promise = require 'bluebird'
_ = require 'lodash'
expect = require('chai').expect

{ cleanup
  clientConnect
  nextTick
  parallel
  setCustomCleanup
  startService
} = require './testutils.coffee'

{ port
  user1
  user2
  user3
  roomName1
  roomName2
  redisConfig
} = require './config.coffee'

module.exports = ->

  instance1 = null
  instance2 = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEach (cb) ->
    cleanup [instance1, instance2], [socket1, socket2, socket3], cb
    instance1 = socket1 = socket2 = socket3 = null

  it 'should cleanup incorrectly shutdown instance data', (done) ->
    instance1 = startService redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    uid = instance1.instanceUID
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket2 = clientConnect user2
          socket2.on 'loginConfirmed', ->
            instance1.redis.disconnect()
            instance1.io.httpServer.close()
            instance1 = null
            instance2.instanceRecovery uid, (error) ->
              expect(error).not.ok
              parallel [
                (cb) ->
                  instance2.execUserCommand user1, 'listOwnSockets'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                (cb) ->
                  instance2.execUserCommand user2, 'listOwnSockets'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                (cb) ->
                  instance2.execUserCommand true, 'roomGetAccessList'
                  , roomName1, 'userlist', (error, data) ->
                    expect(error).not.ok
                    cb()
              ], done

  it 'should emit consistencyFailure on leave channel errors', (done) ->
    instance1 = startService redisConfig
    orig = instance1.transport.leaveChannel
    instance1.transport.__proto__.leaveChannel = ->
      Promise.reject new Error()
    setCustomCleanup (cb) ->
      instance1.transport.__proto__.leaveChannel = orig
      instance1.close cb
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

  it 'should emit consistencyFailure on room access check errors', (done) ->
    instance1 = startService redisConfig
    instance1.addRoom roomName1, null, ->
      instance1.state.getRoom(roomName1).then (room) ->
        orig = room.roomState.hasInList
        room.roomState.__proto__.hasInList = ->
          Promise.reject new Error()
        setCustomCleanup (cb) ->
          room.roomState.__proto__.hasInList = orig
          instance1.close cb
        parallel [
          (cb) ->
            instance1.execUserCommand true
            , 'roomRemoveFromList', roomName1, 'whitelist', [user1]
            , (error) ->
              expect(error).not.ok
              cb()
          (cb) ->
            instance1.once 'storeConsistencyFailure', (error, data) ->
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
          parallel [
            (cb) ->
              instance1.execUserCommand true
              , 'roomAddToList', roomName1, 'whitelist', [user1]
              , (error) ->
                expect(error).not.ok
                cb()
            (cb) ->
              instance1.once 'storeConsistencyFailure', (error, data) ->
                nextTick ->
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys 'roomName', 'userName', 'opType'
                  expect(data.roomName).equal(roomName1)
                  expect(data.userName).equal(user1)
                  expect(data.opType).equal('roomUserlist')
                  cb()
          ], done

  it 'should emit consistencyFailure on rollback room join errors', (done) ->
    instance1 = startService redisConfig
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        instance1.state.getUser user1
        .then (user) ->
          orig1 = user.userState.removeSocketFromRoom
          orig2 = instance1.transport.joinChannel
          user.userState.__proto__.removeSocketFromRoom = ->
            Promise.reject new Error()
          instance1.transport.joinChannel = ->
            Promise.reject new Error()
          setCustomCleanup (cb) ->
            user.userState.__proto__.removeSocketFromRoom =  orig1
            instance1.transport.joinChannel = orig2
            instance1.close cb
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
          ], done

  it 'should emit consistencyFailure on leave room errors', (done) ->
    instance1 = startService redisConfig
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          instance1.state.getRoom roomName1
          .then (room) ->
            orig = room.leave
            room.__proto__.leave = ->
              Promise.reject new Error()
            setCustomCleanup (cb) ->
              room.__proto__.leave = orig
              instance1.close cb
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
            ], done

  it 'should emit consistencyFailure on remove socket errors', (done) ->
    instance1 = startService redisConfig
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', (userName, { id }) ->
        socket1.emit 'roomJoin', roomName1, ->
          instance1.state.getUser user1
          .then (user) ->
            orig = user.userState.removeSocket
            user.userState.__proto__.removeSocket = ->
              Promise.reject new Error()
            setCustomCleanup (cb) ->
              user.userState.__proto__.removeSocket = orig
              instance1.close cb
            socket1.disconnect()
            instance1.on 'storeConsistencyFailure', (error, data) ->
              nextTick ->
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'userName', 'id', 'opType'
                expect(data.userName).equal(user1)
                expect(data.id).equal(id)
                expect(data.opType).equal('userSockets')
                done()

  it 'should emit consistencyFailure on on remove from room errors', (done) ->
    instance1 = startService redisConfig
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          instance1.state.getUser user1
          .then (user) ->
            orig = user.userState.removeAllSocketsFromRoom
            user.userState.__proto__.removeAllSocketsFromRoom = ->
              Promise.reject new Error()
            setCustomCleanup (cb) ->
              user.userState.__proto__.removeAllSocketsFromRoom = orig
              instance1.close cb
            instance1.execUserCommand true
            , 'roomAddToList', roomName1, 'blacklist', [user1]
            , (error) ->
              expect(error).not.ok
            instance1.on 'storeConsistencyFailure', (error, data) ->
              nextTick ->
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys 'roomName', 'userName', 'opType'
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.opType).equal('roomUserlist')
                done()
