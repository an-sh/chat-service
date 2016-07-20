
import _ from 'lodash';
import { expect } from 'chai';

import { cleanup, clientConnect, startService } from './testutils.coffee';

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

  it('should send direct messages', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService({ enableDirectMessages : true });
    socket1 = clientConnect(user1);
    return socket1.on('loginConfirmed', function() {
      socket2 = clientConnect(user2);
      return socket2.on('loginConfirmed', function() {
        socket1.emit('directMessage', user2, message);
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

  it('should not send direct messages when the option is disabled', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService();
    socket1 = clientConnect(user1);
    return socket1.on('loginConfirmed', function() {
      socket2 = clientConnect(user2);
      return socket2.on('loginConfirmed', () =>
        socket1.emit('directMessage', user2, message, function(error, data) {
          expect(error).ok;
          expect(data).null;
          return done();
        }
        )
      
      );
    }
    );
  }
  );

  it('should not send self-direct messages', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService({ enableDirectMessages : true });
    socket1 = clientConnect(user1);
    return socket1.on('loginConfirmed', () =>
      socket1.emit('directMessage', user1, message, function(error, data) {
        expect(error).ok;
        expect(data).null;
        return done();
      }
      )
    
    );
  }
  );

  it('should not send direct messages to offline users', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService({ enableDirectMessages : true });
    socket2 = clientConnect(user2);
    return socket2.on('loginConfirmed', function() {
      socket2.disconnect();
      socket1 = clientConnect(user1);
      return socket1.on('loginConfirmed', () =>
        socket1.emit('directMessage', user2, message, function(error, data) {
          expect(error).ok;
          expect(data).null;
          return done();
        }
        )
      
      );
    }
    );
  }
  );

  it('should echo direct messages to user\'s sockets', function(done) {
    let txt = 'Test message.';
    let message = { textMessage : txt };
    chatService = startService({ enableDirectMessages : true });
    socket1 = clientConnect(user1);
    return socket1.on('loginConfirmed', function() {
      socket3 = clientConnect(user1);
      return socket3.on('loginConfirmed', function() {
        socket2 = clientConnect(user2);
        return socket2.on('loginConfirmed', function() {
          socket1.emit('directMessage', user2, message);
          return socket3.on('directMessageEcho', function(u, msg) {
            expect(u).equal(user2);
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
  }
  );

  return it('should echo system messages to user\'s sockets', function(done) {
    let data = 'some data.';
    chatService = startService();
    socket1 = clientConnect(user1);
    return socket1.on('loginConfirmed', function() {
      socket2 = clientConnect(user1);
      return socket2.on('loginConfirmed', function() {
        socket1.emit('systemMessage', data);
        return socket2.on('systemMessage', function(d) {
          expect(d).equal(data);
          return done();
        }
        );
      }
      );
    }
    );
  }
  );
};
