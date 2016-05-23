
# Frontend example

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
