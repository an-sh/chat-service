
# Chat service

[![NPM Version](https://badge.fury.io/js/chat-service.svg)](https://badge.fury.io/js/chat-service)
[![Build Status](https://travis-ci.org/an-sh/chat-service.svg?branch=master)](https://travis-ci.org/an-sh/chat-service)
[![Appveyor status](https://ci.appveyor.com/api/projects/status/qy7v2maica2urkss?svg=true)](https://ci.appveyor.com/project/an-sh/chat-service)
[![Coverage Status](https://codecov.io/gh/an-sh/chat-service/branch/master/graph/badge.svg)](https://codecov.io/gh/an-sh/chat-service)
[![Dependency Status](https://david-dm.org/an-sh/chat-service.svg)](https://david-dm.org/an-sh/chat-service)

Messaging service designed to handle a vast variety of use cases that
are fit into a chat-like pattern, including exchanging data in
collaborative applications, logging with realtime updates, or a full
protocol/API tunnelling for IoT devices.


## Features


- Reliable room messaging using a server side history storage and a
  synchronisation API.

- Customisable JSON messages format via just a validation function
  (hook), allowing custom or heterogeneous room messages format
  (including support of a binary data inside JSON).

- Per-room user presence API and notifications.

- Room creation and room permissions management APIs (with changes
  notifications). Supports for blacklist or whitelist based access
  modes and a room administrators management.

- Lightweight online user to online user messages with a server side
  permissions management API.

- Seamless support of multiple socket connections for a single user,
  including a reasonable amount of user's action notifications from
  other sockets.

- Written as a stateless microservice, using Redis as a state store,
  can be easily scaled across many machines. Also supports Redis in
  cluster configurations as a store.

- Extensive customisation support. Custom functionality can be added
  via hooks before/after any client message (command). And client
  messages (commands) handlers can be invoked server side as simple
  functions.

- Simple networking, only a socket.io client implementation is
  required, making it possible to use the same server for web (SPA),
  mobile and desktop clients.


## Tutorial

On a server, define a socket connection hook, as the service is
relying on an extern auth implementation. A user just needs to pass an
auth check, no explicit user adding step is required.

```javascript
function onConnect(service, id) {
  // Get socket object by id, assuming socket.io transport.
  let socket = service.nsp.connected[id]
  // Assuming that auth data is passed in a query string.
  let query = socket.handshake.query
  // Check query data.
  // ...
  // Return a promise that resolves with a login string.
  return Promise.resolve(userName)
}
```

Creating a server is a simple object instantiation. __Note:__ that a
`close` method _must_ be called to correctly shutdown a service (see
[Failures recovery](#failures-recovery)).

```javascript
const port = 8000
const ChatService = require('chat-service')
const chatService = new ChatService({port}, {onConnect})
process.on('SIGINT', chatService.close().finally(() => process.exit()))
```

Server is now running on port `8000`, using memory state. By default
`'/chat-service'` socket.io namespace is used. Adding a room with
`admin` user as an owner.

```javascript
chatService.addRoom('default', { owner: 'admin' })
```

On a client just a `socket.io-client` implementation is required. To
send a command use `emit` method, the result (or an error) will be
returned in socket.io ack callback. To listen to server messages use
`on` method.

```javascript
let io = require('socket.io-client')
let url = 'localhost:8000/chat-service'
let user = 'someLogin'
let password = 'somePassword'
let query = `user=${user}&password=${password}`
let params = { query }
// Connect to server.
let socket = io.connect(url, params)
socket.once('loginConfirmed', (userName) => {
  // Auth success.
  socket.on('roomMessage', (room, msg) => {
    // Rooms messages handler (own messages are here too).
  })
  // Join room 'default'.
  socket.emit('roomJoin', 'default', (error, data) => {
    // Check for a command error.
    if (error) return
    // Now we will receive 'default' room messages in 'roomMessage' handler.
    // Now we can also send a message to 'default' room:
    socket.emit('roomMessage', 'default', { textMessage: 'Hello!' })
  })
})
socket.once('loginRejected', (error) => {
  // Auth error handler.
})
```

Look in the API documentation for details about custom message
formats, rooms management, rooms permission and users presence.


## Concepts overview

### User multiple connections

Service completely abstracts a connection concept from a user concept,
so a single user can have more than one connection (including
connections across different nodes). For the user presence the number
of joined sockets must be just greater than zero. All APIs designed to
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

### Reliable messaging and history synchronisation

When a user sends a room message, in the ack callback the message `id`
is returned. It means that the message has been saved in a store (in
an append only circular buffer like structure). Room message ids are a
sequence than increases by one for each successfully sent message in
the room. A client can always check the last room message id via
`roomHistoryInfo` command, and use `roomHistoryGet` command to get
missing messages. Such approach ensures that a message can be
received, unless it is deleted due to rotation.

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
connection hook is supported too. Command and hooks are executed
sequentially: before hook - command - after hook. Sequence termination
in before hooks is supported. Clients can send additional command
arguments, hooks can read them, and reply with additional arguments.

To execute an user command server side `execUserCommand` is
provided. Also there are some more server side only methods provided
by `ServiceAPI` and `Transport`. Look for some customisation cases in
[Customisation examples](#customisation-examples).

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
the command's issuers). Such events are reported via instance events
(see `ChatServiceEvents`), and data can be sync via `RecoveryAPI`
methods.


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

### Explicit multi-device announcements

By default there is no way for other users to know the number and
types of user connections joined to a room. Such information can be
passed, for example in a query string and then saved via a connection
hook. The announcement can be made in `roomJoin` after hook, using
directly transport `sendToChannel` method. Also additional information
regarding joined devices types should be sent from `roomGetAccessList`
after hook (when list name is equal to `'userlist'`).


## API documentation

Is available online at
[gitpages](https://an-sh.github.io/chat-service/0.8/).

- `ServerMessages` class describes socket.io messages that are sent
  from the server to a client.

- `UserCommands` class describes socket.io messages that a client
  sends to a server and receives reply as a command ack.

- `ChatService` class is the package exported object and a service
  instance constructor, describes options. It also contains mixin
  methods for using server side API.

Run `npm install -g codo` and `codo` to generate local documentation.


## Frontend example

An Angular single page chat application with a basic features
demonstration is now in a separate
[repo](https://github.com/an-sh/chat-service-frontend-angular1). You
can also run this example as a cluster with several node
processes. Check `README.md` file in that repository for more
information.


## Debugging

In normal circumstances all errors that are returned to a service user
(via commands ack, `loginConfirmed` or `loginRejected` messages)
should be instances of `ChatServiceError`. All other errors mean a
bug, or some failures in the service infrastructure. To enable debug
logging of such errors use `export NODE_DEBUG=ChatService`. The
library is using bluebird `^3.0.0` promises implementation, so to
enable long stack traces use `export BLUEBIRD_DEBUG=1`. It is highly
recommended to follow this conventions for extension hooks
development.

## Bug reporting

If you encounter a bug in this package, please submit a bug report at
github repo [issues](https://github.com/an-sh/chat-service/issues).


## License

MIT
