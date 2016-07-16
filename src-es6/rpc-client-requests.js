
/**
 * Requests that are sent from a client to a server, for each request
 * a reply will be sent back with a possible result data. Result data
 * types are described as returned values. If ChatService
 * `useRawErrorObjects` option is off, then errors type is
 * `string`. Otherwise errors have a {@link rpcTypes.ChatServiceError}
 * type. Details of how results or errors are returned depend on a
 * transport used, for more information see examples below.
 *
 * @module ClientRequests
 * @example <caption>Socket.io client example.</caption>
 *   let socket = io.connect(url, opts)
 *   socket.once('loginConfirmed', () => {
 *     socket.emit('roomJoin', roomName, (error, result) => {
 *       // this is a socket.io ack waiting callback. socket is joined
 *       // the room, or an error occurred, we get here only when the
 *       // server has finished roomJoin command processing.
 *       // error or results are passed as arguments, using Node.js
 *       // style callbacks.
 *     })
 *   })
 */

 /**
  * Adds user names to user's direct messaging blacklist or whitelist.
  *
  * @param {('blacklist'|'whitelist')} listName List name.
  * @param {Array<string>} userNames User names to add to the list.
  *
  * @returns {void} Acknowledgment without data.
  */
exports.directAddToList = function (listName, userNames) {}

 /**
  * Gets direct messaging blacklist or whitelist.
  *
  * @param {('blacklist'|'whitelist')} listName List name.
  *
  * @returns {Array<string>} The requested list.
  */
exports.directGetAccessList = function (listName) {}

 /**
  * Gets direct messaging whitelist only mode. If it is true then
  * direct messages are allowed only for users that are in the
  * whitelist. Otherwise direct messages are accepted from all users
  * that are not in the blacklist.
  *
  * @returns {boolean} User's whitelist only mode.
  */
exports.directGetWhitelistMode = function () {}

 /**
  * Sends {@link module:ServerNotifications.directMessage} to an
  * another user, if ChatService `enableDirectMessages` option is
  * true. Also sends {@link
  * module:ServerNotifications.directMessageEcho} to other senders's
  * sockets.
  *
  * @param {string} toUser Message receiver.

  * @param {rpcTypes.Message} message Direct message.
  *
  * @returns {rpcTypes.ProcessedMessage} Processed message.
  *
  * @see module:ServerNotifications.directMessage
  * @see module:ServerNotifications.directMessageEcho
  */
exports.directMessage = function (toUser, message) {}

 /**
  * Removes user names from user's direct messaging blacklist or whitelist.
  *
  * @param {('blacklist'|'whitelist')} listName List name.
  * @param {Array<string>} userNames User names to remove from the list.
  *
  * @returns {void} Acknowledgment without data.
  */
exports.directRemoveFromList = function (listName, userNames) {}

 /**
  * Sets direct messaging whitelist only mode.
  *
  * @param {boolean} mode Room mode.
  *
  * @returns {void} Acknowledgment without data.
  *
  * @see module:ClientRequests.directGetWhitelistMode
  */
exports.directSetWhitelistMode = function (mode) {}

 /**
  * Gets a list of all sockets with corresponding joined rooms. This
  * returns information about all user's sockets.
  *
  * @returns {rpcTypes.SocketsInfo} User sockets info.
  *
  * @see module:ServerNotifications.roomJoinedEcho
  * @see module:ServerNotifications.roomLeftEcho
  */
exports.listOwnSockets = function () {}

 /**
  * Adds user names to room's blacklist, adminlist and whitelist. Also
  * removes users that have lost an access permission in the result of
  * an operation, sending {@link
  * module:ServerNotifications.roomAccessRemoved}. Also sends {@link
  * module:ServerNotifications.roomAccessListAdded} to all room users
  * if ChatService `enableAccessListsUpdates` option is true.
  *
  * @param {string} roomName Room name.
  * @param {('blacklist'|'adminlist'|'whitelist')} listName List name.
  * @param {Array<string>} userNames User names to add to the list.
  *
  * @returns {void} Acknowledgment without data.
  *
  * @see module:ServerNotifications.roomAccessRemoved
  * @see module:ServerNotifications.roomAccessListAdded
  */
exports.roomAddToList = function (roomName, listName, userNames) {}

 /**
  * Creates a room if ChatService `enableRoomsManagement` option is
  * true.
  *
  * @param {string} roomName Rooms name.
  * @param {bool} mode Room mode.
  *
  * @returns {void} Acknowledgment without data.
  */
exports.roomCreate = function (roomName, mode) {}

 /**
  * Deletes a room if ChatService `enableRoomsManagement` is true and
  * the user has an owner status. Sends {@link
  * module:ServerNotifications.roomAccessRemoved} to all room users.
  *
  * @param {string} roomName Rooms name.
  *
  * @returns {void} Acknowledgment without data.
  */
exports.roomDelete = function (roomName) {}

 /**
  * Gets room messaging userlist, blacklist, adminlist and whitelist.
  *
  * @param {string} roomName Room name.
  * @param {('blacklist'|'adminlist'|'whitelist'|'userlist')} listName List name.
  *
  * @returns {Array<string>} The requested list.
  */
exports.roomGetAccessList = function (roomName, listName) {}

 /**
  * Gets the room owner.
  *
  * @param {string} roomName Room name.
  *
  * @returns {string} Room owner.
  */
