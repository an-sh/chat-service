'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const { expect } = require('chai')

const {
  cleanup, clientConnect,
  parallel, startService
} = require('./testutils')

const {
  cleanupTimeout, user1, user2,
  roomName1, roomName2
} = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should allow to create and delete rooms', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', roomName1, false, () => {
        socket1.emit('roomJoin', roomName1, (error, data) => {
          expect(error).not.ok
          expect(data).equal(1)
          socket1.emit('roomCreate', roomName1, false, (error, data) => {
            expect(error).ok
            expect(data).null
            socket1.emit('roomDelete', roomName1)
            socket1.on('roomAccessRemoved', r => {
              expect(r).equal(roomName1)
              socket1.emit('roomJoin', roomName1, (error, data) => {
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

  it('should be able to delete empty rooms', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', roomName1, false, () => {
        socket1.emit('roomDelete', roomName1, (error, data) => {
          expect(error).not.ok
          expect(data).null
          done()
        })
      })
    })
  })

  it('should reject to delete a room for a non-owner', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', roomName1, false, () => {
        socket2 = clientConnect(user2)
        socket2.on('loginConfirmed', () => {
          socket2.emit('roomDelete', roomName1, (error, data) => {
            expect(error).ok
            expect(data).null
            done()
          })
        })
      })
    })
  })

  it('should check for an invalid room names', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', 'room}1', false, (error, data) => {
        expect(error).ok
        expect(data).null
        done()
      })
    })
  })

  it('should reject room management when the option is off', function (done) {
    chatService = startService()
    chatService.addRoom(roomName2, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', u => {
        socket1.emit('roomCreate', roomName1, false, (error, data) => {
          expect(error).ok
          expect(data).null
          socket1.emit('roomDelete', roomName2, (error, data) => {
            expect(error).ok
            expect(data).null
            done()
          })
        })
      })
    })
  })

  it('should send access removed on a room deletion', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    chatService.addRoom(roomName1, { owner: user1 }, () => parallel([
      cb => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed',
          () => socket1.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket2 = clientConnect(user2)
        socket2.on('loginConfirmed',
          () => socket2.emit('roomJoin', roomName1, cb))
      }
    ], error => {
      expect(error).not.ok
      parallel([
        cb => socket1.emit('roomDelete', roomName1, cb),
        cb => socket1.on('roomAccessRemoved', r => {
          expect(r).equal(roomName1)
          cb()
        }),
        cb => socket2.on('roomAccessRemoved', r => {
          expect(r).equal(roomName1)
          cb()
        })
      ], done)
    }))
  })
}
