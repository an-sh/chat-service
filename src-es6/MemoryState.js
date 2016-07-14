
const ChatServiceError = require('./ChatServiceError');
const FastMap = require('collections/fast-map');
const FastSet = require('collections/fast-set');
const List = require('collections/list');
const Promise = require('bluebird');
const Room = require('./Room');
const User = require('./User');
const _ = require('lodash');
const promiseRetry = require('promise-retry');
const uid = require('uid-safe');

const { mix } = require('./utils');


// @private
// @nodoc
let initState = function(state, values) {
  if (state) {
    state.clear();
    if (values) {
      return state.addEach(values);
    }
  }
};


// Memory lock operations.
// @mixin
// @private
// @nodoc
let lockOperations = {

  // @private
  lock(key, val, ttl) {
    return promiseRetry({minTimeout: 100, retries : 10, factor: 1.5, randomize : true}
    , (retry, n) => {
      if (this.locks.has(key)) {
        let err = new ChatServiceError('timeout');
        return retry(err);
      } else {
        this.locks.set(key, val); //bug decaffeinate 2.16.0
        return Promise.resolve();
      }
    }
    );
  },

  // @private
  unlock(key, val) {
    let currentVal = this.locks.get(key);
    if (currentVal === val) {
      this.locks.delete(key);
    }
    return Promise.resolve();
  }
};


// Implements state API lists management.
// @private
// @nodoc
class ListsStateMemory {

  // @private
  checkList(listName) {
    if (!this.hasList(listName)) {
      let error = new ChatServiceError('noList', listName);
      return Promise.reject(error);
    } else {
      return Promise.resolve();
    }
  }

  // @private
  addToList(listName, elems) {
    return this.checkList(listName)
    .then(() => {
      this[listName].addEach(elems);
      return Promise.resolve();
    }
    );
  }

  // @private
  removeFromList(listName, elems) {
    return this.checkList(listName)
    .then(() => {
      this[listName].deleteEach(elems);
      return Promise.resolve();
    }
    );
  }

  // @private
  getList(listName) {
    return this.checkList(listName)
    .then(() => {
      let data = this[listName].toArray();
      return Promise.resolve(data);
    }
    );
  }

  // @private
  hasInList(listName, elem) {
    return this.checkList(listName)
    .then(() => {
      let data = this[listName].has(elem);
      data = data ? true : false;
      return Promise.resolve(data);
    }
    );
  }

  // @private
  whitelistOnlySet(mode) {
    this.whitelistOnly = mode ? true : false;
    return Promise.resolve();
  }

  // @private
  whitelistOnlyGet() {
    let wl = this.whitelistOnly || false;
    return Promise.resolve(this.whitelistOnly);
  }
}


// Implements room state API.
// @private
// @nodoc
class RoomStateMemory extends ListsStateMemory {

  // @private
  constructor(server, name) {
    super();
    this.server = server;
    this.name = name;
    this.historyMaxGetMessages = this.server.historyMaxGetMessages;
    this.historyMaxSize = this.server.defaultHistoryLimit;
    this.whitelist = new FastSet();
    this.blacklist = new FastSet();
    this.adminlist = new FastSet();
    this.userlist = new FastSet();
    this.messagesHistory = new List();
    this.messagesTimestamps = new List();
    this.messagesIds = new List();
    this.usersseen = new FastMap();
    this.lastMessageId = 0;
    this.whitelistOnly = false;
    this.owner = null;
  }

  // @private
  initState(state = {}) {
    let { whitelist, blacklist, adminlist
    , whitelistOnly, owner, historyMaxSize } = state;
    initState(this.whitelist, whitelist);
    initState(this.blacklist, blacklist);
    initState(this.adminlist, adminlist);
    initState(this.messagesHistory);
    initState(this.messagesTimestamps);
    initState(this.messagesIds);
    initState(this.usersseen);
    this.whitelistOnly = whitelistOnly ? true : false;
    this.owner = owner ? owner : null;
    return this.historyMaxSizeSet(historyMaxSize);
  }

  // @private
  removeState() {
    return Promise.resolve();
  }

  // @private
  startRemoving() {
    return Promise.resolve();
  }

