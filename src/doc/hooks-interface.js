/*eslint no-unused-vars: 0*/

/**
 * {@link chat-service.ChatService} hooks.
 *
 * @namespace hooks
 * @memberof chat-service
 *
 * @see chat-service.ChatService
 * @see chat-service.hooks.HooksInterface
 * @see chat-service.hooks.RequestsHooks
 */

/**
 * Before hooks are available for all {@link rpc.clientRequests} and
 * are executed after an arguments validation.
 *
 * @param {chat-service.ExecInfo} execInfo Command execution details.
 * @param {callback} [cb] Optional callback.
 *
 * @return {Promise<Array|undefined>} Resolves without a data to
 * continue a command execution. Rejections or a resolved array will
 * stop further execution, and return results to the command issuer.
 * @instance
 */
function beforeHook (execInfo, cb) {}

/**
 * After hooks are available for all {@link rpc.clientRequests} and
 * are executed after ChatService default event handlers.
 *
 * @param {chat-service.ExecInfo} execInfo Command execution details.
 * @param {callback} [cb] Optional callback.
 *
 * @return {Promise<Array|undefined>} Resolves without a data to
 * return unchanged command results to the command issuer. Rejections
 * or a resolved array will override command results.
 * @instance
 */
function afterHook (execInfo, cb) {}

/**
 * Requests hooks. For a concise description see {@link beforeHook}
 * and {@link afterHook}.
 *
 * @interface
 * @borrows beforeHook as RequestsHooks#directAddToListBefore
 * @borrows afterHook as RequestsHooks#directAddToListAfter
 * @borrows beforeHook as RequestsHooks#directGetAccessListBefore
 * @borrows afterHook as RequestsHooks#directGetAccessListAfter
 * @borrows beforeHook as RequestsHooks#directGetWhitelistModeBefore
 * @borrows afterHook as RequestsHooks#directGetWhitelistModeAfter
 * @borrows beforeHook as RequestsHooks#directMessageBefore
 * @borrows afterHook as RequestsHooks#directMessageAfter
 * @borrows beforeHook as RequestsHooks#directRemoveFromListBefore
 * @borrows afterHook as RequestsHooks#directRemoveFromListAfter
 * @borrows beforeHook as RequestsHooks#directSetWhitelistModeBefore
 * @borrows afterHook as RequestsHooks#directSetWhitelistModeAfter
 * @borrows beforeHook as RequestsHooks#listOwnSocketsBefore
 * @borrows afterHook as RequestsHooks#listOwnSocketsAfter
 * @borrows beforeHook as RequestsHooks#roomAddToListBefore
 * @borrows afterHook as RequestsHooks#roomAddToListAfter
 * @borrows beforeHook as RequestsHooks#roomCreateBefore
 * @borrows afterHook as RequestsHooks#roomCreateAfter
 * @borrows beforeHook as RequestsHooks#roomDeleteBefore
 * @borrows afterHook as RequestsHooks#roomDeleteAfter
 * @borrows beforeHook as RequestsHooks#roomGetAccessListBefore
 * @borrows afterHook as RequestsHooks#roomGetAccessListAfter
 * @borrows beforeHook as RequestsHooks#roomGetOwnerBefore
 * @borrows afterHook as RequestsHooks#roomGetOwnerAfter
 * @borrows beforeHook as RequestsHooks#roomGetWhitelistModeBefore
 * @borrows afterHook as RequestsHooks#roomGetWhitelistModeAfter
 * @borrows beforeHook as RequestsHooks#roomHistoryGetBefore
 * @borrows afterHook as RequestsHooks#roomHistoryGetAfter
 * @borrows beforeHook as RequestsHooks#roomHistoryInfoBefore
 * @borrows afterHook as RequestsHooks#roomHistoryInfoAfter
 * @borrows beforeHook as RequestsHooks#roomJoinBefore
 * @borrows afterHook as RequestsHooks#roomJoinAfter
 * @borrows beforeHook as RequestsHooks#roomLeaveBefore
 * @borrows afterHook as RequestsHooks#roomLeaveAfter
 * @borrows beforeHook as RequestsHooks#roomMessageBefore
 * @borrows afterHook as RequestsHooks#roomMessageAfter
 * @borrows beforeHook as RequestsHooks#roomRecentHistoryBefore
 * @borrows afterHook as RequestsHooks#roomRecentHistoryAfter
 * @borrows beforeHook as RequestsHooks#roomRemoveFromListBefore
 * @borrows afterHook as RequestsHooks#roomRemoveFromListAfter
 * @borrows beforeHook as RequestsHooks#roomSetWhitelistModeBefore
 * @borrows afterHook as RequestsHooks#roomSetWhitelistModeAfter
 * @borrows beforeHook as RequestsHooks#roomUserSeenBefore
 * @borrows afterHook as RequestsHooks#roomUserSeenAfter
 * @borrows beforeHook as RequestsHooks#systemMessageBefore
 * @borrows afterHook as RequestsHooks#systemMessageAfter
 * @memberof chat-service.hooks
 */
class RequestsHooks {}

/**
 * Hooks interface.
 * @interface
 * @extends chat-service.hooks.RequestsHooks
 * @memberof chat-service.hooks
 */
class HooksInterface extends RequestsHooks {

  /**
   * Client connection hook. Client can send requests only after this
   * hook is resolved.
   *
   * @param {ChatService} server Service instance.
   * @param {string} id Socket id.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<Array|string>} Resolves either a login string
   * (user name) or an array with a login string and an optional auth
   * data object. User name and auth data are send back with a {@link
   * rpc.serverNotifications.loginConfirmed} message. Error is sent as
   * a {@link rpc.serverNotifications.loginRejected} message.
   */
  onConnect (server, id, cb) {}

  /**
   * Client disconnection hook.
   *
   * @param {ChatService} server Service instance.
   * @param {string} id Socket id.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  onDisconnect (server, id, cb) {}

  /**
   * Executes when server is started (after a state and a transport are
   * up, but before requests processing is started).
   *
   * @param {ChatService} server Service instance.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  onStart (server, cb) {}

  /**
   * Executes when server is closed (after a transport is closed and
   * all clients are disconnected, but a state is still up).
   *
   * @param {ChatService} server Service instance.
   * @param {Error} [error] An error occurred during closing.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  onClose (server, error, cb) {}

  /**
   * Validator for `directMessage` message objects. When is set, a
   * custom format in direct messages is enabled. When hooks resolves,
   * than a message format is considered valid, and the other way
   * around for the rejection case.
   *
   * @param {Object} message Message object.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @see rpc.clientRequests.directMessage
   */
  directMessagesChecker (message, cb) {}

  /**
   * Validator for `roomMessage` message objects. When is set, a
   * custom format in room messages is enabled. When hooks resolves,
   * than a message format is considered valid, and the other way
   * around for the rejection case.
   *
   * @param {Object} message Message object.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @see rpc.clientRequests.roomMessage
   */
  roomMessagesChecker (message, cb) {}

}
