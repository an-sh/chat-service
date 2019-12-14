'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const { expect } = require('chai')

const { cleanup, clientConnect, parallel, startService } =
        require('./testutils')

const { cleanupTimeout, user1, user2, user3, roomName1 } =
        require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should be able to disconnect all user\'s sockets', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      expect(u).equal(user1)
      socket2 = clientConnect(user1)
      socket2.on('loginConfirmed', u => {
        expect(u).equal(user1)
        parallel([
          cb => {
            chatService.disconnectUserSockets(user1)
            cb()
          },
          cb => socket1.on('disconnect', () => {
            expect(socket1.connected).not.ok
            cb()
          }),
          cb => socket2.on('disconnect', () => {
            expect(socket2.connected).not.ok
            cb()
          })
        ], done)
      })
    })
  })

  it('should be able to add users', function (done) {
    chatService = startService()
    chatService.addUser(user1, { whitelistOnly: true }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('directGetWhitelistMode', (error, data) => {
          expect(error).not.ok
          expect(data).true
          done()
        })
      })
    })
  })

  it('should be able to delete users', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      chatService.disconnectUserSockets(user1)
      socket1.on('disconnect', () => {
        chatService.hasUser(user1, (error, data) => {
          expect(error).not.ok
          expect(data).true
          chatService.deleteUser(user1, error => {
            expect(error).not.ok
            chatService.hasUser(user1, (error, data) => {
              expect(error).not.ok
              expect(data).false
              done()
            })
          })
        })
      })
    })
  })

  it('should not delete connected users', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      chatService.deleteUser(user1, error => {
        expect(error).ok
        done()
      })
    })
  })

  it('should be able to delete rooms', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { owner: user1 }, () => {
      chatService.hasRoom(roomName1, (error, data) => {
        expect(error).not.ok
        expect(data).true
        chatService.deleteRoom(roomName1, (error, data) => {
          expect(error).not.ok
          expect(data).not.ok
          chatService.hasRoom(roomName1, (error, data) => {
            expect(error).not.ok
            expect(data).false
            done()
          })
        })
      })
    })
  })

  it('should check user names before adding a new user', function (done) {
    chatService = startService()
    chatService.once('ready', () => {
      chatService.addUser('user:1', null, (error, data) => {
        expect(error).ok
        expect(data).not.ok
        done()
      })
    })
  })

  it('should check existing users before adding a new one', function (done) {
    chatService = startService()
    chatService.addUser(user1, null, () => {
      chatService.addUser(user1, null, (error, data) => {
        expect(error).ok
        expect(data).not.ok
        done()
      })
    })
  })

  it('should check commands for existence', function (done) {
    chatService = startService()
    chatService.addUser(user1, null, () => {
      chatService.execUserCommand(user1, 'nocmd', error => {
        expect(error).ok
        done()
      })
    })
  })

  it('should check for socket ids if required', function (done) {
    chatService = startService()
    chatService.addUser(user1, null, () => {
      chatService.addRoom(roomName1, null, () => {
        chatService.execUserCommand(user1, 'roomJoin', roomName1, error => {
          expect(error).ok
          done()
        })
      })
    })
  })

  it('should be able to change a room owner', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { owner: user1 }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          chatService.changeRoomOwner(roomName1, user2, (error, data) => {
            expect(error).not.ok
            expect(data).not.ok
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

  it('should be able to change a room history limit', function (done) {
    const sz = 100
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      chatService.changeRoomHistoryMaxSize(roomName1, sz, (error, data) => {
        expect(error).not.ok
        expect(data).not.ok
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', () => {
          socket1.emit('roomJoin', roomName1, () => {
            socket1.emit('roomHistoryInfo', roomName1, (error, data) => {
              expect(error).not.ok
              expect(data).ownProperty('historyMaxSize')
              expect(data.historyMaxSize).equal(sz)
              done()
            })
          })
        })
      })
    })
  })

  it('should be able to check room lists', function (done) {
    chatService = startService()
    chatService.addRoom(
      roomName1,
      { adminlist: [user1] },
      () => {
        chatService.roomHasInList(
          roomName1, 'adminlist', user1, (error, data) => {
            expect(error).not.ok
            expect(data).true
            chatService.roomHasInList(
              roomName1, 'adminlist', user2, (error, data) => {
                expect(error).not.ok
                expect(data).false
                done()
              })
          })
      })
  })

  it('should be able to check user lists', function (done) {
    chatService = startService()
    chatService.addUser(
      user1, { blacklist: [user2] },
      () => {
        chatService.userHasInList(
          user1, 'blacklist', user2, (error, data) => {
            expect(error).not.ok
            expect(data).true
            chatService.userHasInList(
              user1, 'blacklist', user3, (error, data) => {
                expect(error).not.ok
                expect(data).false
                done()
              })
          })
      })
  })

  it('should be able to leave and join sockets', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      const context = { userName: user1 }
      socket1.on('loginConfirmed', (userName, { id }) => {
        context.id = id
        chatService.execUserCommand(context, 'roomJoin', roomName1)
        socket1.on('roomJoinedEcho', (roomName, id, njoined) => {
          expect(roomName).equal(roomName1)
          expect(id).equal(context.id)
          expect(njoined).equal(1)
          const msg = { textMessage: 'Text message' }
          chatService.execUserCommand(context, 'roomMessage', roomName1, msg)
          socket1.on('roomMessage', (roomName, message) => {
            expect(roomName).equal(roomName1)
            chatService.execUserCommand(context, 'roomLeave', roomName1)
            socket1.on('roomLeftEcho', (roomName, id, njoined) => {
              expect(roomName).equal(roomName1)
              expect(id).equal(context.id)
              expect(njoined).equal(0)
              done()
            })
          })
        })
      })
    })
  })

  it('should be able to enable access lists updates', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { owner: user1 }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          chatService.changeAccessListsUpdates(roomName1, true, error => {
            expect(error).not.ok
            chatService.execUserCommand(
              user1, 'roomAddToList', roomName1, 'whitelist', [user2])
            socket1.on('roomAccessListAdded', (roomName, listName, names) => {
              expect(roomName).equal(roomName1)
              expect(listName).equal('whitelist')
              expect(names[0]).equal(user2)
              done()
            })
          })
        })
      })
    })
  })

  it('should be able to enable user list updates', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { owner: user1 }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          chatService.changeUserlistUpdates(roomName1, true, error => {
            expect(error).not.ok
            socket1.on('roomUserJoined', (roomName, userName) => {
              expect(roomName).equal(roomName1)
              expect(userName).equal(user2)
              done()
            })
            socket2 = clientConnect(user2)
            socket2.on('loginConfirmed', () => {
              socket2.emit('roomJoin', roomName1)
            })
          })
        })
      })
    })
  })
}
