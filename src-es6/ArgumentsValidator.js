
import ChatServiceError from './ChatServiceError';
import FastMap from 'collections/fast-map';
import Promise from 'bluebird';
import _ from 'lodash';
import check from 'check-types';

import { getUserCommands, possiblyCallback } from './utils';


// Commands arguments type and count validation. Can be used for hooks
// development, an instance of {ArgumentsValidator} implementation is
// available as a member of {ChatService} instance.
class ArgumentsValidator {

  // @private
  // @nodoc
  constructor(server) {
    this.server = server;
    this.checkers = new FastMap();
    this.directMessagesChecker = this.server.directMessagesChecker;
    this.roomMessagesChecker = this.server.roomMessagesChecker;
    this.customCheckers = {
      directMessage : [ null, this.directMessagesChecker ],
      roomMessage : [ null, this.roomMessagesChecker ]
    };
    let commands = getUserCommands(this.server)
    for (let idx in commands) {
      let cmd = commands[idx]
      this.checkers.set(cmd, this[cmd]());
    }
  }

  // Check command arguments.
  //
  // @param name [String] Command name.
  // @param args [Rest...] Command arguments with an optional callback.
  //
  // @return [Promise]
  checkArguments(name, ...args) {
    let [nargs, cb] = possiblyCallback(args);
    return Promise.try(() => {
      let checkers = this.checkers.get(name);
      if (!checkers) {
        var error = new ChatServiceError('noCommand', name);
        return Promise.reject(error);
      }
      var error = this.checkTypes(checkers, nargs);
      if (error) { return Promise.reject(error); }
      let customCheckers = this.customCheckers[name] || [];
      return Promise.each(customCheckers, function(checker, idx) {
        if (checker) {
          return Promise.fromCallback(fn => checker(nargs[idx], fn));
        }
      }
      )
      .return();
    }
    )
    .asCallback(cb);
  }

  // @private
  // @nodoc
  getArgsCount(name) {
    let checker = this.checkers.get(name);
    if (checker) { return checker.length; } else { return 0; }
  }

  // @private
  // @nodoc
  splitArguments(name, oargs) {
    let nargs = this.getArgsCount(name);
    let args = _.slice(oargs, 0, nargs);
    let restArgs = _.slice(oargs, nargs);
    return { args, restArgs };
  }

  // @private
  // @nodoc
  checkMessage(msg) {
    return check.object(msg) &&
      check.string(msg.textMessage) && _.keys(msg).length === 1;
  }

  // @private
  // @nodoc
  checkObject(obj) {
    return check.object(obj);
  }

  // @private
  // @nodoc
  checkTypes(checkers, args) {
    if (args.length !== checkers.length) {
      return new ChatServiceError('wrongArgumentsCount'
      , checkers.length, args.length);
    }
    for (let idx = 0; idx < checkers.length; idx++) {
      let checker = checkers[idx];
      if (!checker(args[idx])) {
        return new ChatServiceError('badArgument', idx, args[idx]);
      }
    }
    return null;
  }

  // @private
  // @nodoc
  directAddToList(listName, userNames) {
    return [
      check.string,
      check.array.of.string
    ];
  }

  // @private
  // @nodoc
  directGetAccessList(listName) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  directGetWhitelistMode() {
    return [];
  }

  // @private
  // @nodoc
  directMessage(toUser, msg) {
    return [
      check.string,
      this.directMessagesChecker ? this.checkObject : this.checkMessage
    ];
  }

  // @private
  // @nodoc
  directRemoveFromList(listName, userNames) {
    return [
      check.string,
      check.array.of.string
    ];
  }

  // @private
  // @nodoc
  directSetWhitelistMode(mode) {
    return [
      check.boolean
    ];
  }

  // @private
  // @nodoc
  disconnect(reason) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  listOwnSockets() {
    return [];
  }

  // @private
  // @nodoc
  roomAddToList(roomName, listName, userNames) {
    return [
      check.string,
      check.string,
      check.array.of.string
    ];
  }

  // @private
  // @nodoc
  roomCreate(roomName, mode) {
    return [
      check.string,
      check.boolean
    ];
  }

  // @private
  // @nodoc
  roomDelete(roomName) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  roomGetAccessList(roomName, listName) {
    return [
      check.string,
      check.string
    ];
  }

  // @private
  // @nodoc
  roomGetOwner(roomName) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  roomGetWhitelistMode(roomName) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  roomRecentHistory(roomName){
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  roomHistoryGet(roomName, id, limit) {
    return [
      check.string,
      str => check.greaterOrEqual(str, 0),
      str => check.greaterOrEqual(str, 1)
    ];
  }

  // @private
  // @nodoc
  roomHistoryInfo(roomName) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  roomJoin(roomName) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  roomLeave(roomName) {
    return [
      check.string
    ];
  }

  // @private
  // @nodoc
  roomMessage(roomName, msg) {
    return [
      check.string,
      this.roomMessagesChecker ? this.checkObject : this.checkMessage
    ];
  }

  // @private
  // @nodoc
  roomRemoveFromList(roomName, listName, userNames) {
    return [
      check.string,
      check.string,
      check.array.of.string
    ];
  }

  // @private
  // @nodoc
  roomSetWhitelistMode(roomName, mode) {
    return [
      check.string,
      check.boolean
    ];
  }

  // @private
  // @nodoc
  roomUserSeen(roomName, userName) {
    return [
      check.string,
      check.string
    ];
  }

  // @private
  // @nodoc
  systemMessage(data) {
    return [
      () => true
    ];
  }
}


export default ArgumentsValidator;
