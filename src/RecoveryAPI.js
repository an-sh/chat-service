
const Promise = require('bluebird')
const _ = require('lodash')

/**
 * Service infrastructure failures recovery.
 *
 * @mixin
 * @memberof chat-service
 * @see chat-service.ChatService
 */
class RecoveryAPI {

  constructor (state, transport, execUserCommand, instanceUID) {
    this.state = state
    this.transport = transport
    this.instanceUID = instanceUID
    this.execUserCommand = execUserCommand
  }

  checkUserSockets (user) {
    let { userName } = user
    return user.userState.getSocketsToInstance().then(sockets => {
      return Promise.each(_.toPairs(sockets), ([socket, instance]) => {
        if (instance === this.instanceUID) {
          if (!this.transport.getSocket(socket)) {
            return user.userState.removeSocket(socket)
          }
        }
        return Promise.resolve()
      })
    }).then(() => {
      return user.userState.getSocketsToRooms()
    }).then(data => {
      let args = _.values(data)
      return _.intersection(...args)
    }).then(rooms => {
      return Promise.each(rooms, roomName => {
        return this.state.getRoom(roomName)
          .then(room => room.roomState.hasInList('userlist', userName))
          .then(isPresent =>
                isPresent ? Promise.resolve() : user.removeFromRoom(roomName))
          .catchReturn()
      })
    })
  }

  checkRoomJoined (room) {
    let { roomName } = room
    return room.getList(null, 'userlist', true).then(userlist => {
      return Promise.each(userlist, userName => {
        return this.state.getUser(userName).then(user => {
          return user.userState.getRoomToSockets(roomName).then(sockets => {
            if (!sockets || !sockets.length) {
              return user.removeFromRoom(roomName)
            } else {
              return Promise.resolve()
            }
          }).catchReturn()
            .then(() => room.checkAcess(userName))
            .catch(() => user.removeFromRoom(roomName))
        }).catchReturn()
      })
    })
  }

  /**
   * Sync user to sockets associations.
   *
   * @param {string} userName User name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  userStateSync (userName, cb) {
    return this.state.getUser(userName)
      .then(user => this.checkUserSockets(user))
      .asCallback(cb)
  }

  /**
   * Sync room to users associations.
   *
   * @param {string} roomName Room name.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  roomStateSync (roomName, cb) {
    return this.state.getRoom(roomName)
      .then(room => this.checkRoomJoined(room))
      .asCallback(cb)
  }

  /**
   * Fix instance data after an incorrect service shutdown.
   *
   * @param {string} id Instance id.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  instanceRecovery (id, cb) {
    return this.state.getInstanceSockets(id).then(sockets => {
      return Promise.each(_.toPairs(sockets), ([id, userName]) => {
        return this.state.getUser(userName)
          .then((user) => user.removeSocket(id))
          .catchReturn()
      })
    }).asCallback(cb)
  }

  /**
   * Get instance heartbeat.
   *
   * @param {string} id Instance id.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<number>} Heartbeat timestamp.
   */
  getInstanceHeartbeat (id, cb) {
    return this.state.getInstanceHeartbeat(id).asCallback(cb)
  }

}

module.exports = RecoveryAPI
