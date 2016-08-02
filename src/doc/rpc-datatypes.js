/*eslint no-unused-vars: 0*/

/**
 * RPC description, can be implemented via any bi-directional
 * messaging protocol.
 * @namespace rpc
 */

/**
 * Custom rpc data types definitions.
 * @namespace rpc.datatypes
 * @memberof rpc
 */

/**
 * Message. Other fields (that are not collide with {@link
 * rpc.datatypes.ProcessedMessage} additional fields) instead of
 * `textMessage` can be used if an appropriate {@link
 * chat-service.hooks.HooksInterface.directMessagesChecker} or {@link
 * chat-service.hooks.HooksInterface.roomMessagesChecker} hook is set.
 *
 * @typedef {Object} Message
 * @memberof rpc.datatypes
 * @property {string} textMessage - Text message.
 */

/**
 * Processed Message. Other fields (that are not collide with a server
 * assigned data) instead of `textMessage` can be used if an
 * appropriate {@link
 * chat-service.hooks.HooksInterface.directMessagesChecker} or {@link
 * chat-service.hooks.HooksInterface.roomMessagesChecker} hook is
 * set. Includes server assigned data.
 *
 * @typedef {Object} ProcessedMessage
 * @memberof rpc.datatypes
 * @property {string} textMessage - Text message.
 * @property {number} timestamp - Timestamp.
 * @property {string} author - Message sender.
 * @property {number} [id] - Message id, for room messages only.
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
 * Chat service error representation. Used when {@link
 * chat-service.config.options} `useRawErrorObjects` is set.
 *
 * @typedef {Object} ChatServiceError
 * @memberof rpc.datatypes
 * @property {string} name - Error name.
 * @property {string} [code] - Error code.
 * @property {Array} [args] - Error format arguments.
 *
 * @see rpc.datatypes.codeToFormat
 */