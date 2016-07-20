/* eslint-env mocha */

const { expect } = require('chai')

const { cleanup, clientConnect, parallel, startService } =
        require('./testutils')

const { cleanupTimeout, user1, user2, user3, roomName1 } =
        require('./config')

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

  it('should get a user mode', function (done) {
    chatService = startService()
    chatService.addUser(user1, { whitelistOnly: true }, () => {
      chatService.execUserCommand(
        user1, 'directGetWhitelistMode', (error, data) => {
          expect(error).not.ok
          expect(data).true
          done()
        })
    })
  })

  it('should change user lists', function (done) {
    chatService = startService()
    chatService.addUser(user1, null, () => {
      chatService.execUserCommand(
        user1, 'directAddToList', 'whitelist', [user2], (error, data) => {
          expect(error).not.ok
          expect(data).null
          chatService.execUserCommand(
            user1, 'directGetAccessList', 'whitelist', (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0]).equal(user2)
              done()
            })
        })
    })
  })

  it('should check room names before adding', function (done) {
    chatService = startService()
    chatService.addRoom('room:1', null, (error, data) => {
      expect(error).ok
      expect(data).not.ok
      done()
    })
  })

  it('should get a room mode', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { whitelistOnly: true }, () => {
      chatService.execUserCommand(
        true, 'roomGetWhitelistMode', roomName1, (error, data) => {
          expect(error).not.ok
          expect(data).true
          done()
        })
    })
  })

  it('should change room lists', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      chatService.execUserCommand(
        true, 'roomAddToList', roomName1, 'whitelist', [user2],
        (error, data) => {
          expect(error).not.ok
          expect(data).not.ok
          chatService.execUserCommand(
            true, 'roomGetAccessList', roomName1, 'whitelist',
            (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0]).equal(user2)
              done()
            })
        })
    })
  })

  it('should send system messages to all user sockets', function (done) {
    let data = 'some data.'
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket2 = clientConnect(user1)
      socket2.on('loginConfirmed', () => parallel([
        cb => chatService.execUserCommand(user1, 'systemMessage', data, cb),
        cb => socket1.on('systemMessage', d => {
          expect(d).equal(data)
          cb()
        }),
        cb => socket2.on('systemMessage', d => {
          expect(d).equal(data)
          cb()
        })
      ], done))
    })
  })

  it('should execute commands without hooks', function (done) {
    let before = null
    let after = null
    let roomAddToListBefore = (callInfo, args, cb) => {
      before = true
      cb()
    }
    let roomAddToListAfter = (callInfo, args, results, cb) => {
      after = true
      cb()
    }
    chatService = startService(null, {roomAddToListBefore, roomAddToListAfter})
    chatService.addRoom(
      roomName1, { owner: user1 },
      () => {
        chatService.addUser(user2, null, () => {
          socket1 = clientConnect(user1)
          socket1.on('loginConfirmed', () => {
            socket1.emit('roomJoin', roomName1, () => {
              chatService.execUserCommand(
                { userName: user1, bypassHooks: true },
                'roomAddToList', roomName1, 'whitelist', [user1]
                , (error, data) => {
                  expect(error).not.ok
                  expect(before).null
                  expect(after).null
                  expect(data).null
                  done()
                })
            })
          })
        })
      })
  })

  it('should bypass user messaging permissions', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ enableDirectMessages: true })
    chatService.addUser(user1, null, () => {
      chatService.addUser(user2, {whitelistOnly: true}, () => {
        socket2 = clientConnect(user2)
        socket2.on('loginConfirmed', () => {
          chatService.execUserCommand(
            { userName: user1, bypassPermissions: true },
            'directMessage', user2, message)
          socket2.on('directMessage', msg => {
            expect(msg).include.keys('textMessage', 'author', 'timestamp')
            expect(msg.textMessage).equal(txt)
            expect(msg.author).equal(user1)
            expect(msg.timestamp).a('Number')
            done()
          })
        })
      })
    })
  })

  it('should bypass room messaging permissions', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(
      roomName1,
      { whitelistOnly: true, whitelist: [user1] },
      () =>
        chatService.addUser(
          user2, null, () => {
            socket1 = clientConnect(user1)
            socket1.on('loginConfirmed', () => {
              socket1.emit('roomJoin', roomName1, () => {
                chatService.execUserCommand(
                  { userName: user2, bypassPermissions: true },
                  'roomMessage', roomName1, message)
                socket1.on('roomMessage', (room, msg) => {
                  expect(room).equal(roomName1)
                  expect(msg.author).equal(user2)
                  expect(msg.textMessage).equal(txt)
                  expect(msg).ownProperty('timestamp')
                  expect(msg).ownProperty('id')
                  done()
                })
              })
            })
          }))
  })

  it('should send room messages without an user', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          chatService.execUserCommand(
            true, 'roomMessage', roomName1, message,
            (error, data) => expect(error).not.ok)
          socket1.on('roomMessage', (room, msg) => {
            expect(room).equal(roomName1)
            expect(room).equal(roomName1)
            expect(msg.author).undefined
            expect(msg.textMessage).equal(txt)
            expect(msg).ownProperty('timestamp')
            expect(msg).ownProperty('id')
            done()
          })
        })
      })
    })
  })

  it('should not allow using non-existing users', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      chatService.execUserCommand(
        user1, 'roomMessage', roomName1, message, (error, data) => {
          expect(error).ok
          expect(data).not.ok
          done()
        })
    })
  })

  it('should check for direct messaging permissions', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('directAddToList', 'blacklist', [user3], error => {
        expect(error).not.ok
        parallel([
          cb => {
            chatService.hasDirectAccess(user1, user2, (error, data) => {
              expect(error).not.ok
              expect(data).true
              cb()
            })
            chatService.hasDirectAccess(user1, user3, (error, data) => {
              expect(error).not.ok
              expect(data).false
              cb()
            })
          }
        ], done)
      })
    })
  })

  it('should check for room messaging permissions', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, {blacklist: [user3]}, () => parallel([
      cb => {
        chatService.hasRoomAccess(roomName1, user2, (error, data) => {
          expect(error).not.ok
          expect(data).true
          cb()
        })
        chatService.hasRoomAccess(roomName1, user3, (error, data) => {
          expect(error).not.ok
          expect(data).false
          cb()
        })
      }
    ], done))
  })
}
