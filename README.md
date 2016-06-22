
# Chat service

[![NPM Version](https://badge.fury.io/js/chat-service.svg)](https://badge.fury.io/js/chat-service)
[![Build Status](https://travis-ci.org/an-sh/chat-service.svg?branch=master)](https://travis-ci.org/an-sh/chat-service)
[![Appveyor status](https://ci.appveyor.com/api/projects/status/qy7v2maica2urkss?svg=true)](https://ci.appveyor.com/project/an-sh/chat-service)
[![Coverage Status](https://coveralls.io/repos/an-sh/chat-service/badge.svg?branch=master&service=github)](https://coveralls.io/github/an-sh/chat-service?branch=master)
[![Dependency Status](https://david-dm.org/an-sh/chat-service.svg)](https://david-dm.org/an-sh/chat-service)

Chat like messaging on top of socket.io, focused on scalability and
extensibility. Designed not to be limited to just a room text chat,
but to handle a vast variety of cases, including exchanging data in
collaborative applications, logging with realtime updates, or a full
protocol/API tunnelling for IoT devices.


### Features


- Reliable room messaging using a server side history storage and a
  synchronisation API.

- Customisable message format via just a validation function (hook),
  allowing custom or heterogeneous room messages format.

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

- Simple networking using only socket.io library with JSON
  messages. Just a socket.io client implementation is required, making
  possible using the same server for web (SPA), mobile and desktop
  clients.


### Tutorial

On a server, lets define the user authentication function, as the
service is relying on an extern auth function. A user just needs to
pass an auth check, no explicit user adding step is required.

```javascript
function onConnect(service, id, cb) {
  // Assuming that auth data is passed in a query string.
  let socket = service.nsp.connected[id]
  let query = socket.handshake.query
  let userName = query.user
  // Check query data.
  cb(null, userName)
  // Or reject auth on error:
  // cb(error)
}
```

Creating a server is a simple object instantiation. __Note:__ that a
`close` method must be called to correctly shutdown a service (if
redis state is used). To fix an incorrect instance shutdown use
`instanceRecover` method.

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
socket.on('loginConfirmed', (userName) => {
  // Auth success.
  socket.on('roomMessage', (room, msg) => {
    // Room message handler.
  })
  // Join room 'default'
  socket.emit('roomJoin', 'default', (error, data) => {
    // Check for a command error.
    if (error) return
    // Now we will receive 'default' room messages in 'roomMessage' handler.
    // Now we can also send a message to 'default' room:
    // socket.emit('roomMessage', 'default', { textMessage: 'Hello!' })
  })
})
socket.on('loginRejected', (error) => {
  // Auth error handler.
})
```

Look in the documentation for details about custom messages format,
management and presence APIs.


### Frontend example

An angular single page chat application with basic features
demonstration is in `example` directory. You can also run this example
as a cluster with several node processes. Check README in that
directory for more information.


### Documentation


Is available online at [gitpages](http://an-sh.github.io/chat-service/0.7/).

- `ServerMessages` class describes socket.io messages that are sent
  from the server to a client.

- `UserCommands` class describes socket.io messages that a client
  sends to a server and receives reply as a socket.io ack.

- `ChatService` class is the server constructor, describes options and
  customisation hooks. It also contains mixin methods for using server
  side API.

Run `npm install -g codo` and `codo` to generate local documentation.


### License

MIT
