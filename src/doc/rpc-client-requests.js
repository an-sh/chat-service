'use strict'
/* eslint no-unused-vars: 0 */

/**
 * Requests that are sent from a client to a server, for each request
 * a reply will be sent back with a possible result data. Some
 * requests will trigger sending {@link rpc.serverNotifications} to
 * other clients. Result data types are described as returned
 * values. If {@link chat-service.config.options} `useRawErrorObjects`
 * option is off, then errors type is `string`. Otherwise errors have
 * a {@link rpc.datatypes.ChatServiceError} type. Details of how
 * results or errors are returned depend on a transport used, for more
 * information see examples below. Essentially each request triggers
 * an execution of a command in a socket+user context.
 *
 * @example <caption>socket.io client example</caption>
 *   let socket = io.connect(url, opts)
 *   socket.on('loginConfirmed', () => {
 *     // Code is run after each reconnection.
 *     socket.emit('roomJoin', roomName, (error, result) => {
 *       // This is a socket.io ack waiting callback. Socket is joined
 *       // the room, or an error occurred, we get here only when the
 *       // server has finished roomJoin command processing. Error
 *       // or results are passed as arguments, using Node.js style
 *       // callbacks.
 *     })
 *   })
 *
 * @namespace clientRequests
 * @memberof rpc
 *
 * @see rpc.serverNotifications
 * @see chat-service.ServiceAPI#execUserCommand
 * @see chat-service.hooks.CommandsHooks
 */

/**
  * Adds user names to user's direct messaging blacklist or whitelist.
  *
  * @param {string} listName List name. Possible values are:
  * 'blacklist'|'whitelist'
  * @param {Array<string>} userNames User names to add to the list.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @memberof rpc.clientRequests
  */
function directAddToList (listName, userNames) {}

/**
  * Gets direct messaging blacklist or whitelist.
  *
  * @param {string} listName List name. Possible values are:
  * 'blacklist'|'whitelist'
  *
  * @returns {Array<string>} The requested list.
  *
  * @memberof rpc.clientRequests
  */
function directGetAccessList (listName) {}

/**
  * Gets direct messaging whitelist only mode. If it is true then
  * direct messages are allowed only for users that are in the
  * whitelist. Otherwise direct messages are accepted from all users
  * that are not in the blacklist.
  *
  * @returns {boolean} User's whitelist only mode.
  *
  * @memberof rpc.clientRequests
  */
function directGetWhitelistMode () {}

/**
  * Sends {@link rpc.serverNotifications.directMessage} to an another
  * user, if {@link chat-service.config.options}
  * `enableDirectMessages` option is true. Also sends {@link
  * rpc.serverNotifications.directMessageEcho} to other sender's
  * sockets.
  *
  * @param {string} toUser Message receiver.

  * @param {rpc.datatypes.Message} message Direct message.
  *
  * @returns {rpc.datatypes.ProcessedMessage} Processed message.
  *
  * @see rpc.serverNotifications.directMessage
  * @see rpc.serverNotifications.directMessageEcho
  *
  * @memberof rpc.clientRequests
  */
function directMessage (toUser, message) {}

/**
  * Removes user names from user's direct messaging blacklist or whitelist.
  *
  * @param {string} listName List name. Possible values are:
  * 'blacklist'|'whitelist'
  * @param {Array<string>} userNames User names to remove from the
  * list.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @memberof rpc.clientRequests
  */
function directRemoveFromList (listName, userNames) {}

/**
  * Sets direct messaging whitelist only mode.
  *
  * @param {boolean} mode Room mode.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @see rpc.clientRequests.directGetWhitelistMode
  *
  * @memberof rpc.clientRequests
  */
function directSetWhitelistMode (mode) {}

/**
  * Gets a list of all sockets with corresponding joined rooms. This
  * returns information about all user's sockets.
  *
  * @returns {rpc.datatypes.SocketsInfo} User sockets info.
  *
  * @see rpc.serverNotifications.roomJoinedEcho
  * @see rpc.serverNotifications.roomLeftEcho
  *
  * @memberof rpc.clientRequests
  */
function listOwnSockets () {}

