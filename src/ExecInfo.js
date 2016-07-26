
/**
 * ExecInfo is available for {@link rpc.clientRequests} hooks.
 * @see chat-service.hooks.HooksInterface
 * @memberof chat-service
 * @interface
 */
class ExecInfo {
  /**
   * Service instance.
   * @name chat-service.ExecInfo#server
   * @type ChatService
   */

  /**
   * User name.
   * @name chat-service.ExecInfo#userName
   * @type String|null
   */

  /**
   * Socket id.
   * @name chat-service.ExecInfo#id
   * @type String|null
   */

  /**
   * Bypass permissions.
   * @name chat-service.ExecInfo#bypassPermissions
   * @type Boolean
   * @default false
   * @see chat-service.ServiceAPI#execUserCommand
   */

  /**
   * Don't call requests hooks if `true`.
   * @name chat-service.ExecInfo#bypassHooks
   * @type Boolean
   * @default false
   * @see chat-service.ServiceAPI#execUserCommand
   */

  /**
   * Request error.
   * @name chat-service.ExecInfo#error
   * @type Error|null
   * @default null
   */

  /**
   * Request results.
   * @name chat-service.ExecInfo#results
   * @type {Array<Object>}
   * @default null
   */

  /**
   * Request arguments.
   * @name chat-service.ExecInfo#args
   * @type {Array<Object>}
   * @default []
   */

  /**
   * Additional arguments, passed after command arguments. Can be used
   * as additional hooks parameters.
   * @name chat-service.ExecInfo#restArgs
   * @type {Array<Object>}
   * @default []
   */

  constructor () {
    this.server = null
    this.userName = null
    this.id = null
    this.bypassPermissions = null
    this.bypassHooks = false
    this.error = null
    this.results = null
    this.args = []
    this.restArgs = []
  }

}

module.exports = ExecInfo
