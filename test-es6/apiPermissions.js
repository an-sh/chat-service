
import _ from 'lodash';
import { expect } from 'chai';

import { cleanup, clientConnect, parallel, startService } from './testutils.coffee';

import { cleanupTimeout, port, user1, user2, user3, roomName1, roomName2 } from './config.coffee';

export default function() {

  let chatService = null;
  let socket1 = null;
  let socket2 = null;
  let socket3 = null;

  afterEach(function(cb) {
    this.timeout(cleanupTimeout);
    cleanup(chatService, [socket1, socket2, socket3], cb);
    return chatService = socket1 = socket2 = socket3 = null;
  });

  it('should get a user mode', function(done) {
    chatService = startService();
    return chatService.addUser(user1, { whitelistOnly : true }, () =>
      chatService.execUserCommand(user1, 'directGetWhitelistMode'
      , function(error, data) {
        expect(error).not.ok;
        expect(data).true;
        return done();
      }
      )
    
    );
  }
  );

  it('should change user lists', function(done) {
    chatService = startService();
    return chatService.addUser(user1, null, () =>
      chatService.execUserCommand(user1
      , 'directAddToList', 'whitelist', [user2], function(error, data) {
        expect(error).not.ok;
        expect(data).null;
        return chatService.execUserCommand(user1
        , 'directGetAccessList', 'whitelist', function(error, data) {
          expect(error).not.ok;
          expect(data).lengthOf(1);
          expect(data[0]).equal(user2);
          return done();
        }
        );
      }
      )
    
    );
  }
  );

  it('should check room names before adding', function(done) {
    chatService = startService();
    return chatService.addRoom('room:1', null, function(error, data) {
      expect(error).ok;
      expect(data).not.ok;
      return done();
    }
    );
  }
  );

  it('should get a room mode', function(done) {
    chatService = startService();
    return chatService.addRoom(roomName1, { whitelistOnly : true }, () =>
      chatService.execUserCommand(true
      , 'roomGetWhitelistMode', roomName1, function(error, data) {
        expect(error).not.ok;
        expect(data).true;
        return done();
      }
      )
    
    );
  }
  );

  it('should change room lists', function(done) {
    chatService = startService();
    return chatService.addRoom(roomName1, null, () =>
      chatService.execUserCommand(true
      , 'roomAddToList', roomName1, 'whitelist', [user2], function(error, data) {
        expect(error).not.ok;
        expect(data).not.ok;
        return chatService.execUserCommand(true
        , 'roomGetAccessList', roomName1, 'whitelist', function(error, data) {
          expect(error).not.ok;
          expect(data).lengthOf(1);
          expect(data[0]).equal(user2);
          return done();
        }
        );
      }
      )
    
    );
  }
  );

  it('should send system messages to all user sockets', function(done) {
    let data = 'some data.';
    chatService = startService();
    socket1 = clientConnect(user1);
    return socket1.on('loginConfirmed', function() {
      socket2 = clientConnect(user1);
      return socket2.on('loginConfirmed', () =>
        parallel([
          cb => chatService.execUserCommand(user1, 'systemMessage', data, cb),
          cb =>
            socket1.on('systemMessage', function(d) {
              expect(d).equal(data);
              return cb();
            }
            )
          ,
          cb =>
            socket2.on('systemMessage', function(d) {
              expect(d).equal(data);
              return cb();
            }
            )
          
        ], done)
      
      );
    }
    );
  }
  );

  it('should execute commands without hooks', function(done) {
    let before = null;
    let after = null;
    let roomAddToListBefore = function(callInfo, args, cb) {
      before = true;
      return cb();
    };
    let roomAddToListAfter = function(callInfo, args, results, cb) {
      after = true;
      return cb();
    };
    chatService = startService(null
      , { roomAddToListBefore, roomAddToListAfter });
    return chatService.addRoom(roomName1, { owner : user1 }, () =>
      chatService.addUser(user2, null, function() {
        socket1 = clientConnect(user1);
        return socket1.on('loginConfirmed', () =>
          socket1.emit('roomJoin', roomName1, () =>
            chatService.execUserCommand({ userName : user1
              , bypassHooks : true }
            , 'roomAddToList', roomName1, 'whitelist', [user1]
            , function(error, data) {
              expect(error).not.ok;
              expect(before).null;
              expect(after).null;
              expect(data).null;
              return done();
            }
            )
          
          )
        
        );
      }
      )
    
    );
  }
  );

  it('should bypass user messaging permissions', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService({ enableDirectMessages : true });
    return chatService.addUser(user1, null, function() {
      chatService.addUser(user2, {whitelistOnly : true}, function() {});
      socket2 = clientConnect(user2);
      return socket2.on('loginConfirmed', function() {
        chatService.execUserCommand({ userName : user1
          , bypassPermissions : true }
        , 'directMessage', user2, message);
        return socket2.on('directMessage', function(msg) {
          expect(msg).include.keys('textMessage', 'author', 'timestamp');
          expect(msg.textMessage).equal(txt);
          expect(msg.author).equal(user1);
          expect(msg.timestamp).a('Number');
          return done();
        }
        );
      }
      );
    }
    );
  }
  );

  it('should bypass room messaging permissions', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService();
    return chatService.addRoom(roomName1
    , { whitelistOnly : true, whitelist : [user1] }
    , () =>
      chatService.addUser(user2, null, function() {
        socket1 = clientConnect(user1);
        return socket1.on('loginConfirmed', () =>
          socket1.emit('roomJoin', roomName1, function() {
            chatService.execUserCommand({ userName : user2
              , bypassPermissions : true }
            , 'roomMessage' , roomName1, message);
            return socket1.on('roomMessage', function(room, msg) {
              expect(room).equal(roomName1);
              expect(msg.author).equal(user2);
              expect(msg.textMessage).equal(txt);
              expect(msg).ownProperty('timestamp');
              expect(msg).ownProperty('id');
              return done();
            }
            );
          }
          )
        
        );
      }
      )
    
    );
  }
  );

  it('should send room messages without an user', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService();
    return chatService.addRoom(roomName1, null, function() {
      socket1 = clientConnect(user1);
      return socket1.on('loginConfirmed', () =>
        socket1.emit('roomJoin', roomName1, function() {
          chatService.execUserCommand(true, 'roomMessage', roomName1, message
          , (error, data) => expect(error).not.ok
          );
          return socket1.on('roomMessage', function(room, msg) {
            expect(room).equal(roomName1);
            expect(room).equal(roomName1);
            expect(msg.author).undefined;
            expect(msg.textMessage).equal(txt);
            expect(msg).ownProperty('timestamp');
            expect(msg).ownProperty('id');
            return done();
          }
          );
        }
        )
      
      );
    }
    );
  }
  );

  it('should not allow using non-existing users', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService();
    return chatService.addRoom(roomName1, null, () =>
      chatService.execUserCommand(user1, 'roomMessage', roomName1, message
      , function(error, data) {
        expect(error).ok;
        expect(data).not.ok;
        return done();
      }
      )
    
    );
  }
  );

  it('should check for direct messaging permissions', function(done) {
    chatService = startService();
    socket1 = clientConnect(user1);
    return socket1.on('loginConfirmed', () =>
      socket1.emit('directAddToList', 'blacklist', [user3], function(error) {
        expect(error).not.ok;
        return parallel([
          function(cb) {
            chatService.hasDirectAccess(user1, user2, function(error, data) {
              expect(error).not.ok;
              expect(data).true;
              return cb();
            }
            );
            return chatService.hasDirectAccess(user1, user3, function(error, data) {
              expect(error).not.ok;
              expect(data).false;
              return cb();
            }
            );
          }
        ], done);
      }
      )
    
    );
  }
  );

  return it('should check for room messaging permissions', function(done) {
    chatService = startService();
    return chatService.addRoom(roomName1, {blacklist : [user3]}, () =>
      parallel([
        function(cb) {
          chatService.hasRoomAccess(roomName1, user2, function(error, data) {
            expect(error).not.ok;
            expect(data).true;
            return cb();
          }
          );
          return chatService.hasRoomAccess(roomName1, user3, function(error, data) {
            expect(error).not.ok;
            expect(data).false;
            return cb();
          }
          );
        }
      ], done)
    
    );
  }
  );
};
