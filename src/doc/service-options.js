/*eslint no-unused-vars: 0*/

/**
 * {@link chat-service.ChatService} options.
 *
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
 * constructor arguments. If `useCluster` is set, used as arguments
 * for a cluster client constructor.
 */

/**
 * @memberof chat-service.config
 * @typedef {Object} SocketIOTransportOptions
 *
 * @property {string} [namespace='/chat-service'] Socket.io namespace.
 *
 * @property {Array<function>|funcition} [middleware] Socket.io
 * middleware to use on namespace.
 *
 * @property {Object} [io] Socket.io instance that should be used by
 * Chat Service.
 *
 * @property {Object} [http] Use socket.io http server integration, used
 * only when no `io` object is passed.
 *
 * @property {Object} [ioOptions] Socket.io additional options, used
 * only when no `io` object is passed.
 */

/**
 * @memberof chat-service.config
 * @typedef {Object} options
 *
 * @property {boolean} [port=8000] Port number.
 *
 * @property {boolean} [enableAccessListsUpdates=false] Default value
 * for new rooms. Enables {@link rpc.serverNotifications.roomModeChanged},
 * {@link rpc.serverNotifications.roomAccessListAdded} and {@link
 * rpc.serverNotifications.roomAccessListRemoved} notifications. Can
 * be changed individually for any room via {@link
 * chat-service.ServiceAPI#changeAccessListsUpdates}.
 *
 * @property {boolean} [enableDirectMessages=false] Enables user to
 * user {@link rpc.clientRequests.directMessage} communication.
 *
 * @property {boolean} [enableRoomsManagement=false] Allows to use
 * {@link rpc.clientRequests.roomCreate} and {@link
 * rpc.clientRequests.roomDelete}.
 *
 * @property {boolean} [enableUserlistUpdates=false] Default value for
 * new rooms. Enables {@link rpc.serverNotifications.roomUserJoined} and
 * {@link rpc.serverNotifications.roomUserLeft} messages. Can be
 * changed individually for any room via {@link
 * chat-service.ServiceAPI#changeUserlistUpdates}.
 *
 * @property {number} [historyMaxGetMessages=100] Room history size
 * available via {@link rpc.clientRequests.roomRecentHistory} or via a
 * single invocation {@link rpc.clientRequests.roomHistoryGet}.
 *
 * @property {number} [historyMaxSize=10000] Default value for
 * rooms. Can be changed individually for any room via {@link
 * chat-service.ServiceAPI#changeRoomHistoryMaxSize}.
 *
 * @property {number} [directListSizeLimit=1000] Maximum number of
 * entries allowed in direct messaging permissions lists.
 *
 * @property {number} [roomListSizeLimit=10000] Maximum number of
 * entries allowed in room messaging permissions lists (the `userlist`
 * is not affected by this option).
 *
 * @property {boolean} [useRawErrorObjects=false] Send error objects
 * instead of strings. See {@link rpc.datatypes.ChatServiceError}.
 *
 * @property {number} [closeTimeout=15000] Maximum time in ms to wait
 * before a server disconnects all clients on shutdown.
 *
 * @property {number} [heartbeatRate=10000] Service instance heartbeat
 * rate in ms.
 *
 * @property {number} [heartbeatTimeout=30000] Service instance
 * heartbeat timeout in ms, after this interval instance is considered
 * inactive.
 *
 * @property {number} [busAckTimeout=5000] Cluster bus ack waiting
 * timeout in ms.
 *
 * @property {('memory'|'redis'|Class)} [state='memory'] Chat state.
 *
 * @property {('socket.io'|Class)} [transport='socket.io'] Transport.
 *
 * @property {('memory'|'redis'|Class)} [adapter='memory'] Adapter for
 * service instances communication, must implement a
 * `socket.io-adapter` API. Used with `socket.io` transport only if no
 * `io` object is passed in `SocketIOTransportOptions`.
 *
 * @property {Options.RedisStateOptions|Object} [stateOptions] Options
 * for a state.
 *
 * @property {Options.SocketIOTransportOptions|Object}
 * [transportOptions] Options for a transport.
 *
 * @property {Object|Array<Object>} [adapterOptions] Adapter
 * constructor arguments, used only when no `io` object is passed in
 * `SocketIOTransportOptions`.
 */
