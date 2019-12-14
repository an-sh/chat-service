'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const Promise = require('bluebird')
const _ = require('lodash')
const { expect } = require('chai')

const {
  cleanup, clientConnect, closeInstance,
  parallel, setCustomCleanup, startService
} = require('./testutils')

const { cleanupTimeout, user1, roomName1 } = require('./config')

module.exports = function () {
  let instance1, socket1, socket2, socket3, orig

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup([instance1], [socket1, socket2, socket3], cb)
    instance1 = socket1 = socket2 = socket3 = orig = null
  })

  it('should recover from rollback room join errors', function (done) {
    instance1 = startService()
    const { addSocketToRoom, removeSocketFromRoom } =
          instance1.state.UserState.prototype
    orig = { addSocketToRoom, removeSocketFromRoom }
    instance1.state.UserState.prototype.removeSocketFromRoom = function () {
      return Promise.reject(new Error())
    }
    instance1.state.UserState.prototype.addSocketToRoom = function () {
      return Promise.reject(new Error('This is an error mockup for testing.'))
    }
    setCustomCleanup(cb => {
      _.assign(instance1.state.UserState.prototype, orig)
      closeInstance(instance1).asCallback(cb)
    })
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        parallel([
          cb => socket1.emit('roomJoin', roomName1, (error, data) => {
            expect(error).ok
            cb()
          }),
          cb => instance1.on('storeConsistencyFailure', (error, data) => {
            process.nextTick(() => {
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys('roomName', 'userName', 'opType')
              expect(data.roomName).equal(roomName1)
              expect(data.userName).equal(user1)
              expect(data.opType).equal('userRooms')
              cb()
            })
          })
        ], error => {
          expect(error).not.ok
          _.assign(instance1.state.UserState.prototype, orig)
          instance1.roomStateSync(roomName1).then(() => Promise.join(
            instance1.execUserCommand(user1, 'listOwnSockets'),
            instance1.execUserCommand(
              true, 'roomGetAccessList', roomName1, 'userlist'),
            (sockets, [list]) => {
              expect(sockets[id]).not.exist
              expect(list).empty
            })).asCallback(done)
        })
      })
    })
  })

  it('should recover from leave room errors', function (done) {
    instance1 = startService()
    const orig = instance1.Room.prototype.leave
    instance1.Room.prototype.leave = function () {
      return Promise.reject(new Error())
    }
    setCustomCleanup(cb => {
      instance1.Room.prototype.leave = orig
      closeInstance(instance1).asCallback(cb)
    })
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, () => {
          parallel([
            cb => socket1.emit('roomLeave', roomName1, (error, data) => {
              expect(error).not.ok
              cb()
            }),
            cb => instance1.on('storeConsistencyFailure', (error, data) => {
              process.nextTick(() => {
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys('roomName', 'userName', 'opType')
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.opType).equal('roomUserlist')
                cb()
              })
            })
          ], error => {
            expect(error).not.ok
            instance1.Room.prototype.leave = orig
            instance1.roomStateSync(roomName1)
              .then(() => Promise.join(
                instance1.execUserCommand(user1, 'listOwnSockets'),
                instance1.execUserCommand(
                  true, 'roomGetAccessList', roomName1, 'userlist'),
                ([sockets], [list]) => {
                  expect(sockets[id]).to.be.an('array')
                  expect(sockets[id]).empty
                  expect(list).empty
                })).asCallback(done)
          })
        })
      })
    })
  })

  it('should recover from remove socket errors', function (done) {
    instance1 = startService()
    orig = instance1.state.UserState.prototype.removeSocket
    instance1.state.UserState.prototype.removeSocket = function () {
      return Promise.reject(new Error())
    }
    setCustomCleanup(cb => {
      instance1.state.UserState.prototype.removeSocket = orig
      closeInstance(instance1).asCallback(cb)
    })
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.disconnect()
          instance1.on('storeConsistencyFailure', (error, data) => {
            process.nextTick(() => {
              expect(error).ok
              instance1.state.UserState.prototype.removeSocket = orig
              expect(data).an('Object')
              expect(data).include.keys('userName', 'id', 'opType')
              expect(data.userName).equal(user1)
              expect(data.id).equal(id)
              expect(data.opType).equal('userSockets')
              instance1.userStateSync(user1)
                .then(() => instance1.execUserCommand(user1, 'listOwnSockets'))
                .spread(sockets => expect(sockets).empty)
                .asCallback(done)
            })
          })
        })
      })
    })
  })

  it('should recover from remove from room errors', function (done) {
    instance1 = startService()
    orig = instance1.state.UserState.prototype.removeAllSocketsFromRoom
    instance1.state.UserState.prototype.removeAllSocketsFromRoom = function () {
      return Promise.reject(new Error())
    }
    setCustomCleanup(cb => {
      instance1.state.UserState.prototype.removeAllSocketsFromRoom = orig
      closeInstance(instance1).asCallback(cb)
    })
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, () => {
          instance1.execUserCommand(
            true, 'roomAddToList', roomName1, 'blacklist', [user1],
            error => expect(error).not.ok)
          instance1.on('storeConsistencyFailure', (error, data) => {
            process.nextTick(() => {
              expect(error).ok
              instance1.state.UserState.prototype.removeAllSocketsFromRoom = orig
              expect(data).an('Object')
              expect(data).include.keys('roomName', 'userName', 'opType')
              expect(data.roomName).equal(roomName1)
              expect(data.userName).equal(user1)
              expect(data.opType).equal('roomUserlist')
              instance1.userStateSync(user1).then(() => Promise.join(
                instance1.execUserCommand(user1, 'listOwnSockets'),
                instance1.execUserCommand(
                  true, 'roomGetAccessList', roomName1, 'userlist'),
                ([sockets], [list]) => {
                  expect(sockets[id]).to.be.an('array')
                  expect(sockets[id]).empty
                  expect(list).empty
                })).asCallback(done)
            })
          })
        })
      })
    })
  })

  it('should recover from room access check errors', function (done) {
    instance1 = startService()
    orig = instance1.state.RoomState.prototype.hasInList
    setCustomCleanup(cb => {
      instance1.state.RoomState.prototype.hasInList = orig
      closeInstance(instance1).asCallback(cb)
    })
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, () => {
          instance1.state.RoomState.prototype.hasInList = function () {
            return Promise.reject(new Error())
          }
          parallel([
            cb => instance1.execUserCommand(
              true, 'roomAddToList', roomName1, 'blacklist', [user1],
              error => {
                expect(error).not.ok
                cb()
              }),
            cb => instance1.once('storeConsistencyFailure', (error, data) => {
              process.nextTick(() => {
                expect(error).ok
                instance1.state.RoomState.prototype.hasInList = orig
                expect(data).an('Object')
                expect(data).include.keys('roomName', 'userName', 'opType')
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.opType).equal('roomUserlist')
                instance1.roomStateSync(roomName1).then(
                  () => instance1.execUserCommand(
                    true, 'roomGetAccessList', roomName1, 'userlist'))
                  .spread(list => {
                    expect(list).an('Array')
                    expect(list).empty
                  }).asCallback(cb)
              })
            })
          ], done)
        })
      })
    })
  })

  it('should emit consistencyFailure on leave channel errors', function (done) {
    instance1 = startService()
    orig = instance1.leaveChannel
    instance1.transport.leaveChannel = function () {
      return Promise.reject(new Error())
    }
    setCustomCleanup(cb => {
      instance1.transport.leaveChannel = orig
      closeInstance(instance1).asCallback(cb)
    })
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, error => {
          expect(error).not.ok
          parallel([
            cb => socket1.emit('roomLeave', roomName1, error => {
              expect(error).not.ok
              cb()
            }),
            cb => instance1.on('transportConsistencyFailure', (error, data) => {
              process.nextTick(() => {
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys('roomName', 'userName', 'id', 'opType')
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.id).equal(id)
                expect(data.opType).equal('transportChannel')
                cb()
              })
            })
          ], done)
        })
      })
    })
  })
}
