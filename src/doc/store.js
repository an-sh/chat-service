'use strict'
/* eslint no-unused-vars: 0 */
/* eslint no-useless-constructor: 0 */

/**
 * Store plugin. See `src/RedisState.js` and `src/MemoryState.js` for
 * implementation details. Methods __MUST__ return bluebird `^3.0.0`
 * compatible promises (not just ES6 promises).
 *
 * @memberof chat-service
 * @protected
 */
class StorePlugin {
  /**
   * @param {chat-service.ChatService} server Service instance.
   * @param {Object} options Store options.
   */
  constructor (server, options) {}
}
