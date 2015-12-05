
# Chat service

[![Build Status](https://travis-ci.org/an-sh/chat-service.svg?branch=master)](https://travis-ci.org/an-sh/chat-service)
[![Coverage Status](https://coveralls.io/repos/an-sh/chat-service/badge.svg?branch=master&service=github)](https://coveralls.io/github/an-sh/chat-service?branch=master)
[![Dependency Status](https://david-dm.org/an-sh/chat-service.svg)](https://david-dm.org/an-sh/chat-service)

Server side chat based on top of socket.io focused on scalability and
extensibility.


### Features

- Simple network layer using socket.io and json based messages.
- Room and user2user chatting with permissions management.
- Allows a single user to have multiple connected sockets.
- Runs as a stateless service with built-in Redis state storage.
- Can be extened via command hooks.
- Can use external state storage implementations.
- Extensive unit test coverage (95%+).


### Basic usage

```javascript
var chatServer = new ChatService({ port : port },
                                 { auth : auth, onConnect : onConnect },
                                 'redis');
```
Here we have created a new server instance. It is ruuning _`port`_
according to options argument. The second argument represents hooks,
that will run during server lifetime. _`auth`_ hook is simular to the
one that is described in socket.io documentation, and _`onConnect`_
hook will run when client is connected. These hook are intended for
integration to existing user authentication systems. The last argument
is a state storage.

Connection from a client side is trivial:
```javascript
socket = ioClient.connect(url1, params);
socket.on('loginConfirmed', function(username) {
  // code
});
```
A conneted client can send `UserCommands` to a server:
```javascript
socket.emit('roomJoin', 'someRoom', function(error, data) {
  // code
});
```
A server reply is send as a socket.io ack and has a standart node
(error, data) callback arguments format. Semantics of most commands is
very straitforward and simple. Only for room commands a client must
join a room to succesfully execute them.

```javascript
socket.on('roomMessage', function(room, user, msg) {
});
```
Also a server will send `ServerMessages`.  Note that these messages
don't require any reply.


### Frontend example

An angular based application is in `example` directory. From this
directory run `npm install && gulp && bin/www` to build the
application and start a server (by default on port 3000).

![Example](http://an-sh.github.io/chat-service/example.png "Example")


### Documentation

Is available at [gitpages](http://an-sh.github.io/chat-service/0.6/)

Run `npm install -g codo` and `codo` to generate documentation. Public
API consists of public methods of the following classes:

- Class: `ServerMessages` - represents socket.io messages sent from a
server to a client. No client reply is requered.
- Class: `UserCommands` - represents socket.io messages sent from a
client to a server. Server will send back a socket.io ack reply with
(error, data) arguments.
- Class: `ChatService` - is a server instance.
- Class: `Room` - represents a room.
- Class: `User` - represents an user.

Look in the test directory, for socket.io-client messages, server
setup and hooks usage.


### License

MIT
