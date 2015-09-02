
# Chat service

[![Build Status](https://travis-ci.org/an-sh/chat-service.svg?branch=master)](https://travis-ci.org/an-sh/chat-service)
[![Coverage Status](https://coveralls.io/repos/an-sh/chat-service/badge.svg?branch=master&service=github)](https://coveralls.io/github/an-sh/chat-service?branch=master)
[![Dependency Status](https://david-dm.org/an-sh/chat-service.svg)](https://david-dm.org/an-sh/chat-service)

Server side chat based on top of socket.io focused on scalability and
extensibility.

### Features

- Simple network layer using socket.io and json based messages.
- Room and user2user chatting with permissions management.
- Runs as a stateless service with built-in Redis state storage.
- Can be extened via command hooks.
- Can use external state storage implementations.
- Extensive unit test coverage (95%+).

### Documentation

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

### TODO

- API for adding custom messages.

### License

MIT
