'use strict'
/* eslint no-unused-vars: 0 */
/* eslint no-useless-constructor: 0 */

/**
 * Handler.
 *
 * @callback chat-service.TransportInterface#handler
 * @param {...*} args
 * @return {Promise<Array>} Array of results.
 */

/**
 * Transport public interface.
 *
 * @interface
 * @memberof chat-service
 */
class TransportInterface {
  /**
   * Connection handshake data. May include other fields.
   *
   * @typedef {Object} HandshakeData
   * @memberof chat-service.TransportInterface
   *
   * @property {boolean} isConnected If the socket is still
   * connected. If it is not, then headers and query will be empty.
   *
   * @property {Object} headers Parsed headers.
   * @property {Object} query Parsed query string.
   */

  /**
   * Binds a handler for a custom transport event for the provided
   * socket. Must not coincide with {@link rpc.clientRequests} or
   * transport system event names. May be used inside {@link
   * chat-service.hooks.HooksInterface#onConnect} hook.
   *
   * @param {string} id Socket id.
   * @param {string} name Event name.
   * @param {chat-service.TransportInterface#handler} fn Handler.
   *
   * @return {undefined}
   */
  bindHandler (id, name, fn) {}

  /**
   * Gets a transport socket by id.
   *
   * @param {string} id Socket id.
   *
   * @return {Object} Socket object.
   */
  getSocket (id) {}

  /**
   * Gets a transport server.
   *
   * @return {Object} Transport server.
   */
  getServer () {}

  /**
   * Sends an event directly to a transport channel. May be used to
   * implement lightweight room notifications.
   *
   * @param {string} channel Corresponds to a room name.
   * @param {string} eventName Event name.
   * @param {...*} eventData Event data.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */

  emitToChannel (channel, eventName, ...eventData) {}

  /**
   *
   * The same as {@link chat-service.TransportInterface#emitToChannel},
   * but excludes the sender socket from recipients.
   *
   * @param {string} id Sender socket id.
   * @param {string} channel Corresponds to a room name.
   * @param {string} eventName Event name.
   * @param {...*} eventData Event data.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  sendToChannel (id, channel, eventName, ...eventData) {}

  /**
   * Gets socket handshake data.
   *
   * @param {string} id Socket id.
   * @returns {chat-service.TransportInterface.HandshakeData} Handshake data.
   */
  getHandshakeData (id) {}
}

/**
 * Transport plugin. Methods __MUST__ return bluebird `^3.0.0`
 * compatible promises (not just ES6 promises). __Note:__ These
 * methods __MUST NOT__ be called directly. For public methods see
 * {@link chat-service.TransportInterface}
 *
 * @implements {chat-service.TransportInterface}
 * @memberof chat-service
 * @protected
 */
class TransportPlugin {
  /**
   * @param {chat-service.ChatService} server Service instance.
   * @param {Object} options Transport options.
   */
  constructor (server, options) {}

  /**
   * Cluster communication via an adapter. Emits messages to all
   * services nodes, including the sender node.
   *
   * @name chat-service.TransportPlugin#clusterBus
   * @type EventEmitter
   * @readonly
   * @protected
   */

  /**
   * Transport is closed and no any handlers invocations will be made.
   *
   * @name chat-service.TransportPlugin#closed
   * @type boolean
   * @readonly
   * @protected
   */

  /**
   * Starts accepting clients' connections. On each new connection
   * `ChatService` integration methods must be called. See
   * `src/SocketIOTransport.js` for details about integration.
   *
   * @return {undefined}
   * @protected
   */
  setEvents () {}

  /**
   * Stops accepting clients' connections. Disconnects all currently
   * connected clients.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   * @protected
   */
  close () {}

  /**
   * Adds a socket to a channel.
   *
   * @param {string} id Socket id.
   * @param {string} channel Transport channel.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   * @protected
   */
  joinChannel (id, channel) {}

  /**
   * Removes a socket form a channel.
   *
   * @param {string} id Socket id.
   * @param {string} channel Transport channel.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   * @protected
   */
  leaveChannel (id, channel) {}

  /**
   * Disconnects a socket.
   *
   * @param {string} id Socket id.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   * @protected
   */
  disconnectSocket (id) {}
}
