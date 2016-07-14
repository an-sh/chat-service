
const Promise = require('bluebird');
const User = require('./User');
const _ = require('lodash');


// @mixin
// API for a service state recovery.
// @see ChatServiceEvents
let RecoveryAPI = {

  // @private
  // @nodoc
  checkUserSockets(user) {
    let { userName } = user;
    return user.userState.getSocketsToInstance()
    .then(sockets => {
      return Promise.each(_.toPairs(sockets), ([socket, instance]) => {
        if (instance === this.instanceUID && !this.transport.getConnectionObject(socket)) {
          return user.userState.removeSocket(socket);
        }
      }
      );
    }
    )
    .then(() => user.userState.getSocketsToRooms())
    .then(function(data) {
      let args = _.values(data);
      return _.intersection(...args);
    })
    .then(rooms => {
      return Promise.each(rooms, roomName => {
        return this.state.getRoom(roomName)
        .then(room => room.roomState.hasInList('userlist', userName))
        .then(function(isPresent) {
          if (!isPresent) {
            return user.removeFromRoom(roomName);
          }
        })
        .catchReturn();
      }
      );
    }
    );
  },

  // @private
  // @nodoc
  checkRoomJoined(room) {
    let { roomName } = room;
    return room.getList(null, 'userlist', true)
    .then(userlist => {
      return Promise.each(userlist, userName => {
        return this.state.getUser(userName)
        .then(user =>
          user.userState.getRoomToSockets(roomName)
          .then(function(sockets) {
            if (!sockets || !sockets.length) {
              return user.removeFromRoom(roomName);
            }
          })
          .catchReturn()
          .then(() => room.checkAcess(userName))
          .catch(() => user.removeFromRoom(roomName))
        )
        .catchReturn();
      }
      );
    }
    );
  },

  // Sync user to sockets associations.
  //
  // @param userName [String] User name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise]
  userStateSync(userName, cb) {
    return this.state.getUser(userName)
    .then(user => {
      return this.checkUserSockets(user);
    }
    )
    .asCallback(cb);
  },

  // Sync room to users associations.
  //
  // @param roomName [String] Room name.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise]
  roomStateSync(roomName, cb) {
    return this.state.getRoom(roomName)
    .then(room => {
      return this.checkRoomJoined(room);
    }
    )
    .asCallback(cb);
  },

  // Fix instance data after an incorrect service shutdown.
  //
  // @param id [String] Instance id.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise]
  instanceRecovery(id, cb) {
    return this.state.getInstanceSockets(id)
    .then(sockets => {
      return Promise.each(_.toPairs(sockets), ([id, userName]) => {
        return this.execUserCommand({userName, id}, 'disconnect', 'instance recovery');
      }
      );
    }
    )
    .asCallback(cb);
  },

  // Get instance heartbeat.
  //
  // @param id [String] Instance id.
  // @param cb [Callback] Optional callback.
  //
  // @return [Promise<Number>] Heartbeat timestamp.
  getInstanceHeartbeat(id, cb) {
    return this.state.getInstanceHeartbeat(id)
    .asCallback(cb);
  }
};


module.exports = RecoveryAPI;
