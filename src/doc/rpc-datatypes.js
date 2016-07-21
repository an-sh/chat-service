/*eslint no-unused-vars: 0*/

/**
 * RPC description.
 * @namespace rpc
 */

/**
 * Custom rpc data types definitions.
 * @namespace rpc.datatypes
 * @memberof rpc
 */

/**
 * Message. Other fields instead of `textMessage` can be used if an
 * appropriate ChatService `directMessagesChecker` or
 * `roomMessagesChecker` hook is set.
 *
 * @typedef {Object} Message
 * @memberof rpc.datatypes
 * @property {string} textMessage - Text message.
 */

/**
 * Processed Message. Other fields instead of `textMessage` can be
 * used if an appropriate ChatService `directMessagesChecker` or
 * `roomMessagesChecker` hook is set. Includes server assigned data.
 *
 * @typedef {Object} ProcessedMessage
 * @memberof rpc.datatypes
 * @property {string} textMessage - Text message.
 * @property {number} timestamp - Timestamp.
 * @property {string} author - Message sender.
 * @property {number|void} id - Message id, for room messages only.
 */

/**
 * Room history information.
 *
 * @typedef {Object} HistoryInfo
 * @memberof rpc.datatypes
 * @property {number} historyMaxGetMessages - Room single get limit.
 * @property {number} historyMaxSize - Room history limit.
 * @property {number} historySize - Room current history size.
 * @property {number} lastMessageId - Room last message id.
 */

/**
 * Room user seen state information.
 *
 * @typedef {Object} UserSeenInfo
 * @memberof rpc.datatypes
 * @property {number} timestamp - Last state changed.
 * @property {boolean} joined - User's current joined state.
 */

/**
 * User sockets info. Keys are socket ids, and values are arrays of
 * joined rooms.
 *
 * @typedef {Object<string, Array<string>>} SocketsInfo
 * @memberof rpc.datatypes
 */

/**
 * User auth data. May have additional properties.
 *
 * @typedef {Object} AuthData
 * @memberof rpc.datatypes
 * @property {string} id - Socket id.
 */

/**
 * Chat service error representation.
 *
 * @typedef {Object} ChatServiceError
 * @memberof rpc.datatypes
 * @property {string} name - Error name.
 * @property {Array} args - Additional error data.
 */
