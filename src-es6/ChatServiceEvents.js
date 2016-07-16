
const { EventEmitter } = require('events')

/**
 * @interface
 * ChatService operational events.
 */
class ChatServiceEvents extends EventEmitter {

  /**
   * Service is ready, state and transport are up.
   * @event ChatServiceEvents#ready
   *
   */

  /**
   * Service is closed, state and transport are closed.
   * @event ChatServiceEvents#closed
   * @param {Error} [error] If was closed due to an error.
   *
   */

  /**
   * State store failed to be updated to reflect the current user
   * connections or presence state
   * @event ChatServiceEvents#storeConsistencyFailure
   * @param {Error} error Error.
   * @param {Object} operationInfo Operation details.
   * @property {String} operationInfo.userName User name.
   * @property {String} operationInfo.opType Operation type.
   * @property {String} [operationInfo.roomName] Room name.
   * @property {String} [operationInfo.id] Socket id.
   */

  /**
   * Failed to teardown a transport connection.
   * @event ChatServiceEvents#transportConsistencyFailure
   *
   * @param {Error} error Error.
   * @param {Object} operationInfo Operation details.
   * @property {String} operationInfo.userName User name.
   * @property {String} operationInfo.opType Operation type.
   * @property {String} [operationInfo.roomName] Room name.
   * @property {String} [operationInfo.id] Socket id.
   */

  /**
   * Lock was hold longer than a lock ttl.
   * @event ChatServiceEvents#lockTimeExceeded
   *
   * @param {String} id Lock id.
   * @param {Object} lockInfo Lock resource details.
   * @property {String} [lockInfo.userName] User name.
   * @property {String} [lockInfo.roomName] Room name.
   */

}

module.exports = ChatServiceEvents
