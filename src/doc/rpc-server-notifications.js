/*eslint valid-jsdoc: [2, { "requireReturn": false }]*/
/*eslint no-unused-vars: 0*/

/**
 * Notifications that are sent from a server to a client, no client's
 * reply is expected.
 *
 * @example <caption>Socket.io client example.</caption>
 *   let socket = io.connect(url, opts)
 *   socket.once('loginConfirmed', () => {
 *     socket.on('directMessage', (message) => {
 *       // just the same as any event. no reply is required.
 *     })
 *   })
 *
 * @namespace serverNotifications
 * @memberof rpc
 */

 /**
  * Direct message. A message will have timestamp and author fields,
  * but other fields can be used if `directMessagesChecker` hook is
  * set.
  *
  * @param {rpcTypes.ProcessedMessage} message Message.
  *
  * @see rpc.clientRequests.directMessage
  *
  * @memberof rpc.serverNotifications
  */
function directMessage (message) {}

 /**
  * Direct message echo. If an user have several connections from
  * different sockets, and if one client sends {@link
  * rpc.clientRequests.directMessage}, others will receive a
  * message echo.
  *
  * @param {string} toUser Message receiver.
  * @param {rpcTypes.ProcessedMessage} message Message.
  *
  * @see rpc.clientRequests.directMessage
  *
  * @memberof rpc.serverNotifications
  */
function directMessageEcho (toUser, message) {}

/**
 * A client should wait until this event before issuing requests. If
 * auth has failed {@link ServerNotification.loginRejected}
 * notification will be emitted instead. Only one of these events will
 * be emitted once per connection.
 *
 * @param {string} userName User name.
 * @param {rpcTypes.AuthData} authData Additional auth data.
 *
 * @see rpc.serverNotifications.loginRejected
 *
 * @memberof rpc.serverNotifications
 */
function loginConfirmed (userName, authData) {}

/**
 * An auth error event.
 *
 * @param {rpcTypes.ChatServiceError|Error|string} reason Error.
 *
 * @see rpc.serverNotifications.loginConfirmed
 *
 * @memberof rpc.serverNotifications
 */
function loginRejected (reason) {}

 /**
  * Indicates that a user has lost a room access permission.
  *
  * @param {string} roomName Room name.
  *
  * @see rpc.clientRequests.roomAddToList
  * @see rpc.clientRequests.roomRemoveFromList
  *
  * @memberof rpc.serverNotifications
  */
function roomAccessRemoved (roomName) {}

 /**
  * Indicates a room access list add.
  *
  * @param {string} roomName Rooms name.
  * @param {string} listName List name. Possible values are:
  * 'blacklist'|'adminlist'|'whitelist'
  * @param {Array<string>} userNames User names removed from the list.
  *
  * @see rpc.clientRequests.roomAddToList
  *
  * @memberof rpc.serverNotifications
  */
function roomAccessListAdded (roomName, listName, userNames) {}

 /**
  * Indicates a room access list remove.
  *
  * @param {string} roomName Rooms name.
  * @param {string} listName List name. Possible values are:
  * 'blacklist'|'adminlist'|'whitelist'
  * @param {Array<string>} userNames User names added to the list.
  *
  * @see rpc.clientRequests.roomRemoveFromList
  *
  * @memberof rpc.serverNotifications
  */
function roomAccessListRemoved (roomName, listName, userNames) {}

 /**
  * Echoes room join from other user's connections.
  *
  * @param {string} roomName User name.
  * @param {string} id Socket id.
  * @param {integer} njoined Number of sockets that are still joined.
  *
  * @see rpc.clientRequests.roomJoin
  *
  * @memberof rpc.serverNotifications
  */
function roomJoinedEcho (roomName, id, njoined) {}

 /**
  * Echoes room leave from other user's connections.
  *
  * @param {string} roomName User name.
  * @param {string} id Socket id.
  * @param {integer} njoined Number of sockets that are still joined.
  *
  * @see rpc.clientRequests.roomLeave
  *
  * @memberof rpc.serverNotifications
  */
function roomLeftEcho (roomName, id, njoined) {}

 /**
  * Room message. A message will have timestamp, id and author fields,
  * but other fields can be used if ChatService `roomMessagesChecker`
  * hook is set.
  *
  * @param {string} roomName Rooms name.
  * @param {rpcTypes.ProcessedMessage} message Message.
  *
  * @see rpc.clientRequests.roomMessage
  *
  * @memberof rpc.serverNotifications
  */
function roomMessage (roomName, message) {}

 /**
  * Indicates a room mode change.
  *
  * @param {string} roomName Rooms name.
  * @param {boolean} mode Room mode.
  *
  * @see rpc.clientRequests.roomSetWhitelistMode
  *
  * @memberof rpc.serverNotifications
  */
function roomModeChanged (roomName, mode) {}

 /**
  * Indicates that an another user has joined a room.
  *
  * @param {string} roomName Rooms name.
  * @param {string} userName User name.
  *
  * @see rpc.clientRequests.roomJoin
  *
  * @memberof rpc.serverNotifications
  */
function roomUserJoined (roomName, userName) {}

 /**
  * Indicates that an another user has left a room.
  *
  * @param {string} roomName Rooms name.
  * @param {string} userName User name.
  *
  * @see rpc.clientRequests.roomLeave
  *
  * @memberof rpc.serverNotifications
  */
function roomUserLeft (roomName, userName) {}

 /**
  * Custom message from an another socket of the same user.
  *
  * @param {Object} message Arbitrary data.
  *
  * @memberof rpc.serverNotifications
  */
function selfBroadcast (message) {}

 /**
  * Indicates a connection of an another socket with the same user.
  *
  * @param {string} id Socket id.
  * @param {integer} nconnected Total number of users's sockets.
  *
  * @memberof rpc.serverNotifications
  */
function socketConnectEcho (id, nconnected) {}

 /**
  * Indicates a disconnection of an another socket with the same user.
  *
  * @param {string} id Socket id.
  * @param {integer} nconnected Total number of users's sockets.
  *
  * @memberof rpc.serverNotifications
  */
function socketDisconnectEcho (id, nconnected) {}
