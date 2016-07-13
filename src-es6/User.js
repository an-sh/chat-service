
import ChatServiceError from './ChatServiceError';
import CommandBinder from './CommandBinder';
import DirectMessaging from './DirectMessaging';
import Promise from 'bluebird';
import UserAssociations from './UserAssociations';
import _ from 'lodash';

import { asyncLimit, checkNameSymbols, mix } from './utils';


// @private
// @nodoc
//
// Client commands implementation.
class User extends DirectMessaging {

  // @private
  constructor(server, userName) {
    super();
    this.server = server;
    this.userName = userName;
    this.state = this.server.state;
    this.transport = this.server.transport;
    this.validator = this.server.validator;
    this.hooks = this.server.hooks;
    this.enableUserlistUpdates = this.server.enableUserlistUpdates;
    this.enableAccessListsUpdates = this.server.enableAccessListsUpdates;
    this.enableRoomsManagement = this.server.enableRoomsManagement;
    this.enableDirectMessages = this.server.enableDirectMessages;
    let State = this.server.state.UserState;
    this.userState = new State(this.server, this.userName);
    this.lockTTL = this.state.lockTTL;
    this.echoChannel = this.userState.echoChannel;
  }

  // @private
  initState(state) {
    return super.initState();
  }

  // @private
  removeState() {
    return super.removeState();
  }

  // @private
  processMessage(msg, setTimestamp = false) {
    delete msg.id;
    delete msg.timestamp;
    if (setTimestamp) {
      msg.timestamp = _.now();
    }
    msg.author = this.userName || msg.author;
    return msg;
  }

  // @private
  exec(command, options = {}, args) {
    let { id } = options;
    if (!this.server.userCommands[command]) {
      var error = new ChatServiceError('noCommand', command);
      return Promise.reject(error);
    }
    if (!id && command === 'disconnect' || command === 'roomJoin' || command === 'roomLeave') {
      var error = new ChatServiceError('noSocket', command);
      return Promise.reject(error);
    }
    let fn = this[command];
    let cmd = this.makeCommand(command, fn);
    return Promise.fromCallback(cb => cmd(args, options, cb)
    , {multiArgs: true});
  }

  // @private
  checkOnline() {
    return this.userState.getAllSockets()
    .then(sockets => {
      if (!sockets || !sockets.length) {
        return Promise.reject(new ChatServiceError('noUserOnline', this.userName));
      }
    }
    );
  }

  // @private
  consistencyFailure(error, operationInfo = {}) {
    operationInfo.userName = this.userName;
    let name = operationInfo.opType === 'transportChannel' ?
      'transportConsistencyFailure'
    :
      'storeConsistencyFailure';
    this.server.emit(name, error, operationInfo);
  }

  // @private
  registerSocket(id) {
    return this.state.addSocket(id, this.userName)
    .then(() => {
      return this.userState.addSocket(id, this.server.instanceUID);
    }
    )
    .then(nconnected => {
      if (!this.transport.getConnectionObject(id)) {
        return this.removeUserSocket(id)
        .then(() => Promise.reject(new ChatServiceError('noSocket', 'connection')));
      } else {
        for (let cmd in this.server.userCommands) {
          this.bindCommand(id, cmd, this[cmd]); //bug decaffeinate 2.16.0
        }
        return [ this, nconnected ];
      }
    }
    );
  }

  // @private
  disconnectInstanceSockets() {
    return this.userState.getAllSockets()
    .then(sockets => {
      return Promise.map(sockets, sid => {
        return this.transport.disconnectClient(sid);
      }
      , { concurrency : asyncLimit });
    }
    );
  }

  // @private
  directAddToList(listName, values) {
    return this.addToList(this.userName, listName, values)
    .return();
  }

  // @private
  directGetAccessList(listName) {
    return this.getList(this.userName, listName);
  }

  // @private
  directGetWhitelistMode() {
    return this.getMode(this.userName);
  }

  // @private
  directMessage(recipientName, msg, {id, bypassPermissions}) {
    if (!this.enableDirectMessages) {
      let error = new ChatServiceError('notAllowed');
      return Promise.reject(error);
    }
    this.processMessage(msg, true);
    return this.server.state.getUser(recipientName)
    .then(recipient => {
      let channel = recipient.echoChannel;
      return recipient.message(this.userName, msg, bypassPermissions)
      .then(() => recipient.checkOnline())
      .then(() => {
        this.transport.emitToChannel(channel, 'directMessage', msg);
        this.transport.sendToChannel(id, this.echoChannel, 'directMessageEcho'
        , recipientName, msg);
        return msg;
      }
      );
    }
    );
  }

