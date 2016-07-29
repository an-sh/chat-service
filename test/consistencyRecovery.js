/* eslint-env mocha */
/*eslint no-proto: 0*/

const Promise = require('bluebird')
const { expect } = require('chai')

const { cleanup, clientConnect, closeInstance, nextTick,
        parallel, setCustomCleanup, startService } = require('./testutils')

const { cleanupTimeout, user1, roomName1 } = require('./config')

module.exports = function () {
  let instance1, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup([instance1], [socket1, socket2, socket3], cb)
    instance1 = socket1 = socket2 = socket3 = null
  })

  it('should recover from rollback room join errors', function (done) {
    instance1 = startService()
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        instance1.state.getUser(user1).then(user => {
          let orig1 = user.userState.removeSocketFromRoom
          let orig2 = user.userState.addSocketToRoom
          setCustomCleanup(cb => {
            user.userState.__proto__.removeSocketFromRoom = orig1
            user.userState.__proto__.addSocketToRoom = orig2
            closeInstance(instance1).asCallback(cb)
          })
          user.userState.__proto__.removeSocketFromRoom = function () {
            return Promise.reject(new Error())
          }
          user.userState.__proto__.addSocketToRoom = function () {
            return Promise.reject(
              new Error('This is an error mockup for testing.'))
          }
          parallel([
            cb => socket1.emit('roomJoin', roomName1, (error, data) => {
              expect(error).ok
              cb()
            }),
            cb => instance1.on('storeConsistencyFailure', (error, data) => {
              nextTick(() => {
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
            user.userState.__proto__.removeSocketFromRoom = orig1
            user.userState.__proto__.addSocketToRoom = orig2
            instance1.roomStateSync(roomName1)
              .then(() => Promise.join(
                instance1.execUserCommand(user1, 'listOwnSockets'),
                instance1.execUserCommand(
                  true, 'roomGetAccessList', roomName1, 'userlist'),
                (sockets, [list]) => {
                  expect(sockets[id]).an.array
                  expect(sockets[id]).empty
                  expect(list).empty
                }).asCallback(done))
          })
        })
      })
    })
  })

  it('should recover from leave room errors', function (done) {
    instance1 = startService()
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, () => {
          instance1.state.getRoom(roomName1).then(room => {
            let orig = room.leave
            setCustomCleanup(cb => {
              room.__proto__.leave = orig
              closeInstance(instance1).asCallback(cb)
            })
            room.__proto__.leave = function () {
              return Promise.reject(new Error())
            }
            parallel([
              cb => socket1.emit('roomLeave', roomName1, (error, data) => {
                expect(error).not.ok
                cb()
              }),
              cb => instance1.on('storeConsistencyFailure', (error, data) => {
                nextTick(() => {
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
              room.__proto__.leave = orig
              instance1.roomStateSync(roomName1)
                .then(() => Promise.join(
                  instance1.execUserCommand(user1, 'listOwnSockets'),
                  instance1.execUserCommand(
                    true, 'roomGetAccessList', roomName1, 'userlist'),
                  ([sockets], [list]) => {
                    expect(sockets[id]).an.array
                    expect(sockets[id]).empty
                    expect(list).empty
                  }).asCallback(done))
            })
          })
        })
      })
    })
  })

  it('should recover from remove socket errors', function (done) {
    instance1 = startService()
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, () => {
          instance1.state.getUser(user1).then(user => {
            let orig = user.userState.removeSocket
            setCustomCleanup(cb => {
              user.userState.__proto__.removeSocket = orig
              closeInstance(instance1).asCallback(cb)
            })
            user.userState.__proto__.removeSocket = function () {
              return Promise.reject(new Error())
            }
            socket1.disconnect()
            instance1.on('storeConsistencyFailure', (error, data) => {
              nextTick(() => {
                user.userState.__proto__.removeSocket = orig
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys('userName', 'id', 'opType')
                expect(data.userName).equal(user1)
                expect(data.id).equal(id)
                expect(data.opType).equal('userSockets')
                instance1.userStateSync(user1)
                  .then(() =>
                        instance1.execUserCommand(user1, 'listOwnSockets'))
                  .spread(sockets => expect(sockets).empty)
                  .asCallback(done)
              })
            })
          })
        })
      })
    })
  })

  it('should recover from remove from room errors', function (done) {
    instance1 = startService()
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, { id }) => {
        socket1.emit('roomJoin', roomName1, () => {
          instance1.state.getUser(user1).then(user => {
            let orig = user.userState.removeAllSocketsFromRoom
            setCustomCleanup(cb => {
              user.userState.__proto__.removeAllSocketsFromRoom = orig
              closeInstance(instance1).asCallback(cb)
            })
            user.userState.__proto__.removeAllSocketsFromRoom = function () {
              return Promise.reject(new Error())
            }
            instance1.execUserCommand(
              true, 'roomAddToList', roomName1, 'blacklist', [user1],
              error => expect(error).not.ok)
            instance1.on('storeConsistencyFailure', (error, data) => {
              nextTick(() => {
                user.userState.__proto__.removeAllSocketsFromRoom = orig
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys('roomName', 'userName', 'opType')
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                expect(data.opType).equal('roomUserlist')
                instance1.userStateSync(user1).then(() => {
                  return Promise.join(
                    instance1.execUserCommand(user1, 'listOwnSockets'),
                    instance1.execUserCommand(
                      true, 'roomGetAccessList', roomName1, 'userlist'),
                    ([sockets], [list]) => {
                      expect(sockets[id]).an.array
                      expect(sockets[id]).empty
                      expect(list).empty
                    })
                }).asCallback(done)
              })
            })
          })
        })
      })
    })
  })

  it('should recover from room access check errors', function (done) {
    instance1 = startService()
    instance1.addRoom(roomName1, null, () => {
      instance1.state.getRoom(roomName1).then(room => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', (userName, { id }) => {
          socket1.emit('roomJoin', roomName1, () => {
            let orig = room.roomState.hasInList
            room.roomState.__proto__.hasInList = function () {
              return Promise.reject(new Error())
            }
            setCustomCleanup(cb => {
              room.roomState.__proto__.hasInList = orig
              closeInstance(instance1).asCallback(cb)
            })
            parallel([
              cb => instance1.execUserCommand(
                true, 'roomAddToList', roomName1, 'blacklist', [user1],
                error => {
                  expect(error).not.ok
                  cb()
                }),
              cb => instance1.once('storeConsistencyFailure', (error, data) => {
                nextTick(() => {
                  room.roomState.__proto__.hasInList = orig
                  expect(error).ok
                  expect(data).an('Object')
                  expect(data).include.keys('roomName', 'userName', 'opType')
                  expect(data.roomName).equal(roomName1)
                  expect(data.userName).equal(user1)
                  expect(data.opType).equal('roomUserlist')
                  return instance1.roomStateSync(roomName1).then(() => {
                    return instance1.execUserCommand(
                      true, 'roomGetAccessList', roomName1, 'userlist')
                  }).spread(list => {
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
  })

  it('should emit consistencyFailure on leave channel errors', function (done) {
    instance1 = startService()
    let orig = instance1.transport.leaveChannel
    instance1.transport.__proto__.leaveChannel = function () {
      return Promise.reject(new Error())
    }
    setCustomCleanup(cb => {
      instance1.transport.__proto__.leaveChannel = orig
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
              nextTick(() => {
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys('roomName', 'userName'
                                          , 'id', 'opType')
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