  // @private
  hasList(listName) {
    return listName === 'adminlist' || listName === 'whitelist' || listName === 'blacklist' || listName === 'userlist';
  }

  // @private
  ownerGet() {
    return Promise.resolve(this.owner);
  }

  // @private
  ownerSet(owner) {
    this.owner = owner;
    return Promise.resolve();
  }

  // @private
  historyMaxSizeSet(historyMaxSize) {
    if (_.isNumber(historyMaxSize) && historyMaxSize >= 0) {
      this.historyMaxSize = historyMaxSize;
    }
    return Promise.resolve();
  }

  // @private
  historyInfo() {
    let historySize = this.messagesHistory.length;
    let info = { historySize, historyMaxSize: this.historyMaxSize
      , historyMaxGetMessages: this.historyMaxGetMessages, lastMessageId: this.lastMessageId };
    return Promise.resolve(info);
  }

  // @private
  getCommonUsers() {
    let diff = (this.userlist.difference(this.whitelist)).difference(this.adminlist);
    let data = diff.toArray();
    return Promise.resolve(data);
  }

  // @private
  messageAdd(msg) {
    let timestamp = _.now();
    this.lastMessageId++;
    let makeResult = () => {
      msg.timestamp = timestamp;
      msg.id = this.lastMessageId;
      return Promise.resolve(msg);
    };
    if (this.historyMaxSize <= 0) {
      return makeResult();
    }
    this.messagesHistory.unshift(msg);
    this.messagesTimestamps.unshift(timestamp);
    this.messagesIds.unshift(this.lastMessageId);
    if (this.messagesHistory.length > this.historyMaxSize) {
      this.messagesHistory.pop();
      this.messagesTimestamps.pop();
      this.messagesIds.pop();
    }
    return makeResult();
  }

  // @private
  messagesGetRecent() {
    let msgs = this.messagesHistory.slice(0, this.historyMaxGetMessages);
    let tss = this.messagesTimestamps.slice(0, this.historyMaxGetMessages);
    let ids = this.messagesIds.slice(0, this.historyMaxGetMessages);
    let data = [];
    for (let idx = 0; idx < msgs.length; idx++) {
      let msg = msgs[idx];
      let obj = _.cloneDeep(msg);
      obj.timestamp = tss[idx];
      obj.id = ids[idx];
      data[idx] = obj;
    }
    return Promise.resolve(data);
  }

  // @private
  messagesGet(id, maxMessages = this.historyMaxGetMessages) {
    if (maxMessages <= 0) { return Promise.resolve([]); }
    id = _.max([0, id]);
    let nmessages = this.messagesIds.length;
    let lastid = this.lastMessageId;
    id = _.min([ id, lastid ]);
    let end = lastid - id;
    let len = _.min([ maxMessages, end ]);
    let start = _.max([ 0, end - len ]);
    let msgs = this.messagesHistory.slice(start, end);
    let tss = this.messagesTimestamps.slice(start, end);
    let ids = this.messagesIds.slice(start, end);
    let data = [];
    for (let idx = 0; idx < msgs.length; idx++) {
      let msg = msgs[idx];
      let obj = _.cloneDeep(msg);
      msg.timestamp = tss[idx];
      msg.id = ids[idx];
      data[idx] = obj;
    }
    return Promise.resolve(msgs);
  }

  // @private
  userSeenGet(userName) {
    let joined = this.userlist.get(userName) ? true : false;
    let timestamp = this.usersseen.get(userName) || null;
    return Promise.resolve({ joined, timestamp });
  }

  // @private
  userSeenUpdate(userName) {
    let timestamp = _.now();
    this.usersseen.set(userName, timestamp);
    return Promise.resolve();
  }
}


// Implements direct messaging state API.
// @private
// @nodoc
class DirectMessagingStateMemory extends ListsStateMemory {

  // @private
  constructor(server, userName) {
    super()
    this.server = server;
    this.userName = userName;
    this.whitelistOnly = false;
    this.whitelist = new FastSet();
    this.blacklist = new FastSet();
  }

