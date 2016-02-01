
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
