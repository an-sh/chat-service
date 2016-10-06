'use strict'
/* eslint-env mocha */

const Buffer = require('safe-buffer').Buffer
const Promise = require('bluebird')
const { expect } = require('chai')

const { cleanup, clientConnect, closeInstance,
        nextTick, ChatService, startService } = require('./testutils')

const { cleanupTimeout, user1, user2,
        roomName1, roomName2 } = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should execute onStart hook', function (done) {
    let onStart = (server, cb) => {
      expect(server).instanceof(ChatService)
      server.addRoom(
        roomName1, { whitelist: [ user1 ], owner: user2 }, cb)
    }
    chatService = startService(null, {onStart})
    chatService.on('ready', () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomGetAccessList', roomName1, 'whitelist', (error, list) => {
              expect(error).not.ok
              expect(list).include(user1)
              socket1.emit('roomGetOwner', roomName1, (error, data) => {
                expect(error).not.ok
                expect(data).equal(user2)
                done()
              })
            })
        })
      })
    })
  })

  it('should exectute onClose hook', function (done) {
    let onClose = (server, error, cb) => {
      expect(server).instanceof(ChatService)
      expect(error).not.ok
      nextTick(cb)
    }
    let chatService1 = startService(null, {onClose})
    closeInstance(chatService1).asCallback(done)
  })

  it('should execute before and after hooks', function (done) {
    let someData = 'data'
    let before, after, sid
    let roomCreateBefore = (execInfo, cb) => {
      let { server, userName, id, args } = execInfo
      let [name, mode] = args
      expect(server).instanceof(ChatService)
      expect(userName).equal(user1)
      expect(id).equal(sid)
      expect(args).instanceof(Array)
      expect(name).a('string')
      expect(mode).a('boolean')
      expect(cb).instanceof(Function)
      before = true
      nextTick(cb)
    }
    let roomCreateAfter = (execInfo, cb) => {
      let { server, userName, id, args, results, error } = execInfo
      let [name, mode] = args
      expect(server).instanceof(ChatService)
      expect(userName).equal(user1)
      expect(id).equal(sid)
      expect(args).instanceof(Array)
      expect(name).a('string')
      expect(mode).a('boolean')
      expect(results).instanceof(Array)
      expect(error).null
      expect(cb).instanceof(Function)
      after = true
      nextTick(cb, null, someData)
    }
    chatService = startService({ enableRoomsManagement: true },
                               { roomCreateBefore, roomCreateAfter })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u, data) => {
      sid = data.id
      socket1.emit('roomCreate', roomName1, true, (error, data) => {
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        done()
      })
    })
  })

  it('should execute hooks using promises api', function (done) {
    let someData = 'data'
    let before, after
    let roomCreateBefore = execInfo => {
      before = true
      return Promise.resolve()
    }
    let roomCreateAfter = execInfo => {
      after = true
      return Promise.resolve(someData)
    }
    chatService = startService({ enableRoomsManagement: true },
                               { roomCreateBefore, roomCreateAfter })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('roomCreate', roomName1, true, (error, data) => {
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        done()
      })
    })
  })

  it('should execute hooks with sync callbacks', function (done) {
    let someData = 'data'
    let before, after
    let roomCreateBefore = (execInfo, cb) => {
      before = true
      cb()
    }
    let roomCreateAfter = (execInfo, cb) => {
      after = true
      cb(null, someData)
    }
    chatService = startService({ enableRoomsManagement: true },
                               { roomCreateBefore, roomCreateAfter })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('roomCreate', roomName1, true, (error, data) => {
        expect(error).not.ok
        expect(before).true
        expect(after).true
        expect(data).equal(someData)
        done()
      })
    })
  })

  it('should store commands additional arguments', function (done) {
    let listOwnSocketsAfter = (execInfo, cb) => {
      let { restArgs } = execInfo
      expect(restArgs).instanceof(Array)
      expect(restArgs).lengthOf(1)
      expect(restArgs[0]).true
      nextTick(cb)
    }
    chatService = startService(null, {listOwnSocketsAfter})
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('listOwnSockets', true, (error, data) => {
        expect(error).not.ok
        done()
      })
    })
  })

  it('should support changing arguments in before hooks', function (done) {
    let roomGetWhitelistModeBefore = (execInfo, cb) => {
      execInfo.args = [roomName2]
      nextTick(cb)
    }
    chatService = startService({ enableRoomsManagement: true },
                               { roomGetWhitelistModeBefore })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('roomCreate', roomName2, false, () => {
        socket1.emit('roomCreate', roomName1, true, () => {
          socket1.emit('roomGetWhitelistMode', roomName1, (error, data) => {
            expect(error).not.ok
            expect(data).false
            done()
          })
        })
      })
    })
  })

  it('should support additional values from after hooks', function (done) {
    let listOwnSocketsAfter = (execInfo, cb) =>
          nextTick(cb, null, ...execInfo.results, true)
    chatService = startService(null, { listOwnSocketsAfter })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', (u, data) => {
      let sid = data.id
      socket1.emit('listOwnSockets', (error, data, moredata) => {
        expect(error).not.ok
        expect(data[sid]).exits
        expect(data[sid]).empty
        expect(moredata).true
        done()
      })
    })
  })

  it('should execute onDisconnect hook', function (done) {
    let onDisconnect = (server, data, cb) => {
      nextTick(() => {
        expect(server).instanceof(ChatService)
        expect(data).an.Object
        expect(data.id).a.string
        expect(data.nconnected).a.Number
        expect(data.roomsRemoved).an.Array
        expect(data.joinedSockets).an.Array
        done()
      })
      nextTick(cb)
    }
    let chatService1 = startService(null, { onDisconnect })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => chatService1.close())
  })

  it('should execute onJoin hook', function (done) {
    let isRun = false
    let onJoin = (server, data, cb) => {
      nextTick(() => {
        if (!isRun) {
          expect(server).instanceof(ChatService)
          expect(data).an.Object
          expect(data.id).a.string
          expect(data.njoined).eql(1)
          expect(data.roomName).equal(roomName1)
          isRun = true
        }
      })
      cb()
    }
    chatService = startService(null, { onJoin })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          expect(isRun).true
          done()
        })
      })
    })
  })

  it('should execute onLeave hook when leaving', function (done) {
    let isRun = false
    let onLeave = (server, data, cb) => {
      nextTick(() => {
        if (!isRun) {
          expect(server).instanceof(ChatService)
          expect(data).an.Object
          expect(data.id).a.string
          expect(data.njoined).eql(0)
          expect(data.roomName).equal(roomName1)
          isRun = true
        }
        cb()
      })
    }
    chatService = startService(null, { onLeave })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomLeave', roomName1, () => {
            expect(isRun).true
            done()
          })
        })
      })
    })
  })

  it('should execute onLeave hook when disconnecting', function (done) {
    let isRun = false
    let id
    let onLeave = (server, data, cb) => {
      nextTick(() => {
        if (!isRun) {
          expect(server).instanceof(ChatService)
          expect(data).an.Object
          expect(data.id).a.string
          expect(data.id).eql(id)
          expect(data.njoined).eql(1)
          expect(data.roomName).equal(roomName1)
          isRun = true
        }
      })
      cb()
    }
    chatService = startService(null, { onLeave })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, data) => {
        id = data.id
        socket1.emit('roomJoin', roomName1, () => {
          socket2 = clientConnect(user1)
          socket2.on('loginConfirmed', () => {
            socket2.emit('roomJoin', roomName1, () => {
              socket1.disconnect()
              socket2.on('socketDisconnectEcho', () => {
                expect(isRun).true
                done()
              })
            })
          })
        })
      })
    })
  })

  it('should execute onLeave hook when removing', function (done) {
    let isRun = false
    let id
    let onLeave = (server, data, cb) => {
      nextTick(() => {
        if (!isRun) {
          expect(server).instanceof(ChatService)
          expect(data).an.Object
          expect(data.id).a.string
          expect(data.id).eql(id)
          expect(data.njoined).eql(0)
          expect(data.roomName).equal(roomName1)
          isRun = true
        }
      })
      cb()
    }
    chatService = startService(null, { onLeave })
    chatService.addRoom(roomName1, {owner: user2}, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (userName, data) => {
        id = data.id
        socket1.emit('roomJoin', roomName1, () => {
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed', () => {
            socket2.emit('roomAddToList', roomName1, 'blacklist', [user1])
            socket1.on('roomAccessRemoved', (roomName) => {
              expect(roomName).eql(roomName1)
              expect(isRun).true
              done()
            })
          })
        })
      })
    })
  })

  it('should stop commands if before hook returns a data', function (done) {
    let val = 'asdf'
    let listOwnSocketsBefore = (execInfo, cb) => nextTick(cb, null, val)
    chatService = startService(null, { listOwnSocketsBefore })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('listOwnSockets', (error, data) => {
        expect(error).null
        expect(data).equal(val)
        done()
      })
    })
  })

  it('should accept custom direct messages using a hook', function (done) {
    let html = '<b>HTML message.</b>'
    let message = { htmlMessage: html }
    let directMessagesChecker = (msg, cb) => nextTick(cb)
    chatService =
      startService({ enableDirectMessages: true }, { directMessagesChecker })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket2 = clientConnect(user2)
      socket2.on('loginConfirmed', () => {
        socket1.emit('directMessage', user2, message)
        socket2.on('directMessage', msg => {
          expect(msg).include.keys('htmlMessage', 'author', 'timestamp')
          expect(msg.htmlMessage).equal(html)
          expect(msg.author).equal(user1)
          expect(msg.timestamp).a('Number')
          done()
        })
      })
    })
  })

  it('should accept custom room messages using a hook', function (done) {
    let html = '<b>HTML message.</b>'
    let message = { htmlMessage: html }
    let roomMessagesChecker = (msg, cb) => nextTick(cb)
    chatService = startService(null, { roomMessagesChecker })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomMessage', roomName1, message)
          socket1.on('roomMessage', (room, msg) => {
            expect(room).equal(roomName1)
            expect(msg).include.keys('htmlMessage', 'author', 'timestamp', 'id')
            expect(msg.htmlMessage).equal(html)
            expect(msg.author).equal(user1)
            expect(msg.timestamp).a('Number')
            expect(msg.id).equal(1)
            done()
          })
        })
      })
    })
  })

  it('should correctly send room messages with a binary data', function (done) {
    let data = Buffer.from([5])
    let message = { data }
    let roomMessagesChecker = (msg, cb) => nextTick(cb)
    chatService = startService(null, { roomMessagesChecker })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomMessage', roomName1, message)
          socket1.on('roomMessage', (room, msg) => {
            expect(room).equal(roomName1)
            expect(msg).include.keys('data', 'author', 'timestamp', 'id')
            expect(msg.data).deep.equal(data)
            expect(msg.author).equal(user1)
            expect(msg.timestamp).a('Number')
            expect(msg.id).equal(1)
            socket1.emit('roomRecentHistory', roomName1, (error, data) => {
              expect(error).not.ok
              expect(data[0]).deep.equal(msg)
              done()
            })
          })
        })
      })
    })
  })
}