  // @private
  initState({ whitelist, blacklist, whitelistOnly } = {}) {
    initState(this.whitelist, whitelist);
    initState(this.blacklist, blacklist);
    this.whitelistOnly = whitelistOnly ? true : false;
    return Promise.resolve();
  }

  // @private
  removeState() {
    return Promise.resolve();
  }

  // @private
  hasList(listName) {
    return listName === 'whitelist' || listName === 'blacklist';
  }
}


// Implements user state API.
// @private
// @nodoc
class UserStateMemory {

  // @private
  constructor(server, userName) {
    this.server = server;
    this.userName = userName;
    this.socketsToRooms = new FastMap();
    this.socketsToInstances = new FastMap();
    this.roomsToSockets = new FastMap();
    this.locks = new FastMap();
    this.echoChannel = this.makeEchoChannelName(this.userName);
  }

  // @private
  makeEchoChannelName(userName) {
    return `echo:${userName}`;
  }

  // @private
  addSocket(id, uid) {
    let roomsset = new FastSet();
    this.socketsToRooms.set(id, roomsset);
    this.socketsToInstances.set(id, uid);
    let nconnected = this.socketsToRooms.length;
    return Promise.resolve(nconnected);
  }

  // @private
  getAllSockets() {
    let sockets = this.socketsToRooms.keysArray();
    return Promise.resolve(sockets);
  }

  // @private
  getSocketsToInstance() {
    let data = this.socketsToInstances.toObject();
    return Promise.resolve(data);
  }

  // @private
  getRoomToSockets(roomName) {
    let socketsset = this.roomsToSockets.get(roomName);
    let data = (socketsset && socketsset.toObject()) || {};
    return Promise.resolve(data);
  }

  // @private
  getSocketsToRooms() {
    let result = {};
    let sockets = this.socketsToRooms.keysArray();
    for (let i = 0; i < sockets.length; i++) {
      let id = sockets[i];
      let socketsset = this.socketsToRooms.get(id);
      result[id] = (socketsset && socketsset.toArray()) || [];
    }
    return Promise.resolve(result);
  }

  // @private
  addSocketToRoom(id, roomName) {
    let roomsset = this.socketsToRooms.get(id);
    let socketsset = this.roomsToSockets.get(roomName);
    if (!socketsset) {
      socketsset = new FastSet();
      this.roomsToSockets.set(roomName, socketsset);
    }
    roomsset.add(roomName);
    socketsset.add(id);
    let njoined = socketsset.length;
    return Promise.resolve(njoined);
  }

  // @private
  removeSocketFromRoom(id, roomName) {
    let roomsset = this.socketsToRooms.get(id);
    let socketsset = this.roomsToSockets.get(roomName);
    if (roomsset) {
      roomsset.delete(roomName);
    }
    if (socketsset) {
      socketsset.delete(id);
    }
    let njoined = (socketsset && socketsset.length) || 0;
    return Promise.resolve(njoined);
  }

  // @private
  removeAllSocketsFromRoom(roomName) {
    let sockets = this.socketsToRooms.keysArray();
    let socketsset = this.roomsToSockets.get(roomName);
    let removedSockets = (socketsset && socketsset.toArray()) || [];
    for (let i = 0; i < removedSockets.length; i++) {
      let id = removedSockets[i];
      let roomsset = this.socketsToRooms.get(id);
      roomsset.delete(roomName);
    }
    if (socketsset) {
      socketsset = socketsset.difference(sockets);
      this.roomsToSockets.set(roomName, socketsset);
    }
    return Promise.resolve(removedSockets);
  }

  // @private
  removeSocket(id) {
    let rooms = this.roomsToSockets.toArray();
    let roomsset = this.socketsToRooms.get(id);
    let removedRooms = (roomsset && roomsset.toArray()) || [];
    let joinedSockets = [];
    for (let idx = 0; idx < removedRooms.length; idx++) {
      let roomName = removedRooms[idx];
      let socketsset = this.roomsToSockets.get(roomName);
      socketsset.delete(id);
      let njoined = socketsset.length;
      joinedSockets[idx] = njoined;
    }
    this.socketsToRooms.delete(id);
    this.socketsToInstances.delete(id);
    let nconnected = this.socketsToRooms.length;
    return Promise.resolve([ removedRooms, joinedSockets, nconnected ]);
  }

