const _ = require('lodash')
const { expect } = require('chai')

const { cleanup, clientConnect, parallel, series, startService } = require('./testutils.coffee')

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

  it('should emit echos for other sockets of the same user', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', function (u, data) {
        let sid1 = data.id
        socket2 = clientConnect(user1)
        return socket2.on('loginConfirmed', function (u, data) {
          let sid2 = data.id
          socket2.emit('roomJoin', roomName1)
          return socket1.on('roomJoinedEcho', function (room, id, njoined) {
            expect(room).equal(roomName1)
            expect(id).equal(sid2)
            expect(njoined).equal(1)
            socket2.emit('roomLeave', roomName1)
            return socket1.on('roomLeftEcho', function (room, id, njoined) {
              expect(room).equal(roomName1)
              expect(id).equal(sid2)
              expect(njoined).equal(0)
              return done()
            }
            )
          }
          )
        }
        )
      }
      )
    }
    )
  }
  )

  it('should emit leave echo on disconnect', function (done) {
    let sid1 = null
    let sid2 = null
    chatService = startService()
    return chatService.addRoom(roomName1, null, () => parallel([
      function (cb) {
        socket3 = clientConnect(user1)
        return socket3.on('loginConfirmed', () => cb())
      },
      function (cb) {
        socket1 = clientConnect(user1)
        return socket1.on('loginConfirmed', function (u, data) {
          sid1 = data.id
          return socket1.emit('roomJoin', roomName1, cb)
        }
        )
      },
      function (cb) {
        socket2 = clientConnect(user1)
        return socket2.on('loginConfirmed', function (u, data) {
          sid2 = data.id
          return socket2.emit('roomJoin', roomName1, cb)
        }
        )
      }
    ], function (error) {
      expect(error).not.ok
      socket2.disconnect()
      return parallel([
        cb => socket1.once('roomLeftEcho', function (room, id, njoined) {
          expect(room).equal(roomName1)
          expect(id).equal(sid2)
          expect(njoined).equal(1)
          return cb()
        }
        )
        ,
        cb => socket3.once('roomLeftEcho', function (room, id, njoined) {
          expect(room).equal(roomName1)
          expect(id).equal(sid2)
          expect(njoined).equal(1)
          return cb()
        }
        )

      ] , function () {
        socket1.disconnect()
        return socket3.on('roomLeftEcho', function (room, id, njoined) {
          expect(room).equal(roomName1)
          expect(id).equal(sid1)
          expect(njoined).equal(0)
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

  it('should update userlist on join and leave', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, () => parallel([
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
      return socket1.emit('roomGetAccessList', roomName1, 'userlist'
        , function (error, data) {
          expect(error).not.ok
          expect(data).lengthOf(2)
          expect(data).include(user1)
          expect(data).include(user2)
          return socket2.emit('roomLeave', roomName1, function (error, data) {
            expect(error).not.ok
            return socket1.emit('roomGetAccessList', roomName1, 'userlist'
              , function (error, data) {
                expect(error).not.ok
                expect(data).lengthOf(1)
                expect(data).include(user1)
                expect(data).not.include(user2)
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
  }
  )

  it('should broadcast join and leave room messages', function (done) {
    chatService = startService({ enableUserlistUpdates: true })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function (error, njoined) {
        expect(error).not.ok
        expect(njoined).equal(1)
        socket2 = clientConnect(user2)
        return socket2.on('loginConfirmed', function () {
          socket2.emit('roomJoin', roomName1)
          return socket1.on('roomUserJoined', function (room, user) {
            expect(room).equal(roomName1)
            expect(user).equal(user2)
            socket2.emit('roomLeave', roomName1)
            return socket1.on('roomUserLeft', function (room, user) {
              expect(room).equal(roomName1)
              expect(user).equal(user2)
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
    }
    )
  }
  )

  it('should update userlist on disconnect', function (done) {
    chatService = startService({ enableUserlistUpdates: true })
    return chatService.addRoom(roomName1, null, () => parallel([
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
      return socket1.emit('roomGetAccessList', roomName1, 'userlist'
        , function (error, data) {
          expect(error).not.ok
          expect(data).lengthOf(2)
          expect(data).include(user1)
          expect(data).include(user2)
          socket2.disconnect()
          return socket1.once('roomUserLeft', () => socket1.emit('roomGetAccessList', roomName1, 'userlist'
            , function (error, data) {
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data).include(user1)
              expect(data).not.include(user2)
              return done()
            }
          )

          )
        }
      )
    }
    )

    )
  }
  )

  it('should store and send room history', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomMessage', roomName1, message, function (error, data) {
        expect(error).not.ok
        expect(data).a('Number')
        return socket1.emit('roomRecentHistory', roomName1, function (error, data) {
          expect(error).not.ok
          expect(data).length(1)
          expect(data[0]).include.keys('textMessage', 'author'
            , 'timestamp', 'id')
          expect(data[0].textMessage).equal(txt)
          expect(data[0].author).equal(user1)
          expect(data[0].timestamp).a('Number')
          expect(data[0].id).equal(1)
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

  it('should send room messages to all joined users', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    return chatService.addRoom(roomName1, null, () => parallel([
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
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.on('roomMessage', function (room, msg) {
          expect(room).equal(roomName1)
          expect(msg.author).equal(user1)
          expect(msg.textMessage).equal(txt)
          expect(msg).ownProperty('timestamp')
          expect(msg).ownProperty('id')
          return cb()
        }
        )
        ,
        cb => socket2.on('roomMessage', function (room, msg) {
          expect(room).equal(roomName1)
          expect(msg.author).equal(user1)
          expect(msg.textMessage).equal(txt)
          expect(msg).ownProperty('timestamp')
          expect(msg).ownProperty('id')
          return cb()
        }
        )

      ], done)
    }
    )

    )
  }
  )

  it('should drop history if limit is zero', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ defaultHistoryLimit: 0 })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomMessage', roomName1, message, () => socket1.emit('roomRecentHistory', roomName1, function (error, data) {
        expect(error).not.ok
        expect(data).empty
        return done()
      }
      )

      )

      )

      )
    }
    )
  }
  )

  it('should not send history if get limit is zero', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ historyMaxGetMessages: 0 })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomMessage', roomName1, message, (error, data) => socket1.emit('roomRecentHistory', roomName1, function (error, data) {
        expect(error).not.ok
        expect(data).empty
        return socket1.emit('roomHistoryGet', roomName1, 0, 10, function (error, data) {
          expect(error).not.ok
          expect(data).empty
          return done()
        }
        )
      }
      )

      )

      )

      )
    }
    )
  }
  )

  it('should send room history maximum size', function (done) {
    let sz = 1000
    chatService = startService({ defaultHistoryLimit: sz })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomHistoryInfo', roomName1, function (error, data) {
        expect(error).not.ok
        expect(data.historyMaxSize).equal(sz)
        return done()
      }
      )

      )

      )
    }
    )
  }
  )

  it('should truncate long history', function (done) {
    let txt1 = 'Test message 1.'
    let message1 = { textMessage: txt1 }
    let txt2 = 'Test message 2.'
    let message2 = { textMessage: txt2 }
    chatService = startService({ defaultHistoryLimit: 1 })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomMessage', roomName1, message1
        , (error, data) => socket1.emit('roomMessage', roomName1, message2
          , (error, data) => socket1.emit('roomRecentHistory', roomName1, function (error, data) {
            expect(error).not.ok
            expect(data).length(1)
            expect(data[0]).include.keys('textMessage', 'author'
              , 'timestamp', 'id')
            expect(data[0].textMessage).equal(txt2)
            expect(data[0].author).equal(user1)
            expect(data[0].timestamp).a('Number')
            expect(data[0].id).equal(2)
            return done()
          }
          )

        )

      )

      )

      )
    }
    )
  }
  )

  it('should sync history', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return series([
        cb => socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, cb)
        )
        ,
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb)
      ], function (error) {
        expect(error).not.ok
        return parallel([
          cb => socket1.emit('roomHistoryGet', roomName1, 0, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(2)
            expect(data[0]).include.keys('textMessage', 'author'
              , 'timestamp', 'id')
            expect(data[0].textMessage).equal(txt)
            expect(data[0].author).equal(user1)
            expect(data[0].timestamp).a('Number')
            expect(data[0].id).equal(2)
            expect(data[1].id).equal(1)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 1, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(1)
            expect(data[0].id).equal(2)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 2, 10, function (error, data) {
            expect(error).not.ok
            expect(data).empty
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

  it('should sync history with respect to the max get', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ historyMaxGetMessages: 2 })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return series([
        cb => socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, cb)
        )
        ,
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb)
      ], function (error) {
        expect(error).not.ok
        return parallel([
          cb => socket1.emit('roomHistoryGet', roomName1, 0, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(2)
            expect(data[0].id).equal(2)
            expect(data[1].id).equal(1)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 1, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(2)
            expect(data[0].id).equal(3)
            expect(data[1].id).equal(2)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 2, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(1)
            expect(data[0].id).equal(3)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 3, 10, function (error, data) {
            expect(error).not.ok
            expect(data).empty
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

  it('should sync history with respect to a history size', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ defaultHistoryLimit: 2 })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return series([
        cb => socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, cb)
        )
        ,
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb)
      ], function (error) {
        expect(error).not.ok
        return parallel([
          cb => socket1.emit('roomHistoryGet', roomName1, 0, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(2)
            expect(data[0].id).equal(3)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 1, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(2)
            expect(data[0].id).equal(3)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 2, 10, function (error, data) {
            expect(error).not.ok
            expect(data).lengthOf(1)
            expect(data[0].id).equal(3)
            return cb()
          }
          )
          ,
          cb => socket1.emit('roomHistoryGet', roomName1, 3, 10, function (error, data) {
            expect(error).not.ok
            expect(data).empty
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

  it('should return and update room sync info', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomHistoryInfo', roomName1, function (error, data) {
        expect(error).not.ok
        expect(data).ownProperty('historyMaxGetMessages')
        expect(data).ownProperty('historyMaxSize')
        expect(data).ownProperty('historySize')
        expect(data).ownProperty('lastMessageId')
        expect(data.lastMessageId).equal(0)
        expect(data.historySize).equal(0)
        return socket1.emit('roomMessage', roomName1, message, () => socket1.emit('roomHistoryInfo', roomName1, function (error, data) {
          expect(error).not.ok
          expect(data.lastMessageId).equal(1)
          expect(data.historySize).equal(1)
          return done()
        }
        )

        )
      }
      )

      )

      )
    }
    )
  }
  )

  it('should get and update user seen info', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      let ts = new Date().getTime()
      let tsmax = ts + 2000
      return parallel([
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
        return socket1.emit('roomUserSeen', roomName1, user2, function (error, info1) {
          expect(error).not.ok
          expect(info1).an('object')
          expect(info1.joined).true
          expect(info1.timestamp).a('Number')
          expect(info1.timestamp).within(ts, tsmax)
          return socket2.emit('roomLeave', roomName1, () => socket1.emit('roomUserSeen', roomName1, user2, function (error, info2) {
            expect(info2).an('object')
            expect(info2.joined).false
            expect(info2.timestamp).a('Number')
            expect(info2.timestamp).within(ts, tsmax)
            expect(info2.timestamp).least(info1.timestamp)
            return done()
          }
          )

          )
        }
        )
      }
      )
    }
    )
  }
  )

  it('should get empty seen info for unseen users', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomUserSeen', roomName1, user2, function (error, info) {
        expect(error).not.ok
        expect(info).an('object')
        expect(info.joined).false
        expect(info.timestamp).null
        return done()
      }
      )

      )

      )
    }
    )
  }
  )

  return it('should list own sockets with rooms', function (done) {
    chatService = startService()
    let { sid1, sid2, sid3 } = {}
    return chatService.addRoom(roomName1, null, () => chatService.addRoom(roomName2, null, () => parallel([
      function (cb) {
        socket1 = clientConnect(user1)
        return socket1.on('loginConfirmed', function (u, data) {
          sid1 = data.id
          return socket1.emit('roomJoin', roomName1, () => socket1.emit('roomJoin', roomName2, cb)
          )
        }
        )
      },
      function (cb) {
        socket2 = clientConnect(user1)
        return socket2.on('loginConfirmed', function (u, data) {
          sid2 = data.id
          return socket2.emit('roomJoin', roomName1, cb)
        }
        )
      },
      function (cb) {
        socket3 = clientConnect(user1)
        return socket3.on('loginConfirmed', function (u, data) {
          sid3 = data.id
          return cb()
        }
        )
      }
    ], function (error) {
      expect(error).not.ok
      return socket2.emit('listOwnSockets', function (error, data) {
        expect(error).not.ok
        expect(data[sid1]).lengthOf(2)
        expect(data[sid2]).lengthOf(1)
        expect(data[sid3]).lengthOf(0)
        expect(data[sid1]).include
          .members([roomName1, roomName2])
        expect(data[sid1]).include(roomName1)
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
