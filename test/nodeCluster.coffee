
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
  redisConfig
} = require './config.coffee'

module.exports = ->

  @timeout 5000
  @slow 2500

  instance1 = null
  instance2 = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEach (cb) ->
    cleanup [instance1, instance2], [socket1, socket2, socket3], cb
    chatService = socket1 = socket2 = socket3 = null

  it 'should send cluster bus custom messages', (done) ->
    event = 'someEvent'
    data = { key : 'value' }
    instance1 = startService _.assign {port : port}, redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    async.parallel [
      (cb) ->
        instance1.on 'ready', cb
      (cb) ->
        instance2.on 'ready', cb
    ], (error) ->
      expect(error).not.ok
      async.parallel [
        (cb) ->
          instance2.clusterBus.on event, (uid, d) ->
            expect(uid).equal(instance1.instanceUID)
            expect(d).deep.equal(data)
            cb()
        (cb) ->
          instance1.clusterBus.on event, (uid, d) ->
            expect(uid).equal(instance1.instanceUID)
            expect(d).deep.equal(data)
            cb()
        (cb) ->
          instance1.clusterBus.emit event, data
          cb()
      ], done

  it 'should actually remove other instances sockets from channel', (done) ->
    instance1 = startService _.assign {port : port}, redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    instance1.addRoom roomName1, { owner : user2 }, ->
      socket1 = clientConnect user1, port
      socket2 = clientConnect user2, port+1
      async.parallel [
        (cb) ->
          socket1 = clientConnect user1, port
          socket1.on 'roomMessage', ->
            done new Error 'Not removed from channel'
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket2 = clientConnect user1, port+1
          socket2.on 'roomMessage', ->
            done new Error 'Not removed from channel'
          socket2.on 'loginConfirmed', ->
            socket2.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket3 = clientConnect user2, port
          socket3.on 'loginConfirmed', ->
            socket3.emit 'roomJoin', roomName1, cb
      ], (error) ->
        expect(error).not.ok
        socket3.emit 'roomAddToList', roomName1, 'blacklist', [user1], ->
          socket3.emit 'roomMessage', roomName1, {textMessage : 'hello'}
          setTimeout done, 1000
