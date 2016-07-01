
### 0.8.0

- Added ChatService clusterBus.
- Added hooks returning promises support.
- Added ready and error ChatService lifecycle events.
- Added storeConsistencyFailure and transportConsistencyFailure events.
- Added support of binary data in custom messages.
- Changed Redis user sockets schema.
- Changed default timeouts values.
- Changed disconnectUserSockets API method.
- Changed hooks callbacks, now must be run async only.
- Changed instanceRecover name to instanceRecovery.
- Changed ioredis version to ^2.0.0.
- Fixed CoffeeScript compilation (use compiled js for npm).
- Fixed channel leaving for sockets in other instances.
- Fixed closeTimeout option passing.
- Fixed redis state graceful shutdown.
- Removed closed ChatService event.
- Removed example application to a separate repo.

### 0.7.0 (2016/05/27)

- Added ServiceAPI for scripting.
- Added hooks for checking custom content in message objects.
- Added listOwnSockets command.
- Added redis socket.io adapter dependency.
- Added roomGetOwner command.
- Added roomHistoryGet and roomHistoryInfo commands.
- Added roomUserSeen command.
- Added socketConnectEcho and socketDisconnectEcho messages.
- Added systemMessage command.
- Changed Redis schema.
- Changed adminlist to accessList.
- Changed auth hook to middleware.
- Changed chat constructor options.
- Changed global rooms history limit to a per-room value.
- Changed hooks API.
- Changed internal APIs (full rewrite, use promises now).
- Changed module export.
- Changed node.js minimum version to 0.12.
- Changed room permissions.
- Changed roomHistory to roomRecentHistory.
- Changed roomJoinedEcho and roomLeftEcho ServerMessages.
- Changed roomMessage and directMessage server messages.
- Changed roomMessage command.
- Cleanup tests, suit split.
- Fixed commands arguments validation.
- Removed listRooms command.

### 0.6.1 (2016/02/01)

- Update dependencies.
- Lock socket-io minor version.

### 0.6.0 (2015/12/05)

- Don't join/leave all user sockets from rooms at server side.
- Rename enableAdminListUpdates to enableAdminlistUpdates.
- Changed onConnect hook arguments.
- Add njoined data in related server messages.
- Fix user remove from room bugs.
- Fix Redis states cleanup functions.
- Include frontend example application.

### 0.5.1 (2015/10/26)

- Security: Fix type error throwing on primitive message objects.

### 0.5.0 (2015/10/07)

- Allow room adminlist changing only for owner.
- Dependencies update.
- Message hooks fix/simplification.
- Pass state options.
- Use locks in redis state.
- Wait for clients disconnection in close function.

### 0.4.0 (2015/09/02)

- Redis state.
- Room listing changed.
- Before and After hooks changed.
- More unit tests.

### 0.3.0 (2015/08/19)

- Some documentation.
- Room join/leave server messages renamed.

### 0.2.0 (2015/08/13)

- New socket.io messages reply format (using ack).
- State store API.

### 0.1.0 (2015/07/21)

- Initial release.
