'use strict'
/* eslint no-unused-vars: 0 */

/**
 * Notifications that are sent from a server to a client, no client's
 * reply is expected.
 *
 * @example <caption>socket.io client example</caption>
 *   let socket = io.connect(url, opts)
 *   // the handler will persist across reconnections.
 *   socket.on('directMessage', message => {
 *     // just the same as any event. no reply is required.
 *   })
 *
 * @namespace serverNotifications
 * @memberof rpc
 *
 * @see rpc.clientRequests
 */

/**
  * Direct message.
  *
  * @param {rpc.datatypes.ProcessedMessage} message Message.
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
  * @param {rpc.datatypes.ProcessedMessage} message Message.
  *
  * @see rpc.clientRequests.directMessage
  *
  * @memberof rpc.serverNotifications
  */
function directMessageEcho (toUser, message) {}

/**
 * A client should wait until this event before issuing any
 * requests. If auth has failed {@link
 * rpc.serverNotifications.loginRejected} notification will be emitted
 * instead. Only one of these two events will be emitted once per
 * connection. Also transport plugins may use other means of login
 * confirmation.
 *
 * @param {string} userName User name.
 * @param {rpc.datatypes.AuthData} authData Additional auth data.
 *
 * @see rpc.serverNotifications.loginRejected
 *
 * @memberof rpc.serverNotifications
 */
function loginConfirmed (userName, authData) {}

/**
 * An auth error event. Also transport plugins may use other means of
 * login rejection.
 *
 * @param {rpc.datatypes.ChatServiceError|string} reason Error.
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
  * @see chat-service.ServiceAPI#changeAccessListsUpdates
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
  * @see chat-service.ServiceAPI#changeAccessListsUpdates
  *
  * @memberof rpc.serverNotifications
  */
function roomAccessListRemoved (roomName, listName, userNames) {}

/**
  * Echoes room join events from other connections of the same user,
  * or a room join event for this connection triggered by the server.
  *
  * @param {string} roomName User name.
  * @param {string} id Socket id.
  * @param {number} njoined Number of sockets that are still joined.
  *
  * @see rpc.clientRequests.roomJoin
  *
  * @memberof rpc.serverNotifications
  */
function roomJoinedEcho (roomName, id, njoined) {}

/**
  * Echoes room leave events from other connections of the same user,
  * or a room leave event for this connection triggered by the server.
  *
  * @param {string} roomName User name.
  * @param {string} id Socket id.
  * @param {number} njoined Number of sockets that are still joined.
  *
  * @see rpc.clientRequests.roomLeave
  *
  * @memberof rpc.serverNotifications
  */
function roomLeftEcho (roomName, id, njoined) {}

/**
  * Room message.
  *
  * @param {string} roomName Rooms name.
  * @param {rpc.datatypes.ProcessedMessage} message Message.
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
  * @see chat-service.ServiceAPI#changeAccessListsUpdates
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
  * @see chat-service.ServiceAPI#changeUserlistUpdates
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
  * @see chat-service.ServiceAPI#changeUserlistUpdates
  *
  * @memberof rpc.serverNotifications
  */
function roomUserLeft (roomName, userName) {}

/**
  * Indicates a connection of an another socket with the same user.
  *
  * @param {string} id Socket id.
  * @param {number} nconnected Total number of users's sockets.
  *
  * @memberof rpc.serverNotifications
  */
function socketConnectEcho (id, nconnected) {}

/**
  * Indicates a disconnection of an another socket with the same user.
  *
  * @param {string} id Socket id.
  * @param {number} nconnected Total number of users's sockets.
  *
  * @memberof rpc.serverNotifications
  */
function socketDisconnectEcho (id, nconnected) {}

/**
  * Custom message from an another socket of the same user.
  *
  * @param {Object} message Arbitrary data.
  *
  * @memberof rpc.serverNotifications
  */
function systemMessage (message) {}