/**
  * Adds user names to room's blacklist, adminlist and whitelist. Also
  * removes users that have lost an access permission in the result of
  * an operation, sending {@link
  * rpc.serverNotifications.roomAccessRemoved}. Also sends {@link
  * rpc.serverNotifications.roomAccessListAdded} to all room users if
  * room's `enableAccessListsUpdates` option is true.
  *
  * @param {string} roomName Room name.
  * @param {string} listName List name. Possible values are:
  * 'blacklist'|'adminlist'|'whitelist'
  * @param {Array<string>} userNames User names to add to the list.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @see rpc.serverNotifications.roomAccessRemoved
  * @see rpc.serverNotifications.roomAccessListAdded
  *
  * @memberof rpc.clientRequests
  */
function roomAddToList (roomName, listName, userNames) {}

/**
  * Creates a room if {@link chat-service.config.options}
  * `enableRoomsManagement` option is true.
  *
  * @param {string} roomName Rooms name.
  * @param {bool} mode Room mode.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @memberof rpc.clientRequests
  */
function roomCreate (roomName, mode) {}

/**
  * Deletes a room if {@link chat-service.config.options}
  * `enableRoomsManagement` is true and the user has an owner
  * status. Sends {@link rpc.serverNotifications.roomAccessRemoved} to
  * all room users.
  *
  * @param {string} roomName Rooms name.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @memberof rpc.clientRequests
  */
function roomDelete (roomName) {}

/**
  * Gets room messaging userlist, blacklist, adminlist and whitelist.
  *
  * @param {string} roomName Room name.
  *
  * @param {string} listName List name. Possible values are:
  * 'blacklist'|'adminlist'|'whitelist'|'userlist'
  *
  * @returns {Array<string>} The requested list.
  *
  * @memberof rpc.clientRequests
  */
function roomGetAccessList (roomName, listName) {}

/**
  * Gets the room owner.
  *
  * @param {string} roomName Room name.
  *
  * @returns {string} Room owner.
  *
  * @memberof rpc.clientRequests
  */
function roomGetOwner (roomName) {}

/**
  * Gets the room messaging whitelist only mode. If it is true, then
  * join is allowed only for users that are in the
  * whitelist. Otherwise all users that are not in the blacklist can
  * join.
  *
  * @param {string} roomName Room name.
  *
  * @returns {boolean} Whitelist only mode.
  *
  * @memberof rpc.clientRequests
  */
function roomGetWhitelistMode (roomName) {}

/**
  * Gets latest room messages. The maximum size is set by {@link
  * chat-service.config.options} `historyMaxGetMessages`
  * option. Messages are sorted as newest first.
  *
  * @param {string} roomName Room name.
  *
  * @returns {Array<rpc.datatypes.ProcessedMessage>} An array of
  * messages.
  *
  * @see rpc.clientRequests.roomMessage
  *
  * @memberof rpc.clientRequests
  */
function roomRecentHistory (roomName) {}

/**
  * Returns messages that were sent after a message with the specified
  * id. The returned number of messages is limited by the limit
  * parameter. The maximum limit is bounded by {@link
  * chat-service.config.options} `historyMaxGetMessages` option. If
  * the specified id was deleted due to history limit, it returns
  * messages starting from the oldest available. Messages are sorted
  * as newest first.
  *
  * @param {string} roomName Room name.
  * @param {number} id Starting message id (not included in result).
  * @param {number} limit Maximum number of messages to return. The
  * maximum number is limited by {@link chat-service.config.options}
  * `historyMaxGetMessages` option.
  *
  * @returns {Array<rpc.datatypes.ProcessedMessage>} An array of messages.
  *
  * @see rpc.clientRequests.roomHistoryInfo
  * @see rpc.clientRequests.roomMessage
  *
  * @memberof rpc.clientRequests
  */
function roomHistoryGet (roomName, id, limit) {}

/**
  * Gets the the room history information.
  *
  * @param {string} roomName Room name.
  *
  * @returns {rpc.datatypes.HistoryInfo} Room history information.
  *
  * @see rpc.clientRequests.roomHistoryGet
  *
  * @memberof rpc.clientRequests
  */
