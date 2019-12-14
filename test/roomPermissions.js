'use strict'
/* eslint-env mocha */
/* eslint-disable no-unused-expressions */

const { expect } = require('chai')

const {
  cleanup, clientConnect, parallel,
  startService
} = require('./testutils')

const {
  cleanupTimeout, user1, user2, user3,
  roomName1
} = require('./config')

module.exports = function () {
  let chatService, socket1, socket2, socket3

  afterEach(function (cb) {
    this.timeout(cleanupTimeout)
    cleanup(chatService, [socket1, socket2, socket3], cb)
    chatService = socket1 = socket2 = socket3 = null
  })

  it('should reject room messages from not joined users', function (done) {
    const txt = 'Test message.'
    const message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomMessage', roomName1, message, (error, data) => {
          expect(error).ok
          expect(data).null
          socket1.emit('roomRecentHistory', roomName1, (error, data) => {
            expect(error).ok
            expect(data).null
            done()
          })
        })
      })
    })
  })

  it('should send a whitelistonly mode', function (done) {
    chatService = startService()
    chatService.addRoom(
      roomName1,
      { whitelistOnly: true, whitelist: [user1] },
      () => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', () => {
          socket1.emit('roomJoin', roomName1, () => {
            socket1.emit('roomGetWhitelistMode', roomName1, (error, data) => {
              expect(error).not.ok
              expect(data).true
              done()
            })
          })
        })
      })
  })

  it('should send lists to room users', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomGetAccessList', roomName1, 'userlist', (error, data) => {
              expect(error).not.ok
              expect(data).an('array')
              expect(data).include(user1)
              done()
            })
        })
      })
    })
  })

  it('should reject send lists to not joined users', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit(
          'roomGetAccessList', roomName1, 'userlist', (error, data) => {
            expect(error).ok
            expect(data).null
            done()
          })
      })
    })
  })

  it('should check room list names', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomGetAccessList', roomName1, 'nolist', (error, data) => {
              expect(error).ok
              expect(data).null
              done()
            })
        })
      })
    })
  })

  it('should allow duplicate adding to lists', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', roomName1, false, () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomAddToList', roomName1, 'adminlist', [user2],
            (error, data) => {
              expect(error).not.ok
              expect(data).null
              socket1.emit(
                'roomAddToList', roomName1, 'adminlist', [user2]
                , (error, data) => {
                  expect(error).not.ok
                  expect(data).null
                  done()
                })
            })
        })
      })
    })
  })

  it('should allow deleting non-existing items from lists', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', u => {
      socket1.emit('roomCreate', roomName1, false, () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomRemoveFromList', roomName1, 'adminlist', [user2],
            (error, data) => {
              expect(error).not.ok
              expect(data).null
              done()
            })
        })
      })
    })
  })

  it('should send access list changed messages', function (done) {
    chatService = startService({ enableAccessListsUpdates: true })
    chatService.addRoom(roomName1, { owner: user1 }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomAddToList', roomName1, 'adminlist', [user3])
          socket1.on('roomAccessListAdded', (r, l, us) => {
            expect(r).equal(roomName1)
            expect(l).equal('adminlist')
            expect(us[0]).equal(user3)
            socket1.emit('roomRemoveFromList', roomName1, 'adminlist', [user3])
            socket1.on('roomAccessListRemoved', (r, l, us) => {
              expect(r).equal(roomName1)
              expect(l).equal('adminlist')
              expect(us[0]).equal(user3)
              done()
            })
          })
        })
      })
    })
  })

  it('should send mode changed messages', function (done) {
    chatService = startService({ enableAccessListsUpdates: true })
    chatService.addRoom(
      roomName1,
      { owner: user1, whitelistOnly: true },
      () => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', () => {
          socket1.emit('roomJoin', roomName1, () => {
            socket1.emit('roomSetWhitelistMode', roomName1, false)
            socket1.on('roomModeChanged', (roomName, mode) => {
              expect(roomName).equal(roomName1)
              expect(mode).false
              done()
            })
          })
        })
      })
  })

  it('should allow wl and bl modifications for admins', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { adminlist: [user1] }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomAddToList', roomName1, 'whitelist', [user2], (error, data) => {
              expect(error).not.ok
              expect(data).null
              socket1.emit(
                'roomGetAccessList', roomName1, 'whitelist', (error, data) => {
                  expect(error).not.ok
                  expect(data).include(user2)
                  socket1.emit(
                    'roomRemoveFromList', roomName1, 'whitelist', [user2],
                    (error, data) => {
                      expect(error).not.ok
                      expect(data).null
                      socket1.emit(
                        'roomGetAccessList', roomName1, 'whitelist',
                        (error, data) => {
                          expect(error).not.ok
                          expect(data).not.include(user2)
                          done()
                        })
                    })
                })
            })
        })
      })
    })
  })

  it('should reject adminlist modifications for admins', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { adminlist: [user1, user2] }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed', () => {
            socket2.emit('roomJoin', roomName1, () => {
              socket1.emit(
                'roomRemoveFromList', roomName1, 'adminlist', [user2],
                (error, data) => {
                  expect(error).ok
                  expect(data).null
                  done()
                })
            })
          })
        })
      })
    })
  })

  it('should reject list modifications with owner for admins', function (done) {
    chatService = startService({ enableRoomsManagement: true })
    socket1 = clientConnect(user1)
    socket1.on('loginConfirmed', () => {
      socket1.emit('roomCreate', roomName1, false, () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomAddToList', roomName1, 'adminlist', [user2], (error, data) => {
              expect(error).not.ok
              expect(data).null
              socket2 = clientConnect(user2)
              socket2.on('loginConfirmed', () => {
                socket2.emit('roomJoin', roomName1, () => {
                  socket2.emit(
                    'roomAddToList', roomName1, 'whitelist', [user1],
                    (error, data) => {
                      expect(error).ok
                      expect(data).null
                      done()
                    })
                })
              })
            })
        })
      })
    })
  })

  it('should reject to modify userlists directly', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { adminlist: [user1] }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomAddToList', roomName1, 'userlist', [user2], (error, data) => {
              expect(error).ok
              expect(data).null
              done()
            })
        })
      })
    })
  })

  it('should reject any lists modifications for non-admins', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomAddToList', roomName1, 'whitelist', [user2], (error, data) => {
              expect(error).ok
              expect(data).null
              done()
            })
        })
      })
    })
  })

  it('should reject mode changes for non-admins', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit(
            'roomSetWhitelistMode', roomName1, true, (error, data) => {
              expect(error).ok
              expect(data).null
              done()
            })
        })
      })
    })
  })

  it('should check room permissions', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, { blacklist: [user1] }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, (error, data) => {
          expect(error).ok
          expect(data).null
          done()
        })
      })
    })
  })

  it('should check room permissions in whitelist mode', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1
      , { whitelist: [user2], whitelistOnly: true }
      , () => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', () => {
          socket1.emit('roomJoin', roomName1, (error, data) => {
            expect(error).ok
            expect(data).null
            socket2 = clientConnect(user2)
            socket2.on('loginConfirmed', () => {
              socket2.emit('roomJoin', roomName1, (error, data) => {
                expect(error).not.ok
                expect(data).equal(1)
                done()
              })
            })
          })
        })
      })
  })

  it('should remove users on permissions changes', function (done) {
    this.timeout(4000)
    this.slow(2000)
    chatService = startService({ enableUserlistUpdates: true })
    chatService.addRoom(
      roomName1, { adminlist: [user1, user3] }, () => parallel([
        cb => {
          socket1 = clientConnect(user1)
          socket1.on('loginConfirmed',
            () => socket1.emit('roomJoin', roomName1, cb))
        },
        cb => {
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed',
            () => socket2.emit('roomJoin', roomName1, cb))
        },
        cb => {
          socket3 = clientConnect(user3)
          socket3.on('loginConfirmed',
            () => socket3.emit('roomJoin', roomName1, cb))
        }
      ], error => {
        expect(error).not.ok
        socket3.on('roomAccessRemoved',
          () => done(new Error('Wrong user removed.')))
        parallel([
          cb => socket1.emit('roomAddToList', roomName1,
            'blacklist', [user2, user3, 'nouser'], cb),
          cb => socket2.on('roomAccessRemoved', r => {
            expect(r).equal(roomName1)
            cb()
          }),
          cb => socket1.on('roomUserLeft', (r, u) => {
            expect(r).equal(roomName1)
            expect(u).equal(user2)
            cb()
          })
        ], error => setTimeout(done, 1000, error))
      })
    )
  })

  it('should remove affected users on mode changes', function (done) {
    this.timeout(4000)
    this.slow(2000)
    chatService = startService()
    chatService.addRoom(roomName1, { adminlist: [user1] }, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed', () => {
            socket2.emit('roomJoin', roomName1, () => {
              socket1.emit('roomSetWhitelistMode', roomName1, true)
              socket1.on('roomAccessRemoved', () => {
                done(new Error('Wrong user removed.'))
              })
              socket2.on('roomAccessRemoved', r => {
                expect(r).equal(roomName1)
                setTimeout(done, 1000)
              })
            })
          })
        })
      })
    })
  })

  it('should remove users on permissions changes in wl mode', function (done) {
    this.timeout(4000)
    this.slow(2000)
    chatService = startService()
    chatService.addRoom(
      roomName1,
      { adminlist: [user1, user3], whitelist: [user2], whitelistOnly: true },
      () => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', () => {
          socket1.emit('roomJoin', roomName1, () => {
            socket2 = clientConnect(user2)
            socket2.on('loginConfirmed', () => {
              socket2.emit('roomJoin', roomName1, () => {
                socket3 = clientConnect(user3)
                socket3.on('loginConfirmed', () => {
                  socket3.emit('roomJoin', roomName1, () => {
                    socket1.emit('roomRemoveFromList', roomName1
                      , 'whitelist', [user2, user3, 'nouser'])
                    socket3.on('roomAccessRemoved', () =>
                      done(new Error('Wrong user removed.')))
                    socket2.on('roomAccessRemoved', r => {
                      expect(r).equal(roomName1)
                      setTimeout(done, 1000)
                    })
                  })
                })
              })
            })
          })
        })
      })
  })

  it('should honour room list size limit', function (done) {
    chatService = startService({ roomListSizeLimit: 1 })
    chatService.addRoom(
      roomName1, { owner: user1 },
      () => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', () => {
          socket1.emit(
            'roomAddToList', roomName1, 'blacklist', [user2, user3],
            (error, data) => {
              expect(error).ok
              done()
            })
        })
      })
  })
}
