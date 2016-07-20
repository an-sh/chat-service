import _ from 'lodash'
import { expect } from 'chai'

import { cleanup, clientConnect, closeInstance, parallel, startService } from './testutils.coffee'

import { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2, redisConfig } from './config.coffee'

export default function() {
  let instance1 = null
  let instance2 = null
  let socket1 = null
  let socket2 = null
  let socket3 = null
  let socket4 = null
  let socket5 = null

  afterEach(function (cb) {
    let chatService
    this.timeout(cleanupTimeout)
    cleanup([instance1, instance2], [socket1, socket2, socket3], cb)
    return chatService = socket1 = socket2 = socket3 = null
  })

  it('should send cluster bus custom messages', function (done) {
    let event = 'someEvent'
    let data = { key: 'value' }
    instance1 = startService(_.assign({port}, redisConfig))
    instance2 = startService(_.assign({port: port + 1}, redisConfig))
    return parallel([
      cb => instance1.on('ready', cb),
      cb => instance2.on('ready', cb)
    ], function (error) {
      expect(error).not.ok
      return parallel([
        cb => instance2.clusterBus.on(event, function (uid, d) {
          expect(uid).equal(instance1.instanceUID)
          expect(d).deep.equal(data)
          return cb()
        }
        )
        ,
        cb => instance1.clusterBus.on(event, function (uid, d) {
          expect(uid).equal(instance1.instanceUID)
          expect(d).deep.equal(data)
          return cb()
        }
        )
        ,
        function (cb) {
          instance1.clusterBus.emit(event, instance1.instanceUID, data)
          return cb()
        }
      ], done)
    }
    )
  }
  )

  it('should actually remove other instances sockets from channel', function (done) {
    this.timeout(4000)
    this.slow(2000)
    instance1 = startService(_.assign({port}, redisConfig))
    instance2 = startService(_.assign({port: port + 1}, redisConfig))
    return instance1.addRoom(roomName1, { owner: user2 }, () => parallel([
      function (cb) {
        socket1 = clientConnect(user1, port)
        socket1.on('roomMessage', () => done(new Error('Not removed from channel'))
        )
        return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, cb)
        )
      },
      function (cb) {
        socket2 = clientConnect(user1, port + 1)
        socket2.on('roomMessage', () => done(new Error('Not removed from channel'))
        )
        return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, cb)
        )
      },
      function (cb) {
        socket3 = clientConnect(user2, port)
        return socket3.on('loginConfirmed', () => socket3.emit('roomJoin', roomName1, cb)
        )
      }
    ], function (error) {
      expect(error).not.ok
      return socket3.emit('roomAddToList', roomName1, 'blacklist', [user1], function () {
        socket3.emit('roomMessage', roomName1, {textMessage: 'hello'})
        return setTimeout(done, 1000)
      }
      )
    }
    )

    )
  }
  )

  it('should disconnect users sockets across all instances', function (done) {
    instance1 = startService(_.assign({port}, redisConfig))
    instance2 = startService(_.assign({port: port + 1}, redisConfig))
    return parallel([
      function (cb) {
        socket1 = clientConnect(user1, port)
        return socket1.on('loginConfirmed', () => cb()
        )
      },
      function (cb) {
        socket2 = clientConnect(user1, port + 1)
        return socket2.on('loginConfirmed', () => cb()
        )
      }
    ], function (error) {
      expect(error).not.ok
      return parallel([
        cb => socket1.on('disconnect', () => cb()),
        cb => socket2.on('disconnect', () => cb()),
        function (cb) {
          instance1.disconnectUserSockets(user1)
          return cb()
        }
      ], done)
    }
    )
  }
  )

  it('should correctly update update presence info on shutdown', function (done) {
    instance1 = startService(_.assign({port}, redisConfig))
    instance2 = startService(_.assign({port: port + 1}, redisConfig))
    let ids = {}
    return instance1.addRoom(roomName1, null, () => parallel([
      function (cb) {
        socket1 = clientConnect(user1, port)
        return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, cb)
        )
      },
      function (cb) {
        socket2 = clientConnect(user2, port)
        return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, cb)
        )
      },
      function (cb) {
        socket3 = clientConnect(user2, port + 1)
        return socket3.on('loginConfirmed', function (u, d) {
          ids[d.id] = d.id
          return socket3.emit('roomJoin', roomName1, cb)
        }
        )
      },
      function (cb) {
        socket4 = clientConnect(user2, port + 1)
        return socket4.on('loginConfirmed', function (u, d) {
          ids[d.id] = d.id
          return socket4.emit('roomJoin', roomName1, cb)
        }
        )
      },
      function (cb) {
        socket5 = clientConnect(user3, port + 1)
        return socket5.on('loginConfirmed', () => socket5.emit('roomJoin', roomName1, cb)
        )
      }
    ], function (error) {
      expect(error).not.ok
      return parallel([
        cb => socket2.on('roomLeftEcho', function (roomName, id, njoined) {
          expect(roomName).equal(roomName1)
          delete ids[id]
          if (_.isEmpty(ids)) {
            expect(njoined).equal(1)
            return cb()
          }
        }
        )
        ,
        cb => socket1.on('roomUserLeft', function (roomName, userName) {
          expect(roomName).equal(roomName1)
          expect(userName).equal(user3)
          return cb()
        }
        )
        ,
        cb => socket2.on('roomUserLeft', function (roomName, userName) {
          expect(roomName).equal(roomName1)
          expect(userName).equal(user3)
          return cb()
        }
        )
        ,
        cb => closeInstance(instance2).asCallback(cb)
      ], function (error) {
        expect(error).not.ok
        return parallel([
          cb => instance1.execUserCommand(user2, 'listOwnSockets'
            , function (error, sockets) {
              expect(error).not.ok
              expect(_.size(sockets)).equal(1)
              return cb()
            }
          )
          ,
          cb => instance1.execUserCommand(user3, 'listOwnSockets'
            , function (error, sockets) {
              expect(error).not.ok
              expect(_.size(sockets)).equal(0)
              return cb()
            }
          )
          ,
          cb => socket1.emit('roomGetAccessList', roomName1, 'userlist',
            function (error, list) {
              expect(error).not.ok
              expect(list).lengthOf(2)
              expect(list).include(user1)
              expect(list).include(user2)
              return cb()
            }
          )

        ], done)
      }
      )
    }
    )

    )
  }
  )

  return it('should cleanup incorrectly shutdown instance data', function (done) {
    instance1 = startService(redisConfig)
    instance2 = startService(_.assign({port: port + 1}, redisConfig))
    let uid = instance1.instanceUID
    return instance1.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
        socket2 = clientConnect(user2)
        return socket2.on('loginConfirmed', function () {
          instance1.redis.disconnect()
          instance1.io.httpServer.close()
          clearInterval(instance1.hbtimer)
          instance1 = null
          return instance2.instanceRecovery(uid, function (error) {
            expect(error).not.ok
            return parallel([
              cb => instance2.execUserCommand(user1, 'listOwnSockets'
                , function (error, data) {
                  expect(error).not.ok
                  expect(data).empty
                  return cb()
                }
              )
              ,
              cb => instance2.execUserCommand(user2, 'listOwnSockets'
                , function (error, data) {
                  expect(error).not.ok
                  expect(data).empty
                  return cb()
                }
              )
              ,
              cb => instance2.execUserCommand(true, 'roomGetAccessList'
                , roomName1, 'userlist', function (error, data) {
                  expect(error).not.ok
                  return cb()
                }
              )

            ], done)
          }
          )
        }
        )
      }
      )

      )
    }
    )
  }
  )
}
