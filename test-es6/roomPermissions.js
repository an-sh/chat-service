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

  it('should reject room messages from not joined users', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomMessage', roomName1, message, function (error, data) {
        expect(error).ok
        expect(data).null
        return socket1.emit('roomRecentHistory', roomName1, function (error, data) {
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

  it('should send a whitelistonly mode', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1
      , { whitelistOnly: true, whitelist: [user1] }
      , function () {
        socket1 = clientConnect(user1)
        return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomGetWhitelistMode', roomName1, function (error, data) {
          expect(error).not.ok
          expect(data).true
          return done()
        }
        )

        )

        )
      }
    )
  }
  )

  it('should send lists to room users', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomGetAccessList', roomName1, 'userlist'
        , function (error, data) {
          expect(error).not.ok
          expect(data).an('array')
          expect(data).include(user1)
          return done()
        }
      )

      )

      )
    }
    )
  }
  )

  it('should reject send lists to not joined users', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomGetAccessList', roomName1, 'userlist'
        , function (error, data) {
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

  it('should ckeck room list names', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomGetAccessList', roomName1, 'nolist'
        , function (error, data) {
          expect(error).ok
          expect(data).null
          return done()
        }
      )

      )

      )
    }
    )
  }
  )

  it('should allow duplicate adding to lists', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', u => socket1.emit('roomCreate', roomName1, false, () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomAddToList', roomName1, 'adminlist', [user2]
      , function (error, data) {
        expect(error).not.ok
        expect(data).null
        return socket1.emit('roomAddToList', roomName1, 'adminlist', [user2]
          , function (error, data) {
            expect(error).not.ok
            expect(data).null
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

  it('should allow not added deleting from lists', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    return socket1.on('loginConfirmed', u => socket1.emit('roomCreate', roomName1, false, () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomRemoveFromList', roomName1, 'adminlist'
      , [user2], function (error, data) {
        expect(error).not.ok
        expect(data).null
        return done()
      }
    )

    )

    )

    )
  }
  )

  it('should send access list changed messages', function (done) {
    chatService = startService({ enableAccessListsUpdates: true })
    return chatService.addRoom(roomName1, { owner: user1 }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
        socket1.emit('roomAddToList', roomName1, 'adminlist', [user3])
        return socket1.on('roomAccessListAdded', function (r, l, us) {
          expect(r).equal(roomName1)
          expect(l).equal('adminlist')
          expect(us[0]).equal(user3)
          socket1.emit('roomRemoveFromList', roomName1, 'adminlist'
            , [user3])
          return socket1.on('roomAccessListRemoved', function (r, l, us) {
            expect(r).equal(roomName1)
            expect(l).equal('adminlist')
            expect(us[0]).equal(user3)
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

  it('should send mode changed messages', function (done) {
    chatService = startService({ enableAccessListsUpdates: true })
    return chatService.addRoom(roomName1
      , { owner: user1, whitelistOnly: true }
      , function () {
        socket1 = clientConnect(user1)
        return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
          socket1.emit('roomSetWhitelistMode', roomName1, false)
          return socket1.on('roomModeChanged', function (roomName, mode) {
            expect(roomName).equal(roomName1)
            expect(mode).false
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

  it('should allow wl and bl modifications for admins', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { adminlist: [user1] }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomAddToList', roomName1, 'whitelist', [user2]
        , function (error, data) {
          expect(error).not.ok
          expect(data).null
          return socket1.emit('roomGetAccessList', roomName1, 'whitelist'
            , function (error, data) {
              expect(error).not.ok
              expect(data).include(user2)
              return socket1.emit('roomRemoveFromList', roomName1, 'whitelist'
                , [user2], function (error, data) {
                  expect(error).not.ok
                  expect(data).null
                  return socket1.emit('roomGetAccessList', roomName1, 'whitelist'
                    , function (error, data) {
                      expect(error).not.ok
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

      )
    }
    )
  }
  )

  it('should reject adminlist modifications for admins', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { adminlist: [user1, user2] }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
        socket2 = clientConnect(user2)
        return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, () => socket1.emit('roomRemoveFromList', roomName1, 'adminlist'
          , [user2] , function (error, data) {
            expect(error).ok
            expect(data).null
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
  }
  )

  it('should reject list modifications with owner for admins'
    , function (done) {
      chatService = startService({ enableRoomsManagement: true })
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomCreate', roomName1, false, () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomAddToList', roomName1, 'adminlist', [user2],
        function (error, data) {
          expect(error).not.ok
          expect(data).null
          socket2 = clientConnect(user2)
          return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, () => socket2.emit('roomAddToList', roomName1, 'whitelist'
            , [user1], function (error, data) {
              expect(error).ok
              expect(data).null
              return done()
            }
          )

          )

          )
        }
      )

      )

      )

      )
    }
  )

  it('should reject direct userlist modifications', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { adminlist: [user1] }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomAddToList', roomName1, 'userlist', [user2]
        , function (error, data) {
          expect(error).ok
          expect(data).null
          return done()
        }
      )

      )

      )
    }
    )
  }
  )

  it('should reject any lists modifications for non-admins', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomAddToList', roomName1, 'whitelist', [user2]
        , function (error, data) {
          expect(error).ok
          expect(data).null
          return done()
        }
      )

      )

      )
    }
    )
  }
  )

  it('should reject mode changes for non-admins', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, () => socket1.emit('roomSetWhitelistMode', roomName1, true
        , function (error, data) {
          expect(error).ok
          expect(data).null
          return done()
        }
      )

      )

      )
    }
    )
  }
  )

  it('should check room permissions', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { blacklist: [user1] }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function (error, data) {
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

  it('should check room permissions in whitelist mode', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1
      , { whitelist: [user2], whitelistOnly: true }
      , function () {
        socket1 = clientConnect(user1)
        return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function (error, data) {
          expect(error).ok
          expect(data).null
          socket2 = clientConnect(user2)
          return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, function (error, data) {
            expect(error).not.ok
            expect(data).equal(1)
            return done()
          }
          )

          )
        }
        )

        )
      }
    )
  }
  )

  it('should remove users on permissions changes', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { adminlist: [user1, user3] }, () => parallel([
      function (cb) {
        socket1 = clientConnect(user1)
        return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, cb)
        )
      },
      function (cb) {
        socket2 = clientConnect(user2)
        return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, cb)
        )
      },
      function (cb) {
        socket3 = clientConnect(user3)
        return socket3.on('loginConfirmed', () => socket3.emit('roomJoin', roomName1, cb)
        )
      }
    ], function (error) {
      expect(error).not.ok
      socket3.on('roomAccessRemoved', () => done(new Error('Wrong user removed.'))
      )
      return parallel([
        cb => socket1.emit('roomAddToList', roomName1, 'blacklist'
          , [user2, user3, 'nouser'], cb)
        ,
        cb => socket2.on('roomAccessRemoved', function (r) {
          expect(r).equal(roomName1)
          return cb()
        }
        )
        ,
        cb => socket1.on('roomUserLeft', function (r, u) {
          expect(r).equal(roomName1)
          expect(u).equal(user2)
          return cb()
        }
        )

      ], done)
    }
    )

    )
  }
  )

  it('should remove affected users on mode changes', function (done) {
    chatService = startService()
    return chatService.addRoom(roomName1, { adminlist: [user1] }, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
        socket2 = clientConnect(user2)
        return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, function () {
          socket1.emit('roomSetWhitelistMode', roomName1, true)
          socket1.on('roomAccessRemoved', () => done(new Error('Wrong user removed.'))
          )
          return socket2.on('roomAccessRemoved', function (r) {
            expect(r).equal(roomName1)
            return done()
          }
          )
        }
        )

        )
      }
      )

      )
    }
    )
  }
  )

  it('should remove users on permissions changes in whitelist mode'
    , function (done) {
      chatService = startService()
      return chatService.addRoom(roomName1
        , { adminlist: [user1, user3],       whitelist: [user2],       whitelistOnly: true }
        , function () {
          socket1 = clientConnect(user1)
          return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
            socket2 = clientConnect(user2)
            return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, function () {
              socket3 = clientConnect(user3)
              return socket3.on('loginConfirmed', () => socket3.emit('roomJoin', roomName1, function () {
                socket1.emit('roomRemoveFromList', roomName1
                  , 'whitelist', [user2, user3, 'nouser'])
                socket3.on('roomAccessRemoved', () => done(new Error('Wrong user removed.'))
                )
                return socket2.on('roomAccessRemoved', function (r) {
                  expect(r).equal(roomName1)
                  return done()
                }
                )
              }
              )

              )
            }
            )

            )
          }
          )

          )
        }
      )
    }
  )

  return it('should remove disconnected users' , function (done) {
    chatService = startService({ enableUserlistUpdates: true })
    return chatService.addRoom(roomName1, null, function () {
      socket1 = clientConnect(user1)
      return socket1.on('loginConfirmed', () => socket1.emit('roomJoin', roomName1, function () {
        socket2 = clientConnect(user2)
        return socket2.on('loginConfirmed', () => socket2.emit('roomJoin', roomName1, function () {
          socket2.disconnect()
          return socket1.on('roomUserLeft', function (r, u) {
            expect(r).equal(roomName1)
            expect(u).equal(user2)
            return done()
          }
          )
        }
        )

        )
      }
      )

      )
    }
    )
  }
  )
}
