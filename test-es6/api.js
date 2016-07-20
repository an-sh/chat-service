import _ from 'lodash'
import { expect } from 'chai'

import { cleanup, clientConnect, parallel, startService } from './testutils.coffee'

import { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2 } from './config.coffee'

export default function() {
  let chatService = null
  let socket1 = null
  let socket2 = null
  let socket3 = null

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    return chatService = socket1 = socket2 = socket3 = null
  })

  it('should support a server side user disconnection', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      expect(u).equal(user1)
      socket2 = clientConnect(user1)
      return socket2.on('loginConfirmed', function (u) {
        expect(u).equal(user1)
        return parallel([
          function (cb) {
            chatService.disconnectUserSockets(user1)
            return cb()
          },
          cb => socket1.on('disconnect', function () {
            expect(socket1.connected).not.ok
            return cb()
          }
          )
          ,
          cb => socket2.on('disconnect', function () {
            expect(socket2.connected).not.ok
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

  it('should support adding users', function (done) {
    chatService = startService()
    return chatService.addUser(user1, { whitelistOnly: true }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('directGetWhitelistMode', function (error, data) {
        expect(error).not.ok
        expect(data).true
        return done()
      }
      )

      )
    }
    )
  }
  )

  it('should support deleting users', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function () {
      chatService.disconnectUserSockets(user1)
      return socket1.on('disconnect', () => chatService.hasUser(user1, function (error, data) {
        expect(error).not.ok
        expect(data).true
        return chatService.deleteUser(user1, function (error) {
          expect(error).not.ok
          return chatService.hasUser(user1, function (error, data) {
            expect(error).not.ok
            expect(data).false
            return done()
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

  it('should not delete connected users', function (done) {
    chatService = startService()
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', () => chatService.deleteUser(user1, function (error) {
      expect(error).ok
      return done()
    }
    )

    )
  }
  )

  it('should support deleting rooms', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { owner: user1 }, () => chatService.hasRoom(roomName1, function (error, data) {
      expect(error).not.ok
      expect(data).true
      return chatService.deleteRoom(roomName1, function (error, data) {
        expect(error).not.ok
        expect(data).not.ok
        return chatService.hasRoom(roomName1, function (error, data) {
          expect(error).not.ok
          expect(data).false
          return done()
        }
        )
      }
      )
    }
    )

    )
  }
  )

  it('should check user names before adding', function (done) {
    chatService = startService()
    return chatService.addUser('user:1', null, function (error, data) {
      expect(error).ok
      expect(data).not.ok
      return done()
    }
    )
  }
  )

  it('should check existing users before adding new ones', function (done) {
    chatService = startService()
    return chatService.addUser(user1, null, () => chatService.addUser(user1, null, function (error, data) {
      expect(error).ok
      expect(data).not.ok
      return done()
    }
    )

    )
  }
  )

  it('should check commands names.', function (done) {
    chatService = startService()
    return chatService.addUser(user1, null, () => chatService.execUserCommand(user1, 'nocmd', function (error) {
      expect(error).ok
      return done()
    }
    )

    )
  }
  )

  it('should check for socket ids if required.', function (done) {
    chatService = startService()
    return chatService.addUser(user1, null, () => chatService.execUserCommand(user1, 'roomJoin', function (error) {
      expect(error).ok
      return done()
    }
    )

    )
  }
  )

  it('should support changing a room owner', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { owner: user1 }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => chatService.changeRoomOwner(roomName1, user2, function (error, data) {
        expect(error).not.ok
        expect(data).not.ok
        return socket1.emit('roomGetOwner', roomName1, function (error, data) {
          expect(error).not.ok
          expect(data).equal(user2)
          return done()
        }
        )
      }
      )

      )

      )
    }
    )
  }
  )

  it('should support changing a room history limit', function (done) {
    let sz = 100
    chatService = startService()
    return chatService.addRoom(roomName1, null, () => chatService.changeRoomHistoryMaxSize(roomName1, sz, function (error, data) {
      expect(error).not.ok
      expect(data).not.ok
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomHistoryInfo', roomName1, function (error, data) {
        expect(error).not.ok
        expect(data).ownProperty('historyMaxSize')
        expect(data.historyMaxSize).equal(sz)
        return done()
      }
      )

      )

      )
    }
    )

    )
  }
  )

  it('should support room list checking', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { adminlist: [user1] }, () => chatService.roomHasInList(roomName1, 'adminlist', user1
      , function (error, data) {
        expect(error).not.ok
        expect(data).true
        return chatService.roomHasInList(roomName1, 'adminlist', user2
          , function (error, data) {
            expect(error).not.ok
            expect(data).false
            return done()
          }
        )
      }
    )

    )
  }
  )

  return it('should support user list checking', function (done) {
    chatService = startService()
    return chatService.addUser(user1, { blacklist: [user2] }, () => chatService.userHasInList(user1, 'blacklist', user2
      , function (error, data) {
        expect(error).not.ok
        expect(data).true
        return chatService.userHasInList(user1, 'blacklist', user3
          , function (error, data) {
            expect(error).not.ok
            expect(data).false
            return done()
          }
        )
      }
    )

    )
  }
  )
}
