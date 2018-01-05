'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const { expect } = require('chai')

const { cleanup, clientConnect, startService } = require('./testutils')

const { cleanupTimeout, user1, roomName1 } = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

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
        expect(error.name).equal('ChatServiceError')
        expect(error.code).equal('noRoom')
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

  it('should have a message validation method', function (done) {
    chatService = startService()
    chatService.once('ready', () => {
      chatService.checkArguments(
        'roomGetAccessList', roomName1, 'userlist', function (error) {
          expect(error).not.ok
          done()
        })
    })
  })

  it('should check for unknown commands', function (done) {
    chatService = startService()
    chatService.once('ready', () => {
      chatService.validator.checkArguments('cmd', function (error) {
        expect(error).ok
        done()
      })
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
}
