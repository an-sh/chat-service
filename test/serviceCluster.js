'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const _ = require('lodash')
const { expect } = require('chai')

const {
  cleanup, clientConnect, closeInstance,
  parallel, startService
} = require('./testutils')

const {
  cleanupTimeout, port, user1, user2, user3,
  roomName1, redisConfig
} = require('./config')

module.exports = function () {
  let instance1, instance2, socket1, socket2, socket3, socket4, socket5

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup([instance1, instance2], [socket1, socket2, socket3], cb)
    instance1 = instance2 = null
    socket1 = socket2 = socket3 = socket4 = socket5 = null
  })

  it('should be able to send custom messages via a bus', function (done) {
    const event = 'someEvent'
    const data = { key: 'value' }
    instance1 = startService(_.assign({ port }, redisConfig))
    instance2 = startService(_.assign({ port: port + 1 }, redisConfig))
    parallel([
      cb => instance1.on('ready', cb),
      cb => instance2.on('ready', cb)
    ], error => {
      expect(error).not.ok
      parallel([
        cb => instance2.clusterBus.on(event, (uid, d) => {
          expect(uid).equal(instance1.instanceUID)
          expect(d).deep.equal(data)
          cb()
        }),
        cb => instance1.clusterBus.on(event, (uid, d) => {
          expect(uid).equal(instance1.instanceUID)
          expect(d).deep.equal(data)
          cb()
        }),
        cb => {
          instance1.clusterBus.emit(event, instance1.instanceUID, data)
          cb()
        }
      ], done)
    })
  })

  it('should remove other instances\' sockets from a channel', function (done) {
    this.timeout(4000)
    this.slow(2000)
    instance1 = startService(_.assign({ port }, redisConfig))
    instance2 = startService(_.assign({ port: port + 1 }, redisConfig))
    instance1.addRoom(roomName1, { owner: user2 }, () => parallel([
      cb => {
        socket1 = clientConnect(user1, port)
        socket1.on('roomMessage',
          () => done(new Error('Not removed from channel')))
        socket1.on('loginConfirmed',
          () => socket1.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket2 = clientConnect(user1, port + 1)
        socket2.on('roomMessage',
          () => done(new Error('Not removed from channel')))
        socket2.on('loginConfirmed',
          () => socket2.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket3 = clientConnect(user2, port)
        socket3.on('loginConfirmed',
          () => socket3.emit('roomJoin', roomName1, cb))
      }
    ], error => {
      expect(error).not.ok
      socket3.emit('roomAddToList', roomName1, 'blacklist', [user1], () => {
        socket3.emit('roomMessage', roomName1, { textMessage: 'hello' })
        setTimeout(done, 1000)
      })
    }))
  })

  it('should disconnect users sockets across all instances', function (done) {
    instance1 = startService(_.assign({ port }, redisConfig))
    instance2 = startService(_.assign({ port: port + 1 }, redisConfig))
    parallel([
      cb => {
        socket1 = clientConnect(user1, port)
        socket1.on('loginConfirmed', () => cb())
      },
      cb => {
        socket2 = clientConnect(user1, port + 1)
        socket2.on('loginConfirmed', () => cb())
      }
    ], error => {
      expect(error).not.ok
      parallel([
        cb => socket1.on('disconnect', () => cb()),
        cb => socket2.on('disconnect', () => cb()),
        cb => {
          instance1.disconnectUserSockets(user1)
          cb()
        }
      ], done)
    })
  })

  it('should correctly update a presence info on a shutdown', function (done) {
    const enableUserlistUpdates = true
    instance1 = startService(_.assign({ port, enableUserlistUpdates },
      redisConfig))
    instance2 = startService(_.assign({ port: port + 1, enableUserlistUpdates },
      redisConfig))
    const ids = {}
    instance1.addRoom(roomName1, null, () => parallel([
      cb => {
        socket1 = clientConnect(user1, port)
        socket1.on('loginConfirmed',
          () => socket1.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket2 = clientConnect(user2, port)
        socket2.on('loginConfirmed',
          () => socket2.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket3 = clientConnect(user2, port + 1)
        socket3.on('loginConfirmed', (u, d) => {
          ids[d.id] = d.id
          socket3.emit('roomJoin', roomName1, cb)
        })
      },
      cb => {
        socket4 = clientConnect(user2, port + 1)
        socket4.on('loginConfirmed', (u, d) => {
          ids[d.id] = d.id
          socket4.emit('roomJoin', roomName1, cb)
        })
      },
      cb => {
        socket5 = clientConnect(user3, port + 1)
        socket5.on('loginConfirmed',
          () => socket5.emit('roomJoin', roomName1, cb))
      }
    ], error => {
      expect(error).not.ok
      parallel([
        cb => socket2.on('roomLeftEcho', (roomName, id, njoined) => {
          expect(roomName).equal(roomName1)
          delete ids[id]
          if (_.isEmpty(ids)) {
            expect(njoined).equal(1)
            cb()
          }
        }),
        cb => socket1.on('roomUserLeft', (roomName, userName) => {
          expect(roomName).equal(roomName1)
          expect(userName).equal(user3)
          cb()
        }),
        cb => socket2.on('roomUserLeft', (roomName, userName) => {
          expect(roomName).equal(roomName1)
          expect(userName).equal(user3)
          cb()
        }),
        cb => closeInstance(instance2).asCallback(cb)
      ], error => {
        expect(error).not.ok
        parallel([
          cb => instance1.execUserCommand(
            user2, 'listOwnSockets', (error, sockets) => {
              expect(error).not.ok
              expect(_.size(sockets)).equal(1)
              cb()
            }),
          cb => instance1.execUserCommand(
            user3, 'listOwnSockets', (error, sockets) => {
              expect(error).not.ok
              expect(_.size(sockets)).equal(0)
              cb()
            }),
          cb => socket1.emit(
            'roomGetAccessList', roomName1, 'userlist', (error, list) => {
              expect(error).not.ok
              expect(list).lengthOf(2)
              expect(list).include(user1)
              expect(list).include(user2)
              cb()
            })
        ], done)
      })
    }))
  })

  it('should be able to cleanup an instance data', function (done) {
    instance1 = startService(redisConfig)
    instance2 = startService(_.assign({ port: port + 1 }, redisConfig))
    const uid = instance1.instanceUID
    instance1.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed', () => {
            clearInterval(instance1.hbtimer)
            instance2.instanceRecovery(uid, error => {
              expect(error).not.ok
              parallel([
                cb => instance2.execUserCommand(
                  user1, 'listOwnSockets', (error, data) => {
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                  }),
                cb => instance2.execUserCommand(
                  user2, 'listOwnSockets', (error, data) => {
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                  }),
                cb => instance2.execUserCommand(
                  true, 'roomGetAccessList', roomName1, 'userlist',
                  (error, data) => {
                    expect(error).not.ok
                    cb()
                  })
              ], done)
            })
          })
        })
      })
    })
  })
}
