
/**
 * Notifications that are sent from a server to a client, no client's
 * reply is expected.
 *
 * @module ServerNotifications
 * @example <caption>Socket.io client example.</caption>
 *   let socket = io.connect(url, opts)
 *   socket.once('loginConfirmed', () => {
 *     socket.on('directMessage', (message) => {
 *       // just the same as any event. no reply is required.
 *     })
 *   })
 */

 /**
  * Direct message. A message will have timestamp and author fields,
  * but other fields can be used if `directMessagesChecker` hook is
  * set.
  *
  * @param {rpcTypes.ProcessedMessage} message Message.
  *
  * @see module:ClientRequests.directMessage
  */
exports.directMessage = function (message) {}

 /**
  * Direct message echo. If an user have several connections from
  * different sockets, and if one client sends {@link
  * module:ClientRequests.directMessage}, others will receive a
  * message echo.
  *
  * @param {string} toUser Message receiver.
  * @param {rpcTypes.ProcessedMessage} message Message.
  *
  * @see module:ClientRequests.directMessage
  */
exports.directMessageEcho = function (toUser, message) {}

/**
 * A client should wait until this event before issuing commands. If
 * auth has failed {@link module:ServerNotification.loginRejected}
 * notification will be emitted instead. Only one of these events will
 * be emitted once per connection.
 *
 * @param {string} userName User name.
 * @param {rpcTypes.AuthData} authData Additional auth data.
 *
 * @see module:ServerNotification.loginRejected
 */
exports.loginConfirmed = function (userName, authData) {}

/**
 * An auth error event.
 *
 * @param {rpcTypes.ChatServiceError|Error|string} reason Error.
 *
 * @see module:ServerNotification.loginConfirmed
 */
exports.loginRejected = function (reason) {}

 /**
  * Indicates that a user has lost a room access permission.
  *
  * @param {string} roomName Room name.
  *
  * @see module:ClientRequests.roomAddToList
  * @see module:ClientRequests.roomRemoveFromList
  */
exports.roomAccessRemoved = function (roomName) {}

 /**
  * Indicates a room access list add.
  *
  * @param {string} roomName Rooms name.
  * @param {('blacklist'|'adminlist'|'whitelist')} listName List name.
  * @param {Array<string>} userNames User names removed from the list.
  *
  * @see module:ClientRequests.roomAddToList
  */
exports.roomAccessListAdded = function (roomName, listName, userNames) {}

 /**
  * Indicates a room access list remove.
  *
  * @param {string} roomName Rooms name.
  * @param {('blacklist'|'adminlist'|'whitelist')} listName List name.
  * @param {Array<string>} userNames User names added to the list.
  *
  * @see module:ClientRequests.roomRemoveFromList
  */
exports.roomAccessListRemoved = function (roomName, listName, userNames) {}

 /**
  * Echoes room join from other user's connections.
  *
  * @param {string} roomName User name.
  * @param {string} id Socket id.
  * @param {integer} njoined Number of sockets that are still joined.
  *
  * @see module:ClientRequests.roomJoin
  */
exports.roomJoinedEcho = function (roomName, id, njoined) {}

 /**
  * Echoes room leave from other user's connections.
  *
  * @param {string} roomName User name.
  * @param {string} id Socket id.
  * @param {integer} njoined Number of sockets that are still joined.
  *
  * @see module:ClientRequests.roomLeave
  */
exports.roomLeftEcho = function (roomName, id, njoined) {}

 /**
  * Room message. A message will have timestamp, id and author fields,
  * but other fields can be used if ChatService `roomMessagesChecker`
  * hook is set.
  *
  * @param {string} roomName Rooms name.
  * @param {rpcTypes.ProcessedMessage} message Message.
  *
  * @see module:ClientRequests.roomMessage
  */
exports.roomMessage = function (roomName, message) {}

 /**
  * Indicates a room mode change.
  *
  * @param {string} roomName Rooms name.
  * @param {boolean} mode Room mode.
  *
  * @see module:ClientRequests.roomSetWhitelistMode
  */
exports.roomModeChanged = function (roomName, mode) {}

 /**
  * Indicates that an another user has joined a room.
  *
  * @param {string} roomName Rooms name.
  * @param {string} userName User name.
  *
  * @see module:ClientRequests.roomJoin
  */
exports.roomUserJoined = function (roomName, userName) {}

 /**
  * Indicates that an another user has left a room.
  *
  * @param {string} roomName Rooms name.
  * @param {string} userName User name.
  *
  * @see module:ClientRequests.roomLeave
  */
exports.roomUserLeft = function (roomName, userName) {}

 /**
  * Custom message from an another socket of the same user.
  *
  * @param {Object} message Arbitrary data.
  */
exports.selfBroadcast = function (message) {}

 /**
  * Indicates a connection of an another socket with the same user.
  *
  * @param {string} id Socket id.
  * @param {integer} nconnected Total number of users's sockets.
  */
exports.socketConnectEcho = function (id, nconnected) {}

 /**
  * Indicates a disconnection of an another socket with the same user.
  *
  * @param {string} id Socket id.
  * @param {integer} nconnected Total number of users's sockets.
  */
exports.socketDisconnectEcho = function (id, nconnected) {}
