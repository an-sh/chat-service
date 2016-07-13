
import ChatServiceError from './ChatServiceError';
import Promise from 'bluebird';
import Redis from 'ioredis';
import Room from './Room';
import User from './User';
import _ from 'lodash';
import promiseRetry from 'promise-retry';
import uid from 'uid-safe';

import { mix } from './utils';


// @private
// @nodoc
let namespace = 'chatservice';

// @private
// @nodoc
let initSet = (redis, set, values) =>
  redis.del(set)
  .then(function() {
    if (!values) {
      return Promise.resolve();
    }
    return redis.sadd(set, values);
  })
;


// State init/remove operations.
// @mixin
// @private
// @nodoc
let stateOperations = {

  // @private
  initState(state) {
    return this.redis.setnx(this.makeKeyName('exists'), true)
    .then(isnew => {
      if (!isnew) {
        let error = new ChatServiceError(this.exitsErrorName, this.name);
        return Promise.reject(error);
      }
    }
    )
    .then(() => {
      return this.stateReset(state);
    }
    )
    .then(() => {
      return this.redis.setnx(this.makeKeyName('isInit'), true);
    }
    );
  },

  // @private
  removeState() {
    return this.stateReset(null)
    .then(() => {
      return this.redis.del(this.makeKeyName('exists'), this.makeKeyName('isInit'));
    }
    );
  },

  // @private
  startRemoving() {
    return this.redis.del(this.makeKeyName('isInit'));
  }
};


// Redis lock operations.
// @mixin
// @private
// @nodoc
let lockOperations = {

  // @private
  lock(key, val, ttl) {
    return promiseRetry({minTimeout: 100, retries : 10, factor: 1.5, randomize : true}
    , (retry, n) => {
      return this.redis.set(key, val, 'NX', 'PX', ttl)
      .then(function(res) {
        if (!res) {
          let err = new ChatServiceError('timeout');
          return retry(err);
        }
      })
      .catch(retry);
    }
    );
  },

  // @private
  unlock(key, val) {
    return this.redis.unlock(key, val);
  }
};


// Redis scripts.
// @private
// @nodoc
let luaCommands = {

  unlock: {
    numberOfKeys: 1,
    lua: `if redis.call("get",KEYS[1]) == ARGV[1] then
  return redis.call("del",KEYS[1])
else
  return 0
end`
  },

  messageAdd: {
    numberOfKeys: 5,
    lua: `local msg = ARGV[1]
local ts = ARGV[2]

local lastMessageId = KEYS[1]
local historyMaxSize = KEYS[2]
local messagesIds = KEYS[3]
local messagesTimestamps = KEYS[4]
local messagesHistory = KEYS[5]

local id = tonumber(redis.call('INCR', lastMessageId))
local maxsz = tonumber(redis.call('GET', historyMaxSize))

redis.call('LPUSH', messagesIds, id)
redis.call('LPUSH', messagesTimestamps, ts)
redis.call('LPUSH', messagesHistory, msg)

local sz = tonumber(redis.call('LLEN', messagesHistory))

if sz > maxsz then
  redis.call('RPOP', messagesIds)
  redis.call('RPOP', messagesTimestamps)
  redis.call('RPOP', messagesHistory)
end

return {id}`
  },

  messagesGet: {
    numberOfKeys: 5,
    lua: `local id = ARGV[1]
local maxlen = ARGV[2]

local lastMessageId = KEYS[1]
local historyMaxSize = KEYS[2]
local messagesIds = KEYS[3]
local messagesTimestamps = KEYS[4]
local messagesHistory = KEYS[5]

local lastid = tonumber(redis.call('GET', lastMessageId))
local maxsz = tonumber(redis.call('GET', historyMaxSize))
local id = math.min(id, lastid)
local endp = lastid - id
local len = math.min(maxlen, endp)
local start = math.max(0, endp - len)

if start >= endp then
  return {}
end

endp = endp - 1
local msgs = redis.call('LRANGE', messagesHistory, start, endp)
local tss = redis.call('LRANGE', messagesTimestamps, start, endp)
local ids = redis.call('LRANGE', messagesIds, start, endp)

return {msgs, tss, ids}`
  },

  getSocketsToRooms: {
    numberOfKeys: 1,
    lua: `local result = {}
local sockets = KEYS[1]
local prefix = ARGV[1]
local ids = redis.call('HKEYS', sockets)

if table.getn(ids) == 0 then
  local jsonResult = cjson.encode(cjson.null)
  return {jsonResult}
end

for i, id in pairs(ids) do
  local joined = redis.call('SMEMBERS', prefix .. id)
  result[id] = joined
end

local jsonResult = cjson.encode(result)
return {jsonResult}`
  },

  removeAllSocketsFromRoom: {
    numberOfKeys: 1,
    lua: `local room = KEYS[1]
local prefix = ARGV[1]
local roomName = ARGV[2]
local ids = redis.call('SMEMBERS', room)

if table.getn(ids) == 0 then
  local jsonResult = cjson.encode(cjson.null)
  return {jsonResult}
end

redis.call('DEL', room)

for i, id in pairs(ids) do
  redis.call('SREM', prefix .. id, roomName)
end

local jsonResult = cjson.encode(ids)
return {jsonResult}`
  },

  removeSocket: {
    numberOfKeys: 2,
    lua: `local id = KEYS[1]
local sockets = KEYS[2]
local prefix = ARGV[1]
local socketid = ARGV[2]

local rooms = redis.call('SMEMBERS', id)
redis.call('DEL', id)

redis.call('HDEL', sockets, socketid)
local nconnected = redis.call('HLEN', sockets)

local removedRooms = {}
local joinedSockets = {}

for i, room in pairs(rooms) do
  local ismember = redis.call('SISMEMBER', prefix .. room, socketid)
  if ismember == 1 then
    redis.call('SREM', prefix .. room, socketid)
    local njoined = redis.call('SCARD', prefix .. room)
    table.insert(removedRooms, room)
    table.insert(joinedSockets, njoined)
  end
end

if table.getn(removedRooms) == 0 or table.getn(rooms) == 0 then
  local jsonResult = cjson.encode({cjson.null, cjson.null, nconnected})
  return {jsonResult}
end

local jsonResult = cjson.encode({removedRooms, joinedSockets, nconnected})
return {jsonResult}`
  }
};


