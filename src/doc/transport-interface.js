/*eslint valid-jsdoc: [2, { "requireReturn": true }]*/
/*eslint no-unused-vars: 0*/
/*eslint no-useless-constructor: 0*/

/**
 * Transport interface. A transport plugin also must implement all
 * private methods.
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
   * @param {chat-service.ChatService} server ChatService.
   * @param {chat-service.config.SocketIOTransportOptions} options
   * Transport options.
   * @param {Class} [adapterConstructor] socket.io-adapter compatible
   * adapter constructor.
   * @param {Array} [adapterOptions] Adapter constructor arguments.
   *
   * @private
   */
  constructor (server, options, adapterConstructor, adapterOptions) {}

  /**
   * Starts accepting of clients connections.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @private
   */
  setEvents () {}

  /**
   * Stops accepting of clients connections. Disconnects currently
   * connected clients.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @private
   */
  close () {}

  /**
   * Creates a handler for a custom transport event. Must not coincide
   * with {@link rpc.clientRequests} or transport system event names.
   *
   * @param {string} id Socket id.
   * @param {string} name Event name.
   * @param {function} fn Handler.
   *
   * @return {undefined}
   */
  bindHandler (id, name, fn) {}

  /**
   * Gets a transport socket object by id.
   *
   * @param {string} id Socket id.
   *
   * @return {Object} Socket object.
   */
  getSocket (id) {}

  /**
   *
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

  /**
   * Adds a socket to a channel.
   *
   * @param {string} id Socket id.
   * @param {string} channel Transport channel.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @private
   */
  joinChannel (id, channel) {}

  /**
   * Removes a socket form a channel.
   *
   * @param {string} id Socket id.
   * @param {string} channel Transport channel.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @private
   */
  leaveChannel (id, channel) {}

  /**
   * Disconnects a socket.
   *
   * @param {string} id Socket id.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @private
   */
  disconnectSocket (id) {}

}
