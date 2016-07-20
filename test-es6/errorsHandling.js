
import _ from 'lodash';
import { expect } from 'chai';

import { ChatService, cleanup, clientConnect, nextTick, parallel, setCustomCleanup, startService } from './testutils.coffee';

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

  it('should check state constructor type', function(done) {
    try {
      return chatService = startService({ state : {} }, null);
    } catch (error) {
      expect(error).ok;
      return nextTick(done);
    }
  }
  );

  it('should check transport constructor type', function(done) {
    try {
      return chatService = startService({ transport : {} }, null);
    } catch (error) {
      expect(error).ok;
      return nextTick(done);
    }
  }
  );

  it('should check adapter constructor type', function(done) {
    try {
      return chatService = startService({ adapter : {} }, null);
    } catch (error) {
      expect(error).ok;
      return nextTick(done);
    }
  }
  );

  it('should rollback a failed room join', function(done) {
    chatService = startService();
    return chatService.addRoom(roomName1, null, function() {
      socket1 = clientConnect(user1);
      return socket1.on('loginConfirmed', function() {
        chatService.transport.joinChannel = function() {
          throw new Error('This is an error mockup for testing.');
        };
        return socket1.emit('roomJoin', roomName1, function(error) {
          expect(error).ok;
          return chatService.execUserCommand(true, 'roomGetAccessList'
          , roomName1, 'userlist', function(error, data) {
            expect(error).not.ok;
            expect(data).an('Array');
            expect(data).lengthOf(0);
            return done();
          }
          );
        }
        );
      }
      );
    }
    );
  }
  );

  it('should rollback a failed socket connect', function(done) {
    chatService = startService();
    chatService.transport.joinChannel = function() {
      throw new Error('This is an error mockup for testing.');
    };
    socket1 = clientConnect(user1);
    return socket1.on('loginRejected', function(error) {
      expect(error).ok;
      return chatService.execUserCommand(user1, 'listOwnSockets', function(error, data) {
        expect(error).not.ok;
        expect(data).empty;
        return done();
      }
      );
    }
    );
  }
  );

  it('should rollback a disconnected socket connection', function(done) {
    chatService = startService();
    let orig = chatService.state.addSocket;
    chatService.state.addSocket = function(id) {
      return orig.apply(chatService.state, arguments)
      .finally(() => chatService.transport.disconnectClient(id));
    };
    let tst = chatService.transport.rejectLogin;
    chatService.transport.rejectLogin = function() {
      tst.apply(chatService.transport, arguments);
      return chatService.execUserCommand(user1, 'listOwnSockets', function(error, data) {
        expect(error).not.ok;
        expect(data).empty;
        return done();
      }
      );
    };
    return socket1 = clientConnect(user1);
  }
  );

  it('should not join a disconnected socket', function(done) {
    chatService = startService();
    return chatService.addRoom(roomName1, null, function() {
      socket1 = clientConnect(user1);
      return socket1.on('loginConfirmed', function() {
        chatService.transport.getConnectionObject = id => null;
        return socket1.emit('roomJoin', roomName1, function(error, data) {
          expect(error).ok;
          return done();
        }
        );
      }
      );
    }
    );
  }
  );

  it('should emit closed on onStart hook error', function(done) {
    let onStart = function(chatService, cb) {
      expect(chatService).instanceof(ChatService);
      return nextTick(cb, new Error());
    };
    chatService = startService(null, { onStart });
    return chatService.on('closed', function(error) {
      expect(error).ok;
      return done();
    }
    );
  }
  );

  it('should propagate transport close errors', function(done) {
    chatService = startService();
    let orig = chatService.transport.close;
    chatService.transport.close = function() {
      return orig.apply(chatService.transport, arguments)
      .then(function() { throw new Error(); });
    };
    return nextTick(() =>
      chatService.close()
      .catch(function(error) {
        expect(error).ok;
        return done();
      })
    );
  }
  );

  it('should propagate onClose errors', function(done) {
    let onClose = function(chatService, error, cb) {
      expect(chatService).instanceof(ChatService);
      expect(error).not.ok;
      return nextTick(cb, new Error());
    };
    chatService = startService(null, { onClose });
    return nextTick(() =>
      chatService.close()
      .catch(function(error) {
        expect(error).ok;
        return done();
      })
    );
  }
  );

  return it('should propagate transport close errors to onClose hook', function(done) {
    let onClose = function(chatService, error, cb) {
      expect(error).ok;
      return nextTick(cb, error);
    };
    chatService = startService(null, { onClose });
    let orig = chatService.transport.close;
    chatService.transport.close = function() {
      return orig.apply(chatService.transport, arguments)
      .then(function() { throw new Error(); });
    };
    return nextTick(() =>
      chatService.close()
      .catch(function(error) {
        expect(error).ok;
        return done();
      })
    );
  }
  );
};