// Implements state API lists management.
// @private
// @nodoc
class ListsStateRedis {

  // @private
  makeKeyName(keyName) {
    return `${namespace}:${this.prefix}:{${this.name}}:${keyName}`;
  }

  // @private
  checkList(listName) {
    if (!this.hasList(listName)) {
      let error = new ChatServiceError('noList', listName);
      return Promise.reject(error);
    }
    return Promise.resolve();
  }

  // @private
  addToList(listName, elems) {
    return this.checkList(listName)
    .then(() => {
      return this.redis.sadd(this.makeKeyName(listName), elems);
    }
    );
  }

  // @private
  removeFromList(listName, elems) {
    return this.checkList(listName)
    .then(() => {
      return this.redis.srem(this.makeKeyName(listName), elems);
    }
    );
  }

  // @private
  getList(listName) {
    return this.checkList(listName)
    .then(() => {
      return this.redis.smembers(this.makeKeyName(listName));
    }
    );
  }

  // @private
  hasInList(listName, elem) {
    return this.checkList(listName)
    .then(() => {
      return this.redis.sismember(this.makeKeyName(listName), elem);
    }
    )
    .then(function(data) {
      let result = data ? true : false;
      return Promise.resolve(result);
    });
  }

  // @private
  whitelistOnlySet(mode) {
    let whitelistOnly = mode ? true : '';
    return this.redis.set(this.makeKeyName('whitelistMode'), whitelistOnly);
  }

  // @private
  whitelistOnlyGet() {
    return this.redis.get(this.makeKeyName('whitelistMode'))
    .then(function(data) {
      let result = data ? true : false;
      return Promise.resolve(result);
    });
  }
}


// Implements room state API.
// @private
// @nodoc
class RoomStateRedis extends ListsStateRedis {

  // @private
  constructor(server, roomName) {
    this.server = server;
    this.roomName = roomName;
    this.name = this.roomName;
    this.historyMaxGetMessages = this.server.historyMaxGetMessages;
    this.redis = this.server.redis;
    this.exitsErrorName = 'roomExists';
    this.prefix = 'rooms';
  }

  // @private
  stateReset(state = {}) {
    let { whitelist, blacklist, adminlist
    , whitelistOnly, owner, historyMaxSize } = state;
    whitelistOnly = whitelistOnly ? true : '';
    if (!owner) { owner = ''; }
    return Promise.all([
      initSet(this.redis, this.makeKeyName('whitelist'), whitelist),
      initSet(this.redis, this.makeKeyName('blacklist'), blacklist),
      initSet(this.redis, this.makeKeyName('adminlist'), adminlist),
      initSet(this.redis, this.makeKeyName('userlist'), null),
      this.redis.del(this.makeKeyName('messagesHistory')),
      this.redis.del(this.makeKeyName('messagesTimestamps')),
      this.redis.del(this.makeKeyName('messagesIds')),
      this.redis.del(this.makeKeyName('usersseen')),
      this.redis.set(this.makeKeyName('lastMessageId'), 0),
      this.redis.set(this.makeKeyName('whitelistMode'), whitelistOnly),
      this.redis.set(this.makeKeyName('owner'), owner),
      this.historyMaxSizeSet(historyMaxSize)
    ]
    )
    .return();
  }