  // @private
  directRemoveFromList(listName, values) {
    return this.removeFromList(this.userName, listName, values)
    .return();
  }

  // @private
  directSetWhitelistMode(mode) {
    return this.changeMode(this.userName, mode)
    .return();
  }

  // @private
  disconnect(reason, {id}) {
    return this.removeSocketFromServer(id);
  }

  // @private
  listOwnSockets() {
    return this.userState.getSocketsToRooms();
  }

  // @private
  roomAddToList(roomName, listName, values, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.addToList(this.userName, listName, values, bypassPermissions);
    }
    )
    .then(userNames => {
      if (this.enableAccessListsUpdates) {
        this.transport.emitToChannel(roomName, 'roomAccessListAdded'
        , roomName, listName, values);
      }
      return this.removeRoomUsers(roomName, userNames)
      .return();
    }
    );
  }

  // @private
  roomCreate(roomName, whitelistOnly, {bypassPermissions}) {
    if (!this.enableRoomsManagement && !bypassPermissions) {
      let error = new ChatServiceError('notAllowed');
      return Promise.reject(error);
    }
    return checkNameSymbols(roomName)
    .then(() => {
      return this.state.addRoom(roomName
      , { owner : this.userName, whitelistOnly });
    }
    )
    .return();
  }

  // @private
  roomDelete(roomName, {bypassPermissions}) {
    if (!this.enableRoomsManagement && !bypassPermissions) {
      let error = new ChatServiceError('notAllowed');
      return Promise.reject(error);
    }
    return this.state.getRoom(roomName)
    .then(room => {
      return room.checkIsOwner(this.userName, bypassPermissions)
      .then(() => room.startRemoving())
      .then(() => room.getUsers())
      .then(userNames => {
        return this.removeRoomUsers(roomName, userNames);
      }
      )
      .then(() => {
        return this.state.removeRoom(roomName);
      }
      )
      .then(() => room.removeState())
      .return();
    }
    );
  }

  // @private
  roomGetAccessList(roomName, listName, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.getList(this.userName, listName, bypassPermissions);
    }
    );
  }

  // @private
  roomGetOwner(roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.getOwner(this.userName, bypassPermissions);
    }
    );
  }

  // @private
  roomGetWhitelistMode(roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.getMode(this.userName, bypassPermissions);
    }
    );
  }

  // @private
  roomRecentHistory(roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.getRecentMessages(this.userName, bypassPermissions);
    }
    );
  }

  // @private
  roomHistoryGet(roomName, msgid, limit, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.getMessages(this.userName, msgid, limit, bypassPermissions);
    }
    );
  }

  // @private
  roomHistoryInfo(roomName, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.getHistoryInfo(this.userName, bypassPermissions);
    }
    );
  }

  // @private
  roomJoin(roomName, {id}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return this.joinSocketToRoom(id, roomName);
    }
    );
  }

  // @private
  roomLeave(roomName, {id}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return this.leaveSocketFromRoom(id, room.roomName);
    }
    );
  }

  // @private
  roomMessage(roomName, msg, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      this.processMessage(msg);
      return room.message(this.userName, msg, bypassPermissions);
    }
    )
    .then(pmsg => {
      this.transport.emitToChannel(roomName, 'roomMessage', roomName, pmsg);
      return pmsg.id;
    }
    );
  }

  // @private
  roomRemoveFromList(roomName, listName, values, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.removeFromList(this.userName, listName, values, bypassPermissions);
    }
    )
    .then(userNames => {
      if (this.enableAccessListsUpdates) {
        this.transport.emitToChannel(roomName, 'roomAccessListRemoved',
        roomName, listName, values);
      }
      return this.removeRoomUsers(roomName, userNames);
    }
    )
    .return();
  }

  // @private
  roomSetWhitelistMode(roomName, mode, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.changeMode(this.userName, mode, bypassPermissions);
    }
    )
    .spread((userNames, mode) => {
      if (this.enableAccessListsUpdates) {
        this.transport.emitToChannel(roomName, 'roomModeChanged', roomName, mode);
      }
      return this.removeRoomUsers(roomName, userNames);
    }
    );
  }

  // @private
  roomUserSeen(roomName, userName, {bypassPermissions}) {
    return this.state.getRoom(roomName)
    .then(room => {
      return room.userSeen(this.userName, userName, bypassPermissions);
    }
    );
  }

  // @private
  systemMessage(data, {id}) {
    this.transport.sendToChannel(id, this.echoChannel, 'systemMessage', data);
    return Promise.resolve();
  }
}

mix(User, CommandBinder, UserAssociations);


export default User;
