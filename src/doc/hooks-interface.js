'use strict'
/*eslint no-unused-vars: 0*/

/**
 * {@link chat-service.ChatService} hooks.
 *
 * @namespace hooks
 * @memberof chat-service
 *
 * @see chat-service.hooks.HooksInterface
 * @see chat-service.hooks.CommandsHooks
 */

/**
 * Before hooks are available for all {@link rpc.clientRequests} and
 * are executed after a command arguments validation, but before
 * Chat Service standard handler.
 *
 * @callback beforeHook
 *
 * @param {chat-service.ExecInfo} execInfo Command execution details.
 * @param {callback} [cb] Optional callback.
 *
 * @return {Promise<Array|undefined>} Resolves without a data to
 * continue a command execution. Rejections or a resolved array will
 * stop further execution, and return results to the command issuer.
 *
 * @static
 */

/**
 * After hooks are available for all {@link rpc.clientRequests} and
 * are executed after Chat Service standard handlers, but before
 * returning results to the command issuer.
 *
 * @callback afterHook
 *
 * @param {chat-service.ExecInfo} execInfo Command execution details.
 * @param {callback} [cb] Optional callback.
 *
 * @return {Promise<Array|undefined>} Resolves without a data to
 * return unchanged command results to the command issuer. Rejections
 * or a resolved array will override command results.
 *
 * @static
 */

/**
 * Commands hooks full list, they are available for all {@link
 * rpc.clientRequests}. There are just two types of command hooks, for
 * a concise description see {@link beforeHook} and {@link afterHook}.
 *
 * @interface
 * @borrows beforeHook as CommandsHooks#directAddToListBefore
 * @borrows afterHook as CommandsHooks#directAddToListAfter
 * @borrows beforeHook as CommandsHooks#directGetAccessListBefore
 * @borrows afterHook as CommandsHooks#directGetAccessListAfter
 * @borrows beforeHook as CommandsHooks#directGetWhitelistModeBefore
 * @borrows afterHook as CommandsHooks#directGetWhitelistModeAfter
 * @borrows beforeHook as CommandsHooks#directMessageBefore
 * @borrows afterHook as CommandsHooks#directMessageAfter
 * @borrows beforeHook as CommandsHooks#directRemoveFromListBefore
 * @borrows afterHook as CommandsHooks#directRemoveFromListAfter
 * @borrows beforeHook as CommandsHooks#directSetWhitelistModeBefore
 * @borrows afterHook as CommandsHooks#directSetWhitelistModeAfter
 * @borrows beforeHook as CommandsHooks#listOwnSocketsBefore
 * @borrows afterHook as CommandsHooks#listOwnSocketsAfter
 * @borrows beforeHook as CommandsHooks#roomAddToListBefore
 * @borrows afterHook as CommandsHooks#roomAddToListAfter
 * @borrows beforeHook as CommandsHooks#roomCreateBefore
 * @borrows afterHook as CommandsHooks#roomCreateAfter
 * @borrows beforeHook as CommandsHooks#roomDeleteBefore
 * @borrows afterHook as CommandsHooks#roomDeleteAfter
 * @borrows beforeHook as CommandsHooks#roomGetAccessListBefore
 * @borrows afterHook as CommandsHooks#roomGetAccessListAfter
 * @borrows beforeHook as CommandsHooks#roomGetOwnerBefore
 * @borrows afterHook as CommandsHooks#roomGetOwnerAfter
 * @borrows beforeHook as CommandsHooks#roomGetWhitelistModeBefore
 * @borrows afterHook as CommandsHooks#roomGetWhitelistModeAfter
 * @borrows beforeHook as CommandsHooks#roomHistoryGetBefore
 * @borrows afterHook as CommandsHooks#roomHistoryGetAfter
 * @borrows beforeHook as CommandsHooks#roomHistoryInfoBefore
 * @borrows afterHook as CommandsHooks#roomHistoryInfoAfter
 * @borrows beforeHook as CommandsHooks#roomJoinBefore
 * @borrows afterHook as CommandsHooks#roomJoinAfter
 * @borrows beforeHook as CommandsHooks#roomLeaveBefore
 * @borrows afterHook as CommandsHooks#roomLeaveAfter
 * @borrows beforeHook as CommandsHooks#roomMessageBefore
 * @borrows afterHook as CommandsHooks#roomMessageAfter
 * @borrows beforeHook as CommandsHooks#roomRecentHistoryBefore
 * @borrows afterHook as CommandsHooks#roomRecentHistoryAfter
 * @borrows beforeHook as CommandsHooks#roomRemoveFromListBefore
 * @borrows afterHook as CommandsHooks#roomRemoveFromListAfter
 * @borrows beforeHook as CommandsHooks#roomSetWhitelistModeBefore
 * @borrows afterHook as CommandsHooks#roomSetWhitelistModeAfter
 * @borrows beforeHook as CommandsHooks#roomUserSeenBefore
 * @borrows afterHook as CommandsHooks#roomUserSeenAfter
 * @borrows beforeHook as CommandsHooks#systemMessageBefore
 * @borrows afterHook as CommandsHooks#systemMessageAfter
 * @memberof chat-service.hooks
 *
 * @see rpc.clientRequests
 * @see chat-service.hooks.HooksInterface
 */
class CommandsHooks {}

/**
 * {@link chat-service.ChatService} hooks interface.
 * @interface
 * @extends chat-service.hooks.CommandsHooks
 * @memberof chat-service.hooks
 */
class HooksInterface extends CommandsHooks {

  /**
   * Client connection hook. Client can send requests or receive
   * notifications only after this hook is resolved.
   *
   * @param {chat-service.ChatService} server Service instance.
   * @param {string} id Socket id.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<Array|string>} Resolves either a login string
   * (user name) or an array with a login string and an optional auth
   * data object. User name and auth data are send back with a {@link
   * rpc.serverNotifications.loginConfirmed} message. Error is sent as
   * a {@link rpc.serverNotifications.loginRejected} message.
   *
   * @static
   */
  onConnect (server, id, cb) {}

  /**
   * Client disconnection hook.
   *
   * @param {chat-service.ChatService} server Service instance.
   * @param {string} id Socket id.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @static
   */
  onDisconnect (server, id, cb) {}

  /**
   * Executes when server is started (after a state and a transport are
   * up, but before requests processing is started).
   *
   * @param {chat-service.ChatService} server Service instance.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @static
   */
  onStart (server, cb) {}

  /**
   * Executes when server is closed (after a transport is closed and
   * all clients are disconnected, but a state is still up).
   *
   * @param {chat-service.ChatService} server Service instance.
   * @param {Error} [error] An error occurred during closing.
   * @param {callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   *
   * @static
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
   *
   * @static
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
   *
   * @static
   */
  roomMessagesChecker (message, cb) {}

}