  // @private
  hasList(listName) {
    return listName === 'adminlist' || listName === 'whitelist' || listName === 'blacklist' || listName === 'userlist';
  }

  // @private
  ownerGet() {
    return this.redis.get(this.makeKeyName('owner'));
  }

  // @private
  ownerSet(owner) {
    return this.redis.set(this.makeKeyName('owner'), owner);
  }

  // @private
  historyMaxSizeSet(historyMaxSize) {
    if (_.isNumber(historyMaxSize) && historyMaxSize >= 0) {
      return this.redis.set(this.makeKeyName('historyMaxSize'), historyMaxSize);
    } else {
      return this.redis.set(this.makeKeyName('historyMaxSize'), this.server.defaultHistoryLimit);
    }
  }

  // @private
  historyInfo() {
    return this.redis.multi()
    .get(this.makeKeyName('historyMaxSize'))
    .llen(this.makeKeyName('messagesHistory'))
    .get(this.makeKeyName('lastMessageId'))
    .exec()
    .spread(([_0, historyMaxSize], [_1, historySize], [_2, lastMessageId]) => {
      historySize = parseInt(historySize);
      historyMaxSize = parseFloat(historyMaxSize);
      lastMessageId = parseInt(lastMessageId);
      let info = { historySize, historyMaxSize
        , historyMaxGetMessages: this.historyMaxGetMessages, lastMessageId };
      return Promise.resolve(info);
    }
    );
  }

  // @private
  getCommonUsers() {
    return this.redis.sdiff(this.makeKeyName('userlist'), this.makeKeyName('whitelist')
    , this.makeKeyName('adminlist'));
  }

  // @private
  messageAdd(msg) {
    let timestamp = _.now();
    let smsg = JSON.stringify(msg);
    return this.redis.messageAdd(this.makeKeyName('lastMessageId')
    , this.makeKeyName('historyMaxSize'), this.makeKeyName('messagesIds')
    , this.makeKeyName('messagesTimestamps'),  this.makeKeyName('messagesHistory')
    , smsg , timestamp)
    .spread(function(id) {
      msg.id = id;
      msg.timestamp = timestamp;
      return Promise.resolve(msg);
    });
  }

  // @private
  convertMessages(msgs, tss, ids) {
    let data = [];
    if (!msgs) {
      return Promise.resolve(data);
    }
    for (let idx = 0; idx < msgs.length; idx++) {
      let msg = msgs[idx];
      let obj = JSON.parse(msg, function(key, val) {
        if (val && val.type === 'Buffer') { return new Buffer(val.data); } else { return val; }
      }
      );
      obj.timestamp = parseInt(tss[idx]);
      obj.id = parseInt(ids[idx]);
      data[idx] = obj;
    }
    return Promise.resolve(data);
  }

  // @private
  messagesGetRecent() {
    if (this.historyMaxGetMessages <= 0) { return Promise.resolve([]); }
    return this.redis.multi()
    .lrange(this.makeKeyName('messagesHistory'), 0, this.historyMaxGetMessages - 1)
    .lrange(this.makeKeyName('messagesTimestamps'), 0, this.historyMaxGetMessages - 1)
    .lrange(this.makeKeyName('messagesIds'), 0, this.historyMaxGetMessages - 1)
    .exec()
    .spread(([_0, msgs], [_1, tss], [_2, ids]) => {
      return this.convertMessages(msgs, tss, ids);
    }
    );
  }

  // @private
  messagesGet(id, maxMessages = this.historyMaxGetMessages) {
    if (maxMessages <= 0) { return Promise.resolve([]); }
    id = _.max([0, id]);
    return this.redis.messagesGet(this.makeKeyName('lastMessageId')
    , this.makeKeyName('historyMaxSize'), this.makeKeyName('messagesIds')
    , this.makeKeyName('messagesTimestamps'),  this.makeKeyName('messagesHistory')
    , id, maxMessages)
    .spread((msgs, tss, ids) => {
      return this.convertMessages(msgs, tss, ids);
    }
    );
  }

  // @private
  userSeenGet(userName) {
    return this.redis.multi()
    .hget(this.makeKeyName('usersseen'), userName)
    .sismember(this.makeKeyName('userlist'), userName)
    .exec()
    .spread(function([_1, ts], [_2, isjoined]) {
      let joined = isjoined ? true : false;
      let timestamp = ts ? parseInt(ts) : null;
      return { joined, timestamp };
    });
  }

