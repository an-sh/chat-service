
/**
 * Hooks interface.
 * @todo Complete this spec.
 * @memberof! chat-service
 * @interface
 */
class HooksInterface {

  /**
   * Client connection hook. Client can send requests only after this
   * hook is resolved.
   *
   * @param {ChatService} server Service instance.
   * @param {string} id Socket id.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<Array|string>} Resolves either a login string
   *   (user name) or an array with a login string and an optional
   *   auth data object. User name and auth data are send back with a
   *   `loginConfirmed` message. Error is sent as a `loginRejected`
   *   message.
   */
  onClientConnect (server, id, cb) {}

  /**
   * Client disconnection hook.
   *
   * @param {ChatService} server Service instance.
   * @param {string} id Socket id.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  onClientDisonnect (server, id, cb) {}

  /**
   * Executes when server is started (after a state and a transport are
   * up, but before message processing is started).
   *
   * @param {ChatService} server Service instance.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  onSeverStart (server, cb) {}

  /**
   * Executes when server is closed (after a transport is closed and
   * all clients are disconnected, but a state is still up).
   *
   * @param {ChatService} server Service instance.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  onServerClose (server, cb) {}

  /**
   * Validator for `directMessage` message objects. When is set, a
   * custom format in direct messages is enabled. When hooks resolves,
   * than a message format is considered valid, and the other way
   * around for the rejection case.
   *
   * @param {Object} message Message object.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  directMessagesValidator (message, cb) {}

  /**
   * Validator for `roomMessage` message objects. When is set, a
   * custom format in room messages is enabled. When hooks resolves,
   * than a message format is considered valid, and the other way
   * around for the rejection case.
   *
   * @param {Object} message Message object.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<undefined>} Promise that resolves without any data.
   */
  roomMessagesValidator (message, cb) {}

  /**
   * Before hooks are available for all `ClientRequests` and are
   * executed after an arguments validation.
   *
   * @param {ExecInfo} execInfo Command execution details.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<Array|void>} Resolves without a data to continue
   *   a command execution. Rejections or a resolved array will stop
   *   further execution, and return results to the command issuer.
   */
  clientRequestBefore (execInfo, cb) {}

  /**
   * After hooks are available for all `ClientRequests` and are
   * executed after ChatService default event handlers.
   *
   * @param {ExecInfo} execInfo Command execution details.
   * @param {Callback} [cb] Optional callback.
   *
   * @return {Promise<Array|void>} Resolves without a data to return
   *   unchanged command results to the command issuer. Rejections or
   *   a resolved array will override command results.
   */
  clientRequestAfter (execInfo, cb) {}

}

module.exports = HooksInterface
