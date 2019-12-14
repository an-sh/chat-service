'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const { expect } = require('chai')

const { cleanup, clientConnect, startService } = require('./testutils')

const { cleanupTimeout, user1, user2, user3 } = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should check user permissions', function (done) {
    const txt = 'Test message.'
    const message = { textMessage: txt }
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket2 = clientConnect(user2)
      socket2.on('loginConfirmed', () => {
        socket2.emit('directAddToList', 'blacklist', [user1], (error, data) => {
          expect(error).not.ok
          expect(data).null
          socket1.emit('directMessage', user2, message, (error, data) => {
            expect(error).ok
            expect(data).null
            done()
          })
        })
      })
    })
  })

  it('should check user permissions in whitelist mode', function (done) {
    const txt = 'Test message.'
    const message = { textMessage: txt }
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket2 = clientConnect(user2)
      socket2.on('loginConfirmed', () => {
        socket2.emit('directAddToList', 'whitelist', [user1], (error, data) => {
          expect(error).not.ok
          expect(data).null
          socket2.emit('directSetWhitelistMode', true, (error, data) => {
            expect(error).not.ok
            expect(data).null
            socket1.emit('directMessage', user2, message, (error, data) => {
              expect(error).not.ok
              expect(data.textMessage).equal(txt)
              socket2.emit(
                'directRemoveFromList', 'whitelist', [user1], (error, data) => {
                  expect(error).not.ok
                  expect(data).null
                  socket1.emit(
                    'directMessage', user2, message, (error, data) => {
                      expect(error).ok
                      expect(data).null
                      done()
                    })
                })
            })
          })
        })
      })
    })
  })

  it('should allow an user to modify own lists', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('directAddToList', 'blacklist', [user2], (error, data) => {
        expect(error).not.ok
        expect(data).null
        socket1.emit('directGetAccessList', 'blacklist', (error, data) => {
          expect(error).not.ok
          expect(data).include(user2)
          socket1.emit(
            'directRemoveFromList', 'blacklist', [user2], (error, data) => {
              expect(error).not.ok
              expect(data).null
              socket1.emit(
                'directGetAccessList', 'blacklist', (error, data) => {
                  expect(error).not.ok
                  expect(data).not.include(user2)
                  done()
                })
            })
        })
      })
    })
  })

  it('should reject to add self to lists', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('directAddToList', 'blacklist', [user1], (error, data) => {
        expect(error).ok
        expect(data).null
        done()
      })
    })
  })

  it('should check user list names', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('directAddToList', 'nolist', [user2], (error, data) => {
        expect(error).ok
        expect(data).null
        done()
      })
    })
  })

  it('should allow duplicate adding to lists', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('directAddToList', 'blacklist', [user2], (error, data) => {
        expect(error).not.ok
        expect(data).null
        socket1.emit('directAddToList', 'blacklist', [user2], (error, data) => {
          expect(error).not.ok
          expect(data).null
          done()
        })
      })
    })
  })

  it('should allow deleting non-existing items from lists', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit(
        'directRemoveFromList', 'blacklist', [user2], (error, data) => {
          expect(error).not.ok
          expect(data).null
          done()
        })
    })
  })

  it('should allow an user to modify own mode', function (done) {
    chatService = startService({ enableDirectMessages: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('directSetWhitelistMode', true, (error, data) => {
        expect(error).not.ok
        expect(data).null
        socket1.emit('directGetWhitelistMode', (error, data) => {
          expect(error).not.ok
          expect(data).true
          done()
        })
      })
    })
  })

  it('should honour direct list size limit', function (done) {
    chatService = startService({ enableDirectMessages: true, directListSizeLimit: 1 })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit(
        'directAddToList', 'blacklist', [user2, user3], (error, data) => {
          expect(error).ok
          done()
        })
    })
  })
}