  // @private
  userSeenUpdate(userName) {
    let timestamp = _.now();
    return this.redis.hset(this.makeKeyName('usersseen'), userName, timestamp);
  }
}

mix(RoomStateRedis, stateOperations);


// Implements direct messaging state API.
// @private
// @nodoc
class DirectMessagingStateRedis extends ListsStateRedis {

  // @private
  constructor(server, userName) {
    this.server = server;
    this.userName = userName;
    this.name = this.userName;
    this.prefix = 'users';
    this.exitsErrorName = 'userExists';
    this.redis = this.server.redis;
  }

  // @private
  hasList(listName) {
    return listName === 'whitelist' || listName === 'blacklist';
  }

  // @private
  stateReset(state = {}) {
    let { whitelist, blacklist, whitelistOnly } = state;
    whitelistOnly = whitelistOnly ? true : '';
    return Promise.all([
      initSet(this.redis, this.makeKeyName('whitelist'), whitelist),
      initSet(this.redis, this.makeKeyName('blacklist'), blacklist),
      this.redis.set(this.makeKeyName('whitelistMode'), whitelistOnly)
    ]
    )
    .return();
  }
}

mix(DirectMessagingStateRedis, stateOperations);


// Implements user state API.
// @private
// @nodoc
class UserStateRedis {

  // @private
  constructor(server, userName) {
    this.server = server;
    this.userName = userName;
    this.name = this.userName;
    this.prefix = 'users';
    this.redis = this.server.redis;
    this.echoChannel = this.makeEchoChannelName(this.userName);
  }

  // @private
  makeKeyName(keyName) {
    return `${namespace}:${this.prefix}:{${this.name}}:${keyName}`;
  }

  // @private
  makeSocketToRooms(id = '') {
    return this.makeKeyName(`socketsToRooms:${id}`);
  }

  // @private
  makeRoomToSockets(room = '') {
    return this.makeKeyName(`roomsToSockets:${room}`);
  }

  // @private
  makeRoomLock(room = '') {
    return this.makeKeyName(`roomLock:${room}`);
  }

  // @private
  makeEchoChannelName(userName) {
    return `echo:${userName}`;
  }

  // @private
  addSocket(id, uid) {
    return this.redis.multi()
    .hset(this.makeKeyName('sockets'), id, uid)
    .hlen(this.makeKeyName('sockets'))
    .exec()
    .spread((_0, [_1, nconnected]) => Promise.resolve(nconnected));
  }

  // @private
  getAllSockets() {
    return this.redis.hkeys(this.makeKeyName('sockets'));
  }

  // @private
  getSocketsToInstance() {
    return this.redis.hgetall(this.makeKeyName('sockets'));
  }

  // @private
  getRoomToSockets(roomName) {
    return this.redis.smembers(this.makeRoomToSockets(roomName));
  }

  // @private
  getSocketsToRooms() {
    return this.redis.getSocketsToRooms(this.makeKeyName('sockets'), this.makeSocketToRooms())
    .spread(function(result) {
      let data = JSON.parse(result) || {};
      for (let k in data) {
        let v = data[k];
        if (_.isEmpty(v)) {
          data[k] = [];
        }
      }
      return Promise.resolve(data);
    });
  }

  // @private
  addSocketToRoom(id, roomName) {
    return this.redis.multi()
    .sadd(this.makeSocketToRooms(id), roomName)
    .sadd(this.makeRoomToSockets(roomName), id)
    .scard(this.makeRoomToSockets(roomName))
    .exec()
    .spread((_0, _1, [_2, njoined]) => Promise.resolve(njoined));
  }

  // @private
  removeSocketFromRoom(id, roomName) {
    return this.redis.multi()
    .srem(this.makeSocketToRooms(id), roomName)
    .srem(this.makeRoomToSockets(roomName), id)
    .scard(this.makeRoomToSockets(roomName))
    .exec()
    .spread((_0, _1, [_2, njoined]) => Promise.resolve(njoined));
  }

  // @private
  removeAllSocketsFromRoom(roomName) {
    return this.redis.removeAllSocketsFromRoom(this.makeRoomToSockets(roomName)
    , this.makeSocketToRooms(), roomName)
    .spread(result => Promise.resolve(JSON.parse(result)));
  }

  // @private
  removeSocket(id) {
    return this.redis.removeSocket(this.makeSocketToRooms(id), this.makeKeyName('sockets')
    , this.makeRoomToSockets(), id)
    .spread(result => Promise.resolve(JSON.parse(result)));
  }