function roomHistoryInfo (roomName) {}

/**
  * Joins room, an user must join the room to receive messages or
  * execute requests with a `room` prefix. Sends {@link
  * rpc.serverNotifications.roomJoinedEcho} to other user's
  * sockets. Also sends {@link rpc.serverNotifications.roomUserJoined}
  * to other room users if room's `enableUserlistUpdates` option is
  * true.
  *
  * @param {string} roomName Room name.
  *
  * @returns {number} A number of still joined user's sockets to the room.
  *
  * @see rpc.serverNotifications.roomJoinedEcho
  * @see rpc.serverNotifications.roomUserJoined
  *
  * @memberof rpc.clientRequests
  */
function roomJoin (roomName) {}

/**
  * Leaves room. Sends {@link rpc.serverNotifications.roomLeftEcho} to
  * other user's sockets. Also sends {@link
  * rpc.serverNotifications.roomUserLeft} to other room users if
  * room's `enableUserlistUpdates` option is true.
  *
  * @param {string} roomName Room name.
  *
  * @returns {number} A number of joined user's sockets to the room.
  *
  * @see rpc.serverNotifications.roomLeftEcho
  * @see rpc.serverNotifications.roomUserLeft
  *
  * @memberof rpc.clientRequests
  */
function roomLeave (roomName) {}

/**
  * Sends {@link rpc.serverNotifications.roomMessage} to all room
  * users.
  *
  * @param {string} roomName Room name.
  * @param {rpc.datatypes.Message} message Message.
  *
  * @returns {number} The message id.
  *
  * @see rpc.serverNotifications.roomMessage
  *
  * @memberof rpc.clientRequests
  */
function roomMessage (roomName, message) {}

/**
  * Gets room's notifications configuration.
  *
  * @param {string} roomName Room name.
  *
  * @returns {rpc.datatypes.NotificationsInfo} Room notifications
  * information.
  *
  * @see rpc.serverNotifications
  *
  * @memberof rpc.clientRequests
  */
function roomNotificationsInfo (roomName) {}

/**
  * Removes user names from room's blacklist, adminlist and
  * whitelist. Also removes users that have lost an access permission
  * in the result of an operation, sending {@link
  * rpc.serverNotifications.roomAccessRemoved}.  Also sends {@link
  * rpc.serverNotifications.roomAccessListRemoved} to all room users
  * if room's `enableAccessListsUpdates` option is true.
  *
  * @param {string} roomName Room name.
  * @param {string} listName List name.  Possible values are:
  * 'blacklist'|'adminlist'|'whitelist'
  * @param {Array<string>} userNames User names to remove from the list.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @see rpc.serverNotifications.roomAccessRemoved
  * @see rpc.serverNotifications.roomAccessListRemoved
  *
  * @memberof rpc.clientRequests
  */
function roomRemoveFromList (roomName, listName, userNames) {}

/**
  * Sets room messaging whitelist only mode. Also removes users that
  * have lost an access permission in the result of an operation,
  * sending {@link rpc.serverNotifications.roomAccessRemoved}. Also
  * sends {@link rpc.serverNotifications.roomModeChanged} to all room
  * users if room's `enableAccessListsUpdates` option is true.
  *
  * @param {string} roomName Room name.
  * @param {boolean} mode Room mode.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @see rpc.clientRequests.roomGetWhitelistMode
  * @see rpc.serverNotifications.roomModeChanged
  *
  * @memberof rpc.clientRequests
  */
function roomSetWhitelistMode (roomName, mode) {}

/**
  * Send user's joined state and last state change timestamp.
  *
  * @param {string} roomName Rooms name.
  * @param {string} userName User name.
  *
  * @returns {rpc.datatypes.UserSeenInfo} Seen info.
  *
  * @memberof rpc.clientRequests
  */
function roomUserSeen (roomName, userName) {}

/**
  * Send data to other connected users's sockets.
  *
  * @param {Object} message Arbitrary data.
  *
  * @returns {undefined} Acknowledgment without data.
  *
  * @memberof rpc.clientRequests
  */
function systemMessage (message) {}
