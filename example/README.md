
# Frontend example

![Example](https://an-sh.github.io/chat-service/example.png "Example")


### Build and run

From this directory execute:

```sh
npm install && gulp && bin/www
```

By default a memory state is used. To use Redis (as a state and
socket.io adapter), set `CHAT_REDIS_CONNECT` environmental variable to
a Redis connect string.

```sh
export CHAT_REDIS_CONNECT="localhost:6379"
bin/www
```

To run several instances of application use:

```sh
export CHAT_REDIS_CONNECT="localhost:6379"
export NODE_ENV=production
PORT=3000 CHAT_PORT=8000 bin/www &
PORT=3001 CHAT_PORT=8001 bin/www &
```

This will start two separate node process, that will communicate and
share data via a Redis server. To correctly shutdown instances use:

```sh
kill -2 <PID>
```