  // @private
  lockToRoom(roomName, ttl) {
    return uid(18)
    .then(val => {
      let start = _.now();
      return this.lock(this.makeRoomLock(roomName), val, ttl)
      .then(() => {
        return Promise.resolve().disposer(() => {
          if (start + ttl < _.now()) {
            this.server.emit('lockTimeExceeded', val, {userName: this.userName, roomName});
          }
          return this.unlock(this.makeRoomLock(roomName), val);
        }
        );
      }
      );
    }
    );
  }
}

mix(UserStateRedis, lockOperations);


// Implements global state API.
// @private
// @nodoc
class RedisState {

  // @private
  constructor(server, options = {}) {
    this.server = server;
    this.options = options;
    this.closed = false;
    if (this.options.useCluster) {
      this.redis = new Redis.Cluster(...this.options.redisOptions);
    } else {
      let redisOptions = _.castArray(this.options.redisOptions); //bug decaffeinate 2.16.0
      this.redis = new Redis(...redisOptions); //bug decaffeinate 2.16.0
    }
    this.RoomState = RoomStateRedis;
    this.UserState = UserStateRedis;
    this.DirectMessagingState = DirectMessagingStateRedis;
    this.lockTTL = this.options.lockTTL || 10000;
    this.instanceUID = this.server.instanceUID;
    this.server.redis = this.redis;
    for (let cmd in luaCommands) {
      let def = luaCommands[cmd];
      this.redis.defineCommand(cmd, {
        numberOfKeys: def.numberOfKeys,
        lua: def.lua
      }
      );
    }
  }

  // @private
  makeKeyName(prefix, name, keyName) {
    return `${namespace}:${prefix}:{${name}}:${keyName}`;
  }

  // @private
  hasRoom(name) {
    return this.redis.get(this.makeKeyName('rooms', name, 'isInit'));
  }

  // @private
  hasUser(name) {
    return this.redis.get(this.makeKeyName('users', name, 'isInit'));
  }

  // @private
  close() {
    this.closed = true;
    return this.redis.quit()
    .return();
  }

  // @private
  getRoom(name, isPredicate = false) {
    let room = new Room(this.server, name);
    return this.hasRoom(name)
    .then(function(exists) {
      if (!exists) {
        if (isPredicate) {
          return Promise.resolve(null);
        } else {
          let error = new ChatServiceError('noRoom', name); //bug decaffeinate 2.16.0
          return Promise.reject(error); //bug decaffeinate 2.16.0
        }
      }
      return Promise.resolve(room);
    });
  }

  // @private
  addRoom(name, state) {
    let room = new Room(this.server, name);
    return room.initState(state)
    .return(room);
  }

  // @private
  removeRoom(name) {
    return Promise.resolve();
  }

  // @private
  addSocket(id, userName) {
    return this.redis.hset(this.makeKeyName('instances', this.instanceUID, 'sockets'), id, userName);
  }

  // @private
  removeSocket(id) {
    return this.redis.hdel(this.makeKeyName('instances', this.instanceUID, 'sockets'), id);
  }

  // @private
  getInstanceSockets(uid = this.instanceUID) {
    return this.redis.hgetall(this.makeKeyName('instances', uid, 'sockets'));
  }

  // @private
  updateHeartbeat() {
    return this.redis.set(this.makeKeyName('instances', this.instanceUID, 'heartbeat'), _.now())
    .catchReturn();
  }

  // @private
  getInstanceHeartbeat(uid = this.instanceUID) {
    return this.redis.get(this.makeKeyName('instances', uid, 'heartbeat'))
    .then(function(ts) {
      if (ts) { return parseInt(ts); } else { return null; }
    });
  }

  // @private
  getOrAddUser(name, state) {
    let user = new User(this.server, name);
    return this.hasUser(name)
    .then(function(exists) {
      if (!exists) { return user.initState(state); }
    })
    .catch(ChatServiceError, e => user
    )
    .return(user);
  }

  // @private
  getUser(name, isPredicate = false) {
    let user = new User(this.server, name);
    return this.hasUser(name)
    .then(function(exists) {
      if (!exists) {
        if (isPredicate) {
          return Promise.resolve(null);
        } else {
          let error = new ChatServiceError('noUser', name); //bug decaffeinate 2.16.0
          return Promise.reject(error); //bug decaffeinate 2.16.0
        }
      }
      return Promise.resolve(user);
    });
  }

  // @private
  addUser(name, state) {
    let user = new User(this.server, name);
    return user.initState(state)
    .return(user);
  }

  // @private
  removeUser(name) {
    return Promise.resolve();
  }
}


export default RedisState;
