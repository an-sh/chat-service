
// ExecInfo is available for {UserCommands} hooks. See
// {HooksInterface}.
class ExecInfo {

  // @property [ChatService] Service instance.
  server = null;

  // @property [String or null] User name.
  userName = null;

  // @property [String or null] Socket id.
  id = null;

  // @property [Boolean] Bypass permissions, see
  //   {ServiceAPI~execUserCommand}.
  bypassPermissions = false;

  // @property [Boolean] Don't call command hooks if `true`.
  bypassHooks = false;

  // @property [Error] Command error.
  error = null;

  // @property [Array<Object>] Command results.
  results = null;

  // @property [Array<Object>] Command arguments.
  args = [];

  // @property [Array<Object>] Additional arguments, passed after
  //   command arguments. Can be used as additional hooks parameters.
  restArgs = [];

  // @private
  // @nodoc
  constructor() {}
}


export default ExecInfo;
