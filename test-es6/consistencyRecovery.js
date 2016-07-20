import Promise from 'bluebird'
import _ from 'lodash'
import { expect } from 'chai'

import { cleanup, clientConnect, closeInstance, nextTick, parallel, setCustomCleanup, startService } from './testutils.coffee'

import { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2 } from './config.coffee'

export default function() {
  let instance1 = null
  let socket1 = null
  let socket2 = null
  let socket3 = null

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup([instance1], [socket1, socket2, socket3], cb)
    return instance1 = socket1 = socket2 = socket3 = null
  })

  it('should recover from rollback room join errors', function (done) {
    instance1 = startService()
    return instance1.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', (userName, { id }) => instance1.state.getUser(user1)
        .then(function (user) {
          let orig1 = user.userState.removeSocketFromRoom
          let orig2 = user.userState.addSocketToRoom
          setCustomCleanup(function (cb) {
            user.userState.__proto__.removeSocketFromRoom = orig1
            user.userState.__proto__.addSocketToRoom = orig2
            return closeInstance(instance1).asCallback(cb)
          })
          user.userState.__proto__.removeSocketFromRoom = () => Promise.reject(new Error())
          user.userState.__proto__.addSocketToRoom = () => Promise.reject(new Error('This is an error mockup for testing.'))
          return parallel([
            cb => socket1.emit('roomJoin', roomName1, function (error, data) {
              expect(error).ok
              return cb()
            }
            )
            ,
            cb => instance1.on('storeConsistencyFailure', function (error, data) {
              nextTick(function () {
                expect(error).ok
                expect(data).an('Object')
                expect(data).include.keys('roomName', 'userName', 'opType')
                expect(data.roomName).equal(roomName1)
                expect(data.userName).equal(user1)
                return expect(data.opType).equal('userRooms')
              })
              return cb()
            }
            )

          ], function (error) {
            expect(error).not.ok
            user.userState.__proto__.removeSocketFromRoom = orig1
            user.userState.__proto__.addSocketToRoom = orig2
            return instance1.roomStateSync(roomName1)
              .then(() => Promise.join(instance1.execUserCommand(user1, 'listOwnSockets')
                , instance1.execUserCommand(true, 'roomGetAccessList'
                  , roomName1, 'userlist')
                , function (sockets, [list]) {
                  expect(sockets[id]).an.array
                  expect(sockets[id]).empty
                  return expect(list).empty
                }
              )
                .asCallback(done)
            )
          }
          )
        })

      )
    }
    )
  }
  )

  it('should recover from leave room errors', function (done) {
    instance1 = startService()
    return instance1.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', (userName, { id }) => socket1.emit('roomJoin', roomName1, () => instance1.state.getRoom(roomName1)
        .then(function (room) {
          let orig = room.leave
          setCustomCleanup(function (cb) {
            room.__proto__.leave = orig
            return closeInstance(instance1).asCallback(cb)
          })
          room.__proto__.leave = () => Promise.reject(new Error())
          return parallel([
            cb => socket1.emit('roomLeave', roomName1, function (error, data) {
              expect(error).not.ok
              return cb()
            }
            )
            ,
            cb => instance1.on('storeConsistencyFailure', (error, data) => nextTick(function () {
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys('roomName', 'userName', 'opType')
              expect(data.roomName).equal(roomName1)
              expect(data.userName).equal(user1)
              expect(data.opType).equal('roomUserlist')
              return cb()
            })

            )

          ], function (error) {
            expect(error).not.ok
            room.__proto__.leave = orig
            return instance1.roomStateSync(roomName1)
              .then(() => Promise.join(instance1.execUserCommand(user1, 'listOwnSockets')
                , instance1.execUserCommand(true, 'roomGetAccessList'
                  , roomName1, 'userlist')
                , function ([sockets] , [list]) {
                  expect(sockets[id]).an.array
                  expect(sockets[id]).empty
                  return expect(list).empty
                }
              )
                .asCallback(done)
            )
          }
          )
        })

      )

      )
    }
    )
  }
  )

  it('should recover from remove socket errors', function (done) {
    instance1 = startService()
    return instance1.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', (userName, { id }) => socket1.emit('roomJoin', roomName1, () => instance1.state.getUser(user1)
        .then(function (user) {
          let orig = user.userState.removeSocket
          setCustomCleanup(function (cb) {
            user.userState.__proto__.removeSocket = orig
            return closeInstance(instance1).asCallback(cb)
          })
          user.userState.__proto__.removeSocket = () => Promise.reject(new Error())
          socket1.disconnect()
          return instance1.on('storeConsistencyFailure', (error, data) => nextTick(function () {
            user.userState.__proto__.removeSocket = orig
            expect(error).ok
            expect(data).an('Object')
            expect(data).include.keys('userName', 'id', 'opType')
            expect(data.userName).equal(user1)
            expect(data.id).equal(id)
            expect(data.opType).equal('userSockets')
            return instance1.userStateSync(user1)
              .then(() => instance1.execUserCommand(user1, 'listOwnSockets'))
              .spread(sockets => expect(sockets).empty)
              .asCallback(done)
          })

          )
        })

      )

      )
    }
    )
  }
  )

  it('should recover from remove from room errors', function (done) {
    instance1 = startService()
    return instance1.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', (userName, { id }) => socket1.emit('roomJoin', roomName1, () => instance1.state.getUser(user1)
        .then(function (user) {
          let orig = user.userState.removeAllSocketsFromRoom
          setCustomCleanup(function (cb) {
            user.userState.__proto__.removeAllSocketsFromRoom = orig
            return closeInstance(instance1).asCallback(cb)
          })
          user.userState.__proto__.removeAllSocketsFromRoom = () => Promise.reject(new Error())
          instance1.execUserCommand(true
            , 'roomAddToList', roomName1, 'blacklist', [user1]
            , error => expect(error).not.ok
          )
          return instance1.on('storeConsistencyFailure', (error, data) => nextTick(function () {
            user.userState.__proto__.removeAllSocketsFromRoom = orig
            expect(error).ok
            expect(data).an('Object')
            expect(data).include.keys('roomName', 'userName', 'opType')
            expect(data.roomName).equal(roomName1)
            expect(data.userName).equal(user1)
            expect(data.opType).equal('roomUserlist')
            return instance1.userStateSync(user1)
              .then(() => Promise.join(instance1.execUserCommand(user1, 'listOwnSockets')
                , instance1.execUserCommand(true, 'roomGetAccessList'
                  , roomName1, 'userlist')
                , function ([sockets] , [list]) {
                  expect(sockets[id]).an.array
                  expect(sockets[id]).empty
                  return expect(list).empty
                }
              )
            )
              .asCallback(done)
          })

          )
        })

      )

      )
    }
    )
  }
  )

  it('should recover from room access check errors', function (done) {
    instance1 = startService()
    return instance1.addRoom(roomName1, null, () => instance1.state.getRoom(roomName1).then(function (room) {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', (userName, { id }) => socket1.emit('roomJoin', roomName1, function () {
        let orig = room.roomState.hasInList
        room.roomState.__proto__.hasInList = () => Promise.reject(new Error())
        setCustomCleanup(function (cb) {
          room.roomState.__proto__.hasInList = orig
          return closeInstance(instance1).asCallback(cb)
        })
        return parallel([
          cb => instance1.execUserCommand(true
            , 'roomAddToList', roomName1, 'blacklist', [user1]
            , function (error) {
              expect(error).not.ok
              return cb()
            }
          )
          ,
          cb => instance1.once('storeConsistencyFailure', (error, data) => nextTick(function () {
            room.roomState.__proto__.hasInList = orig
            expect(error).ok
            expect(data).an('Object')
            expect(data).include.keys('roomName', 'userName', 'opType')
            expect(data.roomName).equal(roomName1)
            expect(data.userName).equal(user1)
            expect(data.opType).equal('roomUserlist')
            return instance1.roomStateSync(roomName1)
              .then(() => instance1.execUserCommand(true, 'roomGetAccessList'
                , roomName1, 'userlist')
            )
              .spread(function (list) {
                expect(list).an('Array')
                return expect(list).empty
              })
              .asCallback(cb)
          })

          )

        ], done)
      }
      )

      )
    })

    )
  }
  )

  return it('should emit consistencyFailure on leave channel errors', function (done) {
    instance1 = startService()
    let orig = instance1.transport.leaveChannel
    instance1.transport.__proto__.leaveChannel = () => Promise.reject(new Error())
    setCustomCleanup(function (cb) {
      instance1.transport.__proto__.leaveChannel = orig
      return closeInstance(instance1).asCallback(cb)
    })
    return instance1.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', (userName, { id }) => socket1.emit('roomJoin', roomName1, function (error) {
        expect(error).not.ok
        return parallel([
          cb => socket1.emit('roomLeave', roomName1, function (error) {
            expect(error).not.ok
            return cb()
          }
          )
          ,
          cb => instance1.on('transportConsistencyFailure', function (error, data) {
            nextTick(function () {
              expect(error).ok
              expect(data).an('Object')
              expect(data).include.keys('roomName', 'userName'
                , 'id', 'opType')
              expect(data.roomName).equal(roomName1)
              expect(data.userName).equal(user1)
              expect(data.id).equal(id)
              return expect(data.opType).equal('transportChannel')
            })
            return cb()
          }
          )

        ], done)
      }
      )

      )
    }
    )
  }
  )
}
