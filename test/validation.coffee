
ChatService = require('../index.js')
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

  it 'should return raw error objects', (done) ->
    chatService = startService { useRawErrorObjects : true }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      socket1.emit 'roomGetAccessList', roomName1, 'nolist', (error) ->
        expect(error.name).equal('noRoom')
        expect(error.args).length.above(0)
        expect(error.args[0]).equal('room1')
        done()

  it 'should validate message argument types', (done) ->
    chatService = startService { enableRoomsManagement : true }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      socket1.emit 'roomCreate', null, false, (error, data) ->
        expect(error).ok
        expect(data).not.ok
        done()

  it 'should have a message validator instance', (done) ->
    chatService = startService()
    chatService.validator.checkArguments 'roomGetAccessList'
      , roomName1, 'userlist', (error) ->
        expect(error).not.ok
        done()

  it 'should check for unknown commands', (done) ->
    chatService = startService()
    chatService.validator.checkArguments 'cmd', (error) ->
      expect(error).ok
      done()

  it 'should validate a message argument count', (done) ->
    chatService = startService { enableRoomsManagement : true }
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      socket1.emit 'roomCreate', (error, data) ->
        expect(error).ok
        expect(data).not.ok
        done()

  it 'should have a server messages and user commands fields', (done) ->
    chatService = startService()
    for k, fn of chatService.serverMessages
      fn()
    for k, fn of chatService.userCommands
      fn()
    process.nextTick -> done()