  // @private
  lockToRoom(roomName, ttl) {
    return uid(18)
    .then(val => {
      let start = _.now();
      return this.lock(roomName, val, ttl)
      .then(() => {
        return Promise.resolve().disposer(() => {
          if (start + ttl < _.now()) {
            this.server.emit('lockTimeExceeded', val, {userName: this.userName, roomName});
          }
          return this.unlock(roomName, val);
        }
        );
      }
      );
    }
    );
  }
}

mix(UserStateMemory, lockOperations);


// Implements global state API.
// @private
// @nodoc
class MemoryState {

  // @private
  constructor(server, options = {}) {
    this.server = server;
    this.options = options;
    this.closed = false;
    this.users = new FastMap();
    this.rooms = new FastMap();
    this.sockets = new FastMap();
    this.RoomState = RoomStateMemory;
    this.UserState = UserStateMemory;
    this.DirectMessagingState = DirectMessagingStateMemory;
    this.instanceUID = this.server.instanceUID;
    this.heartbeatStamp = null;
    this.lockTTL = this.options.lockTTL || 5000;
  }

  // @private
  close() {
    this.closed = true;
    return Promise.resolve();
  }

  // @private
  getRoom(name, isPredicate = false) {
    let r = this.rooms.get(name);
    if (!r) {
      if (isPredicate) {
        return Promise.resolve(null);
      } else {
        let error = new ChatServiceError('noRoom', name); //bug decaffeinate 2.16.0
        return Promise.reject(error); //bug decaffeinate 2.16.0
      }
    }
    return Promise.resolve(r);
  }

  // @private
  addRoom(name, state) {
    let room = new Room(this.server, name);
    if (!this.rooms.get(name)) {
      this.rooms.set(name, room);
    } else {
      let error = new ChatServiceError('roomExists', name); //bug decaffeinate 2.16.0
      return Promise.reject(error); //bug decaffeinate 2.16.0
    }
    if (state) {
      return room.initState(state)
      .return(room);
    } else {
      return Promise.resolve(room); //bug decaffeinate 2.16.0
    }
  }

  // @private
  removeRoom(name) {
    this.rooms.delete(name);
    return Promise.resolve();
  }

  // @private
  addSocket(id, userName) {
    this.sockets.set(id, userName);
    return Promise.resolve();
  }

  // @private
  removeSocket(id) {
    this.sockets.delete(id);
    return Promise.resolve();
  }

  // @private
  getInstanceSockets(uid) {
    return Promise.resolve(this.sockets.toObject());
  }

  // @private
  updateHeartbeat() {
    this.heartbeatStamp = _.now();
    return Promise.resolve();
  }

  // @private
  getInstanceHeartbeat(uid = this.instanceUID) {
    if (uid !== this.instanceUID) { return null; }
    return Promise.resolve(this.heartbeatStamp);
  }

  // @private
  getOrAddUser(name, state) {
    let user = this.users.get(name);
    if (user) { return Promise.resolve(user); }
    return this.addUser(name, state);
  }

  // @private
  getUser(name, isPredicate = false) {
    let user = this.users.get(name);
    if (!user) {
      if (isPredicate) {
        return Promise.resolve(null);
      } else {
        let error = new ChatServiceError('noUser', name); //bug decaffeinate 2.16.0
        return Promise.reject(error); //bug decaffeinate 2.16.0
      }
    } else {
      return Promise.resolve(user); //bug decaffeinate 2.16.0
    }
  }

  // @private
  addUser(name, state) {
    let user = this.users.get(name);
    if (user) {
      let error = new ChatServiceError('userExists', name);
      return Promise.reject(error);
    }
    user = new User(this.server, name);
    this.users.set(name, user);
    if (state) {
      return user.initState(state)
      .return(user);
    } else {
      return Promise.resolve(user); //bug decaffeinate 2.16.0
    }
  }

  // @private
  removeUser(name) {
    this.users.delete(name);
    return Promise.resolve();
  }
}


module.exports = MemoryState;
