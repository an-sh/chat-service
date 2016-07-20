/* eslint-env mocha */

const { expect } = require('chai')

const { cleanup, clientConnect, startService } = require('./testutils')

const { cleanupTimeout, user1, roomName1 } = require('./config')

module.exports = function () {
  let chatService = null
  let socket1 = null
  let socket2 = null
  let socket3 = null

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should return raw error objects', function (done) {
    chatService = startService({ useRawErrorObjects: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('roomGetAccessList', roomName1, 'nolist', function (error) {
        expect(error.name).equal('noRoom')
        expect(error.args).length.above(0)
        expect(error.args[0]).equal('room1')
        done()
      })
    })
  })

  it('should validate message argument types', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', null, false, function (error, data) {
        expect(error).ok
        expect(data).not.ok
        done()
      })
    })
  })

  it('should have a message validator instance', function (done) {
    chatService = startService()
    chatService.validator.checkArguments(
      'roomGetAccessList', roomName1, 'userlist', function (error) {
        expect(error).not.ok
        done()
      })
  })

  it('should check for unknown commands', function (done) {
    chatService = startService()
    chatService.validator.checkArguments('cmd', function (error) {
      expect(error).ok
      done()
    })
  })

  it('should validate a message argument count', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', function (error, data) {
        expect(error).ok
        expect(data).not.ok
        done()
      })
    })
  })

  it('should have a server messages and user commands fields', function (done) {
    chatService = startService()
    for (var k in chatService.serverMessages) {
      var fn = chatService.serverMessages[k]
      fn()
    }
    for (k in chatService.userCommands) {
      fn = chatService.userCommands[k]
      fn()
    }
    for (k in chatService.HooksInterface) {
      fn = chatService.HooksInterface[k]
      fn()
    }
    process.nextTick(done)
  })
}
