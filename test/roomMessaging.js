/* eslint-env mocha */

const { expect } = require('chai')

const { cleanup, clientConnect,
        parallel, series, startService } = require('./testutils')

const { cleanupTimeout, user1, user2,
        roomName1, roomName2 } = require('./config')

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

  it('should emit echos to a non-joined user\'s socket', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (u, data) => {
        socket2 = clientConnect(user1)
        socket2.on('loginConfirmed', (u, data) => {
          let sid2 = data.id
          socket2.emit('roomJoin', roomName1)
          socket1.on('roomJoinedEcho', (room, id, njoined) => {
            expect(room).equal(roomName1)
            expect(id).equal(sid2)
            expect(njoined).equal(1)
            socket2.emit('roomLeave', roomName1)
            socket1.on('roomLeftEcho', (room, id, njoined) => {
              expect(room).equal(roomName1)
              expect(id).equal(sid2)
              expect(njoined).equal(0)
              done()
            })
          })
        })
      })
    })
  })

  it('should emit echos to a joined user\'s socket', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', (u, data) => {
        socket1.emit('roomJoin', roomName1, () => {
          socket2 = clientConnect(user1)
          socket2.on('loginConfirmed', (u, data) => {
            let sid2 = data.id
            socket2.emit('roomJoin', roomName1)
            socket1.on('roomJoinedEcho', (room, id, njoined) => {
              expect(room).equal(roomName1)
              expect(id).equal(sid2)
              expect(njoined).equal(2)
              socket2.emit('roomLeave', roomName1)
              socket1.on('roomLeftEcho', (room, id, njoined) => {
                expect(room).equal(roomName1)
                expect(id).equal(sid2)
                expect(njoined).equal(1)
                done()
              })
            })
          })
        })
      })
    })
  })

  it('should emit leave echo on a disconnect', function (done) {
    let sid1 = null
    let sid2 = null
    chatService = startService()
    chatService.addRoom(roomName1, null, () => parallel([
      cb => {
        socket3 = clientConnect(user1)
        socket3.on('loginConfirmed', () => cb())
      },
      cb => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed', (u, data) => {
          sid1 = data.id
          socket1.emit('roomJoin', roomName1, cb)
        })
      },
      cb => {
        socket2 = clientConnect(user1)
        socket2.on('loginConfirmed', (u, data) => {
          sid2 = data.id
          socket2.emit('roomJoin', roomName1, cb)
        })
      }
    ], error => {
      expect(error).not.ok
      socket2.disconnect()
      parallel([
        cb => socket1.once('roomLeftEcho', (room, id, njoined) => {
          expect(room).equal(roomName1)
          expect(id).equal(sid2)
          expect(njoined).equal(1)
          cb()
        }),
        cb => socket3.once('roomLeftEcho', (room, id, njoined) => {
          expect(room).equal(roomName1)
          expect(id).equal(sid2)
          expect(njoined).equal(1)
          cb()
        })

      ], () => {
        socket1.disconnect()
        socket3.on('roomLeftEcho', (room, id, njoined) => {
          expect(room).equal(roomName1)
          expect(id).equal(sid1)
          expect(njoined).equal(0)
          done()
        })
      })
    }))
  })

  it('should remove disconnected users', function (done) {
    chatService = startService({ enableUserlistUpdates: true })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed', () => {
            socket2.emit('roomJoin', roomName1, () => {
              socket2.disconnect()
              socket1.on('roomUserLeft', (r, u) => {
                expect(r).equal(roomName1)
                expect(u).equal(user2)
                done()
              })
            })
          })
        })
      })
    })
  })

  it('should update userlist on join and leave operations', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => parallel([
      cb => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed',
                   () => socket1.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket2 = clientConnect(user2)
        socket2.on('loginConfirmed',
                   () => socket2.emit('roomJoin', roomName1, cb))
      }
    ], error => {
      expect(error).not.ok
      socket1.emit(
        'roomGetAccessList', roomName1, 'userlist', (error, data) => {
          expect(error).not.ok
          expect(data).lengthOf(2)
          expect(data).include(user1)
          expect(data).include(user2)
          socket2.emit('roomLeave', roomName1, (error, data) => {
            expect(error).not.ok
            socket1.emit(
              'roomGetAccessList', roomName1, 'userlist', (error, data) => {
                expect(error).not.ok
                expect(data).lengthOf(1)
                expect(data).include(user1)
                expect(data).not.include(user2)
                done()
              })
          })
        })
    }))
  })

  it('should broadcast join and leave room messages', function (done) {
    chatService = startService({ enableUserlistUpdates: true })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, (error, njoined) => {
          expect(error).not.ok
          expect(njoined).equal(1)
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed', () => {
            socket2.emit('roomJoin', roomName1)
            socket1.on('roomUserJoined', (room, user) => {
              expect(room).equal(roomName1)
              expect(user).equal(user2)
              socket2.emit('roomLeave', roomName1)
              socket1.on('roomUserLeft', (room, user) => {
                expect(room).equal(roomName1)
                expect(user).equal(user2)
                done()
              })
            })
          })
        })
      })
    })
  })

  it('should update userlist on a disconnect', function (done) {
    chatService = startService({ enableUserlistUpdates: true })
    chatService.addRoom(roomName1, null, () => parallel([
      cb => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed',
                   () => socket1.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket2 = clientConnect(user2)
        socket2.on('loginConfirmed',
                   () => socket2.emit('roomJoin', roomName1, cb))
      }
    ], error => {
      expect(error).not.ok
      socket1.emit(
        'roomGetAccessList', roomName1, 'userlist', (error, data) => {
          expect(error).not.ok
          expect(data).lengthOf(2)
          expect(data).include(user1)
          expect(data).include(user2)
          socket2.disconnect()
          socket1.once('roomUserLeft', () => {
            socket1.emit(
              'roomGetAccessList', roomName1, 'userlist', (error, data) => {
                expect(error).not.ok
                expect(data).lengthOf(1)
                expect(data).include(user1)
                expect(data).not.include(user2)
                done()
              })
          })
        })
    }))
  })

  it('should store and send a room history', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomMessage', roomName1, message, (error, data) => {
            expect(error).not.ok
            expect(data).a('Number')
            socket1.emit('roomRecentHistory', roomName1, (error, data) => {
              expect(error).not.ok
              expect(data).length(1)
              let props = ['textMessage', 'author', 'timestamp', 'id']
              expect(data[0]).include.keys(...props)
              expect(data[0].textMessage).equal(txt)
              expect(data[0].author).equal(user1)
              expect(data[0].timestamp).a('Number')
              expect(data[0].id).equal(1)
              done()
            })
          })
        })
      })
    })
  })

  it('should send room messages to all joined users', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(roomName1, null, () => parallel([
      cb => {
        socket1 = clientConnect(user1)
        socket1.on('loginConfirmed',
                   () => socket1.emit('roomJoin', roomName1, cb))
      },
      cb => {
        socket2 = clientConnect(user2)
        socket2.on('loginConfirmed',
                   () => socket2.emit('roomJoin', roomName1, cb))
      }
    ], error => {
      expect(error).not.ok
      parallel([
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.on('roomMessage', (room, msg) => {
          expect(room).equal(roomName1)
          expect(msg.author).equal(user1)
          expect(msg.textMessage).equal(txt)
          expect(msg).ownProperty('timestamp')
          expect(msg).ownProperty('id')
          cb()
        }),
        cb => socket2.on('roomMessage', (room, msg) => {
          expect(room).equal(roomName1)
          expect(msg.author).equal(user1)
          expect(msg.textMessage).equal(txt)
          expect(msg).ownProperty('timestamp')
          expect(msg).ownProperty('id')
          cb()
        })
      ], done)
    }))
  })

  it('should drop a history if the limit is zero', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ defaultHistoryLimit: 0 })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomMessage', roomName1, message, () => {
            socket1.emit('roomRecentHistory', roomName1, (error, data) => {
              expect(error).not.ok
              expect(data).empty
              done()
            })
          })
        })
      })
    })
  })

  it('should not send a history if the limit is zero', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ historyMaxGetMessages: 0 })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomMessage', roomName1, message, () => {
            socket1.emit('roomRecentHistory', roomName1, (error, data) => {
              expect(error).not.ok
              expect(data).empty
              socket1.emit(
                'roomHistoryGet', roomName1, 0, 10, (error, data) => {
                  expect(error).not.ok
                  expect(data).empty
                  done()
                })
            })
          })
        })
      })
    })
  })

  it('should send a room history maximum size', function (done) {
    let sz = 1000
    chatService = startService({ defaultHistoryLimit: sz })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomHistoryInfo', roomName1, (error, data) => {
            expect(error).not.ok
            expect(data.historyMaxSize).equal(sz)
            done()
          })
        })
      })
    })
  })

  it('should truncate a long history', function (done) {
    let txt1 = 'Test message 1.'
    let message1 = { textMessage: txt1 }
    let txt2 = 'Test message 2.'
    let message2 = { textMessage: txt2 }
    chatService = startService({ defaultHistoryLimit: 1 })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomMessage', roomName1, message1, () => {
            socket1.emit('roomMessage', roomName1, message2, () => {
              socket1.emit('roomRecentHistory', roomName1, (error, data) => {
                expect(error).not.ok
                expect(data).length(1)
                let props = ['textMessage', 'author', 'timestamp', 'id']
                expect(data[0]).include.keys(...props)
                expect(data[0].textMessage).equal(txt2)
                expect(data[0].author).equal(user1)
                expect(data[0].timestamp).a('Number')
                expect(data[0].id).equal(2)
                done()
              })
            })
          })
        })
      })
    })
  })

  it('should support a history synchronisation', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      series([
        cb => socket1.on('loginConfirmed',
                         () => socket1.emit('roomJoin', roomName1, cb)),
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb)
      ], error => {
        expect(error).not.ok
        parallel([
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 0, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(2)
              let props = ['textMessage', 'author', 'timestamp', 'id']
              expect(data[0]).include.keys(...props)
              expect(data[0].textMessage).equal(txt)
              expect(data[0].author).equal(user1)
              expect(data[0].timestamp).a('Number')
              expect(data[0].id).equal(2)
              expect(data[1].id).equal(1)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 1, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0].id).equal(2)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 2, 10, (error, data) => {
              expect(error).not.ok
              expect(data).empty
              cb()
            })
        ], done)
      })
    })
  })

  it('should sync a history with respect to the limit', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ historyMaxGetMessages: 2 })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      series([
        cb => socket1.on('loginConfirmed',
                         () => socket1.emit('roomJoin', roomName1, cb)),
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb)
      ], error => {
        expect(error).not.ok
        parallel([
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 0, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(2)
              expect(data[1].id).equal(1)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 1, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(3)
              expect(data[1].id).equal(2)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 2, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0].id).equal(3)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 3, 10, (error, data) => {
              expect(error).not.ok
              expect(data).empty
              cb()
            })
        ], done)
      })
    })
  })

  it('should sync a history with respect to a history size', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService({ defaultHistoryLimit: 2 })
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      series([
        cb => socket1.on('loginConfirmed',
                         () => socket1.emit('roomJoin', roomName1, cb)),
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb),
        cb => socket1.emit('roomMessage', roomName1, message, cb)
      ], error => {
        expect(error).not.ok
        parallel([
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 0, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(3)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 1, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(2)
              expect(data[0].id).equal(3)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 2, 10, (error, data) => {
              expect(error).not.ok
              expect(data).lengthOf(1)
              expect(data[0].id).equal(3)
              cb()
            }),
          cb =>
            socket1.emit('roomHistoryGet', roomName1, 3, 10, (error, data) => {
              expect(error).not.ok
              expect(data).empty
              cb()
            })
        ], done)
      })
    })
  })

  it('should send and update a room sync info', function (done) {
    let txt = 'Test message.'
    let message = { textMessage: txt }
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomHistoryInfo', roomName1, (error, data) => {
            expect(error).not.ok
            expect(data).ownProperty('historyMaxGetMessages')
            expect(data).ownProperty('historyMaxSize')
            expect(data).ownProperty('historySize')
            expect(data).ownProperty('lastMessageId')
            expect(data.lastMessageId).equal(0)
            expect(data.historySize).equal(0)
            socket1.emit('roomMessage', roomName1, message, () => {
              socket1.emit('roomHistoryInfo', roomName1, (error, data) => {
                expect(error).not.ok
                expect(data.lastMessageId).equal(1)
                expect(data.historySize).equal(1)
                done()
              })
            })
          })
        })
      })
    })
  })

  it('should get and update an user seen info', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      let ts = new Date().getTime()
      let tsmax = ts + 2000
      parallel([
        cb => {
          socket1 = clientConnect(user1)
          socket1.on('loginConfirmed',
                     () => socket1.emit('roomJoin', roomName1, cb))
        },
        cb => {
          socket2 = clientConnect(user2)
          socket2.on('loginConfirmed',
                     () => socket2.emit('roomJoin', roomName1, cb))
        }
      ], error => {
        expect(error).not.ok
        socket1.emit('roomUserSeen', roomName1, user2, (error, info1) => {
          expect(error).not.ok
          expect(info1).an('object')
          expect(info1.joined).true
          expect(info1.timestamp).a('Number')
          expect(info1.timestamp).within(ts, tsmax)
          socket2.emit('roomLeave', roomName1, () => {
            socket1.emit('roomUserSeen', roomName1, user2, (error, info2) => {
              expect(error).not.ok
              expect(info2).an('object')
              expect(info2.joined).false
              expect(info2.timestamp).a('Number')
              expect(info2.timestamp).within(ts, tsmax)
              expect(info2.timestamp).least(info1.timestamp)
              done()
            })
          })
        })
      })
    })
  })

  it('should send an empty seen info for unseen users', function (done) {
    chatService = startService()
    chatService.addRoom(roomName1, null, () => {
      socket1 = clientConnect(user1)
      socket1.on('loginConfirmed', () => {
        socket1.emit('roomJoin', roomName1, () => {
          socket1.emit('roomUserSeen', roomName1, user2, (error, info) => {
            expect(error).not.ok
            expect(info).an('object')
            expect(info.joined).false
            expect(info.timestamp).null
            done()
          })
        })
      })
    })
  })

  it('should include info in users\' sockets lists', function (done) {
    chatService = startService()
    let { sid1, sid2, sid3 } = {}
    chatService.addRoom(roomName1, null, () => {
      chatService.addRoom(roomName2, null, () => {
        parallel([
          cb => {
            socket1 = clientConnect(user1)
            socket1.on('loginConfirmed', (u, data) => {
              sid1 = data.id
              socket1.emit('roomJoin', roomName1,
                           () => socket1.emit('roomJoin', roomName2, cb))
            })
          },
          cb => {
            socket2 = clientConnect(user1)
            socket2.on('loginConfirmed', (u, data) => {
              sid2 = data.id
              socket2.emit('roomJoin', roomName1, cb)
            })
          },
          cb => {
            socket3 = clientConnect(user1)
            socket3.on('loginConfirmed', (u, data) => {
              sid3 = data.id
              cb()
            })
          }
        ], error => {
          expect(error).not.ok
          socket2.emit('listOwnSockets', (error, data) => {
            expect(error).not.ok
            expect(data[sid1]).lengthOf(2)
            expect(data[sid2]).lengthOf(1)
            expect(data[sid3]).lengthOf(0)
            expect(data[sid1]).include.members([roomName1, roomName2])
            expect(data[sid1]).include(roomName1)
            done()
          })
        })
      })
    })
  })
}