exports.roomGetOwner = function (roomName) {}

 /**
  * Gets the room messaging whitelist only mode. If it is true, then
  * join is allowed only for users that are in the
  * whitelist. Otherwise all users that are not in the blacklist can
  * join.
  *
  * @param {string} roomName Room name.
  *
  * @returns {boolean} Whitelist only mode.
  */
exports.roomGetWhitelistMode = function (roomName) {}

 /**
  * Gets latest room messages. The maximum size is set by ChatService
  * `historyMaxGetMessages` option. Messages are sorted as newest
  * first.
  *
  * @param {string} roomName Room name.
  *
  * @returns {Array<rpcTypes.ProcessedMessage>} An array of messages.
  *
  * @see module:ClientRequests.roomMessage
  */
exports.roomRecentHistory = function (roomName) {}

 /**
  * Returns messages that were sent after a message with the specified
  * id. The returned number of messages is limited by the limit
  * parameter. The maximum limit is bounded by ChatService
  * `historyMaxGetMessages` option. If the specified id was deleted
  * due to history limit, it returns messages starting from the oldest
  * available. Messages are sorted as newest first.
  *
  * @param {string} roomName Room name.
  * @param {integer} id Starting message id.
  * @param {integer} limit Maximum number of messages to return. The
  *   maximum number is limited by ChatService `historyMaxGetMessages`
  *   option.
  *
  * @returns {Array<rpcTypes.ProcessedMessage>} An array of messages.
  *
  * @see module:ClientRequests.roomHistoryLastId
  * @see module:ClientRequests.roomMessage
  */
exports.roomHistoryGet = function (roomName, id, limit) {}

 /**
  * Gets the the room history information.
  *
  * @param {string} roomName Room name.
  *
  * @returns {rpcTypes.HistoryInfo} Room history information.
  *
  * @see module:ClientRequests.roomHistoryGet
  */
exports.roomHistoryInfo = function (roomName) {}

 /**
  * Joins room, an user must join the room to receive messages or
  * execute room commands. Sends {@link
  * module:ServerNotifications.roomJoinedEcho} to other user's
  * sockets. Also sends {@link
  * module:ServerNotifications.roomUserJoined} to other room users if
  * ChatService `enableUserlistUpdates` option is true.
  *
  * @param {string} roomName Room name.
  *
  * @returns {integer} A number of still joined user's sockets to the room.
  *
  * @see module:ServerNotifications.roomJoinedEcho
  * @see module:ServerNotifications.roomUserJoined
  */
exports.roomJoin = function (roomName) {}

 /**
  * Leaves room. Sends {@link module:ServerNotifications.roomLeftEcho}
  * to other user's sockets. Also sends {@link
  * module:ServerNotifications.roomUserLeft} to other room users if
  * ChatService `enableUserlistUpdates` option is true.
  *
  * @param {string} roomName Room name.
  *
  * @returns {integer} A number of joined user's sockets to the room.
  *
  * @see module:ServerNotifications.roomLeftEcho
  * @see module:ServerNotifications.roomUserLeft
  */
exports.roomLeave = function (roomName) {}

 /**
  * Sends {@link module:ServerNotifications.roomMessage} to all room
  * users.
  *
  * @param {string} roomName Room name.
  * @param {rpcTypes.Message} message Message.
  *
  * @returns {integer} The message id.
  *
  * @see module:ServerNotifications.roomMessage
  */
exports.roomMessage = function (roomName, message) {}

 /**
  * Removes user names from room's blacklist, adminlist and
  * whitelist. Also removes users that have lost an access permission
  * in the result of an operation, sending {@link
  * module:ServerNotifications.roomAccessRemoved}.  Also sends {@link
  * module:ServerNotifications.roomAccessListRemoved} to all room
  * users if ChatService `enableAccessListsUpdates` option is true.
  *
  * @param {string} roomName Room name.
  * @param {('blacklist'|'adminlist'|'whitelist')} listName List name.
  * @param {Array<string>} userNames User names to remove from the list.
  *
  * @returns {void} Acknowledgment without data.
  *
  * @see module:ServerNotifications.roomAccessRemoved
  * @see module:ServerNotifications.roomAccessListRemoved
  */
exports.roomRemoveFromList = function (roomName, listName, userNames) {}

 /**
  * Sets room messaging whitelist only mode. Also removes users that
  * have lost an access permission in the result of an operation,
  * sending {@link module:ServerNotifications.roomAccessRemoved}.
  *
  * @param {string} roomName Room name.
  * @param {boolean} mode Room mode.
  *
  * @returns {void} Acknowledgment without data.
  *
  * @see module:ClientRequests.roomGetWhitelistMode
  * @see module:ServerNotifications.roomAccessRemoved
  */
exports.roomSetWhitelistMode = function (roomName, mode) {}

 /**
  * Send user's joined state and last state change timestamp.
  *
  * @param {string} roomName Rooms name.
  * @param {string} userName User name.
  *
  * @returns {rpcTypes.UserSeenInfo} Seen info.
  */
exports.roomUserSeen = function (roomName, userName) {}

 /**
  * Send data to other connected users's sockets.
  *
  * @param {Object} message Arbitrary data.
  *
  * @returns {void} Acknowledgment without data.
  */
exports.selfBroadcast = function (message) {}
