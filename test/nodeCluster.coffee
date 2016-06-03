
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
    instance2.clusterBus.on event, (uid, d) ->
      expect(uid).equal(instance1.instanceUID)
      expect(d).deep.equal(data)
      done()
    instance1.clusterBus.on event, ->
      done new Error 'Should not emit cluster messages to itself'
    async.parallel [
      (cb) ->
        instance1.on 'ready', cb
      (cb) ->
        instance2.on 'ready', cb
    ], (error) ->
      expect(error).not.ok
      instance1.clusterBus.emit event, data
