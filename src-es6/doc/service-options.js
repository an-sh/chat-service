
/**
 * {@link ChatService} constructor options.
 * @namespace config
 * @memberof chat-service
 */

/**
 * @memberof chat-service.config
 * @typedef {Object} RedisStateOptions
 *
 * @property {boolean} [useCluster=false] Enable Redis cluster.
 *
 * @property {number} [lockTTL=10000] Locks timeout in ms.
 *
 * @property {Object|Array<Object>} [redisOptions] ioredis client
 *   constructor arguments. If `useCluster` is set, used as arguments
 *   for a Cluster client.
 */

/**
 * @memberof chat-service.config
 * @typedef {Object} SocketIOTransportOptions
 *
 * @property {string} [namespace='/chat-service'] Socket.io namespace.
 *
 * @property {Object} [io] Socket.io instance that should be used by
 *   ChatService.
 *
 * @property {Object} [http] Use socket.io http server integration, used
 *   only when no `io` object is passed.
 *
 * @property {Object} [ioOptions] Socket.io additional options, used
 *   only when no `io` object is passed.
 */

/**
 * @memberof chat-service.config
 * @typedef {Object} options
 *
 * @property {boolean} [port=8000] Port number.
 *
 * @property {boolean} [enableAccessListsUpdates=false] Enables
 *   {UserCommands#roomModeChanged},
 *   {UserCommands#roomAccessListAdded} and
 *   {UserCommands#roomAccessListRemoved} notifications.
 *
 * @property {boolean} [enableDirectMessages=false] Enables user to
 *   user {UserCommands#directMessage} communication.
 *
 * @property {boolean} [enableRoomsManagement=false] Allows to use
 *   {UserCommands#roomCreate} and {UserCommands#roomDelete}.
 *
 * @property {boolean} [enableUserlistUpdates=false] Enables
 *   {ServerMessages#roomUserJoined} and {ServerMessages#roomUserLeft}
 *   messages.
 *
 * @property {number} [historyMaxGetMessages=100] Room history size
 *   available via {UserCommands#roomRecentHistory} or via a single
 *   invocation {UserCommands#roomHistoryGet}.
 *
 * @property {number} [defaultHistoryLimit=10000] Is used for
 *   {UserCommands#roomCreate} or when {ServiceAPI~addRoom} is called
 *   without `historyMaxSize` option.
 *
 * @property {boolean} [useRawErrorObjects=false] Send error objects
 *   instead of strings. See {ChatServiceError}.
 *
 * @property {number} [closeTimeout=15000] Maximum time in ms to wait
 *   before a server disconnects all clients on shutdown.
 *
 * @property {number} [heartbeatRate=10000] Service instance heartbeat
 *   rate in ms.
 *
 * @property {number} [heartbeatTimeout=30000] Service instance
 *   heartbeat timeout in ms, after this interval instance is
 *   considered inactive.
 *
 * @property {number} [busAckTimeout=5000] Cluster bus ack waiting
 *   timeout in ms.
 *
 * @property {('memory'|'redis'|Class)} [state='memory'] Chat
 *   state.
 *
 * @property {('socket.io'|Class)} [transport='socket.io']
 *   Transport.
 *
 * @property {('memory'|'redis'|Class)} [adapter='memory']
 *   Socket.io adapter, used only if no `io` object is passed in
 *   `transportOptions`.
 *
 * @property {Options.RedisStateOptions|Object}
 *   [stateOptions] Options for a state.
 *
 * @property {Options.SocketIOTransportOptions|Object}
 *   [transportOptions] Options for a transport.
 *
 * @property {Object|Array<Object>} [adapterOptions] Socket.io adapter
 *   constructor arguments, used only when no `io` object is passed in
 *   `SocketIOTransportOptions`.
 */
