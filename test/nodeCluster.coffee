
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
    instance1 = startService {port : port, state : 'redis', adapter : 'redis'}
    instance2 = startService {port : port+1, state : 'redis', adapter : 'redis'}
    instance2.clusterBus.on event, (d) ->
      expect(d).deep.equal(data)
      done()
    instance1.clusterBus.on event, ->
      done new Error 'Should not emit cluster messages to itself'
    setTimeout ->
      instance1.clusterBus.emit event, data
    , 1000
