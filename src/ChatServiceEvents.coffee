
EventEmitter = require('events').EventEmitter

# ChatService operational events.
class ChatServiceEvents extends EventEmitter

  # @event ready Service is ready.
  #
  # @event closed
  #   Service is closed.
  #   @param [Error or undefined] error Non-null if closed due to an error.
  #
  # @event storeConsistencyFailure
  #   Store failed to be updated to reflect the current user
  #   connections or presence state.
  #
  #   @param [Error] error Error.
  #   @param [Object] operationInfo Operation details.
  #   @option operationInfo [String] userName User name.
  #   @option operationInfo [String] opType Operation type.
  #   @option operationInfo [String or undefined] roomName Room name.
  #   @option operationInfo [String or undefined] id Socket id.
  #
  # @event transportConsistencyFailure
  #   Failed to tear down a transport connection.
  #
  #   @param [Error] error Error.
  #   @param [Object] operationInfo Operation details.
  #   @option operationInfo [String] userName User name.
  #   @option operationInfo [String] opType Operation type.
  #   @option operationInfo [String or undefined] roomName Room name.
  #   @option operationInfo [String or undefined] id Socket id.
  constructor : ->
    super


module.exports = ChatServiceEvents
