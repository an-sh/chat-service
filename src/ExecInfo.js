
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
   * @type string|null
   */

  /**
   * Socket id.
   * @name chat-service.ExecInfo#id
   * @type string|null
   */

  /**
   * Bypass permissions.
   * @name chat-service.ExecInfo#bypassPermissions
   * @type boolean
   * @default false
   * @see chat-service.ServiceAPI#execUserCommand
   */

  /**
   * If command is executed from a server side.
   * @name chat-service.ExecInfo#isLocalCall
   * @type boolean
   * @default false
   * @see chat-service.ServiceAPI#execUserCommand
   */

  /**
   * Don't call requests hooks if `true`.
   * @name chat-service.ExecInfo#bypassHooks
   * @type boolean
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
    this.args = []
    this.bypassHooks = false
    this.bypassPermissions = null
    this.error = null
    this.id = null
    this.isLocalCall = false
    this.restArgs = []
    this.results = null
    this.server = null
    this.userName = null
  }

}

module.exports = ExecInfo
