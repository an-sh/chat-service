const _ = require('lodash')
const { expect } = require('chai')

const { cleanup, clientConnect, parallel, startService } = require('./testutils.coffee')

const { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2 } = require('./config.coffee')

module.exports = function() {
  let chatService = null
  let socket1 = null
  let socket2 = null
  let socket3 = null

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    return chatService = socket1 = socket2 = socket3 = null
  })

  it('should create and delete rooms', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', u => socket1.emit('roomCreate', roomName1, false, () => socket1.emit('roomJoin', roomName1, function (error, data) {
      expect(error).not.ok
      expect(data).equal(1)
      return socket1.emit('roomCreate', roomName1, false, function (error, data) {
        expect(error).ok
        expect(data).null
        socket1.emit('roomDelete', roomName1)
        return socket1.on('roomAccessRemoved', function (r) {
          expect(r).equal(roomName1)
          return socket1.emit('roomJoin', roomName1, function (error, data) {
            expect(error).ok
            expect(data).null
            return done()
          }
          )
        }
        )
      }
      )
    }
    )

    )

    )
  }
  )

  it('should reject delete rooms for non-owners', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', function (u) {
      socket1.emit('roomCreate', roomName1, false, function () {})
      socket2 = clientConnect(user2)
      return socket2.on('loginConfirmed', u => socket2.emit('roomDelete', roomName1, function (error, data) {
        expect(error).ok
        expect(data).null
        return done()
      }
      )

      )
    }
    )
  }
  )

  it('should check for invalid room names', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', u => socket1.emit('roomCreate', 'room}1', false, function (error, data) {
      expect(error).ok
      expect(data).null
      return done()
    }
    )

    )
  }
  )

  it('should reject room management when the option is disabled', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName2, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', u => socket1.emit('roomCreate', roomName1, false, function (error, data) {
        expect(error).ok
        expect(data).null
        return socket1.emit('roomDelete', roomName2, function (error, data) {
          expect(error).ok
          expect(data).null
          return done()
        }
        )
      }
      )

      )
    }
    )
  }
  )

  return it('should send access removed on a room deletion', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    return chatService.addRoom(roomName1, { owner: user1 }, () => parallel([
      function (cb) {
        socket1 = clientConnect(user1)
        return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, cb)
        )
      },
      function (cb) {
        socket2 = clientConnect(user2)
        return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, cb)
        )
      }
    ], function (error) {
      expect(error).not.ok
      return parallel([
        cb => socket1.emit('roomDelete', roomName1, cb),
        cb => socket1.on('roomAccessRemoved', function (r) {
          expect(r).equal(roomName1)
          return cb()
        }
        )
        ,
        cb => socket2.on('roomAccessRemoved', function (r) {
          expect(r).equal(roomName1)
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
