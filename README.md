
# Chat Service

[![NPM Version](https://badge.fury.io/js/chat-service.svg)](https://badge.fury.io/js/chat-service)
[![Build Status](https://travis-ci.org/an-sh/chat-service.svg?branch=master)](https://travis-ci.org/an-sh/chat-service)
[![Appveyor status](https://ci.appveyor.com/api/projects/status/qy7v2maica2urkss/branch/master?svg=true)](https://ci.appveyor.com/project/an-sh/chat-service)
[![Coverage Status](https://codecov.io/gh/an-sh/chat-service/branch/master/graph/badge.svg)](https://codecov.io/gh/an-sh/chat-service)
[![Dependency Status](https://david-dm.org/an-sh/chat-service.svg)](https://david-dm.org/an-sh/chat-service)
[![JavaScript Style Guide](https://img.shields.io/badge/code%20style-standard-brightgreen.svg)](http://standardjs.com/)

Room messaging server implementation that is using a bidirectional RPC
protocol to implement chat-like communication. Designed to handle
common public network messaging problems like reliable delivery,
multiple connections from a single user, real-time permissions and
presence. RPC requests processing and a room messages format are
customisable via hooks, allowing to implement anything from a
chat-rooms server to a collaborative application with a complex
conflict resolution. Room messages also can be used to create public
APIs or to tunnel M2M communications for IoT devices.


### Features


- Reliable room messaging using a server side history storage and a
  synchronisation API.

- Arbitrary messages format via just a validation function (hook),
  allowing custom/heterogeneous messages formats (including a binary
  data inside messages).

- Per-room user presence API with notifications.

- Realtime room creation and per-room users permissions management
  APIs. Supports for blacklist or whitelist based access modes and an
  optional administrators group.

- Seamless support of multiple users' connections from various devises
  to any service instance.

- Written as a stateless microservice, uses Redis (also supports
  cluster configurations) as a state store, can be horizontally scaled
  on demand.

- Extensive customisation support. Custom functionality can be added
  via hooks before/after for any client request processing. And
  requests (commands) handlers can be invoked server side via an API.

- Pluginable networking transport. Client-server communication is done
  via a bidirectional RPC protocol. Socket.io transport implementation
  is included.

- Pluginable state store. Memory and Redis stores are included.

- Supports lightweight online user to online user messaging.


## Table of Contents

- [Background](#background)
- [Installation](#installation)
- [Usage](#usage)
- [API](#api)
- [Concepts overview](#concepts-overview)
- [Customisation examples](#customisation-examples)
- [Contribute](#contribute)
- [License](#license)


## Background

Read this
[article](https://medium.com/@an_sh_1/chat-service-project-announcement-and-overview-92283fe80d93)
for more background information.


## Installation

This project is a [node](http://nodejs.org) module available via
[npm](https://npmjs.com). Go check them out if you don't have them
locally installed.

```sh
$ npm i chat-service
```


## Usage

### Quickstart with socket.io

First define a server configuration. On a server-side define a socket
connection hook, as the service is relying on an extern auth
implementation. An user just needs to pass an auth check, no explicit
user adding step is required.

```javascript
const ChatService = require('chat-service')

const port = 8000

function onConnect (service, id) {
  // Assuming that auth data is passed in a query string.
  let { query } = service.transport.getHandshakeData(id)
  let { userName } = query
  // Actually check auth data.
  // ...
  // Return a promise that resolves with a login string.
  return Promise.resolve(userName)
}
```

Creating a server is a simple object instantiation. Note: `close`
method _must_ be called to correctly shutdown a service instance (see
[Failures recovery](#failures-recovery)).

```javascript
const chatService = new ChatService({port}, {onConnect})

process.on('SIGINT', () => chatService.close().finally(() => process.exit()))
```

Server is now running on port `8000`, using `memory` state. By default
`'/chat-service'` socket.io namespace is used. Add a room with `admin`
user as the room owner. All rooms must be explicitly created (option
to allow rooms creation from a client side is also provided).

```javascript
// The room configuration and messages will persist if redis state is
// used. addRoom will reject a promise if the room is already created.
chatService.hasRoom('default').then(hasRoom => {
  if (!hasRoom) {
    return chatService.addRoom('default', { owner: 'admin' })
  }
})
```

On a client just a `socket.io-client` implementation is required. To
send a request (command) use `emit` method, the result (or an error)
will be returned in socket.io ack callback. To listen to server
messages use `on` method.

```javascript
const io = require('socket.io-client')

// Use https or wss in production.
let url = 'ws://localhost:8000/chat-service'
let userName = 'user' // for example and debug
let token = 'token' // auth token
let query = `userName=${userName}&token=${token}`
let opts = { query }

// Connect to a server.
let socket = io.connect(url, opts)

// Rooms messages handler (own messages are here too).
socket.on('roomMessage', (room, msg) => {
  console.log(`${msg.author}: ${msg.textMessage}`)
})

// Auth success handler.
socket.on('loginConfirmed', userName => {
  // Join room named 'default'.
  socket.emit('roomJoin', 'default', (error, data) => {
    // Check for a command error.
    if (error) { return }
    // Now we will receive 'default' room messages in 'roomMessage' handler.
    // Now we can also send a message to 'default' room:
    socket.emit('roomMessage', 'default', { textMessage: 'Hello!' })
  })
})

// Auth error handler.
socket.on('loginRejected', error => {
  console.error(error)
})
```

It is a runnable code, files are in `example` directory.

### Integrating with other messaging systems

It is possible to use other transports other than socket.io. There is
a proof of concept
[transport](https://github.com/an-sh/chat-service-ws-messaging), that
is using a WebSocket connection with some minimal API abstraction
layer [ws-messaging](https://github.com/an-sh/ws-messaging) and a
simple
[emitter-pubsub-broker](https://github.com/an-sh/emitter-pubsub-broker)
as backend messaging fanout abstraction.

Here are the main things that a transport must allow to do:

- Send messages from a server to groups of clients (based on a single
  string full match criteria, a.k.a. room messaging).

- Implement request-reply communication from a client to a server.

- Implement some kind of persistent connection (or semantically
  equivalent), it is required for a presence tracking.

### Integrating with other databases

Chat Service is using Redis as a shared store with persistence. In a
real application some of this information may be needed by other
services, but it is not practical to fully reimplement the state
store. A better alternative approach is to use hooks. For example, to
save all room messages inside an another database just a
`roomMessageAfter` hook can be used. Also `ServiceAPI` can be exposed
via backend messaging buses to other internal servers.


### Debugging

Under normal circumstances all errors that are returned to a service
user (via request replies, `loginConfirmed` or `loginRejected`
messages) are instances of `ChatServiceError`. All other errors
indicate a program bug or a failure in a service infrastructure. To
enable debug logging of such errors use `export
NODE_DEBUG=ChatService`. The library is using bluebird `^3.0.0`
promises implementation, so to enable long stack traces use `export
BLUEBIRD_DEBUG=1`. It is highly recommended to use promise versions of
APIs for hooks and `ChatServiceError` subclasses for returning hooks
custom errors.


## API

Server side
[API](https://an-sh.github.io/chat-service/1.0/chat-service.html) and
[RPC](https://an-sh.github.io/chat-service/1.0/rpc.html) documentation
is available online.


## Concepts overview

### User multiple connections

Service completely abstracts a connection concept from a user concept,
so a single user can have more than one connection (including
connections across different nodes). For user presence the number of
joined sockets must be just greater than zero. All APIs designed to
work on the user level, handling seamlessly user's multiple
connections.

Connections are completely independent, no additional client side
support is required. But there are info messages and commands that can
be used to get information about other user's connections. It makes
possible to realise client-side sync patterns, like keeping all
connections to be joined to the same rooms.

### Room permissions

Each room has a permissions system. There is a single owner user, that
has all administrator privileges and can assign users to the
administrators group. Administrators can manage other users' access
permissions. Two modes are supported: blacklist and whitelist. After
access lists/mode modifications, service automatically removes users
that have lost an access permission.

If `enableRoomsManagement` options is enabled users can create rooms
via `roomCreate` command. The creator of a room will be it's owner and
can also delete it via `roomDelete` command.

Before hooks can be used to implement additional permissions systems.

### Reliable messaging and history synchronisation

When a user sends a room message, in RPC reply the message `id` is
returned. It means that the message has been saved in a store (in an
append only circular buffer like structure). Room message ids are a
sequence starting from `1`, that increases by one for each
successfully sent message in the room. A client can always check the
last room message id via `roomHistoryInfo` command, and use
`roomHistoryGet` command to get missing messages. Such approach
ensures that a message can be received, unless it is deleted due to
rotation.

### Custom messages format

By default a client can send messages that are limited to just a
`{textMessage: 'Some string'}`. To enable custom messages format
provide `directMessagesChecker` or `roomMessagesChecker` hooks. When a
hook resolves, a message format is accepted. Messages can be arbitrary
data with a few restrictions. The top level must be an `Object`,
without `timestamp`, `author` or `id` fields (service will fill this
fields before sending messages). The nested levels can include
arbitrary data types (even binary), but no nested objects with a field
`type` set to `'Buffer'` (used for binary data manipulations).

### Integration and customisations

Each user command supports before and after hook adding, and a client
connection/disconnection hooks are supported too. Command and hooks
are executed sequentially: before hook - command - after hook (it will
be called on command errors too). Sequence termination in before hooks
is possible. Clients can send additional command arguments, hooks can
read them, and reply with additional arguments.

To execute an user command server side `execUserCommand` is
provided. Also there are some more server side only methods provided
by `ServiceAPI` and `TransportInterface`. Look for some customisation
cases in [Customisation examples](#customisation-examples).

### Failures recovery

Service keeps user presence and connection data in a store, that may
be persistent or shared. So if an instance is shutdown incorrectly
(without calling or waiting for `close` method to finish) or lost
completely network connection to a store, presence data will become
incorrect. To fix this case `instanceRecovery` method is provided.

Also there are more subtle cases regarding connection-dependant data
consistency. Transport communication instances and store instances can
experience various kind of network, software or hardware failures. In
some edge cases (like operation on multiple users) such failures can
cause inconsistencies (for the most part errors will be returned to
the command's issuers). These events are reported via an instance
emitter (like `storeConsistencyFailure` event), and data can be sync
via `RecoveryAPI` methods.


## Customisation examples

### Anonymous listeners

By default every user is assumed to have an unique login
(userName). Instead of managing names generation, an integration with
a separate transport can be used (or a multiplexed connection, for
example an another socket.io namespace). Room messages can be
forwarded from `roomMessage` after hook to a transport, that is
accessible without a login. And vice versa some service commands can
be executed by anonymous users via `execUserCommand` with bypassing
permissions option turned on.

### Messages aggregation and filtering

A `roomMessage` after hook can be also used to forward messages from
one room to another. So rooms can be used for messages aggregation
from another rooms. Since hooks are just functions and have a full
access to messages content, it allows to implement arbitrary
content-based forwarding rules. Including implementing systems with
highly personalised user (client) specific feeds.

### Explicit multi-device announcements

By default there is no way for other users to know the number and
types of user connections joined to a room. Such information can be
passed, for example in a query string and then saved via a connection
hook. The announcement can be made in `onJoin` and `onLeave` hooks,
using directly transport `sendToChannel` method. Also additional
information regarding joined devices types should be sent from
`roomGetAccessList` after hook (when list name is equal to
`'userlist'`).

### Messages editing and deletion

There is no delete or edit operation, as they will make
inconsistencies inside a room history. A common alternative for
deleting and editing is to use room messages with a special meaning
that clients will use to hide or alter messages.


## Contribute

If you encounter a bug in this package, please submit a bug report to
github repo [issues](https://github.com/an-sh/chat-service/issues).

PRs are also accepted.


## License

MIT
